{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeApplications #-}

module Emanote.Model.StaticFile where

import Control.Lens.TH (makeLenses)
import qualified Data.Aeson as Aeson
import Data.IxSet.Typed (Indexable (..), IxSet, ixFun, ixList)
import Data.Time (UTCTime)
import qualified Emanote.Route as R
import qualified Emanote.Model.Link.WikiLink as WL

data StaticFile = StaticFile
  { _staticFileRoute :: R.R 'R.AnyExt,
    _staticFilePath :: FilePath,
    -- | Indicates that this file was updated no latter than the given time.
    _staticFileTime :: UTCTime
  }
  deriving (Eq, Ord, Show, Generic, Aeson.ToJSON)

type StaticFileIxs = '[R.R 'R.AnyExt, WL.WikiLink]

type IxStaticFile = IxSet StaticFileIxs StaticFile

instance Indexable StaticFileIxs StaticFile where
  indices =
    ixList
      (ixFun $ one . _staticFileRoute)
      (ixFun staticFileSelfRefs)

staticFileSelfRefs :: StaticFile -> [WL.WikiLink]
staticFileSelfRefs =
  WL.allowedWikiLinks
    . R.liftLinkableRoute
    . _staticFileRoute

makeLenses ''StaticFile