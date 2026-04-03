# Forward Curves page module
# Panel 1: scaled comparison chart (multi-ticker, date slider, normalized)
# Panel 2: 3D forward curve surface (plotly, viridis, regime floor)
# Panels 3 & 4: stubs
# Each panel owns its controls inline — no shared sidebar
# Parameters:
#   id     - module namespace id
#   dflong - full RTL::dflong tibble (passed from app_server)
#   r      - shared reactiveValues (written by analysis modules, read here)
# Example: mod_fwd_curves_ui("fwd_curves") / mod_fwd_curves_server("fwd_curves", dflong, r)

mod_fwd_curves_ui <- function(id) {
  ns <- shiny::NS(id)
  bslib::page_fluid(
    # Row 1 — Panel 1 and Panel 2 side by side
    bslib::layout_columns(
      col_widths = c(6, 6),

      bslib::card(
        bslib::card_body(
          shiny::tags$strong("Scaled Forward Curve Comparison"),
          shiny::tags$hr(style = "margin: 4px 0 8px 0;"),
          bslib::layout_columns(
            col_widths = c(6, 6),
            shiny::selectizeInput(
              ns("tickers_compare"),
              "Tickers",
              choices  = TICKERS,
              selected = c("CL", "BRN"),
              multiple = TRUE,
              options  = list(maxItems = 6)
            ),
            shiny::uiOutput(ns("date_slider_ui"))
          ),
          plotly::plotlyOutput(ns("plot_comparison"), height = "350px")
        )
      ),

      bslib::card(
        bslib::card_body(
          shiny::tags$strong("3D Forward Curve Surface"),
          shiny::tags$hr(style = "margin: 4px 0 8px 0;"),
          shiny::selectInput(
            ns("ticker_3d"),
            "Ticker",
            choices  = TICKERS,
            selected = "CL",
            width    = "200px"
          ),
          plotly::plotlyOutput(ns("plot_3d"), height = "350px")
        )
      )
    ),

    # Row 2 — Panel 3 and Panel 4 side by side (stubs)
    bslib::layout_columns(
      col_widths = c(6, 6),

      bslib::card(
        bslib::card_body(
          shiny::tags$strong("Slope & Regime Analytics"),
          shiny::tags$hr(style = "margin: 4px 0 8px 0;"),
          "Coming soon."
        )
      ),

      bslib::card(
        bslib::card_body(
          shiny::tags$strong("PCA Decomposition"),
          shiny::tags$hr(style = "margin: 4px 0 8px 0;"),
          "Coming soon."
        )
      )
    )
  )
}

mod_fwd_curves_server <- function(id, dflong, r) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Dates where ALL selected comparison tickers have data
    comparison_dates <- shiny::reactive({
      shiny::req(input$tickers_compare)
      date_sets <- lapply(input$tickers_compare, function(tkr) {
        unique(get_ticker(dflong, tkr)$date)
      })
      sort(Reduce(union, date_sets))
    })

    # Date slider restricted to valid intersection dates
    output$date_slider_ui <- shiny::renderUI({
      dates <- comparison_dates()
      shiny::req(length(dates) > 0)
      shiny::sliderInput(
        ns("snap_date"),
        "Snapshot Date",
        min        = min(dates),
        max        = max(dates),
        value      = max(dates),
        step       = 1,
        timeFormat = "%Y-%m-%d"
      )
    })

    # Panel 1 — scaled comparison chart
    output$plot_comparison <- plotly::renderPlotly({
      shiny::req(input$tickers_compare, input$snap_date)
      snap <- as.Date(input$snap_date)

      curves <- lapply(input$tickers_compare, function(tkr) {
        dat <- get_ticker(dflong, tkr) |>
          dplyr::filter(date == snap) |>
          dplyr::arrange(tenor)
        if (nrow(dat) == 0) return(NULL)
        history <- get_ticker(dflong, tkr)
        mn  <- min(history$value, na.rm = TRUE)
        mx  <- max(history$value, na.rm = TRUE)
        dplyr::mutate(dat, norm_value = (value - mn) / (mx - mn), ticker = tkr)
      })

      curves <- dplyr::bind_rows(curves)
      shiny::validate(shiny::need(nrow(curves) > 0, "No data for selected tickers on this date."))

      plotly::plot_ly(
        data      = curves,
        x         = ~tenor,
        y         = ~norm_value,
        color     = ~ticker,
        type      = "scatter",
        mode      = "lines+markers",
        text      = ~paste0(ticker, " M", sprintf("%02d", tenor), "<br>Raw: ", round(value, 2)),
        hoverinfo = "text"
      ) |>
        plotly::layout(
          xaxis  = list(title = "Tenor (months)"),
          yaxis  = list(title = "Normalized Price [0-1]", range = c(0, 1)),
          legend = list(orientation = "h")
        )
    })

    # Panel 2 — 3D forward curve surface with regime floor
    output$plot_3d <- plotly::renderPlotly({
      shiny::req(input$ticker_3d)
      tkr <- input$ticker_3d

      # Compute or retrieve cached regime
      cache_key <- paste0(tkr, "_regime")
      if (is.null(r[[cache_key]])) {
        r[[cache_key]] <- compute_regime(get_ticker(dflong, tkr))
      }
      regime_df <- r[[cache_key]]

      wide       <- pivot_ticker_wide(get_ticker(dflong, tkr))
      tenor_cols <- setdiff(names(wide), "date")
      dates      <- wide$date
      price_mat  <- as.matrix(wide[, tenor_cols])
      tenors     <- as.integer(sub(paste0("^", tkr), "", tenor_cols))

      regime_aligned <- regime_df |>
        dplyr::filter(date %in% dates) |>
        dplyr::arrange(match(date, dates))

      regime_num <- dplyr::case_when(
        regime_aligned$regime == "contango"      ~ 0,
        regime_aligned$regime == "backwardation" ~ 1,
        TRUE                                     ~ 0.5
      )

      floor_z     <- matrix(min(price_mat, na.rm = TRUE), nrow = nrow(price_mat), ncol = ncol(price_mat))
      floor_color <- matrix(rep(regime_num, ncol(price_mat)), nrow = nrow(price_mat))
      date_str    <- as.character(dates)  # ISO strings so plotly recognises as dates

      plotly::plot_ly() |>
        plotly::add_surface(
          x             = tenors,
          y             = date_str,
          z             = price_mat,
          colorscale    = "Viridis",
          showscale     = TRUE,
          name          = "Price",
          hovertemplate = "Tenor: %{x}<br>Price: %{z:.2f}<extra></extra>"
        ) |>
        plotly::add_surface(
          x             = tenors,
          y             = date_str,
          z             = floor_z,
          surfacecolor  = floor_color,
          colorscale    = list(list(0, "#4393c3"), list(1, "#d6604d")),
          showscale     = FALSE,
          opacity       = 0.6,
          name          = "Regime",
          hovertemplate = "Regime floor<extra></extra>"
        ) |>
        plotly::layout(
          scene = list(
            xaxis = list(title = "Tenor"),
            yaxis = list(title = "Date", tickformat = "%m-%Y"),
            zaxis = list(title = "Price")
          )
        )
    })
  })
}
