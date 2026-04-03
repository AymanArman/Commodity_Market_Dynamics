library(testthat)
library(shiny)
library(RTL)
library(dplyr)
library(tidyr)

source("R/utils_data.R")
source("R/mod_market_dynamics.R")

testthat::test_file("tests/testthat/test_phase3.R", reporter = "summary")
