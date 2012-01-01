module Main 
where

  import           Network.Mom.Patterns
  import qualified System.ZMQ as Z
  import qualified Data.ByteString.Char8 as B
  import           Control.Exception

  main :: IO ()
  main = Z.withContext 1 $ \ctx -> do
    let ap = Address "tcp://localhost:5555" []
    withClient ctx ap (return . B.pack) (return . B.unpack) $ \c -> do
      ei <- request c (enum "test") (toString "\n")
      case ei of
        Left  e -> putStrLn $ "Error: " ++ show (e::SomeException)
        Right t -> putStrLn t
    where enum = once (return . Just)
