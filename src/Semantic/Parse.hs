{-# LANGUAGE GADTs #-}
module Semantic.Parse where

import Analysis.ConstructorName (ConstructorName, constructorLabel)
import Analysis.IdentifierName (IdentifierName, identifierLabel)
import Analysis.Declaration (HasDeclaration, declarationAlgebra)
import Analysis.PackageDef (HasPackageDef, packageDefAlgebra)
import Data.Blob
import Data.JSON.Fields
import Parsing.Parser
import Prologue hiding (MonadError(..))
import Rendering.Graph
import Rendering.Renderer
import Semantic.IO (NoLanguageForBlob(..), FormatNotSupported(..))
import Semantic.Task
import Serializing.Format

parseBlobs :: (Members '[Distribute WrappedTask, Task, Exc SomeException] effs, Monoid output) => TermRenderer output -> [Blob] -> Eff effs output
parseBlobs renderer blobs = distributeFoldMap (WrapTask . parseBlob renderer) blobs

-- | A task to parse a 'Blob' and render the resulting 'Term'.
parseBlob :: Members '[Task, Exc SomeException] effs => TermRenderer output -> Blob -> Eff effs output
parseBlob renderer blob@Blob{..}
  | Just (SomeParser parser) <- someParser (Proxy :: Proxy '[ConstructorName, HasPackageDef, HasDeclaration, IdentifierName, Foldable, Functor, ToJSONFields1]) <$> blobLanguage
  = parse parser blob >>= case renderer of
    JSONTermRenderer           -> decorate constructorLabel >=> decorate identifierLabel >=> render (renderJSONTerm blob)
    SExpressionTermRenderer    ->                                                            serialize SExpression
    TagsTermRenderer           -> decorate (declarationAlgebra blob)                     >=> render (renderToTags blob)
    ImportsTermRenderer        -> decorate (declarationAlgebra blob) >=> decorate (packageDefAlgebra blob) >=> render (renderToImports blob)
    SymbolsTermRenderer fields -> decorate (declarationAlgebra blob)                     >=> render (renderToSymbols fields blob)
    DOTTermRenderer            ->                                                            render renderTreeGraph >=> serialize (DOT (termStyle blobPath))
  | otherwise = throwError (SomeException (NoLanguageForBlob blobPath))


astParseBlobs :: (Members '[Distribute WrappedTask, Task, Exc SomeException] effs, Monoid output) => TermRenderer output -> [Blob] -> Eff effs output
astParseBlobs renderer blobs = distributeFoldMap (WrapTask . astParseBlob renderer) blobs
  where
    astParseBlob :: Members '[Task, Exc SomeException] effs => TermRenderer output -> Blob -> Eff effs output
    astParseBlob renderer blob@Blob{..}
      | Just (SomeASTParser parser) <- someASTParser <$> blobLanguage
      = parse parser blob >>= case renderer of
        SExpressionTermRenderer    -> serialize SExpression
        JSONTermRenderer           -> render (renderJSONTerm' blob)
        _                          -> pure $ throwError (SomeException (FormatNotSupported "Only SExpression and JSON output supported for tree-sitter ASTs."))
      | otherwise = throwError (SomeException (NoLanguageForBlob blobPath))
