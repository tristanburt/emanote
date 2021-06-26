{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}

module Emanote.Model.Meta where

import Control.Lens.Operators as Lens ((^.))
import Data.Aeson (FromJSON)
import qualified Data.Aeson as Aeson
import qualified Data.IxSet.Typed as Ix
import Emanote.Model (Model, modelLookupNoteByRoute, modelSData)
import Emanote.Model.Note (lookupAeson, noteMeta)
import Emanote.Model.SData (sdataValue)
import qualified Emanote.Model.SData as SData
import qualified Emanote.Route as R

-- | Look up a specific key in the meta for a given route.
lookupRouteMeta :: FromJSON a => a -> NonEmpty Text -> R.LMLRoute -> Model -> a
lookupRouteMeta x k r =
  lookupAeson x k . getEffectiveRouteMeta r

-- | Get the (final) metadata of a note at the given route, by merging it with
-- the defaults specified in parent routes all the way upto index.yaml.
getEffectiveRouteMeta :: R.LMLRoute -> Model -> Aeson.Value
getEffectiveRouteMeta mr model =
  let defaultFiles = R.routeInits @'R.Yaml (coerce $ R.lmlRouteCase mr)
      defaults = flip mapMaybe (toList defaultFiles) $ \r -> do
        v <- getYamlMeta r model
        guard $ v /= Aeson.Null
        pure v
      frontmatter = do
        x <- (^. noteMeta) <$> modelLookupNoteByRoute mr model
        guard $ x /= Aeson.Null
        pure x
      metas = defaults <> maybe mempty one frontmatter
   in maybe Aeson.Null SData.mergeAesons $ nonEmpty metas

getYamlMeta :: R.R 'R.Yaml -> Model -> Maybe Aeson.Value
getYamlMeta r model =
  fmap (^. sdataValue) . Ix.getOne . Ix.getEQ r $ model ^. modelSData

getIndexYamlMeta :: Model -> Aeson.Value
getIndexYamlMeta =
  fromMaybe Aeson.Null . getYamlMeta R.indexRoute
