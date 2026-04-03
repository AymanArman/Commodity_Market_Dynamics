# Entry point for shiny::runApp()
# Files sourced explicitly to guarantee correct load order

source("R/app_config.R")
source("R/utils_data.R")
source("R/mod_analysis_regime.R")
source("R/mod_analysis_returns.R")
source("R/mod_analysis_var.R")
source("R/mod_fwd_curves.R")
source("R/mod_volatility.R")
source("R/mod_market_dynamics.R")
source("R/mod_cross_market.R")
source("R/run_app.R")
source("R/app_ui.R")
source("R/app_server.R")

shiny::shinyApp(ui = app_ui, server = app_server)
