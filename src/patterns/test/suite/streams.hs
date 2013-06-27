module Main
where

  import           Common
  import           System.Exit
  import qualified System.ZMQ as Z
  import           Test.QuickCheck
  import qualified Data.ByteString.Char8 as B
  import           Data.List (sort)
  import qualified Data.Conduit as C
  import qualified Data.Conduit.List as CL
  import           Data.Conduit (($=), ($$), (=$))
  import           Control.Applicative ((<$>))
  import           Control.Concurrent
  import           Control.Monad.Trans (liftIO)
  import           Control.Exception (try, throwIO, SomeException)

  import           Network.Mom.Patterns.Streams.Types
  import           Network.Mom.Patterns.Streams.Streams


  isock,osock :: String
  isock = "inproc://_in"
  osock = "inproc://_out"
  osock1, osock2, osock3, osock4, osock5, osock6 :: String
  osock1 = "inproc://_out1"
  osock2 = "inproc://_out2"
  osock3 = "inproc://_out3"
  osock4 = "inproc://_out4"
  osock5 = "inproc://_out5"
  osock6 = "inproc://_out6"

  prpStreamList :: NonEmptyList String -> Property
  prpStreamList (NonEmpty s) = testContext s $ \_ -> 
    try $ map B.unpack <$> C.runResourceT (
          streamList (map B.pack s) $$ CL.consume)

  prpPassThrough1_ :: NonEmptyList String -> Property
  prpPassThrough1_ (NonEmpty s) = testContext s $ \_ -> 
    try $ map B.unpack <$> C.runResourceT (
          streamList (map B.pack s) $= passThrough $$ CL.consume)

  prpPassThrough_1 :: NonEmptyList String -> Property
  prpPassThrough_1 (NonEmpty s) = testContext s $ \_ -> 
    try $ map B.unpack <$> C.runResourceT (
          streamList (map B.pack s) $$ passThrough =$ CL.consume)

  prpPassThrough2 :: NonEmptyList String -> Property
  prpPassThrough2 (NonEmpty s) = testContext s $ \_ -> 
    try $ map B.unpack <$> C.runResourceT (
          streamList (map B.pack s) $= passThrough $$ passThrough =$ CL.consume)

  prpPassOne1 :: NonEmptyList Char -> Property
  prpPassOne1 (NonEmpty s) = testContext s $ \ctx -> 
    withStreams ctx "passOne1" (-1) 
                [Poll "in"  isock ServerT Bind [] [],
                 Poll "out" osock ClientT Bind [] []]
                ignoreTmo onErr job $ \_ -> 
                  Z.withSocket ctx Z.Req $ \c -> do
                    Z.connect c isock 
                    Z.withSocket ctx Z.Rep $ \srv -> do
                      Z.connect srv osock 
                      Z.send c (B.pack s) []
                      (Right . B.unpack) <$> Z.receive srv []
    where job x = pass1 x ["out"]

  prpPassOne :: NonEmptyList String -> Property
  prpPassOne (NonEmpty ss) = testContext [head ss] $ \ctx -> 
    withStreams ctx "passOne" (-1) 
                [Poll "in"  isock ServerT Bind [] [],
                 Poll "out" osock ClientT Bind [] []]
                ignoreTmo onErr job $ \_ -> 
                  Z.withSocket ctx Z.Req $ \c -> do
                    Z.connect c isock 
                    Z.withSocket ctx Z.Rep $ \s -> do
                      Z.connect s osock 
                      sendAll c (map B.pack ss)
                      (Right . map B.unpack) <$> recvAll s
    where job s = pass1 s ["out"]

  prpPassAll :: NonEmptyList String -> Property
  prpPassAll (NonEmpty ss) = testContext ss $ \ctx -> 
    withStreams ctx "passAll" (-1) 
                [Poll "in"  isock ServerT Bind [] [],
                 Poll "out" osock ClientT Bind [] []]
                ignoreTmo onErr job $ \_ -> 
                  Z.withSocket ctx Z.Req $ \c -> do
                    Z.connect c isock 
                    Z.withSocket ctx Z.Rep $ \s -> do
                      Z.connect s osock 
                      sendAll c (map B.pack ss)
                      (Right . map B.unpack) <$> recvAll s
    where job s = passThrough =$ passAll s ["out"]

  prpMultiOut :: NonEmptyList String -> Property
  prpMultiOut (NonEmpty ss) = testContext ["out1", "out2", "out4"] $ \ctx ->
    withStreams ctx "MultiOut" (-1) 
                [Poll "in"   isock  ServerT Bind [] [],
                 Poll "out1" osock1 ClientT Bind [] [],
                 Poll "out2" osock2 ClientT Bind [] [],
                 Poll "out3" osock3 ClientT Bind [] [],
                 Poll "out4" osock4 ClientT Bind [] [],
                 Poll "out5" osock5 ClientT Bind [] [],
                 Poll "out6" osock6 ClientT Bind [] []]
                ignoreTmo onErr job $ \_ -> 
                  Z.withSocket ctx Z.Req $ \c -> do
                    Z.connect c isock
                    m <- newMVar []
                    withStreams ctx "test" (-1)
                      [Poll "out1" osock1 ServerT Connect [] [],
                       Poll "out2" osock2 ServerT Connect [] [],
                       Poll "out3" osock3 ServerT Connect [] [],
                       Poll "out4" osock4 ServerT Connect [] [],
                       Poll "out5" osock5 ServerT Connect [] [],
                       Poll "out6" osock6 ServerT Connect [] []]
                      ignoreTmo onErr (tester m) $ \_ -> do
                        sendAll c (map B.pack ss)
                        threadDelay 10000
                        Right . sort <$> readMVar m
    where job s = passAll s ["out1", "out2", "out4"]
          tester m s = liftIO (modifyMVar_ m $ \l -> 
                                   return (getSource s:l))
                       >> ignoreStream

  prpRecvControl :: NonEmptyList String -> Property
  prpRecvControl (NonEmpty ss) = testContext ss $ \ctx -> 
    withStreams ctx "passAll" (-1) 
                [Poll "in"  isock ServerT Bind [] [],
                 Poll "out" osock ClientT Bind [] []]
                ignoreTmo onErr job $ \r -> 
                  Z.withSocket ctx Z.Req $ \c -> do
                    Z.connect c isock 
                    sendAll c (map B.pack ss)
                    mbR <- receive r 10000 (Just <$> CL.consume)
                    case mbR of 
                      Nothing -> throwIO $ ProtocolExc "Nothing received"
                      Just  x -> return $ Right $ map B.unpack x
    where job s = passAll s [internal]
 
  prpSendControl :: NonEmptyList String -> Property
  prpSendControl (NonEmpty ss) = testContext ss $ \ctx -> 
    withStreams ctx "passAll" (-1) 
                [Poll "in"  isock ServerT Bind [] [],
                 Poll "out" osock ClientT Bind [] []]
                ignoreTmo onErr job $ \c -> 
                  Z.withSocket ctx Z.Rep $ \r -> do
                    Z.connect r osock 
                    send c ["out"] (streamList $ map B.pack ss)
                    (Right . map B.unpack) <$> recvAll r 
    where job s = passAll s ["in"]

  testStreams :: Context    -> [String]   ->
                 AccessType -> AccessType -> 
                 Z.Socket a -> Z.Socket b ->
                 IO (Either SomeException [String])
  testStreams ctx ss one two s1 s2 = 
    withStreams ctx "passAll" (-1) 
                [Poll "in"  isock one Bind [""] [],
                 Poll "out" osock two Bind [] []]
                ignoreTmo onErr job $ \_ -> do
                    Z.connect s1 isock 
                    Z.connect s2 osock 
                    sendAll s1 (map B.pack ss)
                    (Right . map B.unpack) <$> recvAll s2
    where job s = passAll s ["out"]

  prpPubSub :: NonEmptyList String -> Property
  prpPubSub (NonEmpty ss) = testContext ss $ \ctx -> 
    Z.withSocket ctx Z.Pub $ \p ->
      Z.withSocket ctx Z.Sub $ \s -> do
        Z.subscribe s ""
        testStreams ctx ss SubT PubT p s

  prpPushPull :: NonEmptyList String -> Property
  prpPushPull (NonEmpty ss) = testContext ss $ \ctx -> 
    Z.withSocket ctx Z.Push $ \p ->
      Z.withSocket ctx Z.Pull $ \s -> 
        testStreams ctx ss PullT PipeT p s

  prpPeerPeer :: NonEmptyList String -> Property
  prpPeerPeer (NonEmpty ss) = testContext ss $ \ctx -> 
    Z.withSocket ctx Z.Pair $ \p ->
      Z.withSocket ctx Z.Pair $ \s -> 
        testStreams ctx ss PeerT PeerT p s

  prpDealerDealer :: NonEmptyList String -> Property
  prpDealerDealer (NonEmpty ss) = testContext ss $ \ctx -> 
    Z.withSocket ctx Z.Dealer $ \p ->
      Z.withSocket ctx Z.Dealer $ \s -> 
        testStreams ctx ss DealerT DealerT p s

  -- pass with
  -- - Router/Dealer <--
  -- Timeout is called
  -- OnError is called with 
  --   - Fatal
  --   - Critical 
  --   - Error

  -- pause streams
  -- resume streams
  -- pause 1 stream
  -- resume 1 stream
  -- remove stream
  -- change timeout
  -- stop streams

  {-
  prpAddStream :: NonEmptyList String -> Property
  prpAddStream (NonEmpty ss) = testContext ss $ \ctx ->
    try $ withStreams ctx "Test" (-1) 
                [Poll "in"  isock ServerT Bind [] []]
                ignoreTmo onErr job $ \x -> 
      Z.withSocket ctx Z.Req $ \c ->
        Z.withSocket ctx Z.Rep $ \s -> do
          Z.connect c isock
          Z.bind    s osock
          addStream x "out" osock ClientT Connect [] []
          sendAll c (map B.pack ss) 
          (map B.unpack) <$> recvAll s 
    where job s = let trgs = filterStreams s (/= "in")
                   in passAll s trgs
  -}
          
  checkAll :: IO ()
  checkAll = do
    let good = "OK. All Tests passed."
    let bad  = "Bad. Some Tests failed."
    putStrLn "========================================="
    putStrLn "       Patterns Library Test Suite"
    putStrLn "                 Streams"
    putStrLn "========================================="
    r <- runTest "Stream list"
                  (deepCheck prpStreamList)        ?>
         runTest "passThrough1_"
                  (deepCheck prpPassThrough1_)     ?>
         runTest "passThrough_1"
                  (deepCheck prpPassThrough_1)     ?>
         runTest "passThrough2"
                  (deepCheck prpPassThrough2)      ?> 
         runTest "Pass one passes one"
                  (deepCheck prpPassOne1)          ?>
         runTest "Pass one passes one with many"
                  (deepCheck prpPassOne)           ?>
         runTest "Pass all passes all"
                  (deepCheck prpPassAll)           ?>
         runTest "Pass to exactly all out streams"
                  (deepCheck prpMultiOut)          ?> 
         runTest "Pub-Sub"
                  (deepCheck prpPubSub)            ?>
         runTest "Push-Pull"
                  (deepCheck prpPushPull)          ?>
         runTest "Peer-Peer"
                  (deepCheck prpPeerPeer)          ?> 
         runTest "Receive through Control"
                  (deepCheck prpRecvControl)       ?>
         runTest "Send through Control"
                  (deepCheck prpSendControl) 

         {-
         runTest "Timeout" (oneCheck prp_onTmo)      ?>
         runTest "Error" (deepCheck prp_onErr)       ?> 
         runTest "Parameter" (deepCheck prp_Param)   ?> 
         runTest "Start/Pause" (deepCheck prp_Pause) ?> 
         runTest "add"         (deepCheck prp_add)
         -}
    case r of
      Success {} -> do
        putStrLn good
        exitSuccess
      _ -> do
        putStrLn bad
        exitFailure

  main :: IO ()
  main = checkAll
