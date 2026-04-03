library(testthat)
library(shiny)
library(RTL)
library(dplyr)
library(tidyr)
library(vars)
library(zoo)

source("R/utils_data.R")
source("R/mod_analysis_var.R")
source("R/mod_cross_market.R")

testthat::test_file("tests/testthat/test_phase4.R", reporter = "summary")
