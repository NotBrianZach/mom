{-# LANGUAGE DeriveDataTypeable #-}
module Network.Mom.Patterns.Broker.Common
where

  import           Network.Mom.Patterns.Streams.Streams
  import           Network.Mom.Patterns.Streams.Types

  import qualified Data.ByteString.Char8  as B
  import qualified Data.ByteString        as BB
  import           Data.Word
  import           Data.Typeable (Typeable)
  import qualified Data.Conduit as C
  import qualified Data.Conduit.List as CL
  import           Control.Monad (unless)
  import           Control.Monad.Trans (liftIO)
  import           Control.Exception (throwIO)
  import           Control.Applicative ((<$>))

  mdpC01, mdpW01 :: B.ByteString
  mdpC01 = B.pack "MDPC01"
  mdpW01 = B.pack "MDPW01"

  xReady, xRequest, xReply, xHeartBeat, xDisc :: B.ByteString
  xReady     = BB.pack [0x01]
  xRequest   = BB.pack [0x02]
  xReply     = BB.pack [0x03]
  xHeartBeat = BB.pack [0x04]
  xDisc      = BB.pack [0x05]

  type ServiceName = String

  mdpCSndReq :: ServiceName -> Conduit B.ByteString ()
  mdpCSndReq sn = mapM_ C.yield [B.empty, mdpC01, B.pack sn] >> passThrough

  mdpCRcvReq :: Conduit o (Identity, B.ByteString)
  mdpCRcvReq = do i <- identity
                  protocol
                  sn <- getChunk 
                  return (i, sn)
    where  protocol = chunk mdpC01 "Unknown Protocol - expected Client 0.1"

  mdpCSndRep :: B.ByteString -> [Identity] -> Conduit B.ByteString ()
  mdpCSndRep sn is = mapM_ C.yield hdr >> passThrough
    where hdr = toIs is ++ [mdpC01, sn]

  mdpCRcvRep :: ServiceName -> Conduit B.ByteString ()
  mdpCRcvRep sn = empty >> protocol >> serviceName >> passThrough
    where protocol    = chunk mdpC01 "Unknown Protocol - expected Client 0.1"
          serviceName = chunk (B.pack sn) ("Wrong service - expected: " ++ sn)

  mdpWSndReq :: Identity -> [Identity] -> Conduit B.ByteString ()
  mdpWSndReq w is = mapM_ C.yield hdr >> passThrough
    where hdr = [w, B.empty, mdpW01, xRequest] ++ toIs is ++ [B.empty]

  mdpWRcvReq :: Conduit o WFrame
  mdpWRcvReq = do 
    empty >> protocol
    t <- frameType
    case t of
      HeartBeatT  -> return $ WBeat B.empty
      DisconnectT -> return $ WDisc B.empty
      RequestT    -> WRequest <$> envelope
      x           -> liftIO $ throwIO $ ProtocolExc $
                       "Unexpected Frame from Broker: " ++ show x
    where protocol = chunk mdpW01 ("Unknown Protocol from Broker " ++
                                   " -- expected: Worker 0.1")

  mdpWSndRep :: [Identity] -> Conduit B.ByteString ()
  mdpWSndRep  is = propagateList (hdr is) >> passThrough
    where hdr is = [B.empty, -- identity delimiter
                    mdpW01,
                    xReply] ++ toIs is ++ [B.empty]
 
  mdpWRcvRep :: Conduit o WFrame
  mdpWRcvRep = do
    w <- identity
    protocol
    t <- frameType
    case t of
      HeartBeatT  -> return $ WBeat w
      DisconnectT -> return $ WDisc w
      ReadyT      -> WReady w <$> getSrvName
      ReplyT      -> getRep w
      x           -> liftIO $ throwIO $ ProtocolExc $
                       "Unexpected Frame from Worker: " ++ show x
    where protocol   = chunk mdpW01 "Unknown Protocol from Worker"
          getSrvName = getChunk
          getRep w   = do is <- envelope
                          return $ WReply w is 

  -- to be done:
  -- receive either client or worker request
  {-
  mdpXRcvReq :: ServiceName -> Conduit o Request
  mdpXRcvReq sn = do empty 
                     p <- getChunk
                     getTheRest p
    where getTheRest p | p == mdpW01 = mdpWRcvReq
                       | p == mdpC01 = mdpCRcvReq 
                       | otherwise   = liftIO (throwIO $ ProtocolExc $
                                                 "Unknown protocol: " ++ 
                                                 B.unpack p)

  data Request = CReq Identity B.ByteString
               | WReq WFrame
  -}

  mdpWBeat :: Conduit B.ByteString ()
  mdpWBeat = propagateList beat
    where beat = [B.empty,
                  mdpW01,
                  xHeartBeat]


  mdpWConnect :: ServiceName -> Source
  mdpWConnect sn = streamList [B.empty, -- identity delimiter
                               mdpW01, 
                               xReady, 
                               B.pack sn]
  mdpWDisconnect :: Source
  mdpWDisconnect = streamList [B.empty, -- identity delimiter
                               mdpW01,
                               xDisc]


  ------------------------------------------------------------------------
  -- Worker frames
  ------------------------------------------------------------------------
  data WFrame = WBeat    Identity
              | WReady   Identity B.ByteString
              | WReply   Identity [Identity]
              | WRequest          [Identity]
              | WDisc    Identity
    deriving (Eq, Show)


  data FrameType = ReadyT | RequestT | ReplyT | HeartBeatT | DisconnectT
    deriving (Eq, Show, Read)

  frameType :: Conduit o FrameType
  frameType = do
    mbT <- C.await
    case mbT of
      Nothing -> liftIO (throwIO $ ProtocolExc 
                           "Incomplete Message: No Frame Type")
      Just t  | t == xHeartBeat -> return HeartBeatT
              | t == xReady     -> return ReadyT
              | t == xReply     -> return ReplyT
              | t == xDisc      -> return DisconnectT
              | t == xRequest   -> return RequestT
              | otherwise       -> liftIO (throwIO $ ProtocolExc $ 
                                     "Unknown Frame: " ++ B.unpack t)

  identity :: Conduit o Identity
  identity = do
    mbI <- C.await
    case mbI of
      Nothing -> liftIO (throwIO $ ProtocolExc 
                           "Incomplete Message: No Identity")
      Just i  | B.null i  -> 
                  liftIO (throwIO $ ProtocolExc 
                           "Incomplete Message: Empty Identity")
              | otherwise -> empty >> return i

  envelope :: Conduit o [Identity]
  envelope = go []
    where go is = do
            mbI <- C.await
            case mbI of
              Nothing -> liftIO (throwIO $ ProtocolExc 
                                   "Incomplete Message: No Identity")
              Just i  | B.null i  -> 
                          if null is 
                            then liftIO (throwIO $
                                   ProtocolExc  
                                      "Incomplete Message: No identities")
                            else return is
                      | otherwise -> empty >> go (i:is) 

  toIs :: [Identity] -> [B.ByteString]
  toIs = foldr toI []
    where toI i is  = [i, B.empty] ++ is