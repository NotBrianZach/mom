module Main
where

  import Test

  import Types
  import Config
  import Sender

  import Network.Mom.Stompl.Frame

  import Control.Concurrent
  import Control.Monad.State

  import System.Exit
  import System.Environment
  import System.FilePath (FilePath, (</>))

  import qualified Network.Socket as S
  import           Network.BSD (getProtocolNumber) 

  import qualified Data.ByteString.Char8 as B
  import qualified Data.ByteString.UTF8  as U

  import Data.List (delete, insert)

  main :: IO ()
  main = do
    os <- getArgs
    case os of
      [p] -> tSender p
      _   -> putStrLn "I need a Stompl Server Configuration File."

  cid1 :: Int
  cid1 = 1

  tid1 :: String
  tid1 = "tx-1"

  q1   :: String
  q1   = "/q/a"

  mkTests :: S.Socket -> TestGroup Sender
  mkTests s = 
    let t1 = [mkTest "Test Connect   "    (testConnect s),
              mkTest "Test Disconnect"     testDisconnect]

        t2 = [mkTest "Test Connect"       (testConnect s),
              mkTest "Test Sub   with Id" (testSub   "sub-1" 0 Auto),
              mkTest "Test UnSub with Id" (testUnSub "sub-1" 0     )]

        t3 = [mkTest "Test Sub   with    Id" (testSub   "sub-1" 0 Auto),
              mkTest "Test UnSub without Id" (do 
                                                ok <- testUnSub "" 0 
                                                return $ neg ok),
              mkTest "Test UnSub with    Id" (testUnSub "sub-1" 0)]

        t4 = [mkTest "Test Sub  " (testSub   "" 0 Auto),
              mkTest "Test UnSub" (testUnSub "" 0)]

        t5 = [mkTest "Test Sub  " (testSub   "" 0 Auto),
              mkTest "Test Sub  " (testSub   "" 1 Auto),
              mkTest "Test Sub  " (testSub   "" 2 Auto),
              mkTest "Test UnSub" (testUnSub "" 2),
              mkTest "Test UnSub" (testUnSub "" 1),
              mkTest "Test UnSub" (testUnSub "" 0)]

        t5b = [mkTest "Test Sub  " (testSub   "sub-1" 0 Auto),
               mkTest "Test Sub  " (testSub   "sub-2" 1 Auto),
               mkTest "Test Sub  " (testSub   "sub-3" 2 Auto),
               mkTest "Test UnSub" (testUnSub "sub-3" 2),
               mkTest "Test UnSub" (testUnSub "sub-2" 1),
               mkTest "Test UnSub" (testUnSub "sub-1" 0)]

        t6 = [mkTest "Test Sub  " (testSub   "sub-1" 0 Auto), 
              mkTest "Test Send "  testSend,
              mkTest "Test UnSub" (testUnSub "sub-1" 0)]

        t7 = [mkTest "Test Disconnect"  testDisconnect,
              mkTest "Test Connect   " (testConnect s),
              mkTest "Test Sub       " (testSub   "sub-1" 0 Client),
              mkTest "Test Send      "  testSend,
              mkTest "Test Ack       "  testAck,
              mkTest "Test UnSub     " (testUnSub "sub-1" 0)]

        t8 = [mkTest "Test Sub       " (testSub "sub-1" 0 Auto),
              mkTest "Test Begin     " testBegin,
              mkTest "Test Send Tx   " testTxSend,
              mkTest "Test Abort     " testAbort,
              mkTest "Test UnSub     " (testUnSub "sub-1" 0)]

        t9 = [mkTest "Test Sub       " (testSub "sub-1" 0 Auto),
              mkTest "Test Begin     " testBegin,
              mkTest "Test Send Tx   " testTxSend,
              mkTest "Test Commit    " testCommit,
              mkTest "Test UnSub     " (testUnSub "sub-1" 0)]

    in  mkMetaGroup 
                 "Sender Tests" (Stop (Fail ""))
                 [mkGroup "Connect"                          (Stop $ Fail "") t1,
                  mkGroup "Sub with Id"                      (Stop $ Fail "") t2,
                  mkGroup "Sub with Id, Unsub without Id"    (Stop $ Fail "") t3,
                  mkGroup "Sub/UnSub without Id"             (Stop $ Fail "") t4,
                  mkGroup "Multiple Sub/Unsub without Id"    (Stop $ Fail "") t5,
                  mkGroup "Multiple Sub/Unsub with    Id"    (Stop $ Fail "") t5b,
                  mkGroup "Send"                             (Stop $ Fail "") t6,
                  mkGroup "Send in Client Mode"              (Stop $ Fail "") t7,
                  mkGroup "Send Tx Abort      "              (Stop $ Fail "") t8,
                  mkGroup "Send Tx Commit     "              (Stop $ Fail "") t9]

  tSender :: FilePath -> IO ()
  tSender dir = do
    s   <- mkSocket "127.0.0.1" 5432
    v   <- mkConfig (dir </> "stompl.cfg") dummyChange dummyChange
    cfg <- readMVar v
    let g = mkTests s
    (r, s) <- evalStateT (execGroup g) $ mkBook (getSender cfg) 
    putStrLn s
    case r of
      Pass -> do
        exitSuccess
      Fail _ -> do
        exitFailure

  mkSocket :: String -> S.PortNumber -> IO S.Socket
  mkSocket h p = do
    proto <- getProtocolNumber "tcp"
    sock  <- S.socket S.AF_INET S.Stream proto
    addr  <- S.inet_addr h
    S.bindSocket sock (S.SockAddrInet p addr)
    return sock

  testConnect :: S.Socket -> Sender TestResult
  testConnect s = do
    handleRequest $ RegMsg cid1 s
    b <- get
    case bookCons b of
      [] -> do
        return $ Fail "No Connection"
      [c] -> do
        return Pass

  testDisconnect :: Sender TestResult
  testDisconnect = do
    handleRequest $ UnRegMsg cid1
    b <- get
    case bookCons b of
      [] -> return Pass
      _  -> return $ Fail "Connection not removed"

  testSub :: String -> Int -> AckMode -> Sender TestResult
  testSub sid l a = 
    case mkSubscribe sid a of
      Left e -> return $ Fail "Could not make Subscription Frame"
      Right f -> do
        handleRequest $ FrameMsg cid1 f
        b <- get
        case bookSubs b of
          [] -> return $ Fail "Could not add Subscription"
          [s] -> 
            if l == 0 
              then checkQueue q1
              else return $ Fail "Could not add Subscription"
          s   -> 
            if length s == l + 1 
              then checkQueue q1
            else return $ Fail "Could not add Subscription"

  testUnSub :: String -> Int -> Sender TestResult
  testUnSub sid l =
    case mkUnSubscribe sid of
      Left e -> return $ Fail "Could not make Unsub Frame"
      Right f -> do
        handleRequest $ FrameMsg cid1 f
        b <- get
        case bookSubs b of
          [] -> do
            if l == 0 
             then do
               t <- checkQueue q1
               return $ neg t
             else return $ Fail "Could not unsubscribe"
          s  -> do
            if length s == l
              then checkQueue q1
              else return $ Fail "Could not unsubscribe"

  testSend :: Sender TestResult
  testSend = do
    case mkSend "" of
      Left e -> return $ Fail "Could not make Send Frame"
      Right f -> do
        handleRequest $ FrameMsg cid1 f
        mbM <- getLastMsg
        case mbM of
          Nothing -> return $ Fail "No Message inserted"
          Just m  -> do
            liftIO $ putStrLn $ "After Send: " ++ (show m)
            return Pass

  testAck :: Sender TestResult
  testAck = do
    mbM <- getLastMsg 
    case mbM of
      Nothing -> return $ Fail "No Message available"
      Just m  -> do
        let m'  = setState cid1 Sent m 
        liftIO $ putStrLn $ "Message: " ++ (show m')
        updMsg q1 m m'
        case mkAck $ strId m of 
          Left e  -> return $ Fail "Could not make Ack Frame"
          Right f -> do
            handleRequest $ FrameMsg cid1 f
            mbM2 <- getLastMsg
            case mbM2 of
              Nothing -> return Pass
              Just n  -> return $ Fail ("Message not acknowledged: " ++ (show n))

  testBegin :: Sender TestResult
  testBegin = do
    clearTx
    case mkBegin tid1 of
      Left  e  -> return $ Fail "Could not make Begin Frame"
      Right f  -> do
        handleRequest $ FrameMsg cid1 f
        txs <- getTxs
        case txs of 
          []  -> return $ Fail "Could not add Transaction"
          [t] -> return Pass 
          _   -> return $ Fail "Too many transactions!"

  testAbort :: Sender TestResult
  testAbort = 
    case mkAbort tid1 of
      Left  e -> return $ Fail "Could not make Abort Frame"
      Right f -> do
        handleRequest $ FrameMsg cid1 f
        txs <- getTxs
        case getTx tid1 txs of
          Nothing -> return Pass
          Just _  -> return $ Fail "Could not abort Transaction"

  testCommit :: Sender TestResult
  testCommit = 
    case mkCommit tid1 of
      Left e  -> return $ Fail "Could not make Commit Frame"
      Right f -> do
        txs <- getTxs
        case getTx (mkTxId cid1 tid1) txs of
          Nothing -> return $ Fail ("Transaction " ++ tid1 ++ " not found")
          Just t  -> do
            handleRequest $ FrameMsg cid1 f
            txs' <- getTxs
            case getTx tid1 txs' of
              Just _  -> return $ Fail "Could not commit transaction"
              Nothing -> do
                mbM <- getLastMsg
                case mbM of
                  Nothing -> return $ Fail "Message not sent"
                  Just m  -> return Pass

  testTxSend :: Sender TestResult
  testTxSend = do
    case mkSend tid1 of
      Left  e -> return $ Fail "Could not make Send Frame"
      Right f -> do
        handleRequest $ FrameMsg cid1 f
        ts <- getTxFrames
        case ts of
          []  -> do
            return $ Fail "Message not in Transaction"
          [f] -> do
            return Pass
          _   -> return $ Fail "Too many frames!"

  checkQueue :: String -> Sender TestResult
  checkQueue n = do
    b <- get
    let qs = bookQs b
    case getQueue n qs of
      Nothing -> return $ Fail ("Queue " ++ n ++ " not found")
      Just q  -> return Pass

  clearTx :: Sender ()
  clearTx = do
    b <- get
    case bookTrans b of
      [] -> return ()
      ts -> put b {bookTrans = []}

  getTxFrames :: Sender [Frame]
  getTxFrames = do
    b <- get
    case getTx (mkTxId cid1 tid1) $ bookTrans b of
      Nothing -> return []
      Just t  -> return $ txFrames t

  getTxs :: Sender [Transaction]
  getTxs = do
    b <- get
    return $ bookTrans b
        
  updMsg :: String -> MsgStore -> MsgStore -> Sender ()
  updMsg n m m' = do
    b <- get
    case getQueue n $ bookQs b of
      Nothing -> do
        liftIO $ putStrLn $ "Queue " ++ n ++ " not found."
        return ()
      Just q -> do
        let q' = q {qMsgs = insert m' $ delete m $ qMsgs q}
        put b {bookQs = insert q' $ delete q $ bookQs b}

  getLastMsg :: Sender (Maybe MsgStore)
  getLastMsg = do
    b <- get
    case bookQs b of
      [] -> return Nothing
      qs -> case qMsgs $ head qs of
              [] -> return Nothing
              ms -> return $ Just $ head ms

  mkConnect :: Either String Frame
  mkConnect = 
    mkConFrame [mkLogHdr  "guest",
                mkPassHdr "guest"] 

  mkSubscribe :: String -> AckMode -> Either String Frame
  mkSubscribe sid a =
    let ih = if null sid then [] else [mkIdHdr sid] 
    in  mkSubFrame (ih ++ [mkDestHdr q1,
                           mkAckHdr  (show a)])

  mkUnSubscribe :: String -> Either String Frame
  mkUnSubscribe sid =
    let hs = if null sid then [mkDestHdr q1]
                         else [mkIdHdr   sid]
    in  mkUSubFrame hs

  mkSend :: String -> Either String Frame
  mkSend tx = 
    let b  = B.pack "hello world"
        th = if null tx then [] else [mkTrnHdr tx]
    in  mkSndFrame ([mkDestHdr q1] ++ th)
                   (B.length b) b

  mkAck :: String -> Either String Frame
  mkAck mid = 
    mkAckFrame [mkMIdHdr mid]

  mkBegin :: String -> Either String Frame
  mkBegin tx = mkBgnFrame [mkTrnHdr tx]

  mkAbort :: String -> Either String Frame
  mkAbort tx = mkAbrtFrame [mkTrnHdr tx]

  mkCommit :: String -> Either String Frame
  mkCommit tx = mkCmtFrame [mkTrnHdr tx]
               
  dummyChange :: ChangeAction
  dummyChange _ = return ()

  
