library(testthat)
library(RTL)
library(dplyr)
library(tidyr)
library(zoo)

source("R/utils_data.R")
source("R/mod_analysis_regime.R")

testthat::test_file("tests/testthat/test_phase1.R", reporter = "summary")
