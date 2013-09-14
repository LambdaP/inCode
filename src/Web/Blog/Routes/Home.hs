{-# LANGUAGE OverloadedStrings #-}

module Web.Blog.Routes.Home (routeHome) where

import Control.Monad.IO.Class
import Control.Monad.State
import Web.Blog.Database
import Web.Blog.Models
import Web.Blog.Models.Util
import Web.Blog.Render
import Config.SiteData
import Web.Blog.Types
import Web.Blog.Views.Home
import qualified Data.Map                    as M
import qualified Data.Text                   as T
import qualified Database.Persist.Postgresql as D

routeHome :: Int -> RouteEither
routeHome page = do
  let
    m = appPrefsHomeEntries $ siteDataAppPrefs siteData

  maxPage' <- liftIO $ runDB $ maxPage m

  if page < 1 || page > maxPage'
    then
      return $ Left "/"
    else do
      let
        pageTitle =
          if page == 1
            then
              Nothing
            else
              Just $ T.concat ["Home (Page ", T.pack $ show page,")"]

        urlBase = renderUrl' "/home/"

      eList <- liftIO $ runDB $
        postedEntries [ D.Desc EntryPostedAt
                      , D.LimitTo m
                      , D.OffsetBy $ (page - 1) * m ]
          >>= mapM wrapEntryData

      blankPageData <- genPageData

      let
        pdMap = execState $ do
          when (page > 1) $ do
            let
              prevUrl = if page == 1
                then renderUrl' "/"
                else T.append urlBase $ T.pack $ show $ page - 1
            modify $
              M.insert "prevPage" prevUrl
            modify $
              M.insert "pageNum" $ T.pack $ show page


          when (page < maxPage') $
            modify $
              M.insert "nextPage" (T.append urlBase $ T.pack $ show $ page + 1)

        view = viewHome eList page
        pageData = blankPageData { pageDataTitle = pageTitle
                                 , pageDataCss   = ["/css/page/home.css"
                                                   ,"/css/pygments.css"]
                                 , pageDataJs    = ["/js/disqus_count.js"]
                                 , pageDataMap   = pdMap M.empty
                                 }

      return $ Right (view, pageData)

maxPage :: Int -> D.SqlPersistM Int
maxPage perPage = do
  c <- postedEntryCount
  return $ (c + perPage - 1) `div` perPage
