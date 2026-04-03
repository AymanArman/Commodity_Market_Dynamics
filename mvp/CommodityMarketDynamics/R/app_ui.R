# Top-level UI — defines the page layout and navigation structure
# All page modules are called here; no analytical logic lives in this file
# Example: run_app() renders this UI
app_ui <- function(request) {
  tagList(
    golem_add_external_resources(),
    bslib::page_navbar(
      title = "Commodity Market Dynamics",
      theme = bslib::bs_theme(version = 5, bootswatch = "flatly"),
      bslib::nav_panel(
        title = "Forward Curves",
        mod_fwd_curves_ui("fwd_curves")
      ),
      bslib::nav_panel(
        title = "Volatility",
        mod_volatility_ui("volatility")
      ),
      bslib::nav_panel(
        title = "Market Dynamics",
        mod_market_dynamics_ui("market_dynamics")
      ),
      bslib::nav_panel(
        title = "Cross-Market Relationships",
        mod_cross_market_ui("cross_market")
      ),
      bslib::nav_panel(
        title = "Hedging Analytics",
        bslib::card(
          bslib::card_header("Hedging Analytics"),
          bslib::card_body("Coming soon.")
        )
      )
    )
  )
}

# Loads external resources from inst/app/www (CSS, JS, favicons)
golem_add_external_resources <- function() {
  htmltools::tags$head(
    golem::favicon(),
    golem::bundle_resources(
      path = app_sys("app/www"),
      app_title = "Commodity Market Dynamics"
    )
  )
}
