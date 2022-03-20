{-# LANGUAGE CPP #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}

{-|
Module      : Text.Pretty.Simple.Internal.ExprParser
Copyright   : (c) Dennis Gosnell, 2016
License     : BSD-style (see LICENSE file)
Maintainer  : cdep.illabout@gmail.com
Stability   : experimental
Portability : POSIX

-}
module Text.Pretty.Simple.Internal.ExprParser
  where

import Text.Pretty.Simple.Internal.Expr (CommaSeparated(..), Expr(..))
import Control.Arrow (first)
import Data.Char (isAlpha, isDigit, isHexDigit)

-- | 'testString1' and 'testString2' are convenient to use in GHCi when playing
-- around with how parsing works.
testString1 :: String
testString1 = "Just [TextInput {textInputClass = Just (Class {unClass = \"class\"}), textInputId = Just (Id {unId = \"id\"}), textInputName = Just (Name {unName = \"name\"}), textInputValue = Just (Value {unValue = \"value\"}), textInputPlaceholder = Just (Placeholder {unPlaceholder = \"placeholder\"})}, TextInput {textInputClass = Just (Class {unClass = \"class\"}), textInputId = Just (Id {unId = \"id\"}), textInputName = Just (Name {unName = \"name\"}), textInputValue = Just (Value {unValue = \"value\"}), textInputPlaceholder = Just (Placeholder {unPlaceholder = \"placeholder\"})}]"

-- | See 'testString1'.
testString2 :: String
testString2 = "some stuff (hello [\"dia\\x40iahello\", why wh, bye] ) (bye)"

expressionParse :: String -> [Expr]
expressionParse = fst . parseExprs

parseExpr :: String -> (Expr, String)
parseExpr ('(':rest) = first (Parens . CommaSeparated) $ parseCSep ')' rest
parseExpr ('[':rest) = first (Brackets . CommaSeparated) $ parseCSep ']' rest
parseExpr ('{':rest) = first (Braces . CommaSeparated) $ parseCSep '}' rest
parseExpr ('"':rest) = first StringLit $ parseStringLit rest
parseExpr ('\'':rest) = first CharLit $ parseCharLit rest
parseExpr ('0':'x':c:rest) | isHexDigit c = first (NumberLit . ('0' :) . ('x' :)) $ parseNumberLit c rest
parseExpr (c:rest)         | isDigit c    = first NumberLit                       $ parseNumberLit c rest
parseExpr other      = first Other $ parseOther other

-- | Parse multiple expressions.
--
-- >>> parseExprs "Just 'a'"
-- ([Other "Just ",CharLit "a"],"")
--
-- Handle escaped characters correctly
--
-- >>> parseExprs $ "Foo \"hello \\\"world!\""
-- ([Other "Foo ",StringLit "hello \\\"world!"],"")
-- >>> parseExprs $ "'\\''"
-- ([CharLit "\\'"],"")
parseExprs :: String -> ([Expr], String)
parseExprs [] = ([], "")
parseExprs s@(c:_)
  | c `elem` (")]}," :: String) = ([], s)
  | otherwise = let (parsed, rest') = parseExpr s
                    (toParse, rest) = parseExprs rest'
                 in (parsed : toParse, rest)

parseCSep :: Char -> String -> ([[Expr]], String)
parseCSep _ [] = ([], "")
parseCSep end s@(c:cs)
  | c == end = ([], cs)
  -- Mismatch condition; if the end does not match, there is a mistake
  -- Perhaps there should be a Missing constructor for Expr
  | c `elem` (")]}" :: String) = ([], s)
  | c == ',' = parseCSep end cs
  | otherwise = let (parsed, rest') = parseExprs s
                    (toParse, rest) = parseCSep end rest'
                 in (parsed : toParse, rest)

-- | Parse string literals until a trailing double quote.
--
-- >>> parseStringLit "foobar\" baz"
-- ("foobar"," baz")
--
-- Keep literal back slashes:
--
-- >>> parseStringLit "foobar\\\" baz\" after"
-- ("foobar\\\" baz"," after")
parseStringLit :: String -> (String, String)
parseStringLit [] = ("", "")
parseStringLit ('"':rest) = ("", rest)
parseStringLit ('\\':c:cs) = ('\\':c:cs', rest)
  where (cs', rest) = parseStringLit cs
parseStringLit (c:cs) = (c:cs', rest)
  where (cs', rest) = parseStringLit cs

-- | Parse character literals until a trailing single quote.
--
-- >>> parseCharLit "a' foobar"
-- ("a"," foobar")
--
-- Keep literal back slashes:
--
-- >>> parseCharLit "\\'' hello"
-- ("\\'"," hello")
parseCharLit :: String -> (String, String)
parseCharLit [] = ("", "")
parseCharLit ('\'':rest) = ("", rest)
parseCharLit ('\\':c:cs) = ('\\':c:cs', rest)
  where (cs', rest) = parseCharLit cs
parseCharLit (c:cs) = (c:cs', rest)
  where (cs', rest) = parseCharLit cs

-- | Parses integers and reals, like @123@ and @45.67@.
--
-- To be more precise, any numbers matching the regex @\\d+(\\.\\d+)?(e[\\+-]?\\d+)?@
-- should get parsed by this function.
--
-- >>> parseNumberLit '3' "456hello world []"
-- ("3456","hello world []")
-- >>> parseNumberLit '0' ".12399880 foobar"
-- ("0.12399880"," foobar")
parseNumberLit :: Char -> String -> (String, String)
parseNumberLit firstDigit = go (firstDigit :) False False
  where
    go :: (String -> String) -> Bool -> Bool -> String -> (String, String)
    go f _ _ [] = (f "", "")
    go f False hasExponent ('.':rest) = go (f . ('.' :)) True hasExponent rest
    go f _ False ('e':'+':rest)                    = go (f . ('e' :) . ('+' :)) True True rest
    go f _ False ('e':'-':rest)                    = go (f . ('e' :) . ('-' :)) True True rest
    go f _ False ('e':rest)                        = go (f . ('e' :))           True True rest
    go f hasDecimal hasExponent rest
      | not (null remainingDigits) = go (f . (remainingDigits ++)) hasDecimal hasExponent rest'
      | otherwise                  = (f "", rest)
      where (remainingDigits, rest') = span isHexDigit rest

-- | This function consumes input, stopping only when it hits a special
-- character or a digit.  However, if the digit is in the middle of a
-- Haskell-style identifier (e.g. @foo123@), then keep going
-- anyway.
--
-- This is almost the same as the function
--
-- > parseOtherSimple = span $ \c ->
-- >   notElem c ("{[()]}\"," :: String) && not (isDigit c) && (c /= '\'')
--
-- except 'parseOther' ignores digits and single quotes that appear in
-- Haskell-like identifiers.
--
-- >>> parseOther "hello world []"
-- ("hello world ","[]")
-- >>> parseOther "hello234 world"
-- ("hello234 world","")
-- >>> parseOther "hello 234 world"
-- ("hello ","234 world")
-- >>> parseOther "hello{[ 234 world"
-- ("hello","{[ 234 world")
-- >>> parseOther "H3110 World"
-- ("H3110 World","")
-- >>> parseOther "Node' (Leaf' 1) (Leaf' 2)"
-- ("Node' ","(Leaf' 1) (Leaf' 2)")
-- >>> parseOther "I'm One"
-- ("I'm One","")
-- >>> parseOther "I'm 2"
-- ("I'm ","2")
parseOther :: String -> (String, String)
parseOther = go False
  where
    go
      :: Bool
      -- ^ in an identifier?
      -> String
      -> (String, String)
    go _ [] = ("", "")
    go insideIdent cs@(c:cs')
      | c `elem` ("{[()]}\"," :: String) = ("", cs)
      | ignoreInIdent c && not insideIdent = ("", cs)
      | insideIdent = first (c :) (go (isIdentRest c) cs')
      | otherwise = first (c :) (go (isIdentBegin c) cs')

    isIdentBegin :: Char -> Bool
    isIdentBegin '_' = True
    isIdentBegin c = isAlpha c

    isIdentRest :: Char -> Bool
    isIdentRest '_' = True
    isIdentRest '\'' = True
    isIdentRest c = isAlpha c || ignoreInIdent c

    ignoreInIdent :: Char -> Bool
    ignoreInIdent x = isDigit x || x == '\''
