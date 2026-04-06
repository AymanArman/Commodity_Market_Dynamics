# Pre-computes cross-ticker time-varying Kalman betas for all 30 directed M1 pairs.
# All 6 tickers (CL, BRN, NG, HO, RB, HTT) x 5 non-self = 30 pairs; diagonal excluded.
# HTT uses level differences (delta P) automatically via compute_returns().
# Returns are computed via compute_returns() — never independently.
#
# Parameters:
#   dflong - full RTL::dflong tibble (date, series, value)
#   r      - shiny::reactiveValues object; writes r$kalman_cross_betas
# Returns: nothing; writes r$kalman_cross_betas as long-format tibble
#          (date, from_ticker, to_ticker, beta, r_squared)
#
# Example (non-reactive):
#   r <- list(); mod_kalman_cross_server(RTL::dflong, r)
mod_kalman_cross_server <- function(dflong, r) {
  tickers <- c("CL", "BRN", "NG", "HO", "RB", "HTT")

  # Extract M1 daily returns for each ticker via compute_returns()
  m1_returns <- purrr::map(tickers, function(ticker) {
    ticker_data <- dflong |> dplyr::filter(startsWith(series, ticker))
    returns     <- compute_returns(ticker_data)
    returns |>
      dplyr::filter(tenor == "M01") |>
      dplyr::select(date, return) |>
      dplyr::rename(!!ticker := return)
  })

  # Inner join all 6 M1 return series on overlapping dates
  m1_wide <- purrr::reduce(m1_returns, dplyr::inner_join, by = "date") |>
    dplyr::arrange(date)

  # Build all 30 directed pairs
  pairs <- expand.grid(
    from_ticker = tickers,
    to_ticker   = tickers,
    stringsAsFactors = FALSE
  ) |>
    dplyr::filter(from_ticker != to_ticker)  # exclude diagonal

  results <- purrr::map_dfr(seq_len(nrow(pairs)), function(i) {
    from <- pairs$from_ticker[i]
    to   <- pairs$to_ticker[i]

    x   <- m1_wide[[from]]
    y   <- m1_wide[[to]]
    res <- kalman_scalar(x, y)

    dplyr::tibble(
      date        = m1_wide$date,
      from_ticker = from,
      to_ticker   = to,
      beta        = res$beta,
      r_squared   = pmax(0, pmin(1, res$r_squared))
    )
  })

  # Drop initialisation row
  results <- results |>
    dplyr::group_by(from_ticker, to_ticker) |>
    dplyr::slice(-1) |>
    dplyr::ungroup()

  r$kalman_cross_betas <- results
}
