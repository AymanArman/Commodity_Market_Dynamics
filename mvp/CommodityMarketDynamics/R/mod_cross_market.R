# Cross-Market Relationships page module
# Panel 1: rolling correlation between two tickers' M01 returns, background shaded by
#           volatility regime (high vol = rolling SD above 75th percentile of its history)
# Panel 2: IRF chart from pre-computed VAR — shock ticker selector, each responding
#           ticker colored distinctly; CI ribbons shown at low opacity in the same color
# Parameters:
#   id     - module namespace id
#   dflong - full RTL::dflong tibble (passed from app_server)
#   r      - shared reactiveValues; reads r$var_results (written by mod_analysis_var)
# Example: mod_cross_market_ui("cross_market") / mod_cross_market_server("cross_market", dflong, r)

# Converts contiguous high-volatility run segments into a list of plotly rect shape objects.
# Shapes are anchored in paper y-coordinates so they span behind all traces.
# Parameters:
#   dates      - Date vector parallel to high_vol
#   high_vol   - logical vector, TRUE where rolling SD exceeds the vol threshold
#   fill_color - RGBA fill string for the high-vol shading
# Returns: list of plotly shape definition lists
# Example: vol_regime_shapes(dates, roll_sd > quantile(roll_sd, 0.75))
vol_regime_shapes <- function(dates, high_vol, fill_color = "rgba(255, 99, 71, 0.12)") {
  n      <- length(dates)
  shapes <- list()
  in_seg <- FALSE
  seg_start <- NULL

  for (i in seq_len(n)) {
    hv <- !is.na(high_vol[i]) && isTRUE(high_vol[i])
    if (hv && !in_seg) {
      in_seg    <- TRUE
      seg_start <- dates[i]
    } else if (!hv && in_seg) {
      in_seg <- FALSE
      shapes <- c(shapes, list(list(
        type      = "rect",
        xref      = "x", x0 = as.character(seg_start), x1 = as.character(dates[i - 1L]),
        yref      = "paper", y0 = 0, y1 = 1,
        fillcolor = fill_color,
        line      = list(width = 0),
        layer     = "below"
      )))
    }
  }
  # Close any segment that runs to the end of the series
  if (in_seg) {
    shapes <- c(shapes, list(list(
      type      = "rect",
      xref      = "x", x0 = as.character(seg_start), x1 = as.character(dates[n]),
      yref      = "paper", y0 = 0, y1 = 1,
      fillcolor = fill_color,
      line      = list(width = 0),
      layer     = "below"
    )))
  }
  shapes
}


mod_cross_market_ui <- function(id) {
  ns <- shiny::NS(id)
  bslib::page_fluid(

    # Panel 1 — rolling correlation with vol regime shading
    bslib::layout_columns(
      col_widths = 12,
      bslib::card(
        bslib::card_body(
          shiny::tags$strong("Rolling Cross-Market Correlation"),
          shiny::tags$hr(style = "margin: 4px 0 8px 0;"),
          bslib::layout_columns(
            col_widths = c(3, 3, 6),
            shiny::selectInput(ns("ticker_a"), "Ticker A", choices = TICKERS, selected = "CL"),
            shiny::selectInput(ns("ticker_b"), "Ticker B", choices = TICKERS, selected = "BRN"),
            shiny::sliderInput(
              ns("roll_window"), "Rolling window (days)",
              min = 20, max = 120, value = 60, step = 5
            )
          ),
          plotly::plotlyOutput(ns("plot_roll_corr"), height = "350px")
        )
      )
    ),

    # Panel 2 — IRF chart
    bslib::layout_columns(
      col_widths = 12,
      bslib::card(
        bslib::card_body(
          shiny::tags$strong("Impulse Response Functions (VAR)"),
          shiny::tags$hr(style = "margin: 4px 0 8px 0;"),
          shiny::uiOutput(ns("var_lag_label")),
          shiny::selectInput(ns("shock_ticker"), "Shock ticker", choices = TICKERS, selected = "CL"),
          plotly::plotlyOutput(ns("plot_irf"), height = "420px"),
          shiny::tags$p(
            style = "color: #888; font-size: 0.85em; margin-top: 8px;",
            paste(
              "VAR calibrated on historical return innovations.",
              "Structural breaks (e.g. COVID, shale revolution)",
              "mean historical relationships may not hold forward."
            )
          )
        )
      )
    )
  )
}

