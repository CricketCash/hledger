{-|

A reader for the timelog file format generated by timeclock.el
(<http://www.emacswiki.org/emacs/TimeClock>). Example:

@
i 2007\/03\/10 12:26:00 hledger
o 2007\/03\/10 17:26:02
@

From timeclock.el 2.6:

@
A timelog contains data in the form of a single entry per line.
Each entry has the form:

  CODE YYYY/MM/DD HH:MM:SS [COMMENT]

CODE is one of: b, h, i, o or O.  COMMENT is optional when the code is
i, o or O.  The meanings of the codes are:

  b  Set the current time balance, or \"time debt\".  Useful when
     archiving old log data, when a debt must be carried forward.
     The COMMENT here is the number of seconds of debt.

  h  Set the required working time for the given day.  This must
     be the first entry for that day.  The COMMENT in this case is
     the number of hours in this workday.  Floating point amounts
     are allowed.

  i  Clock in.  The COMMENT in this case should be the name of the
     project worked on.

  o  Clock out.  COMMENT is unnecessary, but can be used to provide
     a description of how the period went, for example.

  O  Final clock out.  Whatever project was being worked on, it is
     now finished.  Useful for creating summary reports.
@

-}

module Hledger.Read.TimelogReader (
  -- * Reader
  reader,
  -- * Tests
  tests_Hledger_Read_TimelogReader
)
where
import Prelude ()
import Prelude.Compat
import Control.Monad (liftM)
import Control.Monad.Except (ExceptT)
import Data.List (isPrefixOf, foldl')
import Data.Maybe (fromMaybe)
import Test.HUnit
import Text.Parsec hiding (parse)
import System.FilePath

import Hledger.Data
-- XXX too much reuse ?
import Hledger.Read.JournalReader (
  directive, historicalpricedirective, defaultyeardirective, emptyorcommentlinep, datetimep,
  parseJournalWith, modifiedaccountname
  )
import Hledger.Utils


reader :: Reader
reader = Reader format detect parse

format :: String
format = "timelog"

-- | Does the given file path and data look like it might be timeclock.el's timelog format ?
detect :: FilePath -> String -> Bool
detect f s
  | f /= "-"  = takeExtension f == '.':format               -- from a file: yes if the extension is .timelog
  | otherwise = "i " `isPrefixOf` s || "o " `isPrefixOf` s  -- from stdin: yes if it starts with "i " or "o "

-- | Parse and post-process a "Journal" from timeclock.el's timelog
-- format, saving the provided file path and the current time, or give an
-- error.
parse :: Maybe FilePath -> Bool -> FilePath -> String -> ExceptT String IO Journal
parse _ = parseJournalWith timelogFile

timelogFile :: ParsecT [Char] JournalContext (ExceptT String IO) (JournalUpdate, JournalContext)
timelogFile = do items <- many timelogItem
                 eof
                 ctx <- getState
                 return (liftM (foldl' (\acc new x -> new (acc x)) id) $ sequence items, ctx)
    where
      -- As all ledger line types can be distinguished by the first
      -- character, excepting transactions versus empty (blank or
      -- comment-only) lines, can use choice w/o try
      timelogItem = choice [ directive
                          , liftM (return . addHistoricalPrice) historicalpricedirective
                          , defaultyeardirective
                          , emptyorcommentlinep >> return (return id)
                          , liftM (return . addTimeLogEntry)  timelogentry
                          ] <?> "timelog entry, or default year or historical price directive"

-- | Parse a timelog entry.
timelogentry :: ParsecT [Char] JournalContext (ExceptT String IO) TimeLogEntry
timelogentry = do
  sourcepos <- getPosition
  code <- oneOf "bhioO"
  many1 spacenonewline
  datetime <- datetimep
  account <- fromMaybe "" <$> optionMaybe (many1 spacenonewline >> modifiedaccountname)
  description <- fromMaybe "" <$> optionMaybe (many1 spacenonewline >> restofline)
  return $ TimeLogEntry sourcepos (read [code]) datetime account description

tests_Hledger_Read_TimelogReader = TestList [
 ]

