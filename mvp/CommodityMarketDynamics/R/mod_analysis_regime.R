# Analysis module — contango/backwardation regime classification
# Computes regime per date for a given ticker; writes r$[ticker]_regime
# No UI — pure computation. Called from app_server.R.
# Parameters:
#   id     - module namespace id
#   dflong - full RTL::dflong tibble
#   r      - shared reactiveValues; this module writes to it
# Example: mod_analysis_regime_server("analysis_regime", dflong, r)

mod_analysis_regime_server <- function(id, dflong, r) {
  shiny::moduleServer(id, function(input, output, session) {
    # Phase 1 implementation goes here
  })
}

# Classifies each date as contango, backwardation, or neutral based on M01 vs last tenor.
# Smoothing: 5-day rolling majority vote suppresses single-day flickers.
# Parameters:
#   ticker_long - output of get_ticker() for one ticker
# Returns: tibble with columns date, regime (character: "contango"/"backwardation"/"neutral")
# Example: compute_regime(get_ticker(dflong, "CL"))
compute_regime <- function(ticker_long) {
  tenors <- ticker_long |>
    dplyr::group_by(date) |>
    dplyr::summarise(
      m1 = value[tenor == min(tenor)],
      mN = value[tenor == max(tenor)],
      .groups = "drop"
    ) |>
    dplyr::filter(!is.na(m1), !is.na(mN))

  tenors <- tenors |>
    dplyr::mutate(
      regime_raw = dplyr::case_when(
        m1 < mN ~ "contango",
        m1 > mN ~ "backwardation",
        TRUE    ~ "neutral"
      )
    )

  tenors <- tenors |>
    dplyr::arrange(date) |>
    dplyr::mutate(
      regime = zoo::rollapply(
        regime_raw,
        width = 5,
        FUN   = function(x) names(which.max(table(x))),
        fill  = regime_raw,
        align = "right"
      )
    ) |>
    dplyr::select(date, regime)

  tenors
}
