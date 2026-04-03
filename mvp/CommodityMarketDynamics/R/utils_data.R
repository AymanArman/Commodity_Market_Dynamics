# Data utility functions shared across all modules

# Valid tickers available in RTL::dflong for this project
TICKERS <- c("CL", "BRN", "NG", "HO", "RB", "HTT")

# Filters dflong to a single ticker and returns all its series in long format.
# Ticker prefix matched against the series column (e.g. "CL" matches "CL01".."CL36").
# Parameters:
#   dflong  - the full RTL::dflong tibble (date, series, value)
#   ticker  - character string, one of TICKERS
# Returns: tibble with columns date, series, value, tenor (integer)
# Example: get_ticker(dflong, "CL")
get_ticker <- function(dflong, ticker) {
  dflong |>
    dplyr::filter(startsWith(series, ticker)) |>
    dplyr::mutate(tenor = as.integer(sub(paste0("^", ticker), "", series)))
}

# Returns the front month (tenor = 1) series for a given ticker in long format.
# Parameters:
#   dflong  - the full RTL::dflong tibble
#   ticker  - character string, one of TICKERS
# Returns: tibble with columns date, series, value
# Example: get_front_month(dflong, "CL")
get_front_month <- function(dflong, ticker) {
  front_series <- paste0(ticker, "01")
  dflong |> dplyr::filter(series == front_series)
}

# Pivots a long-format ticker tibble to wide format: rows = date, columns = series.
# Parameters:
#   ticker_long - output of get_ticker()
# Returns: tibble with date column and one column per tenor
# Example: pivot_ticker_wide(get_ticker(dflong, "CL"))
pivot_ticker_wide <- function(ticker_long) {
  wide       <- ticker_long |>
    dplyr::select(date, series, value) |>
    tidyr::pivot_wider(names_from = series, values_from = value) |>
    dplyr::arrange(date)
  # Sort tenor columns by tenor number — pivot_wider orders by first appearance
  tenor_cols <- setdiff(names(wide), "date")
  tenor_nums <- as.integer(sub("^[A-Z]+", "", tenor_cols))
  wide[, c("date", tenor_cols[order(tenor_nums)])]
}
