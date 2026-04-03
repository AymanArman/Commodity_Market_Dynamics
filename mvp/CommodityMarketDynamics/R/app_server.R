# Top-level server — loads data once, initialises shared reactive state, calls all modules
# dflong is loaded here and passed down; no child module loads it independently
# Example: run_app() calls this server
app_server <- function(input, output, session) {

  # Load full dataset once — never reloaded by child modules
  dflong <- RTL::dflong

  # Shared reactive state — analysis modules write to r; display modules read from it
  r <- shiny::reactiveValues()

  # Initialise analysis modules — these write results to r
  mod_analysis_regime_server("analysis_regime", dflong = dflong, r = r)
  mod_analysis_returns_server("analysis_returns", dflong = dflong, r = r)
  mod_analysis_var_server("analysis_var", dflong = dflong, r = r)

  # Initialise page modules — these read from r and render UI
  mod_fwd_curves_server("fwd_curves", dflong = dflong, r = r)
  mod_volatility_server("volatility", dflong = dflong, r = r)
  mod_market_dynamics_server("market_dynamics", dflong = dflong, r = r)
  mod_cross_market_server("cross_market", dflong = dflong, r = r)
}
