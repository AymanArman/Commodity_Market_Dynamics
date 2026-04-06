# Cross-Market Relationships Page — Row 1: Rolling Correlation with Vol Regime Shading
# Renders a rolling correlation line between the front-month returns of two selected
# tickers. Background is shaded red in high-vol periods (rolling avg vol above 80th
# percentile). Reactive to ticker selection and window slider.
#
# Parameters:
#   id     - Shiny module ID
#   dflong - full RTL::dflong tibble (date, series, value), passed from server
#
# Example:
#   mod_cm_rolling_corr_ui("cm_rolling_corr")
#   mod_cm_rolling_corr_server("cm_rolling_corr", dflong = dflong)

# ── UI ───────────────────────────────────────────────────────────────────────

mod_cm_rolling_corr_ui <- function(id) {
  ns <- shiny::NS(id)

  tagList(
    # Controls row: two-ticker selector + rolling window slider
    shiny::fluidRow(
      shiny::column(
        width = 4,
        shinyWidgets::pickerInput(
          inputId  = ns("tickers"),
          label    = "Select two commodities",
          choices  = c("CL", "BRN", "NG", "HO", "RB", "HTT"),
          selected = c("CL", "BRN"),
          multiple = TRUE,
          options  = shinyWidgets::pickerOptions(maxOptions = 2)
        )
      ),
      shiny::column(
        width = 4,
        shiny::sliderInput(
          inputId = ns("window"),
          label   = "Rolling window (days)",
          min     = 21L,
          max     = 252L,
          value   = 90L,
          step    = 1L
        )
      )
    ),
    # Chart row: 2-width margins, 8-width chart (centred)
    # No border-bottom so the narrative card below reads as part of the same row
    shiny::fluidRow(
      style = "border-bottom: none !important; margin-bottom: 0 !important; padding-bottom: 0 !important;",
      shiny::column(width = 2),
      shiny::column(
        width = 8,
        plotly::plotlyOutput(ns("corr_chart"), height = "450px")
      ),
      shiny::column(width = 2)
    ),
    # Narrative row: same centred alignment
    shiny::fluidRow(
      shiny::column(width = 2),
      shiny::column(
        width = 8,
        bslib::card(
          bslib::card_body(
            shiny::p(
              "Rolling correlation reveals whether cross-market relationships are ",
              "stable or regime-dependent. Volatility regime shading tests the ",
              "assumption directly — if the correlation line behaves differently ",
              "inside high-vol windows than outside, the relationship strengthens ",
              "or breaks down under stress. This has direct implications for ",
              "diversification and cross-market hedges: a hedge that holds during ",
              "calm periods may fail precisely when it is most needed."
            )
          )
        )
      ),
      shiny::column(width = 2)
    )
  )
}

# ── Helpers ──────────────────────────────────────────────────────────────────

# Identifies contiguous date ranges where a logical vector is TRUE.
# Returns a data.frame with columns x0, x1 (Date) for each run.
# Parameters:
#   dates    - Date vector aligned with is_high (same length)
#   is_high  - logical vector; TRUE = high-vol period
# Example:
#   get_high_vol_periods(dates_vec, vol_vec > threshold)
get_high_vol_periods <- function(dates, is_high) {
  if (all(is.na(is_high)) || !any(is_high, na.rm = TRUE)) {
    return(data.frame(x0 = as.Date(character()), x1 = as.Date(character())))
  }
  # Replace NA with FALSE so rle runs cleanly
  is_high[is.na(is_high)] <- FALSE
  rl     <- rle(is_high)
  ends   <- cumsum(rl$lengths)
  starts <- ends - rl$lengths + 1L
  # Keep only TRUE runs
  keep   <- which(rl$values)
  data.frame(
    x0 = dates[starts[keep]],
    x1 = dates[ends[keep]]
  )
}

# ── Server ───────────────────────────────────────────────────────────────────

