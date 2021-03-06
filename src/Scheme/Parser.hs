module Scheme.Parser
  ( readExpr
  ) where

import Control.Monad (liftM)
import Control.Monad.Error
import Data.Array
import Data.Char (toLower)
import Data.Complex (Complex(..))
import Data.Ratio (Rational, (%))
import Numeric (readHex, readOct)
import Scheme.Data
import System.Environment
import Text.ParserCombinators.Parsec hiding (spaces)

readExpr :: String -> ThrowsError LispVal
readExpr input =
  case parse parseExpr "lisp" input of
    Left err -> throwError $ Parser err
    Right val -> return val

--
-- LispVal Parsers
--
parseExpr :: Parser LispVal
parseExpr =
  parseAtom <|> parseString <|> parseNumber <|> parseQuoted <|> parseQuasiQuoted <|> do
    char '('
    x <- try parseList <|> parseDottedList
    char ')'
    return x

parseQuasiQuoted :: Parser LispVal
parseQuasiQuoted = do
  char '`'
  x <- parseExpr
  return $ List [Atom "quasiquote", x]

parseUnQuote :: Parser LispVal
parseUnQuote = do
  char ','
  x <- parseExpr
  return $ List [Atom "unquote", x]

parseAtom :: Parser LispVal
parseAtom = do
  first <- letter <|> symbol
  rest <- many (letter <|> digit <|> symbol)
  (return . Atom) (first : rest)

parseVector :: Parser LispVal
parseVector = do
  arrayValues <- sepBy parseExpr spaces
  return $ Vector (listArray (0, (length arrayValues - 1)) arrayValues)

parseNumber :: Parser LispVal
parseNumber = parsePlainNumber <|> parseRadixNumber

parsePlainNumber :: Parser LispVal
parsePlainNumber = many1 digit >>= return . Number . read

parseRadixNumber :: Parser LispVal
parseRadixNumber =
  char '#' >> (parseDecimal <|> parseBinary <|> parseOctal <|> parseHex)

parseDecimal :: Parser LispVal
parseDecimal = do
  char 'd'
  n <- many1 digit
  (return . Number . read) n

parseBinary :: Parser LispVal
parseBinary = do
  char 'b'
  n <- many $ oneOf "01"
  (return . Number . bin2int) n

parseOctal :: Parser LispVal
parseOctal = do
  char 'o'
  n <- many $ oneOf "01234567"
  (return . Number . (readWith readOct)) n

parseHex :: Parser LispVal
parseHex = do
  char 'x'
  n <- many $ oneOf "0123456789abcdefABCDEF"
  (return . Number . (readWith readHex)) n

parseRatio :: Parser LispVal
parseRatio = do
  num <- fmap read $ many1 digit
  char '/'
  denom <- fmap read $ many1 digit
  (return . Ratio) (num % denom)

parseFloat :: Parser LispVal
parseFloat = do
  whole <- many1 digit
  char '.'
  decimal <- many1 digit
  return $ Float (read (whole ++ "." ++ decimal))

parseComplex :: Parser LispVal
parseComplex = do
  r <- fmap toDouble (try parseFloat <|> parsePlainNumber)
  char '+'
  i <- fmap toDouble (try parseFloat <|> parsePlainNumber)
  char 'i'
  (return . Complex) (r :+ i)
  where
    toDouble (Float x) = x
    toDouble (Number x) = fromIntegral x

parseString :: Parser LispVal
parseString = do
  char '"'
  s <- many (escapedChars <|> (noneOf ['\\', '"']))
  char '"'
  (return . String) s

parseChar :: Parser LispVal
parseChar = do
  string "#\\"
  s <- many1 letter
  return $
    case (map toLower s) of
      "space" -> Char ' '
      "newline" -> Char '\n'
      [x] -> Char x

parseBool :: Parser LispVal
parseBool = do
  char '#'
  c <- oneOf "tf"
  return $
    case c of
      't' -> Bool True
      'f' -> Bool False

parseList :: Parser LispVal
parseList = liftM List $ sepBy parseExpr spaces

parseDottedList :: Parser LispVal
parseDottedList = do
  head <- endBy parseExpr spaces
  tail <- char '.' >> spaces >> parseExpr
  return $ DottedList head tail

parseQuoted :: Parser LispVal
parseQuoted = do
  char '\''
  x <- parseExpr
  return $ List [Atom "quote", x]

--
-- Helpers
--
escapedChars :: Parser Char
escapedChars = do
  char '\\'
  c <- oneOf ['\\', '"', 'n', 'r', 't']
  return $
    case c of
      '\\' -> c
      '"' -> c
      'n' -> '\n'
      'r' -> '\r'
      't' -> '\t'

symbol :: Parser Char
symbol = oneOf "!$%&|*+-/:<=>?@^_~"

spaces :: Parser ()
spaces = skipMany1 space

bin2int :: String -> Integer
bin2int s = sum $ map (\(i, x) -> i * (2 ^ x)) $ zip [0 ..] $ map p (reverse s)
  where
    p '0' = 0
    p '1' = 1

readWith f s = fst $ f s !! 0
