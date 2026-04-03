# Analysis module — VAR, Granger causality, and IRF computation
# Builds a 6-ticker front-month return matrix, fits one VAR, runs Granger causality,
# and pre-computes IRFs for all shock tickers. Runs once on app load (not lazy).
# Writes r$var_results; display module reads from it without any recomputation.
# Parameters:
#   id     - module namespace id
#   dflong - full RTL::dflong tibble
#   r      - shared reactiveValues; this module writes r$var_results
# Example: mod_analysis_var_server("analysis_var", dflong, r)

# Builds a wide data.frame of front-month daily returns for all 6 tickers.
# Log returns for price tickers (CL, BRN, NG, HO, RB); level differences for HTT
# (a spread that crosses zero, making log returns undefined).
# Rows are inner-joined on date — only dates common to all tickers are kept.
# Parameters:
#   dflong - full RTL::dflong tibble (date, series, value)
# Returns: data.frame with columns CL, BRN, NG, HO, RB, HTT; no NA values
# Example: build_var_matrix(RTL::dflong)
build_var_matrix <- function(dflong) {
  tickers  <- c("CL", "BRN", "NG", "HO", "RB", "HTT")
  ret_list <- lapply(tickers, function(tkr) {
    fm      <- get_front_month(dflong, tkr) |> dplyr::arrange(date)
    has_neg <- any(fm$value < 0, na.rm = TRUE)
    fm |>
      dplyr::mutate(
        ret = if (has_neg) value - dplyr::lag(value) else log(value / dplyr::lag(value))
      ) |>
      dplyr::filter(!is.na(ret)) |>
      dplyr::select(date, !!tkr := ret)
  })
  # Inner-join all tickers to the common date range
  ret_wide <- Reduce(function(a, b) dplyr::inner_join(a, b, by = "date"), ret_list)
  ret_wide <- stats::na.omit(ret_wide)
  as.data.frame(ret_wide[, tickers])
}

# Selects consensus VAR lag from VARselect output.
# Picks the lag chosen by the most criteria simultaneously; ties broken by lower lag.
# Parameters:
#   var_select - output of vars::VARselect()
# Returns: integer scalar — selected lag length
# Example: select_var_lag(vars::VARselect(data, lag.max = 10, type = "const"))
select_var_lag <- function(var_select) {
  lags       <- var_select$selection  # named integer vector: AIC(n)=3, HQ(n)=2, SC(n)=2, FPE(n)=3
  votes      <- table(lags)
  max_votes  <- max(votes)
  candidates <- as.integer(names(votes[votes == max_votes]))
  min(candidates)
}

mod_analysis_var_server <- function(id, dflong, r) {
  shiny::moduleServer(id, function(input, output, session) {
    message("mod_analysis_var: building return matrix...")
    var_mat <- build_var_matrix(dflong)
    tickers <- colnames(var_mat)

    # Lag selection across all four criteria simultaneously
    message("mod_analysis_var: selecting lag (lag.max = 10)...")
    var_select <- vars::VARselect(var_mat, lag.max = 10, type = "const")
    lag_n      <- select_var_lag(var_select)

    # Human-readable label — strip "(n)" suffix from criterion names for display
    criteria_raw   <- names(var_select$selection)[var_select$selection == lag_n]
    criteria_clean <- gsub("\\(n\\)", "", criteria_raw)
    lag_label      <- paste0("VAR(", lag_n, ") \u2014 selected by ",
                             paste(criteria_clean, collapse = ", "))

    # Fit VAR with selected lag.
    # do.call is used so the stored call contains the literal lag value, not the symbol
    # lag_n. vars::irf() bootstrap calls stats::update() which re-evaluates the original
    # call in a different frame — if lag_n is a symbol it won't resolve there.
    message("mod_analysis_var: fitting VAR(", lag_n, ")...")
    var_fit <- do.call(vars::VAR, list(y = var_mat, p = lag_n, type = "const"))

    # Granger causality — test each ticker as a cause within the VAR system
    message("mod_analysis_var: computing Granger causality...")
    granger <- lapply(tickers, function(tkr) vars::causality(var_fit, cause = tkr))
    names(granger) <- tickers

    # Pre-compute orthogonalised IRFs for all 6 shock tickers
    # 20-day horizon, 95% bootstrap CI, 100 runs (chosen for MVP speed)
    message("mod_analysis_var: computing IRFs (100 bootstrap runs \u00d7 6 shocks)...")
    irfs <- lapply(tickers, function(shock) {
      vars::irf(var_fit, impulse = shock, n.ahead = 20,
                boot = TRUE, ci = 0.95, runs = 100, ortho = TRUE)
    })
    names(irfs) <- tickers

    r$var_results <- list(
      var_fit   = var_fit,
      lag_n     = lag_n,
      lag_label = lag_label,
      granger   = granger,
      irfs      = irfs,
      tickers   = tickers
    )
    message("mod_analysis_var: r$var_results written.")
  })
}
