{-# LANGUAGE DeriveDataTypeable #-}
-------------------------------------------------------------------------------
-- |
-- Module     : Network/Mom/Stompl/Client/Exception.hs
-- Copyright  : (c) Tobias Schoofs
-- License    : LGPL 
-- Stability  : experimental
-- Portability: portable
--
-- Exceptions for the Stompl Client
-------------------------------------------------------------------------------
module Network.Mom.Stompl.Client.Exception (
                          StomplException(..), try, convertError)
where

  import Control.Exception hiding (try)
  import Control.Applicative ((<$>))
  import Data.Typeable (Typeable)

  ------------------------------------------------------------------------
  -- | The Stompl Client uses exceptions to communicate errors
  --   to the user application.
  ------------------------------------------------------------------------
  data StomplException =
                       -- | Currently not used
                       SocketException   String
                       -- | Thrown
                       --   when a worker thread terminates
                       --   unexpectedly;
                       --   usually, this is a consequence 
                       --   of another error (/e.g./ the broker
                       --   closed the socket) and you will
                       --   probably receive another exception
                       --   (/e.g./ a BrokerException)
                       | WorkerException String
                       -- | Thrown when something 
                       --   against the protocol happens, /e.g./
                       --   an unexpected frame is received
                       --   or a message from a queue
                       --   that was not subscribed
                       | ProtocolException String
                       -- | Thrown on wrong uses of queues, /e.g./
                       --   use of a queue outside its scope
                       | QueueException    String
                       -- | Thrown on transaction errors, /e.g./
                       --   pending acks
                       | TxException       String
                       -- | Thrown on connection errors, /e.g./
                       --   connection was disconnected
                       | ConnectException  String
                       -- | Should be thrown 
                       --   by user-defined converters
                       | ConvertException  String
                       -- | Thrown when an error frame is received
                       | BrokerException   String
                       -- | Thrown by /abort/
                       | AppException      String
                       -- | You hit a bug!
                       --   This exception is only thrown
                       --   when something really strange happened
                       | OuchException     String
    deriving (Show, Read, Typeable, Eq)

  instance Exception StomplException

  ------------------------------------------------------------------------
  -- | Catches any 'StomplException',
  --   including asynchronous exceptions coming from internal threads
  ------------------------------------------------------------------------
  try :: IO a -> IO (Either StomplException a)
  try act = (Right <$> act) `catch` (return . Left)

  ------------------------------------------------------------------------
  -- | Throws 'ConvertException'
  --   to signal a conversion error.
  ------------------------------------------------------------------------
  convertError :: String -> IO a
  convertError e = throwIO $ ConvertException e

