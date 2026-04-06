# Fetches FRED Treasury CMT rates via tidyquant and writes r$yield_curves.
# Fetches 8 series: DGS1MO, DGS3MO, DGS6MO, DGS1, DGS2, DGS5, DGS10, DGS30.
# Forward-fills missing values (FRED publishes NA on holidays/weekends).
# Called once at app startup from app_server.R.
#
# Parameters:
#   r - shiny::reactiveValues object (shared app state)
# Returns: nothing; writes r$yield_curves as long-format tibble
#          (date, series, rate)
#
# Example (non-reactive context):
#   r <- list(); mod_yield_curves_server(r)
mod_yield_curves_server <- function(r) {
  fred_tickers <- c(
    "DGS1MO", "DGS3MO", "DGS6MO",
    "DGS1", "DGS2", "DGS5", "DGS10", "DGS30"
  )

  # Fetch all 8 series from FRED — wrapped in tryCatch so a network failure
  # (no internet, FRED outage, SSL error) degrades gracefully rather than
  # crashing app_server before any display modules are wired up.
  # Modules that depend on r$yield_curves guard with shiny::req(!is.null(...)).
  raw <- tryCatch(
    tidyquant::tq_get(
      fred_tickers,
      get  = "economic.data",
      from = "2000-01-01"
    ),
    error = function(e) {
      warning("mod_yield_curves: FRED fetch failed — yield curve features disabled. ",
              conditionMessage(e))
      NULL
    }
  )

  if (is.null(raw) || nrow(raw) == 0 || !"price" %in% names(raw)) {
    r$yield_curves <- NULL
    return(invisible(NULL))
  }

  # Rename to standard schema and forward-fill NAs per series (holiday gaps)
  yield_curves <- raw |>
    dplyr::rename(series = symbol, rate = price) |>
    dplyr::arrange(series, date) |>
    dplyr::group_by(series) |>
    tidyr::fill(rate, .direction = "down") |>
    dplyr::ungroup() |>
    dplyr::filter(!is.na(rate)) |>
    dplyr::mutate(date = as.Date(date))

  r$yield_curves <- yield_curves
}
