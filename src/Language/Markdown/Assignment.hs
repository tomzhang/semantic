{-# LANGUAGE DataKinds, RankNTypes, TypeOperators #-}
module Language.Markdown.Assignment
( assignment
, Syntax
, Grammar
, Language.Markdown.Assignment.Term
) where

import qualified CMarkGFM
import Data.ByteString (ByteString)
import Data.Functor (void)
import Data.Record
import Data.Syntax (makeTerm)
import qualified Data.Syntax as Syntax
import Data.Syntax.Assignment hiding (Assignment, Error)
import qualified Data.Syntax.Assignment as Assignment
import Data.Term as Term (Term(..), TermF(..), termIn)
import qualified Data.Text as Text
import Data.Text.Encoding (encodeUtf8)
import Data.Union
import GHC.Stack
import Language.Markdown as Grammar (Grammar(..))
import qualified Language.Markdown.Syntax as Markup

type Syntax =
  '[ Markup.Document
   -- Block elements
   , Markup.BlockQuote
   , Markup.Heading
   , Markup.HTMLBlock
   , Markup.OrderedList
   , Markup.Paragraph
   , Markup.ThematicBreak
   , Markup.UnorderedList
   , Markup.Table
   , Markup.TableRow
   , Markup.TableCell
   -- Inline elements
   , Markup.Code
   , Markup.Emphasis
   , Markup.Image
   , Markup.LineBreak
   , Markup.Link
   , Markup.Strong
   , Markup.Text
   , Markup.Strikethrough
   -- Assignment errors; cmark does not provide parse errors.
   , Syntax.Error
   , []
   ]

type Term = Term.Term (Union Syntax) (Record Location)
type Assignment = HasCallStack => Assignment.Assignment (TermF [] CMarkGFM.NodeType) Grammar Language.Markdown.Assignment.Term


assignment :: Assignment
assignment = Syntax.handleError $ makeTerm <$> symbol Document <*> children (Markup.Document <$> many blockElement)


-- Block elements

blockElement :: Assignment
blockElement = choice
  [ paragraph
  , list
  , blockQuote
  , codeBlock
  , thematicBreak
  , htmlBlock
  , heading
  , table
  ]

paragraph :: Assignment
paragraph = makeTerm <$> symbol Paragraph <*> children (Markup.Paragraph <$> many inlineElement)

list :: Assignment
list = termIn <$> symbol List <*> ((\ (CMarkGFM.LIST CMarkGFM.ListAttributes{..}) -> case listType of
  CMarkGFM.BULLET_LIST -> inj . Markup.UnorderedList
  CMarkGFM.ORDERED_LIST -> inj . Markup.OrderedList) . termAnnotation . termOut <$> currentNode <*> children (many item))

item :: Assignment
item = makeTerm <$> symbol Item <*> children (many blockElement)

heading :: Assignment
heading = makeTerm <$> symbol Heading <*> ((\ (CMarkGFM.HEADING level) -> Markup.Heading level) . termAnnotation . termOut <$> currentNode <*> children (many inlineElement) <*> manyTill blockElement (void (symbol Heading) <|> eof))

blockQuote :: Assignment
blockQuote = makeTerm <$> symbol BlockQuote <*> children (Markup.BlockQuote <$> many blockElement)

codeBlock :: Assignment
codeBlock = makeTerm <$> symbol CodeBlock <*> ((\ (CMarkGFM.CODE_BLOCK language _) -> Markup.Code (nullText language)) . termAnnotation . termOut <$> currentNode <*> source)

thematicBreak :: Assignment
thematicBreak = makeTerm <$> token ThematicBreak <*> pure Markup.ThematicBreak

htmlBlock :: Assignment
htmlBlock = makeTerm <$> symbol HTMLBlock <*> (Markup.HTMLBlock <$> source)

table :: Assignment
table = makeTerm <$> symbol Table <*> children (Markup.Table <$> many tableRow)

tableRow :: Assignment
tableRow = makeTerm <$> symbol TableRow <*> children (Markup.TableRow <$> many tableCell)

tableCell :: Assignment
tableCell = makeTerm <$> symbol TableCell <*> children (Markup.TableCell <$> many inlineElement)

-- Inline elements

inlineElement :: Assignment
inlineElement = choice
  [ strong
  , emphasis
  , strikethrough
  , text
  , link
  , htmlInline
  , image
  , code
  , lineBreak
  , softBreak
  ]

strong :: Assignment
strong = makeTerm <$> symbol Strong <*> children (Markup.Strong <$> many inlineElement)

emphasis :: Assignment
emphasis = makeTerm <$> symbol Emphasis <*> children (Markup.Emphasis <$> many inlineElement)

strikethrough :: Assignment
strikethrough = makeTerm <$> symbol Strikethrough <*> children (Markup.Strikethrough <$> many inlineElement)

text :: Assignment
text = makeTerm <$> symbol Text <*> (Markup.Text <$> source)

htmlInline :: Assignment
htmlInline = makeTerm <$> symbol HTMLInline <*> (Markup.HTMLBlock <$> source)

link :: Assignment
link = makeTerm <$> symbol Link <*> ((\ (CMarkGFM.LINK url title) -> Markup.Link (encodeUtf8 url) (nullText title)) . termAnnotation . termOut <$> currentNode) <* advance

image :: Assignment
image = makeTerm <$> symbol Image <*> ((\ (CMarkGFM.IMAGE url title) -> Markup.Image (encodeUtf8 url) (nullText title)) . termAnnotation . termOut <$> currentNode) <* advance

code :: Assignment
code = makeTerm <$> symbol Code <*> (Markup.Code Nothing <$> source)

lineBreak :: Assignment
lineBreak = makeTerm <$> token LineBreak <*> pure Markup.LineBreak

softBreak :: Assignment
softBreak = makeTerm <$> token SoftBreak <*> pure Markup.LineBreak


-- Implementation details

nullText :: Text.Text -> Maybe ByteString
nullText text = if Text.null text then Nothing else Just (encodeUtf8 text)