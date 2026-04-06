#' The application User-Interface
#'
#' @param request Internal parameter for `{shiny}`.
#'     DO NOT REMOVE.
#' @import shiny
#' @noRd
app_ui <- function(request) {
  tagList(
    golem_add_external_resources(),
    bslib::page_navbar(
      title  = "Commodity Market Dynamics",
      theme  = bslib::bs_theme(
        version    = 5,
        bg         = "#48495e",
        fg         = "#f9f9f9",
        primary    = "#F87217",
        secondary  = "#179df8",
        base_font  = bslib::font_google("Times New Roman", local = FALSE)
      ) |>
        bslib::bs_add_rules("
          /* Card body */
          .card { background-color: #757a8a !important; }

          /* Card header */
          .card-header { background-color: #75858a !important; }

          /* Spacing + thin dashed divider between fluid rows */
          .container-fluid > .row,
          .tab-pane > .row,
          .shiny-panel-conditional > .row {
            margin-bottom: 28px;
            padding-bottom: 28px;
            border-bottom: 1px dashed rgba(249,249,249,0.25);
          }
          /* Remove divider from last row in each panel */
          .container-fluid > .row:last-child,
          .tab-pane > .row:last-child,
          .shiny-panel-conditional > .row:last-child {
            border-bottom: none;
          }
        "),
      # --- Page stubs (Phase 0 scaffold — content added in Phases 1–5) ---
      bslib::nav_panel(
        title = "Forward Curves",
        mod_fc_comparison_ui("fc_comp"),
        mod_fc_surface_ui("fc_surface"),
        mod_fc_monthly_ui("fc_monthly"),
        mod_fc_pca_ui("fc_pca")
      ),
      bslib::nav_panel(
        title = "Volatility",
        mod_vol_density_ui("vol_density"),
        mod_vol_heatmap_ui("vol_heatmap"),
        mod_vol_rolling_ui("vol_rolling")
      ),
      bslib::nav_panel(
        title = "Market Dynamics",
        mod_market_dynamics_ui("md")
      ),
      bslib::nav_panel(
        title = "Cross-Market Relationships",
        mod_cm_rolling_corr_ui("cm_rolling_corr"),
        mod_cm_var_ui("cm_var")
      ),
      bslib::nav_panel(
        title = "Hedging Analytics",
        mod_hedge_swap_ui("hedge_swap"),
        mod_hedge_roll_ui("hedge_roll"),
        mod_hedge_options_ui("hedge_options"),
        mod_hedge_term_ui("hedge_term"),
        mod_hedge_cross_ui("hedge_cross")
      )
    )
  )
}

#' Add external Resources to the Application
#'
#' This function is internally used to add external
#' resources inside the Shiny application.
#'
#' @import shiny
#' @importFrom golem add_resource_path activate_js favicon bundle_resources
#' @noRd
golem_add_external_resources <- function() {
  add_resource_path(
    "www",
    app_sys("app/www")
  )

  tags$head(
    favicon(),
    bundle_resources(
      path = app_sys("app/www"),
      app_title = "CommodityMarketDynamics"
    )
    # Add here other external resources
    # for example, you can add shinyalert::useShinyalert()
  )
}
