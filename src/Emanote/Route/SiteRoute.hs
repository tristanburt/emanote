{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}

module Emanote.Route.SiteRoute
  ( SiteRoute,
    IndexR (..),
    TagIndexR (..),
    MissingR (..),
    VirtualRoute,
    ResourceRoute,
    decodeVirtualRoute,
    noteFileSiteRoute,
    staticFileSiteRoute,
    lmlSiteRoute,
  )
where

import Emanote.Route.SiteRoute.Class
import Emanote.Route.SiteRoute.Type
