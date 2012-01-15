module Service (
          Service, srvContext, srvName, srvId,
          stop, pause, resume, appCmd,
          withService, poll, xpoll, XPoll(..),
          periodic, periodicSend, 
          Timeout, Millisecond, Identifier)
where

  import           Factory

  import qualified Data.ByteString.Char8 as B
  import           Data.Time.Clock
  import           Data.Map (Map)

  import           Control.Concurrent 
  import           Control.Applicative ((<$>))
  import           Control.Monad
  import           Prelude hiding (catch)
  import           Control.Exception (bracket, finally)
  import qualified System.ZMQ as Z

  ------------------------------------------------------------------------
  -- | Generic Service data type
  ------------------------------------------------------------------------
  data Service = Service {
                   srvCtx    :: Z.Context,
                   -- | Obtains the service name
                   srvName   :: String,
                   srvCmd    :: Z.Socket Z.Pub,
                   srvId     :: ThreadId
                 }

  ------------------------------------------------------------------------
  -- | Obtains the 'Z.Context' from 'Service'
  ------------------------------------------------------------------------
  srvContext :: Service -> Z.Context
  srvContext = srvCtx

  stop  :: Service -> IO ()
  stop = sendCmd STOP

  ------------------------------------------------------------------------
  -- | Pauses the 'Service'
  ------------------------------------------------------------------------
  pause :: Service -> IO ()
  pause = sendCmd PAUSE

  ------------------------------------------------------------------------
  -- | Resumes the 'Service'
  ------------------------------------------------------------------------
  resume :: Service -> IO ()
  resume = sendCmd RESUME

  ------------------------------------------------------------------------
  -- | Changes the 'Service' control parameter
  ------------------------------------------------------------------------
  appCmd :: String -> Service -> IO ()
  appCmd s = sendCmd $ APP s

  data Command = STOP | PAUSE | RESUME | APP String
    deriving (Eq, Show, Read)

  sendCmd :: Command -> Service -> IO ()
  sendCmd c s = Z.send (srvCmd s) (B.pack $ show c) []

  readCmd :: String -> Either String Command
  readCmd s = case s of
               "STOP"   -> Right STOP
               "PAUSE"  -> Right PAUSE
               "RESUME" -> Right RESUME
               x        -> if take 4 x == "APP " 
                             then Right $ APP (drop 4 x)
                             else Left  $ "No Command: " ++ x

  withService :: Z.Context -> String -> String -> 
                (Z.Context -> String -> String -> String -> IO ()) -> 
                (Service -> IO ()) -> IO ()
  withService ctx name param service action = do
    m <- newEmptyMVar
    Z.withSocket ctx Z.Pub $ \cmd -> do
      sn <- ("inproc://srv_" ++) <$> show <$> mkUniqueId
      Z.bind cmd sn
      bracket (start sn cmd m) stop action
    takeMVar m
    where start sn cmd m = do
            tid <- forkIO $ (service ctx name sn param) `finally` (putMVar m ())
            return $ Service ctx name cmd tid

  poll :: Bool -> [Z.Poll] -> (String -> IO ()) -> String -> IO ()
  poll paused poller rcv param 
    | paused    = handleCmd paused poller rcv param
    | otherwise = do  
        [c, s] <- Z.poll poller (-1)
        case c of 
          Z.S _ Z.In -> handleCmd paused poller rcv param
          _          -> 
            case s of
              Z.S _ Z.In -> rcv param >> poll paused poller rcv param
              _          ->              poll paused poller rcv param

  handleCmd :: Bool -> [Z.Poll] -> (String -> IO ()) -> String -> IO ()
  handleCmd paused poller@[Z.S sock _, _] rcv param = do
    x <- Z.receive sock []
    case readCmd $ B.unpack x of
      Left  _   -> poll paused poller rcv param 
      Right cmd -> case cmd of
                     STOP   -> return ()
                     PAUSE  -> poll True   poller rcv param
                     RESUME -> poll False  poller rcv param
                     APP p  -> poll paused poller rcv p
  handleCmd _ _ _ _ = ouch "invalid poller in 'handleCmd'!"

  type Identifier = String
  type Timeout    = Z.Timeout

  data XPoll = XPoll {
                 xpTmo   :: Timeout,
                 xpMap   :: Map Identifier Z.Poll,
                 xpIds   :: [Identifier],
                 xpPoll  :: [Z.Poll]
               }

  xpoll :: Bool -> XPoll -> 
           (String -> IO ()) ->
           (XPoll -> Identifier -> Z.Poll -> String -> IO ()) -> String -> IO ()
  xpoll paused xp ontmo rcv param 
    | paused    = handleCmdX paused xp ontmo rcv param
    | otherwise = do
        (c:ss) <- Z.poll (xpPoll xp) (xpTmo xp)
        case c of 
          Z.S _ Z.In -> handleCmdX paused xp ontmo rcv param
          _          -> go (xpIds xp) ss
    where go _      []     = xpoll paused xp ontmo rcv param
          go (i:is) (s:ss) =
            case s of
              Z.S _ Z.In -> rcv xp i s param >>
                            xpoll paused xp ontmo rcv param
              _          -> go is ss
          go _      _     = error "Ouch!"

  handleCmdX :: Bool -> XPoll -> 
                (String -> IO ()) -> 
                (XPoll -> Identifier -> Z.Poll -> String -> IO ()) -> String -> IO ()
  handleCmdX paused xp ontmo rcv param = 
    case xpPoll xp of 
      (Z.S sock _ : _) -> do
        x <- Z.receive sock []
        case readCmd $ B.unpack x of
          Left _    -> xpoll paused xp ontmo rcv param
          Right cmd -> case cmd of
                         STOP   -> return ()
                         PAUSE  -> xpoll True   xp ontmo rcv param
                         RESUME -> xpoll False  xp ontmo rcv param
                         APP p  -> xpoll paused xp ontmo rcv p
      _ -> ouch "invalid poller in 'handleCmdX'!"

  periodicSend :: Bool -> Millisecond -> Z.Socket Z.Sub -> (String -> IO ()) -> String -> IO ()
  periodicSend paused period cmd send param = do
    release <- getCurrentTime
    periodicSend_ paused period release cmd send param

  periodicSend_ :: Bool -> Millisecond -> UTCTime -> Z.Socket Z.Sub -> (String -> IO ()) -> String -> IO ()
  periodicSend_ paused period release cmd send param
    | paused    = handleCmdSnd True period release cmd send param 
    | otherwise = send param >> handleCmdSnd paused period release cmd send param 

  handleCmdSnd :: Bool -> Millisecond -> UTCTime -> Z.Socket Z.Sub -> (String -> IO ()) -> String -> IO ()
  handleCmdSnd paused period release sock send param = do
    [Z.S _ evt] <- Z.poll [Z.S sock Z.In] 0
    case evt of 
      Z.In   -> do
        x        <- Z.receive sock []
        release' <- waitNext period release
        case readCmd $ B.unpack x of
          Left  _   -> periodicSend_ paused period release' sock send param
          Right cmd -> 
            case cmd of
              STOP   -> return ()
              PAUSE  -> periodicSend_ True   period release' sock send param
              RESUME -> periodicSend_ False  period release' sock send param
              APP p  -> periodicSend_ paused period release' sock send p
      _ -> do
        release' <- waitNext period release
        periodicSend_ paused period release' sock send param

  ouch :: String -> a
  ouch s = error $ "Ouch! You hit a bug, please report: " ++ s

  periodic :: Int -> IO () -> IO ()
  periodic period act = getCurrentTime                 >>= go
    where go release  = act >> waitNext period release >>= go 

  waitNext :: Int -> UTCTime -> IO UTCTime
  waitNext period release = do
     now <- getCurrentTime
     let next = release `timeAdd` period
     if (now `timeAdd` 10) >= next
       then return now
       else do
         let sleepTime = next `diffUTCTime` now
         threadDelay (1000 * nominal2ms sleepTime)
         getCurrentTime

  timeAdd :: UTCTime -> Int -> UTCTime
  timeAdd t p = ms2nominal p `addUTCTime` t

  ms2nominal :: Int -> NominalDiffTime
  ms2nominal m = fromIntegral m / (1000::NominalDiffTime)

  nominal2ms :: NominalDiffTime -> Int
  nominal2ms n = ceiling (n * (fromIntegral (1000::Int)))

  type Millisecond = Int
