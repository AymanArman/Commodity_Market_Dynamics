# Top-level server — loads dflong and all static data once, initialises shared
# reactive state, and wires all analysis modules and page modules.
# No child module loads data independently; all data flows down as arguments.
#
#' @param input,output,session Internal parameters for {shiny}. DO NOT REMOVE.
#' @import shiny
#' @noRd
app_server <- function(input, output, session) {

  # Load commodity futures dataset once — never reloaded by child modules
  dflong <- RTL::dflong

  # Shared reactive state — analysis modules write; display modules read
  r <- shiny::reactiveValues()

  # --- Load static EIA files at startup ---
  # All files: sheet="Data 1", skip=2, two columns (date, value)
  # Date column is Excel serial numbers; converted via origin "1899-12-30"
  load_eia_xls <- function(filename) {
    path <- system.file("extdata", filename, package = "CommodityMarketDynamics")
    readxl::read_xls(path, sheet = "Data 1", skip = 2,
                     col_names = c("date", "value")) |>
      dplyr::mutate(
        # suppressWarnings: non-numeric rows (text headers/footers) produce NAs
        # that are removed by the filter below — the warning is expected and safe
        date  = suppressWarnings(as.Date(as.numeric(date), origin = "1899-12-30")),
        value = suppressWarnings(as.numeric(value))
      ) |>
      dplyr::filter(!is.na(date), !is.na(value))
  }

  r$eia_crude_prod      <- load_eia_xls("PET.WCRFPUS2.W.xls")
  r$eia_crude_inputs    <- load_eia_xls("PET.WCRRIUS2.W.xls")
  r$eia_distillate_stocks <- load_eia_xls("PET.WDISTUS1.W.xls")
  r$eia_gasoline_stocks <- load_eia_xls("PET.WGTSTUS1.W.xls")
  r$eia_ng_storage      <- load_eia_xls("NG.NW2_EPG0_SWO_R48_BCF.W.xls")
  r$eia_lng_exports     <- load_eia_xls("N9133US2m.xls")

  # --- Wire analysis modules (all run once at startup) ---
  mod_yield_curves_server(r)
  mod_kalman_betas_server(dflong, r)
  mod_kalman_cross_server(dflong, r)
  mod_var_server(dflong, r)

  # --- Page modules ---
  mod_fc_comparison_server("fc_comp",    dflong = dflong)
  mod_fc_surface_server("fc_surface",   dflong = dflong)
  mod_fc_monthly_server("fc_monthly",   dflong = dflong)
  mod_fc_pca_server("fc_pca",           dflong = dflong, r = r)

  # --- Volatility page modules ---
  mod_vol_density_server("vol_density",  dflong = dflong)
  mod_vol_heatmap_server("vol_heatmap",  dflong = dflong)
  mod_vol_rolling_server("vol_rolling",  dflong = dflong)

  # --- Market Dynamics page ---
  mod_market_dynamics_server("md", dflong = dflong, r = r)

  # --- Cross-Market Relationships page ---
  mod_cm_rolling_corr_server("cm_rolling_corr", dflong = dflong)
  mod_cm_var_server("cm_var", r = r)

  # --- Hedging Analytics page ---
  mod_hedge_swap_server("hedge_swap",       dflong = dflong)
  mod_hedge_roll_server("hedge_roll",       dflong = dflong)
  mod_hedge_options_server("hedge_options", r = r, dflong = dflong)
  mod_hedge_term_server("hedge_term",       dflong = dflong, r = r)
  mod_hedge_cross_server("hedge_cross",     r = r, dflong = dflong)
}
