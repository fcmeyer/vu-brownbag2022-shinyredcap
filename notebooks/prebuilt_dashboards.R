# to get ExPanDaR, you will need to install from github:
# devtools::install_github("joachim-gassen/ExPanDaR")

library(tidyverse)
require(datadigest)
require(radiant)
require(ExPanDaR)

# Step 1: download my data
my_data <- REDCapR::redcap_read(
  redcap_uri = 'https://redcap.vanderbilt.edu/api/',
  token = Sys.getenv('REDCAP_API_KEY_VU')
)$data

# Step 2: launch a dashboard!

# for datadigest
datadigest::explorerApp()

# For radiant
radiant::radiant()

# For Expandar
ExPanDaR::ExPanD(my_data)
