# Analysis module — log returns computation
# Computes daily log returns per tenor for a given ticker; writes r$[ticker]_returns
# No UI — pure computation. Caching is handled lazily in display modules.
# Parameters:
#   id     - module namespace id
#   dflong - full RTL::dflong tibble
#   r      - shared reactiveValues; display modules write to it on first demand
# Example: mod_analysis_returns_server("analysis_returns", dflong, r)

mod_analysis_returns_server <- function(id, dflong, r) {
  shiny::moduleServer(id, function(input, output, session) {
    # Computation is triggered lazily by display modules via compute_returns()
  })
}

# Computes daily log returns per tenor from a long-format ticker tibble.
# Formula: log(price_t / price_{t-1}) per tenor series.
# Returns are computed in long format per series independently before pivoting wide —
# this ensures each tenor's lag references only its own prior observation, not the prior
# row of a joint wide table (which would propagate NAs across tenors with different date
# coverage).
# Parameters:
#   ticker_long - output of get_ticker() for one ticker
# Returns: wide tibble with date column and one column per tenor series (e.g. CL01...CL36)
# Example: compute_returns(get_ticker(dflong, "CL"))
compute_returns <- function(ticker_long) {
  # Spread tickers can have negative values — log returns are undefined when the series
  # crosses zero. Use level differences for those; log returns for price-based tickers.
  has_negative <- any(ticker_long$value < 0, na.rm = TRUE)

  ticker_long |>
    dplyr::arrange(series, date) |>
    dplyr::group_by(series) |>
    dplyr::mutate(
      ret = if (has_negative)
        value - dplyr::lag(value)          # level difference for spread tickers
      else
        log(value / dplyr::lag(value))     # log return for price tickers
    ) |>
    dplyr::ungroup() |>
    dplyr::filter(!is.na(ret)) |>
    dplyr::select(date, series, ret) |>
    tidyr::pivot_wider(names_from = series, values_from = ret) |>
    dplyr::arrange(date)
}