mod_cross_market_server <- function(id, dflong, r) {
  shiny::moduleServer(id, function(input, output, session) {

    # Compute M01 returns for one ticker directly from dflong (no r dependency)
    # Log returns for price tickers; level differences for HTT
    front_returns <- function(ticker) {
      fm <- get_front_month(dflong, ticker) |> dplyr::arrange(date)
      has_neg <- any(fm$value < 0, na.rm = TRUE)
      fm |>
        dplyr::mutate(
          ret = if (has_neg) value - dplyr::lag(value) else log(value / dplyr::lag(value))
        ) |>
        dplyr::filter(!is.na(ret)) |>
        dplyr::select(date, ret)
    }

    # Panel 1 — rolling correlation
    output$plot_roll_corr <- plotly::renderPlotly({
      shiny::req(input$ticker_a, input$ticker_b, input$roll_window)
      shiny::validate(shiny::need(
        input$ticker_a != input$ticker_b,
        "Select two different tickers."
      ))

      ret_a  <- front_returns(input$ticker_a) |> dplyr::rename(ret_a = ret)
      ret_b  <- front_returns(input$ticker_b) |> dplyr::rename(ret_b = ret)
      joined <- dplyr::inner_join(ret_a, ret_b, by = "date") |>
        dplyr::arrange(date) |>
        dplyr::filter(!is.na(ret_a) & !is.na(ret_b))

      w <- input$roll_window

      # Rolling pairwise correlation via zoo
      ret_mat  <- zoo::zoo(cbind(joined$ret_a, joined$ret_b), joined$date)
      roll_cor <- zoo::rollapply(
        ret_mat,
        width      = w,
        FUN        = function(x) stats::cor(x[, 1], x[, 2], use = "complete.obs"),
        by.column  = FALSE,
        align      = "right",
        fill       = NA
      )

      # Vol regime: rolling SD of equally-weighted blended return
      blended  <- zoo::zoo((joined$ret_a + joined$ret_b) / 2, joined$date)
      roll_sd  <- zoo::rollapply(blended, width = w, FUN = stats::sd,
                                 align = "right", fill = NA)
      vol_thr  <- stats::quantile(as.numeric(roll_sd), 0.75, na.rm = TRUE)
      high_vol <- as.numeric(roll_sd) > vol_thr

      plot_df <- data.frame(
        date     = joined$date,
        roll_cor = as.numeric(roll_cor),
        high_vol = high_vol
      ) |> dplyr::filter(!is.na(roll_cor))

      shapes <- c(
        vol_regime_shapes(plot_df$date, plot_df$high_vol),
        # Zero reference line
        list(list(
          type = "line",
          xref = "paper", x0 = 0, x1 = 1,
          yref = "y",     y0 = 0, y1 = 0,
          line = list(color = "black", width = 0.8, dash = "dot")
        ))
      )

      plotly::plot_ly(
        plot_df,
        x             = ~date,
        y             = ~roll_cor,
        type          = "scatter",
        mode          = "lines",
        name          = paste0(input$ticker_a, " / ", input$ticker_b),
        line          = list(color = "#1565C0", width = 1.5),
        hovertemplate = "Date: %{x}<br>Correlation: %{y:.3f}<extra></extra>"
      ) |>
        plotly::layout(
          xaxis       = list(title = "Date"),
          yaxis       = list(title = "Correlation", range = c(-1, 1)),
          shapes      = shapes,
          annotations = list(list(
            xref      = "paper", yref = "paper",
            x = 0.01, y = 0.97,
            text      = paste0(
              "<span style='color:rgba(255,99,71,0.7)'>\u25a0</span>",
              " High volatility period"
            ),
            showarrow = FALSE,
            font      = list(size = 11),
            align     = "left"
          ))
        )
    })

    # VAR lag label displayed above IRF chart
    output$var_lag_label <- shiny::renderUI({
      shiny::req(r$var_results)
      shiny::tags$p(
        style = "color: #555; font-size: 0.88em; margin-bottom: 4px;",
        r$var_results$lag_label
      )
    })

    # Panel 2 — IRF chart
    output$plot_irf <- plotly::renderPlotly({
      shiny::req(r$var_results, input$shock_ticker)
      shock   <- input$shock_ticker
      results <- r$var_results
      irf_obj <- results$irfs[[shock]]

      # All tickers except the shock ticker respond
      respond_tickers <- setdiff(results$tickers, shock)
      horizon         <- 0:20
      n_resp          <- length(respond_tickers)

      # One distinct color per responding ticker; ribbon uses same color at low opacity
      line_colors <- viridisLite::turbo(n_resp, begin = 0.1, end = 0.9)

      p <- plotly::plot_ly()

      for (i in seq_along(respond_tickers)) {
        tkr <- respond_tickers[i]
        # irf_obj$irf indexed by shock ticker: matrix (n.ahead+1 rows × K response cols)
        pt    <- as.numeric(irf_obj$irf[[shock]][, tkr])
        lower <- as.numeric(irf_obj$Lower[[shock]][, tkr])
        upper <- as.numeric(irf_obj$Upper[[shock]][, tkr])

        line_col <- line_colors[i]
        rgb_vals <- grDevices::col2rgb(line_col)
        band_col <- sprintf("rgba(%d,%d,%d,0.15)", rgb_vals[1], rgb_vals[2], rgb_vals[3])

        # CI ribbon: upper path forward then lower path reversed for a closed polygon
        p <- plotly::add_trace(
          p,
          x          = c(horizon, rev(horizon)),
          y          = c(upper, rev(lower)),
          type       = "scatter",
          mode       = "none",
          fill       = "toself",
          fillcolor  = band_col,
          showlegend = FALSE,
          hoverinfo  = "skip"
        )

        # Point estimate line
        p <- plotly::add_trace(
          p,
          x             = horizon,
          y             = pt,
          type          = "scatter",
          mode          = "lines",
          name          = tkr,
          line          = list(color = line_col, width = 1.8),
          hovertemplate = paste0(tkr, " \u2014 Day %{x}: %{y:.5f}<extra></extra>")
        )
      }

      p |> plotly::layout(
        xaxis  = list(title = "Days after shock", dtick = 2),
        yaxis  = list(title = "Orthogonalised response"),
        shapes = list(list(
          type = "line",
          xref = "paper", x0 = 0, x1 = 1,
          yref = "y",     y0 = 0, y1 = 0,
          line = list(color = "black", width = 0.8, dash = "dot")
        )),
        legend = list(x = 1.01, y = 1)
      )
    })
  })
}
