library(testthat)
library(RTL)
library(dplyr)
library(tidyr)

source("R/utils_data.R")
source("R/mod_analysis_returns.R")

testthat::test_file("tests/testthat/test_phase2.R", reporter = "summary")
