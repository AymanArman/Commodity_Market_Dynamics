# Pre-computes within-ticker time-varying Kalman betas for all tickers at startup.
# For each ticker (CL, BRN, NG, HO, RB), runs a scalar Kalman filter on daily
# log returns for each back tenor Mn vs the front month M1. M1 vs M1 (diagonal)
# is excluded. Returns are computed via compute_returns() — never independently.
# Strictly causal (no look-ahead).
#
# Parameters:
#   dflong - full RTL::dflong tibble (date, series, value)
#   r      - shiny::reactiveValues object; writes r$kalman_betas
# Returns: nothing; writes r$kalman_betas as long-format tibble
#          (date, ticker, tenor, beta, r_squared)
#
# Example (non-reactive):
#   r <- list(); mod_kalman_betas_server(RTL::dflong, r)
mod_kalman_betas_server <- function(dflong, r) {
  tickers <- c("CL", "BRN", "NG", "HO", "RB")  # HTT excluded — spread ticker

  results <- purrr::map_dfr(tickers, function(ticker) {
    # Get all series for this ticker and compute returns via shared utility
    ticker_data <- dflong |> dplyr::filter(startsWith(series, ticker))
    returns     <- compute_returns(ticker_data)

    # Pivot to wide: rows = date, columns = M01, M02, ...
    wide <- returns |>
      tidyr::pivot_wider(names_from = tenor, values_from = return) |>
      dplyr::arrange(date)

    # M1 returns (x in regression)
    if (!"M01" %in% names(wide)) return(NULL)
    x_dates <- wide$date
    x       <- wide[["M01"]]

    # Back tenors only (M02, M03, ...) — exclude M01
    back_tenors <- setdiff(names(wide), c("date", "M01"))
    if (length(back_tenors) == 0) return(NULL)

    purrr::map_dfr(back_tenors, function(tn) {
      y   <- wide[[tn]]
      res <- kalman_scalar(x, y)

      dplyr::tibble(
        date      = x_dates,
        ticker    = ticker,
        tenor     = tn,
        beta      = res$beta,
        r_squared = pmax(0, pmin(1, res$r_squared))  # clamp to [0,1]
      )
    })
  })

  # Drop initialisation row (first date has no prior observation)
  results <- results |>
    dplyr::group_by(ticker, tenor) |>
    dplyr::slice(-1) |>
    dplyr::ungroup()

  r$kalman_betas <- results
}
