module Emanote.Pandoc.Filter.Url
  ( urlResolvingSplice,
    brokenLinkAttr,
    resolveWikiLinkMustExist,
  )
where

import Control.Lens.Operators ((^.))
import Control.Monad.Except (MonadError, throwError)
import qualified Data.Text as T
import Data.Time (UTCTime, defaultTimeLocale, formatTime)
import Data.WorldPeace.Union (absurdUnion, openUnionLift)
import qualified Ema
import qualified Ema.CLI
import Emanote.Model (Model)
import qualified Emanote.Model as M
import qualified Emanote.Model.Link.Rel as Rel
import qualified Emanote.Model.Note as MN
import qualified Emanote.Model.StaticFile as SF
import qualified Emanote.Model.Title as Tit
import qualified Emanote.Pandoc.Markdown.Syntax.WikiLink as WL
import Emanote.Prelude (h)
import qualified Emanote.Route as R
import qualified Emanote.Route.SiteRoute as SR
import qualified Heist.Extra.Splices.Pandoc as HP
import Heist.Extra.Splices.Pandoc.Ctx (ctxSansCustomSplicing)
import Heist.Extra.Splices.Pandoc.Render (plainify)
import qualified Heist.Interpreted as HI
import qualified Text.Pandoc.Definition as B

-- | Resolve all URLs in inlines (<a> and <img>)
urlResolvingSplice ::
  Monad n => Ema.CLI.Action -> Model -> HP.RenderCtx n -> B.Inline -> Maybe (HI.Splice n)
urlResolvingSplice emaAction model (ctxSansCustomSplicing -> ctx) inl =
  case inl of
    B.Link attr@(_id, _class, otherAttrs) is (url, tit) -> do
      uRel <- Rel.parseUnresolvedRelTarget (otherAttrs <> one ("title", tit)) url
      case resolveUnresolvedRelTarget model uRel of
        Left err ->
          pure $ brokenLinkSpanWrapper err inl
        Right sr -> do
          -- TODO: If uRel is `Rel.URTWikiLink (WL.WikiLinkEmbed, _)`, *and* it appears
          -- in B.Para (so do this in block-level custom splice), then embed it.
          -- We don't do this here, as this inline splice can't embed block elements.
          let (newIs, newUrl) = replaceLinkNodeWithRoute emaAction model sr (is, url)
          pure $ HP.rpInline ctx $ B.Link attr newIs (newUrl, tit)
    B.Image attr@(id', class', otherAttrs) is' (url, tit) -> do
      let is = imageInlineFallback url is'
      uRel <- Rel.parseUnresolvedRelTarget (otherAttrs <> one ("title", tit)) url
      case resolveUnresolvedRelTarget model uRel of
        Left err ->
          pure $
            brokenLinkSpanWrapper err $
              B.Image (id', class', otherAttrs) is (url, tit)
        Right sr -> do
          let (newIs, newUrl) = replaceLinkNodeWithRoute emaAction model sr (is, url)
          pure $ HP.rpInline ctx $ B.Image attr newIs (newUrl, tit)
    _ -> Nothing
  where
    -- Fallback to filename if no "alt" text is specified
    imageInlineFallback fn = \case
      [] -> one $ B.Str fn
      x -> x
    brokenLinkSpanWrapper err inline =
      HP.rpInline ctx $
        B.Span (brokenLinkAttr err) $ one inline

brokenLinkAttr :: Text -> B.Attr
brokenLinkAttr err =
  ("", ["emanote:broken-link"], [("title", err)])

replaceLinkNodeWithRoute ::
  Ema.CLI.Action ->
  Model ->
  (SR.SiteRoute, Maybe UTCTime) ->
  ([B.Inline], Text) ->
  ([B.Inline], Text)
replaceLinkNodeWithRoute emaAction model (r, mTime) (inner, url) =
  let finalInner =
        if url == plainify inner -- It's a wiki-link with no custom text
          then fromMaybe inner $ siteRouteDefaultInnerText r
          else inner
   in ( finalInner,
        foldUrlTime (Ema.routeUrl model r) mTime
      )
  where
    siteRouteDefaultInnerText =
      absurdUnion
        `h` (\(SR.MissingR _) -> Nothing)
        `h` ( \(resR :: SR.ResourceRoute) ->
                resR & absurdUnion
                  `h` ( \(lmlR :: R.LMLRoute) ->
                          Tit.toInlines . MN._noteTitle <$> M.modelLookupNoteByRoute lmlR model
                      )
                  `h` ( \(_ :: R.StaticFileRoute, _ :: FilePath) ->
                          -- Just append a file: prefix, to existing wiki-link.
                          pure $ B.Str "File:" : inner
                      )
            )
        `h` (\(_ :: SR.VirtualRoute) -> Nothing)
    foldUrlTime linkUrl mUrlTime =
      linkUrl
        -- In live server mode, append last modification time if any, such
        -- that the browser is forced to refresh the inline image on hot
        -- reload (Ema's DOM patch).
        <> fromMaybe
          ""
          ( do
              guard $ emaAction == Ema.CLI.Run
              t <- mUrlTime
              pure $ toText $ "?t=" <> formatTime defaultTimeLocale "%s" t
          )

resolveUnresolvedRelTarget ::
  Model -> Rel.UnresolvedRelTarget -> Either Text (SR.SiteRoute, Maybe UTCTime)
resolveUnresolvedRelTarget model = \case
  Rel.URTWikiLink (_wlType, wl) -> do
    resourceSiteRoute <$> resolveWikiLinkMustExist model wl
  Rel.URTResource r ->
    resourceSiteRoute <$> resolveModelRouteMustExist r
  Rel.URTVirtual virtualRoute -> do
    pure $
      openUnionLift virtualRoute
        & (,Nothing)
  where
    resolveModelRouteMustExist r =
      case resolveModelRoute model r of
        Nothing ->
          Left "Link does not refer to any known file"
        Just v -> Right v

resolveWikiLinkMustExist :: MonadError Text m => Model -> WL.WikiLink -> m (Either MN.Note SF.StaticFile)
resolveWikiLinkMustExist model wl =
  case nonEmpty (M.modelWikiLinkTargets wl model) of
    Nothing -> do
      throwError "Wiki-link does not refer to any known file"
    Just (target :| []) ->
      pure target
    Just targets -> do
      let targetsStr =
            targets <&> \case
              Left note -> R.encodeRoute $ R.lmlRouteCase $ note ^. MN.noteRoute
              Right sf -> R.encodeRoute $ sf ^. SF.staticFileRoute
      throwError $
        "Wikilink "
          <> show wl
          <> " is ambiguous; referring to one of: "
          <> T.intercalate ", " (toText <$> toList targetsStr)

resolveModelRoute :: Model -> R.ModelRoute -> Maybe (Either MN.Note SF.StaticFile)
resolveModelRoute model lr = do
  let eRoute = R.modelRouteCase lr
  bitraverse
    (`M.modelLookupNoteByRoute` model)
    (`M.modelLookupStaticFileByRoute` model)
    eRoute

resourceSiteRoute :: Either MN.Note SF.StaticFile -> (SR.SiteRoute, Maybe UTCTime)
resourceSiteRoute = \case
  Left note ->
    SR.noteFileSiteRoute note
      & (,Nothing)
  Right sf ->
    SR.staticFileSiteRoute sf
      & (,Just $ sf ^. SF.staticFileTime)
