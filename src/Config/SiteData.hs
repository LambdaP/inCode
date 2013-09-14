module Config.SiteData (
    siteData
  ) where

import Web.Blog.Types
import qualified Data.Text as T (concat)

siteData :: SiteData
siteData =
  SiteData
    { siteDataTitle           = "in Code"
    , siteDataAuthorInfo      = authorInfo
    , siteDataDescription     = description
    , siteDataCopyright       = "2013 Justin Le"
    , siteDataHostConfig      = hostConfig
    , siteDataDeveloperAPIs   = developerAPIs
    , siteDataAppPrefs        = appPrefs
    , siteDataDatabaseConfig  = databaseConfig
    , siteDataSiteEnvironment = SiteEnvironmentDevelopment
    }
  where
    description = T.concat
      [ "Weblog of Justin Le, covering his various adventures in "
      , "programming and explorations in the vast worlds of computation, "
      , "physics, and knowledge."]
    authorInfo = AuthorInfo
                   { authorInfoName      = "Justin Le"
                   , authorInfoEmail     = "mstksg@gmail.com"
                   , authorInfoRel       = "https://plus.google.com/107705320197444500140"
                   , authorInfoFacebook  = "mstksg"
                   , authorInfoTwitterID = "907281"
                   , authorInfoGPlus     = "107705320197444500140"
                   , authorInfoGithub    = "mstksg"
                   , authorInfoLinkedIn  = "lejustin"
                   }

    hostConfig = HostConfig
                   { hostConfigHost = "blog-dev.jle0.com"
                   , hostConfigPort = Just 4288
                   }

    developerAPIs = DeveloperAPIs
                      ("UA-443711-7", "jle0.com")
                      "justinleblogdevelopment"
                      "645245675494525"
                      "ra-520df7c304b817b9"
                      "justinleblogdevelopment"
    appPrefs = AppPrefs
                 { appPrefsSlugLength  = 8
                 , appPrefsHomeEntries = 5
                 , appPrefsLedeMax     = 2
                 , appPrefsFeedEntries = 15
                 }
    databaseConfig = Just DatabaseConfig
                       { databaseConfigHost     = "localhost"
                       , databaseConfigName     = "test_blog"
                       , databaseConfigUser     = "blog-test"
                       , databaseConfigPassword = "blog-testblog-test"
                       , databaseConfigPort     = 4432
                       }
