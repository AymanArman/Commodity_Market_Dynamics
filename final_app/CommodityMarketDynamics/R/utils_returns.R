# Computes daily returns for a single ticker's long-format tibble.
# Detects negative values and switches to level differences (delta P) for spread
# tickers such as HTT; otherwise computes daily log returns per tenor.
# Drops the leading NA row produced by differencing.
#
# Parameters:
#   ticker_data - long-format tibble with columns (date, series, value)
#                 filtered to a single ticker (e.g. all CL01..CL36 rows)
# Returns: long-format tibble with columns (date, tenor, return)
#          where tenor is zero-padded string format "M01", "M02", ...
#
# Example:
#   dflong |> dplyr::filter(startsWith(series, "CL")) |> compute_returns()
# Clips daily returns to [1st, 99th] percentile independently for each tenor.
# Used before density computation in mod_vol_density to remove extreme outliers
# without distorting the bulk of the distribution.
#
# Parameters:
#   returns_long - long-format tibble with columns (date, tenor, return)
#                  as produced by compute_returns()
# Returns: same tibble with return values clipped per-tenor to [p01, p99]
#
# Example:
#   dflong |> dplyr::filter(startsWith(series, "CL")) |>
#     compute_returns() |> clip_returns_by_tenor()
clip_returns_by_tenor <- function(returns_long) {
  returns_long |>
    dplyr::group_by(tenor) |>
    dplyr::mutate(
      p01    = stats::quantile(return, 0.01, na.rm = TRUE),
      p99    = stats::quantile(return, 0.99, na.rm = TRUE),
      return = pmax(pmin(return, p99), p01)
    ) |>
    dplyr::ungroup() |>
    dplyr::select(-p01, -p99)
}

compute_returns <- function(ticker_data) {
  # Detect whether this ticker uses level differences.
  # Uses proportion threshold (>0.1% negative) rather than any() to avoid
  # switching CL/BRN/etc. to delta P on the basis of a single anomalous day
  # (e.g. WTI went negative in April 2020 — ~0.01% of its history).
  # HTT is structurally a spread with ~0.4% negative values, well above 0.1%.
  prop_negative <- mean(ticker_data$value < 0, na.rm = TRUE)
  use_diff      <- prop_negative > 0.001

  result <- ticker_data |>
    dplyr::arrange(series, date) |>
    dplyr::group_by(series) |>
    dplyr::mutate(
      return = if (use_diff) {
        value - dplyr::lag(value)      # delta P for spread tickers (e.g. HTT)
      } else {
        log(value / dplyr::lag(value)) # log return for outright tickers
      }
    ) |>
    dplyr::ungroup() |>
    dplyr::filter(is.finite(return))

  # Convert series name to zero-padded tenor string: "CL01" -> "M01"
  result |>
    dplyr::mutate(
      tenor = paste0("M", sub("^[A-Za-z]+", "", series))
    ) |>
    dplyr::select(date, tenor, return)
}
