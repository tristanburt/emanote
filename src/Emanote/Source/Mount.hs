{-# LANGUAGE TypeApplications #-}

-- | This is a fork of Ema.Helper.FileSystem (forked for ghcid-convenience), to
-- be *soon* made a separate Haskell library.
module Emanote.Source.Mount where

import Control.Concurrent (threadDelay)
import Control.Monad.Logger
  ( LogLevel (LevelDebug, LevelError, LevelInfo),
    MonadLogger,
    logWithoutLoc,
  )
import Data.LVar (LVar)
import qualified Data.LVar as LVar
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import System.Directory (canonicalizePath)
import System.FSNotify
  ( ActionPredicate,
    Event (..),
    StopListening,
    WatchManager,
    watchTree,
    withManager,
  )
import System.FilePath (isRelative, makeRelative)
import System.FilePattern (FilePattern, (?==))
import System.FilePattern.Directory (getDirectoryFilesIgnore)
import UnliftIO (MonadUnliftIO, finally, newTBQueueIO, race_, try, withRunInIO, writeTBQueue)
import UnliftIO.STM (TBQueue, readTBQueue)

-- | Like `unionMount` but updates a `LVar` as well handles exceptions by logging them.
unionMountOnLVar ::
  forall source tag model m.
  ( MonadIO m,
    MonadUnliftIO m,
    MonadLogger m,
    Ord source,
    Ord tag
  ) =>
  Set (source, FilePath) ->
  [(tag, FilePattern)] ->
  [FilePattern] ->
  LVar model ->
  model ->
  (Change source tag -> m (model -> model)) ->
  m ()
unionMountOnLVar sources pats ignore modelLVar model0 handleAction = do
  -- This TMVar is used to ensure the LVar semantics that `set` is called once
  -- /after/ the initial file listing is read, and `modify` is called for each
  -- subsequent inotify events.
  initialized <- newTMVarIO False
  unionMount sources pats ignore $ \changes -> do
    updateModel <-
      interceptExceptions id $
        handleAction changes
    atomically (takeTMVar initialized) >>= \case
      False -> do
        LVar.set modelLVar (updateModel model0)
      True -> do
        LVar.modify modelLVar updateModel
    atomically $ putTMVar initialized True

-- Log and ignore exceptions
--
-- TODO: Make user defineeable?
interceptExceptions :: (MonadIO m, MonadUnliftIO m, MonadLogger m) => a -> m a -> m a
interceptExceptions default_ f = do
  try f >>= \case
    Left (ex :: SomeException) -> do
      log LevelError $ "User exception: " <> show ex
      pure default_
    Right v ->
      pure v

-------------------------------------
-- Candidate for moving to a library
-------------------------------------

unionMount ::
  forall source tag m.
  ( MonadIO m,
    MonadUnliftIO m,
    MonadLogger m,
    Ord source,
    Ord tag
  ) =>
  Set (source, FilePath) ->
  [(tag, FilePattern)] ->
  [FilePattern] ->
  (Change source tag -> m ()) ->
  m ()
unionMount sources pats ignore handleAction = do
  void . flip runStateT (emptyOverlayFs @source) $ do
    -- Initial traversal of sources
    changes0 :: Change source tag <-
      fmap snd . flip runStateT Map.empty $ do
        forM_ sources $ \(src, folder) -> do
          taggedFiles <- filesMatchingWithTag folder pats ignore
          forM_ taggedFiles $ \(tag, fs) -> do
            forM_ fs $ \fp -> do
              put =<< lift . changeInsert src tag fp (Update ()) =<< get
    lift $ handleAction changes0
    -- Run fsnotify on sources
    ofs <- get
    q :: TBQueue (x, FilePath, FileAction ()) <- liftIO $ newTBQueueIO 1
    lift $
      race_ (onChange q (toList sources)) $
        void . flip runStateT ofs $
          forever $ do
            (src, fp, act) <- atomically $ readTBQueue q
            let shouldIgnore = any (?== fp) ignore
            whenJust (guard (not shouldIgnore) >> getTag pats fp) $ \tag -> do
              changes <- fmap snd . flip runStateT Map.empty $ do
                put =<< lift . changeInsert src tag fp act =<< get
              lift $ handleAction changes

filesMatching :: (MonadIO m, MonadLogger m) => FilePath -> [FilePattern] -> [FilePattern] -> m [FilePath]
filesMatching parent' pats ignore = do
  parent <- liftIO $ canonicalizePath parent'
  log LevelInfo $ toText $ "Traversing " <> parent <> " for files matching " <> show pats <> ", ignoring " <> show ignore
  liftIO $ getDirectoryFilesIgnore parent pats ignore

-- | Like `filesMatching` but with a tag associated with a pattern so as to be
-- able to tell which pattern a resulting filepath is associated with.
filesMatchingWithTag :: (MonadIO m, MonadLogger m, Ord b) => FilePath -> [(b, FilePattern)] -> [FilePattern] -> m [(b, [FilePath])]
filesMatchingWithTag parent' pats ignore = do
  fs <- filesMatching parent' (snd <$> pats) ignore
  let m = Map.fromListWith (<>) $
        flip mapMaybe fs $ \fp -> do
          tag <- getTag pats fp
          pure (tag, one fp)
  pure $ Map.toList m

getTag :: [(b, FilePattern)] -> FilePath -> Maybe b
getTag pats fp =
  let pull patterns =
        listToMaybe $
          flip mapMaybe patterns $ \(tag, pattern) -> do
            guard $ pattern ?== fp
            pure tag
   in if isRelative fp
        then pull pats
        else -- `fp` is an absolute path (because of use of symlinks), so let's
        -- be more lenient in matching it. Note that this does meat we might
        -- match files the user may not have originally intended. This is
        -- the trade offs with using symlinks.
          pull $ second ("**/" <>) <$> pats

data FileAction a = Update a | Delete
  deriving (Eq, Show)

onChange ::
  forall x m.
  (MonadIO m, MonadLogger m, MonadUnliftIO m) =>
  TBQueue (x, FilePath, FileAction ()) ->
  [(x, FilePath)] ->
  -- | The filepath is relative to the folder being monitored, unless if its
  -- ancestor is a symlink.
  m ()
onChange q roots = do
  withManagerM $ \mgr -> do
    stops <- forM roots $ \(x, rootRel) -> do
      -- NOTE: It is important to use canonical path, because this will allow us to
      -- transform fsnotify event's (absolute) path into one that is relative to
      -- @parent'@ (as passed by user), which is what @f@ will expect.
      root <- liftIO $ canonicalizePath rootRel
      log LevelInfo $ toText $ "Monitoring " <> root <> " for changes"
      watchTreeM mgr root (const True) $ \event -> do
        log LevelDebug $ show event
        let rel = makeRelative root
            f a fp act = atomically $ writeTBQueue q (a, fp, act)
        case event of
          Added (rel -> fp) _ _ -> f x fp $ Update ()
          Modified (rel -> fp) _ _ -> f x fp $ Update ()
          Removed (rel -> fp) _ _ -> f x fp Delete
          Unknown (rel -> fp) _ _ -> f x fp Delete
    liftIO (threadDelay maxBound)
      `finally` do
        log LevelInfo "Stopping change monitor"
        liftIO $ forM_ stops id

withManagerM ::
  (MonadIO m, MonadUnliftIO m) =>
  (WatchManager -> m a) ->
  m a
withManagerM f = do
  withRunInIO $ \run ->
    withManager $ \mgr -> run (f mgr)

watchTreeM ::
  forall m.
  (MonadIO m, MonadUnliftIO m) =>
  WatchManager ->
  FilePath ->
  ActionPredicate ->
  (Event -> m ()) ->
  m StopListening
watchTreeM wm fp pr f =
  withRunInIO $ \run ->
    watchTree wm fp pr $ \evt -> run (f evt)

log :: MonadLogger m => LogLevel -> Text -> m ()
log = logWithoutLoc "Emanote.Source.Mount"

-- TODO: Abstract in module with StateT / MonadState
newtype OverlayFs source = OverlayFs
  { unOverlayFs :: Map FilePath (Set source)
  }

-- TODO: Replace this with a function taking `NonEmpty source`
emptyOverlayFs :: Ord source => OverlayFs source
emptyOverlayFs = OverlayFs mempty

overlayFsModify :: FilePath -> (Set src -> Set src) -> OverlayFs src -> OverlayFs src
overlayFsModify k f (OverlayFs m) =
  OverlayFs $
    Map.insert k (f $ fromMaybe Set.empty $ Map.lookup k m) m

overlayFsAdd :: Ord src => FilePath -> src -> OverlayFs src -> OverlayFs src
overlayFsAdd fp src =
  overlayFsModify fp $ Set.insert src

overlayFsRemove :: Ord src => FilePath -> src -> OverlayFs src -> OverlayFs src
overlayFsRemove fp src =
  overlayFsModify fp $ Set.delete src

overlayFsLookup :: FilePath -> OverlayFs source -> Maybe (NonEmpty (source, FilePath))
overlayFsLookup fp (OverlayFs m) = do
  sources <- nonEmpty . toList =<< Map.lookup fp m
  pure $ sources <&> (,fp)

-- Files matched by each tag pattern, each represented by their corresponding
-- file (absolute path) in the individual sources. It is up to the user to union
-- them (for now).
--
-- If a path is represented by Nothing, it means it just got removed from the
-- last source, and the app must remove it from its internal state.
type Change source tag = Map tag (Map FilePath (FileAction (NonEmpty (source, FilePath))))

changeInsert ::
  (Ord source, Ord tag, MonadState (OverlayFs source) m) =>
  source ->
  tag ->
  FilePath ->
  FileAction () ->
  Change source tag ->
  m (Change source tag)
changeInsert src tag fp act ch = do
  fmap snd . flip runStateT ch $ do
    -- First, register this change in the overlayFs
    lift $
      modify $
        (if act == Delete then overlayFsRemove else overlayFsAdd)
          fp
          src
    overlays <- fmap (maybe Delete Update) $ lift $ gets $ overlayFsLookup fp
    gets (Map.lookup tag) >>= \case
      Nothing ->
        modify $ Map.insert tag $ Map.singleton fp overlays
      Just files ->
        modify $ Map.insert tag $ Map.insert fp overlays files
