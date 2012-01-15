module Helper
where

  import qualified Data.Enumerator        as E
  import           Data.Enumerator (($$))
  import qualified Data.Enumerator.Binary as EB
  import qualified Data.Enumerator.List   as EL
  import qualified Data.ByteString.Char8  as B
  import qualified Database.HDBC          as SQL
  import           Control.Concurrent
  import           Control.Monad.Trans
  import           Control.Monad
  import           Network.Mom.Patterns
  import qualified System.IO              as IO
  import           System.Environment
  import           System.Posix.Signals

  getOs :: IO (LinkType, Int, [String])
  getOs = do
    os <- getArgs
    case os of
      [t, p]  -> case parseLink t of
                   Just l  -> return (l, read p, [])
                   Nothing -> usage1
      (t:p:r) -> case parseLink t of
                   Just l  -> return (l, read p, r)
                   Nothing -> usage1
      _       -> usage1 

  getPorts :: IO (Int, Int, [String])
  getPorts = do
    os <- getArgs
    case os of
      [s, t]  -> return (read s, read t, [])
      (s:t:r) -> return (read s, read t, r)
      _       -> usage2 

  usage1 :: IO a
  usage1 = error "<program> 'bind' | 'connect' <port>"

  usage2 :: IO a
  usage2 = error "<program> <port1> <port2>"

  untilInterrupt :: IO () -> IO ()
  untilInterrupt run = do
     continue <- newMVar True
     _ <- installHandler sigINT (Catch $ handler continue) Nothing
     go continue 
    where handler m = modifyMVar_ m (\_ -> return False)
          go      m = do run
                         continue <- readMVar m
                         when continue $ go m

  address :: LinkType         -> 
             String -> String -> Int -> 
             [SocketOption]   -> AccessPoint
  address t prot add port os = 
    case t of
      Bind    -> Address (prot ++ "://*:"             ++ show port) os
      Connect -> Address (prot ++ "://" ++ add ++ ":" ++ show port) os

  onErr :: OnError
  onErr c e n = do
    putStrLn $ show c ++ " in " ++ n ++ ": " ++ show e
    return Nothing 

  onErr_ :: OnError_
  onErr_ c e n = putStrLn $ show c ++ " in " ++ n ++ ": " ++ show e

  dbExec :: SQL.Statement -> [SQL.SqlValue] -> IO ()
  dbExec s ps = SQL.execute s ps >>= \_ -> return ()

  dbFetcher :: SQL.Statement -> Fetch [SQL.SqlValue] String
  dbFetcher s _ _ stp = tryIO (SQL.execute s []) >>= \_ -> go stp
    where go step = 
            case step of
              E.Continue k -> do
                mbR <- tryIO $ SQL.fetchRow s
                case mbR of
                  Nothing -> E.continue k
                  Just r  -> go $$ k (E.Chunks [convRow r])
              _ -> E.returnI step
          convRow :: [SQL.SqlValue] -> String
          convRow [sqlId, sqlName] =
              show idf ++ ": " ++ name
            where idf  = (SQL.fromSql sqlId)::Int
                  name = case SQL.fromSql sqlName of
                           Nothing -> "NN"
                           Just r  -> r
          convRow _ = undefined

  fileFetcher :: IO.Handle -> Fetch_ B.ByteString 
  fileFetcher h c _ = handleFetcher 4096 h c ()

  handleFetcher :: Integer -> IO.Handle -> Fetch_ B.ByteString
  handleFetcher bufSize h _ _ = EB.enumHandle bufSize h

  output :: Dump String
  output c = do
    mbi <- EL.head
    case mbi of
      Nothing -> return ()
      Just i  -> liftIO (putStrLn i) >> output c

  outit :: E.Iteratee String IO ()
  outit = do
    mbi <- EL.head
    case mbi of
      Nothing -> return ()
      Just i  -> liftIO (putStrLn i) >> outit


