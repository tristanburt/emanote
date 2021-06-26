{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE UndecidableInstances #-}

module Emanote.Pandoc.Markdown.Syntax.WikiLink
  ( WikiLink,
    WikiLinkType (..),
    wikilinkSpec,
    mkWikiLinkFromUrlAndAttrs,
    allowedWikiLinks,
  )
where

import qualified Commonmark as CM
import qualified Commonmark.Pandoc as CP
import qualified Commonmark.TokParsers as CT
import Control.Monad (liftM2)
import Data.Data (Data)
import qualified Data.List.NonEmpty as NE
import qualified Data.Map.Strict as Map
import qualified Data.Text as T
import Ema (Slug (unSlug))
import qualified Ema
import Emanote.Route (ModelRoute, R (unRoute), lmlRouteCase, modelRouteCase)
import qualified Text.Megaparsec as M
import qualified Text.Pandoc.Builder as B
import qualified Text.Parsec as P
import Text.Read (Read (readsPrec))
import qualified Text.Show (Show (show))

-- | Represents the "Foo" in [[Foo]]
--
-- As wiki links may contain multiple path components, it can also represent
-- [[Foo/Bar]], hence we use nonempty slug list.
newtype WikiLink = WikiLink {unWikiLink :: NonEmpty Slug}
  deriving (Eq, Ord, Typeable, Data)

instance Show WikiLink where
  show (toList . fmap unSlug . unWikiLink -> slugs) =
    toString $ "[[" <> T.intercalate "/" slugs <> "]]"

mkWikiLinkFromUrlAndAttrs :: [(Text, Text)] -> Text -> Maybe (WikiLinkType, WikiLink)
mkWikiLinkFromUrlAndAttrs (Map.fromList -> attrs) s = do
  wlType :: WikiLinkType <- readMaybe . toString <=< Map.lookup htmlAttr $ attrs
  wl <- mkWikiLinkFromUrl s
  pure (wlType, wl)
  where
    mkWikiLinkFromUrl :: Text -> Maybe WikiLink
    mkWikiLinkFromUrl url = do
      slugs <- nonEmpty $ Ema.decodeSlug <$> T.splitOn "/" url
      pure $ WikiLink slugs

-- | Return the various ways to link to this markdown route
--
-- Foo/Bar/Qux.md -> [[Qux]], [[Bar/Qux]], [[Foo/Bar/Qux]]
--
-- All possible combinations of Wikilink type use is automatically included.
allowedWikiLinks :: ModelRoute -> [(WikiLinkType, WikiLink)]
allowedWikiLinks =
  liftM2 (,) wlAllTypes
    . mapMaybe (fmap WikiLink . nonEmpty)
    . toList
    . NE.tails
    . wlParts
  where
    wlAllTypes :: [WikiLinkType] = [minBound .. maxBound]
    wlParts =
      either (unRoute . lmlRouteCase) unRoute
        . modelRouteCase

-------------------------
-- Parser
--------------------------

-- | A # prefix or suffix allows semantically distinct wikilinks
--
-- Typically called branching link or a tag link, when used with #.
data WikiLinkType
  = -- | [[Foo]]
    WikiLinkNormal
  | -- | [[Foo]]#
    WikiLinkBranch
  | -- | #[[Foo]]
    WikiLinkTag
  | -- | ![[Foo]]
    WikiLinkEmbed
  deriving (Eq, Show, Ord, Typeable, Data, Enum, Bounded)

instance Read WikiLinkType where
  readsPrec _ s
    | s == show WikiLinkNormal = [(WikiLinkNormal, "")]
    | s == show WikiLinkBranch = [(WikiLinkBranch, "")]
    | s == show WikiLinkTag = [(WikiLinkTag, "")]
    | s == show WikiLinkEmbed = [(WikiLinkEmbed, "")]
    | otherwise = []

-- | The HTML 'data attribute' storing the wiki-link type.
htmlAttr :: Text
htmlAttr = "data-wikilink-type"

class HasWikiLink il where
  wikilink :: WikiLinkType -> Text -> il -> il

instance HasWikiLink (CP.Cm b B.Inlines) where
  wikilink typ t il = CP.Cm $ B.linkWith attrs t "" $ CP.unCm il
    where
      attrs = ("", [], [(htmlAttr, show typ)])

-- | Like `Commonmark.Extensions.Wikilinks.wikilinkSpec` but Zettelkasten-friendly.
--
-- Compared with the official extension, this has two differences:
--
-- - Supports flipped inner text, eg: `[[Foo | some inner text]]`
-- - Supports neuron folgezettel, i.e.: #[[Foo]] or [[Foo]]#
wikilinkSpec ::
  (Monad m, CM.IsInline il, HasWikiLink il) =>
  CM.SyntaxSpec m il bl
wikilinkSpec =
  mempty
    { CM.syntaxInlineParsers =
        [ P.try $
            P.choice
              [ P.try (CT.symbol '#' *> pWikilink WikiLinkTag),
                P.try (CT.symbol '!' *> pWikilink WikiLinkEmbed),
                P.try (pWikilink WikiLinkBranch <* CT.symbol '#'),
                P.try (pWikilink WikiLinkNormal)
              ]
        ]
    }
  where
    pWikilink typ = do
      replicateM_ 2 $ CT.symbol '['
      P.notFollowedBy (CT.symbol '[')
      url <-
        CM.untokenize
          <$> many
            ( CT.satisfyTok
                ( \t ->
                    not (CT.hasType (CM.Symbol '|') t || CT.hasType (CM.Symbol ']') t)
                )
            )
      title <-
        M.option url $
          -- TODO: Should parse as inline so link text can be formatted?
          CM.untokenize
            <$> ( CT.symbol '|'
                    *> many (CT.satisfyTok (not . CT.hasType (CM.Symbol ']')))
                )
      replicateM_ 2 $ CT.symbol ']'
      return $ wikilink typ url (CM.str title)
