library(testthat)
library(RTL)
library(dplyr)
library(tidyr)

source("R/utils_data.R")

testthat::test_file("tests/testthat/test_phase0.R", reporter = "summary")
