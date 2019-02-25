-- | Types for the http lib

module YAHDL.HTTP.Types
  ( RestError(..)
  , RateLimitState(..)
  , DiscordResponseType(..)
  , GatewayResponse
  , BotGatewayResponse
  )
where

import           Data.Aeson
import qualified StmContainers.Map             as SC
import           Control.Concurrent.STM.Lock    ( Lock )
import           Control.Concurrent.Event       ( Event )

import           YAHDL.HTTP.Route


data RestError
  = HTTPError { status :: Int
              , response :: Maybe Value
              }
  | DecodeError
  deriving (Show, Generic)

data RateLimitState = RateLimitState
  { rateLimits :: SC.Map Route Lock
  , globalLock :: Event
  } deriving (Generic)

data DiscordResponseType
  -- | A good response
  = Good Value
  -- | We got a response but also exhausted the bucket
  | ExhaustedBucket Value
    Int -- ^ Retry after (milliseconds)
  -- | We hit a 429, no response and ratelimited
  | Ratelimited
    Int -- ^ Retry after (milliseconds)
    Bool -- ^ Global ratelimit
  -- | Discord's error, we should retry (HTTP 5XX)
  | ServerError Int
  -- | Our error, we should fail
  | ClientError Int Value

data GatewayResponse = GatewayResponse
  { url :: Text
  } deriving (Generic, Show)

instance FromJSON GatewayResponse where
  parseJSON = genericParseJSON jsonOptions

data BotGatewayResponse = BotGatewayResponse
  { url    :: Text
  , shards :: Int
  } deriving (Generic, Show)

instance FromJSON BotGatewayResponse where
  parseJSON = genericParseJSON jsonOptions
