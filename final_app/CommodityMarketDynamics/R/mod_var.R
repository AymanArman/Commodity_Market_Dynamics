# Estimates a weekly VAR model at app startup and writes r$var_results.
# Weekly aggregation: filter dflong to Friday closes (or last available trading
# day of each week) before computing returns — daily data is NOT passed to VAR.
# Returns: log returns for CL, BRN, NG, HO, RB; weekly delta P for HTT.
# All 6 series standardised to z-scores before estimation.
# Cholesky ordering: BRN -> CL -> HO -> RB -> HTT -> NG (column order in matrix).
# Lag selected where >= 2 of AIC, HQ, BIC, FPE agree; capped at 6.
#
# Parameters:
#   dflong - full RTL::dflong tibble (date, series, value)
#   r      - shiny::reactiveValues object; writes r$var_results
# Returns: nothing; writes r$var_results as a varest object
#
# Example (non-reactive):
#   r <- list(); mod_var_server(RTL::dflong, r)
mod_var_server <- function(dflong, r) {
  tickers       <- c("CL", "BRN", "NG", "HO", "RB", "HTT")
  chol_order    <- c("BRN", "CL", "HO", "RB", "HTT", "NG")

  # --- Step 1: Filter to front month (M1) and last available day of each week ---
  front_series <- paste0(tickers, "01")   # c("CL01","BRN01","NG01","HO01","RB01","HTT01")

  weekly_prices <- dflong |>
    dplyr::filter(series %in% front_series) |>
    dplyr::mutate(
      year_week = paste0(lubridate::isoyear(date), "-", sprintf("%02d", lubridate::isoweek(date)))
    ) |>
    dplyr::group_by(series, year_week) |>
    dplyr::filter(date == max(date)) |>
    dplyr::ungroup() |>
    dplyr::select(date, series, value)

  # --- Step 2: Compute weekly returns per ticker ---
  # Log returns for outright tickers; delta P for HTT (negative values present)
  weekly_returns <- purrr::map_dfr(tickers, function(ticker) {
    front    <- paste0(ticker, "01")
    sub_data <- weekly_prices |> dplyr::filter(series == front)

    # Guard: if no rows, skip this ticker — setdiff check below will warn
    if (nrow(sub_data) == 0L) return(NULL)

    # Use compute_returns (detects HTT via negative values)
    returns <- compute_returns(sub_data) |>
      dplyr::mutate(ticker = ticker) |>
      dplyr::select(date, ticker, return)
  })

  # --- Step 3: Pivot to wide; inner join all 6 tickers on shared dates ---
  var_wide <- weekly_returns |>
    tidyr::pivot_wider(names_from = ticker, values_from = return) |>
    dplyr::arrange(date) |>
    tidyr::drop_na()  # inner join equivalent — removes rows with any NA

  if (nrow(var_wide) < 52) {
    warning("mod_var: fewer than 52 weekly observations after inner join — VAR not estimated")
    return(invisible(NULL))
  }

  # Verify all 6 tickers survived the join; abort if any are missing —
  # Cholesky ordering requires the full set
  missing_tickers <- setdiff(tickers, names(var_wide))
  if (length(missing_tickers) > 0) {
    warning("mod_var: tickers dropped from VAR input due to missing dates: ",
            paste(missing_tickers, collapse = ", "),
            " — VAR not estimated")
    return(invisible(NULL))
  }

  # --- Step 4: Standardise to z-scores ---
  var_matrix <- var_wide |>
    dplyr::select(dplyr::all_of(chol_order)) |>
    dplyr::mutate(dplyr::across(dplyr::everything(), ~ (. - mean(., na.rm = TRUE)) / sd(., na.rm = TRUE))) |>
    as.data.frame()

  # --- Step 5: Select lag via VARselect (>= 2 criteria must agree) ---
  var_select <- vars::VARselect(var_matrix, lag.max = 8, type = "const")
  lag_counts <- table(var_select$selection)
  best_lag   <- as.integer(names(lag_counts)[which.max(lag_counts)])

  lag_criterion <- "consensus"
  if (max(lag_counts) < 2) {
    # No consensus — fall back to BIC (most parsimonious)
    best_lag      <- unname(var_select$selection[["SC(n)"]])
    lag_criterion <- "BIC"
    message("mod_var: no lag consensus — using BIC lag = ", best_lag)
  }

  if (best_lag > 6) {
    message("mod_var: consensus lag ", best_lag, " > 6; capping at 6")
    best_lag <- 6L
  }

  # --- Step 6: Estimate VAR with Cholesky column order ---
  # Attach dates as row names so downstream modules and tests can recover the timeline
  var_dates          <- var_wide$date
  rownames(var_matrix) <- as.character(var_dates)

  var_model <- do.call(
    vars::VAR,
    list(y = var_matrix, p = best_lag, type = "const")
  )

  # Store input dates and lag criterion as attributes for use in Phase 4 IRF
  attr(var_model, "var_dates")      <- var_dates
  attr(var_model, "lag_criterion")  <- lag_criterion

  r$var_results <- var_model
}
