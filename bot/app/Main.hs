{-# OPTIONS_GHC -fplugin=Polysemy.Plugin #-}

{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedLabels #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE ApplicativeDo #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE UndecidableInstances #-}

module Main (main) where

import Calamity
import Calamity.Cache.InMemory
import Calamity.Commands
import Calamity.Commands.Context (useFullContext, FullContext (FullContext))
import qualified Calamity.Interactions as I
import Calamity.Metrics.Noop
import Control.Concurrent
import Optics
import Control.Monad
import qualified Data.Text as T
import qualified Di
import qualified DiPolysemy as DiP
import qualified Polysemy as P
import qualified Polysemy.Async as P
import qualified Polysemy.State as P
import System.Environment (getEnv)
import TextShow
import Calamity.Utils.CDNUrl (assetHashFile)
import Calamity (RawEmoji)

data MyViewState = MyViewState
  { numOptions :: Int
  , selected :: Maybe T.Text
  }

$(makeFieldLabelsNoPrefix ''MyViewState)

main :: IO ()
main = do
  token <- T.pack <$> getEnv "BOT_TOKEN"
  Di.new $ \di ->
    void . P.runFinal . P.embedToFinal . DiP.runDiToIO di
      . runCacheInMemory
      . runMetricsNoop
      . useConstantPrefix "!"
      . useFullContext
      $ runBotIO (BotToken token) defaultIntents $ do
        addCommands $ do
          helpCommand
          -- just some examples

          command @'[User] "pfp" \ctx u -> do
            Right pfp <- fetchAsset (u ^. #avatar)
            let name = case u ^. #avatar % #hash of
                  Just hash -> assetHashFile hash
                  Nothing -> "default.png"
                file = CreateMessageAttachment name (Just "Your avatar") pfp
            void $ tell ctx file
          command @'[User] "utest" \ctx u -> do
            void . tell @T.Text ctx $ "got user: " <> showt u
          command @'[Named "u" User, Named "u1" User] "utest2" \ctx u u1 -> do
            void . tell @T.Text ctx $ "got user: " <> showt u <> "\nand: " <> showt u1
          command @'[T.Text, Snowflake User] "test" \_ctx something aUser -> do
            DiP.info $ "something = " <> showt something <> ", aUser = " <> showt aUser
          group "testgroup" $ do
            void $ command @'[[T.Text]] "test" \ctx l -> do
              void . tell @T.Text ctx $ "you sent: " <> showt l
            group "say" do
              command @'[KleenePlusConcat T.Text] "this" \ctx msg -> do
                void $ tell @T.Text ctx msg
          command @'[] "explode" \_ctx -> do
            Just _ <- pure Nothing
            DiP.debug @T.Text "unreachable!"
          command @'[] "bye" \ctx -> do
            void $ tell @T.Text ctx "bye!"
            stopBot

          command @'[[RawEmoji]] "reactpls" \ctx emojis -> do
            DiP.debug @T.Text ("emojis: " <> showt emojis)
            forM_ emojis \e ->
              invoke $ CreateReaction ctx ctx e

          -- views!

          command @'[] "components" \ctx -> do
            let view options = do
                  ~(add, done) <- I.row do
                    add <- I.button ButtonPrimary "add"
                    done <- I.button ButtonPrimary "done"
                    pure (add, done)
                  s <- I.select options
                  pure (add, done, s)
            let initialState = MyViewState 1 Nothing
            s <- P.evalState initialState $
              I.runView (view ["0"]) (tell ctx) \(add, done, s) -> do
                when add do
                  n <- P.gets (^. #numOptions)
                  let n' = n + 1
                  P.modify' (#numOptions .~ n')
                  let options = map (T.pack . show) [0 .. n]
                  I.replaceView (view options) (void . I.edit)

                when done do
                  finalSelected <- P.gets (^. #selected)
                  I.endView finalSelected
                  I.deleteInitialMsg
                  void . I.respond $ case finalSelected of
                    Just x -> "Thanks: " <> x
                    Nothing -> "Oopsie"

                case s of
                  Just s' -> do
                    P.modify' (#selected ?~ s')
                    void I.deferComponent
                  Nothing -> pure ()
            P.embed $ print s

          -- more views!

          command @'[] "cresponses" \ctx -> do
            let view = I.row do
                  a <- I.button ButtonPrimary "defer"
                  b <- I.button ButtonPrimary "deferEph"
                  c <- I.button ButtonPrimary "deferComp"
                  d <- I.button ButtonPrimary "modal"
                  pure (a, b, c, d)

                modalView = do
                  a <- I.textInput TextInputShort "a"
                  b <- I.textInput TextInputParagraph "b"
                  pure (a, b)

            I.runView view (tell ctx) $ \(a, b, c, d) -> do
              when a do
                void I.defer
                P.embed $ threadDelay 1000000
                void $ I.followUp @T.Text "lol"

              when b do
                void I.deferEphemeral
                P.embed $ threadDelay 1000000
                void $ I.followUpEphemeral @T.Text "lol"

              when c do
                void I.deferComponent
                P.embed $ threadDelay 1000000
                void $ I.followUp @T.Text "lol"

              when d do
                void . P.async $ do
                  I.runView modalView (void . I.pushModal "lol") $ \(a, b) -> do
                    P.embed $ print (a, b)
                    void $ I.respond ("Thanks: " <> a <> " " <> b)
                    I.endView ()

              pure ()

        react @( 'CustomEvt (CtxCommandError FullContext)) \(CtxCommandError ctx e) -> do
          DiP.info $ "Command failed with reason: " <> showt e
          case e of
            ParseError n r ->
              void . tell ctx $
                "Failed to parse parameter: " <> codeline n
                  <> ", with reason: "
                  <> codeblock' Nothing r
            CheckError n r ->
              void . tell ctx $
                "The following check failed: " <> codeline n
                  <> ", with reason: "
                  <> codeblock' Nothing r
            InvokeError n r ->
              void . tell ctx $
                "The command: " <> codeline n
                  <> ", failed with reason: "
                  <> codeblock' Nothing r