mod_cm_rolling_corr_server <- function(id, dflong) {
  shiny::moduleServer(id, function(input, output, session) {

    # Rolling correlation and vol regime — recomputes on ticker or window change
    corr_data <- shiny::reactive({
      shiny::req(length(input$tickers) == 2, input$window)

      t1 <- input$tickers[1]
      t2 <- input$tickers[2]
      win <- as.integer(input$window)

      # Extract M01 log returns for each ticker
      get_m1_returns <- function(ticker) {
        dflong |>
          dplyr::filter(series == paste0(ticker, "01")) |>
          compute_returns() |>   # returns (date, tenor, return)
          dplyr::select(date, return)
      }
      r1 <- get_m1_returns(t1)
      r2 <- get_m1_returns(t2)

      # Inner join on shared dates
      joined <- dplyr::inner_join(r1, r2, by = "date", suffix = c("_t1", "_t2")) |>
        dplyr::arrange(date)

      shiny::req(nrow(joined) > win)

      # Rolling correlation — bivariate zoo::rollapplyr
      ret_mat <- as.matrix(joined[, c("return_t1", "return_t2")])
      roll_corr <- zoo::rollapplyr(
        data       = ret_mat,
        width      = win,
        FUN        = function(m) stats::cor(m[, 1], m[, 2], use = "complete.obs"),
        by.column  = FALSE,
        fill       = NA,
        align      = "right"
      )

      # High-vol regime: 21-day rolling sd for each ticker, averaged across both
      roll_vol1 <- zoo::rollapply(joined$return_t1, width = 21L, FUN = stats::sd,
                                  fill = NA, align = "right")
      roll_vol2 <- zoo::rollapply(joined$return_t2, width = 21L, FUN = stats::sd,
                                  fill = NA, align = "right")
      avg_vol    <- rowMeans(cbind(roll_vol1, roll_vol2), na.rm = FALSE)

      # 80th percentile threshold (data-driven, not hardcoded)
      vol_threshold <- stats::quantile(avg_vol, probs = 0.80, na.rm = TRUE)
      is_high_vol   <- avg_vol > vol_threshold

      # Contiguous high-vol periods as date ranges
      hv_periods <- get_high_vol_periods(joined$date, is_high_vol)

      list(
        dates         = joined$date,
        roll_corr     = roll_corr,
        hv_periods    = hv_periods,
        vol_threshold = vol_threshold
      )
    })

    output$corr_chart <- plotly::renderPlotly({
      cd <- corr_data()
      shiny::req(length(cd$roll_corr) > 0)

      t1  <- input$tickers[1]
      t2  <- input$tickers[2]
      dat <- dplyr::tibble(date = cd$dates, corr = cd$roll_corr) |>
        dplyr::filter(!is.na(corr))

      # Base correlation line
      p <- plotly::plot_ly(
        data          = dat,
        x             = ~date,
        y             = ~corr,
        type          = "scatter",
        mode          = "lines",
        name          = paste0(t1, " / ", t2),
        line          = list(color = "#210000", width = 1.5),
        hovertemplate = "%{x|%b %d, %Y}: %{y:.3f}<extra></extra>"
      )

      # High-vol shading: red rect shapes at 20% opacity
      hv_shapes <- lapply(seq_len(nrow(cd$hv_periods)), function(i) {
        list(
          type      = "rect",
          x0        = format(cd$hv_periods$x0[i]),
          x1        = format(cd$hv_periods$x1[i]),
          y0        = 0, y1 = 1, xref = "x", yref = "paper",
          fillcolor = "rgba(200,50,50,0.20)",
          line      = list(width = 0),
          layer     = "below"
        )
      })

      # Horizontal reference line at y = 0
      zero_line <- list(
        type  = "line",
        x0    = 0, x1 = 1, xref = "paper",
        y0    = 0, y1 = 0, yref = "y",
        line  = list(color = "#444444", width = 1, dash = "dash")
      )
      all_shapes <- c(hv_shapes, list(zero_line))

      p |>
        plotly::layout(
          xaxis       = list(title = "Date"),
          yaxis       = list(title = "Rolling Correlation", range = c(-1, 1)),
          shapes      = all_shapes,
          legend      = list(orientation = "h", y = -0.15),
          hovermode   = "x unified"
        ) |>
        apply_theme()
    })
  })
}
