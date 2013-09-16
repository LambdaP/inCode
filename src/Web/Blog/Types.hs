module Web.Blog.Types (
    SiteData(..)
  , SiteEnvironment(..)
  , HostConfig(..)
  , DeveloperAPIs(..)
  , AuthorInfo(..)
  , AppPrefs(..)
  , DatabaseConfig(..)
  , SiteRender
  , PageDataMap
  , PageData(..)
  , RouteEither
  , error404
  ) where

import Control.Monad.Reader
import qualified Data.Map         as M
import qualified Data.Text        as T
import qualified Data.Text.Lazy   as L
import qualified Text.Blaze.Html5 as H
import qualified Web.Scotty       as S

data SiteData = SiteData
                { siteDataTitle           :: T.Text
                , siteDataAuthorInfo      :: AuthorInfo
                , siteDataDescription     :: T.Text
                , siteDataCopyright       :: T.Text
                , siteDataPublicBlobs     :: Maybe T.Text
                , siteDataHostConfig      :: HostConfig
                , siteDataDeveloperAPIs   :: DeveloperAPIs
                , siteDataAppPrefs        :: AppPrefs
                , siteDataDatabaseConfig  :: Maybe DatabaseConfig
                , siteDataSiteEnvironment :: SiteEnvironment
                }

data SiteEnvironment = SiteEnvironmentProduction | SiteEnvironmentDevelopment

data HostConfig = HostConfig
                  { hostConfigHost :: T.Text
                  , hostConfigPort :: Maybe Int
                  }

data DeveloperAPIs = DeveloperAPIs
                     { developerAPIsAnalytics       :: (T.Text,T.Text)
                     , developerAPIsDisqusShortname :: T.Text
                     , developerAPIsFacebook        :: T.Text
                     , developerAPIsAddThis         :: T.Text
                     , developerAPIsFeedburner      :: T.Text
                     }

data AuthorInfo = AuthorInfo
                  { authorInfoName      :: T.Text
                  , authorInfoEmail     :: T.Text
                  , authorInfoRel       :: T.Text
                  , authorInfoFacebook  :: T.Text
                  , authorInfoTwitterID :: T.Text
                  , authorInfoGPlus     :: T.Text
                  , authorInfoGithub    :: T.Text
                  , authorInfoLinkedIn  :: T.Text
                  }

data AppPrefs = AppPrefs
                { appPrefsSlugLength  :: Int
                , appPrefsHomeEntries :: Int
                , appPrefsLedeMax     :: Int
                , appPrefsFeedEntries :: Int
                }

data DatabaseConfig = DatabaseConfig
                      { databaseConfigHost     :: T.Text
                      , databaseConfigName     :: T.Text
                      , databaseConfigUser     :: T.Text
                      , databaseConfigPassword :: T.Text
                      , databaseConfigPort     :: Int
                      }

type SiteRender a = ReaderT PageData S.ActionM a

type PageDataMap = M.Map T.Text T.Text

data PageData = PageData
                { pageDataTitle    :: Maybe T.Text
                , pageDataDesc     :: Maybe T.Text
                , pageDataImage    :: Maybe FilePath
                , pageDataType     :: Maybe T.Text
                , pageDataUrl      :: Maybe T.Text
                , pageDataCss      :: [T.Text]
                , pageDataJs       :: [T.Text]
                , pageDataHeaders  :: [H.Html]
                , pageDataMap      :: PageDataMap
                }

type RouteEither = S.ActionM (Either L.Text (SiteRender H.Html, PageData))

error404 :: L.Text -> Either L.Text a
error404 reason = Left $ L.append "/not-found?err=" reason
