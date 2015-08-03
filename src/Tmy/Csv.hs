{-# LANGUAGE OverloadedLists #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}

module Tmy.Csv where

import Control.Applicative                  ((<$>), (<*>))
import Control.Monad                        (mplus)
import qualified Data.ByteString      as B  (span, spanEnd)
import qualified Data.ByteString.Lazy as BL (readFile, empty)
import Data.Csv                      hiding (decodeByName, decode)
import Data.Csv.Streaming                   (Records(Cons, Nil), decodeByName, decode)
import Data.Time.Calendar                   (fromGregorianValid)
import Data.Time.Format                     (formatTime)
import Data.Time.LocalTime                  (LocalTime(LocalTime), makeTimeOfDayValid)
import System.Locale                        (iso8601DateFormat, defaultTimeLocale)
import Text.Printf                          (printf)


newtype Spaced a = Spaced {unSpaced :: a} deriving (Show, Eq, Ord, ToField)

instance FromField a => FromField (Spaced a) where
    parseField bs = Spaced <$> parseField (fst . B.spanEnd (== 32) . snd . B.span (== 32) $ bs) -- a space character, or use isSpace to include all whitespace


newtype Double1Dec = Double1Dec Double deriving (Show, Eq, Ord, FromField, Num, Fractional)

instance ToField Double1Dec where
    toField (Double1Dec d) = toField (printf "%.1f" d :: String)


-- TODO: orphan instance, maybe some form of newtype would be better?
instance ToField LocalTime where
    toField lt = toField (formatTime defaultTimeLocale (iso8601DateFormat (Just "%H:%M:%S")) lt)


recsAsList :: [Records a] -> Records a -> [a]
recsAsList xs     (Cons (Right a) rs) = a : recsAsList xs rs  -- value found
recsAsList _      (Cons (Left e)  _)  = error e               -- error but we can continue, but we're not going to
recsAsList _      (Nil  (Just e)  _)  = error e               -- failed to parse to the end
recsAsList (x:xs) (Nil  Nothing   _)  = recsAsList xs x       -- success, read next list
-- TODO: non-exhaustive, but it's right here?
recsAsList []     (Nil  Nothing   _)  = []                    -- success and done!


-- | For parsing LocalTime from a CSV with columns like:
--   'Year Month Day Hours Minutes in YYYY, MM, DD, HH24, MI format in Local time'
fieldsToLocalTime :: Int -> Record -> Parser LocalTime
fieldsToLocalTime i v = do
    mplus (colsToLocalTime (v .! i) (v .! (i+1)) (v .! (i+2)) (v .! (i+3)) (v .! (i+4)))
          (fail $ "Could not parse date starting at col " ++ show i)


colsToLocalTime :: Parser Integer -> Parser Int -> Parser Int -> Parser Int -> Parser Int -> Parser LocalTime
colsToLocalTime y m d h mn = do
    mlt <- maybeLocalTime <$> y <*> m <*> d <*> h <*> mn
    maybe (fail $ "Could not parse date") return mlt


maybeLocalTime :: Integer -> Int -> Int -> Int -> Int -> Maybe LocalTime
maybeLocalTime y m d h mn = LocalTime <$> (fromGregorianValid y m d)
                                      <*> (makeTimeOfDayValid h mn 0)


mapRecords_ :: (a -> IO ()) -> Records a -> IO ()
mapRecords_ f (Cons eith rs) = do
    either (printFailure "Record failed: ") f eith
    mapRecords_ f rs
mapRecords_ _ (Nil err _) = do
    maybe (return ()) (printFailure "Failed to parse: ") err


readCsv :: FromNamedRecord a => FilePath -> IO (Records a)
readCsv fn = do
    bs <- BL.readFile fn
    case decodeByName bs of
        Left err -> do
            putStrLn ("Failed to read file '" ++ fn ++ "': " ++ err)
            return (Nil Nothing BL.empty)
        Right (_, rs) -> return rs


readIndexedCsv :: FromRecord a => FilePath -> IO (Records a)
readIndexedCsv fn = do
    bs <- BL.readFile fn
    return (decode HasHeader bs)


printFailure :: String -> String -> IO ()
printFailure pre err = putStrLn (pre ++ err)
