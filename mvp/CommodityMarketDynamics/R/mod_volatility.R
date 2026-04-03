# Volatility page module
# Panel 1: cascading ridgeline density plot (per tenor, viridis, tenor 1 at back/top)
# Panel 2: tenor return correlation matrix heatmap
# Both panels driven by a single ticker selector; returns are lazily cached in r
# Parameters:
#   id     - module namespace id
#   dflong - full RTL::dflong tibble (passed from app_server)
#   r      - shared reactiveValues (written lazily here; read by other modules)
# Example: mod_volatility_ui("volatility") / mod_volatility_server("volatility", dflong, r)

# Converts a hex color string to an rgba() string with specified alpha.
# Parameters:
#   hex   - hex color string (e.g. "#440154")
#   alpha - numeric in [0, 1]
# Returns: character string e.g. "rgba(68,1,84,0.25)"
# Example: hex_to_rgba("#440154", 0.25)
hex_to_rgba <- function(hex, alpha = 0.25) {
  rgb_vals <- grDevices::col2rgb(hex)
  sprintf("rgba(%d,%d,%d,%.2f)", rgb_vals[1], rgb_vals[2], rgb_vals[3], alpha)
}

mod_volatility_ui <- function(id) {
  ns <- shiny::NS(id)
  bslib::page_fluid(
    # Shared ticker selector — applies to both panels
    shiny::selectInput(
      ns("ticker_vol"),
      "Ticker",
      choices  = TICKERS,
      selected = "CL",
      width    = "150px"
    ),

    # Row 1 — density chart + notes
    bslib::layout_columns(
      col_widths = c(8, 4),

      bslib::card(
        bslib::card_body(
          shiny::tags$strong("Return Distribution by Tenor"),
          shiny::tags$hr(style = "margin: 4px 0 8px 0;"),
          shiny::uiOutput(ns("tenor_filter_ui")),
          plotly::plotlyOutput(ns("plot_hist"), height = "350px")
        )
      ),

      bslib::card(
        bslib::card_body(
          shiny::tags$p("Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat."),
          shiny::tags$p("Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.")
        )
      )
    ),

    # Row 2 — notes + correlation matrix
    bslib::layout_columns(
      col_widths = c(6, 6),

      bslib::card(
        bslib::card_body(
          shiny::tags$p("Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat."),
          shiny::tags$p("Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.")
        )
      ),

      bslib::card(
        bslib::card_body(
          shiny::tags$strong("Tenor Return Correlation Matrix"),
          shiny::tags$hr(style = "margin: 4px 0 8px 0;"),
          plotly::plotlyOutput(ns("plot_corr"), height = "420px")
        )
      )
    )
  )
}

mod_volatility_server <- function(id, dflong, r) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Lazy-cached log returns for selected ticker
    returns_wide <- shiny::reactive({
      shiny::req(input$ticker_vol)
      tkr       <- input$ticker_vol
      cache_key <- paste0(tkr, "_returns")
      if (is.null(r[[cache_key]])) {
        r[[cache_key]] <- compute_returns(get_ticker(dflong, tkr))
      }
      r[[cache_key]]
    })

    # Tenor range slider — dynamically generated from available tenors for selected ticker
    output$tenor_filter_ui <- shiny::renderUI({
      rw         <- returns_wide()
      tkr        <- input$ticker_vol
      tenor_cols <- setdiff(names(rw), "date")
      tenor_nums <- sort(as.integer(sub(paste0("^", tkr), "", tenor_cols)))
      shiny::sliderInput(
        ns("tenor_range"),
        "Tenor range",
        min   = min(tenor_nums),
        max   = max(tenor_nums),
        value = c(min(tenor_nums), max(tenor_nums)),
        step  = 1
      )
    })

    # Panel 1 — overlaid density curves per tenor; x-axis clipped to 1st/99th percentile
    output$plot_hist <- plotly::renderPlotly({
      shiny::req(input$ticker_vol, input$tenor_range)
      rw         <- returns_wide()
      tkr        <- input$ticker_vol
      tenor_cols <- setdiff(names(rw), "date")
      tenor_nums <- as.integer(sub(paste0("^", tkr), "", tenor_cols))

      # Filter to user-selected tenor range
      selected_cols <- tenor_cols[
        tenor_nums >= input$tenor_range[1] & tenor_nums <= input$tenor_range[2]
      ]
      shiny::validate(shiny::need(length(selected_cols) > 0, "No tenors in selected range."))

      n      <- length(selected_cols)
      colors <- viridisLite::turbo(n)

      # Shared x-axis bounds: pool all values, clip to 1st/99th percentile
      all_vals <- unlist(lapply(selected_cols, function(col) rw[[col]][!is.na(rw[[col]])]))
      x_lo     <- stats::quantile(all_vals, 0.01)
      x_hi     <- stats::quantile(all_vals, 0.99)

      # Pre-compute densities within clipped bounds
      dens_list <- lapply(selected_cols, function(col) {
        vals <- rw[[col]][!is.na(rw[[col]])]
        stats::density(vals, from = x_lo, to = x_hi, n = 256)
      })

      # Alpha decreases from tenor 1 (most opaque) to tenor N (most transparent)
      alpha_max <- 0.45
      alpha_min <- 0.08
      alphas    <- if (n == 1) alpha_max else
        seq(alpha_min, alpha_max, length.out = n)

      # Overlaid density curves: fill to zero, line darker than fill area
      # Render from tenor N down to tenor 1 so tenor 1 is drawn last (sits on top)
      p <- plotly::plot_ly()
      for (i in rev(seq_along(selected_cols))) {
        col <- selected_cols[i]
        d   <- dens_list[[i]]
        p <- plotly::add_lines(
          p,
          x             = d$x,
          y             = d$y,
          name          = col,
          fill          = "tozeroy",
          fillcolor     = hex_to_rgba(colors[i], alphas[i]),
          line          = list(color = colors[i], width = 1.5),
          showlegend    = (n <= 12),
          hovertemplate = paste0(col, "<br>Return: %{x:.4f}<br>Density: %{y:.4f}<extra></extra>")
        )
      }

      is_spread <- any(get_ticker(dflong, tkr)$value < 0, na.rm = TRUE)
      x_label   <- if (is_spread) "Level Difference" else "Log Return"

      p |> plotly::layout(
        xaxis = list(title = x_label, range = c(x_lo, x_hi)),
        yaxis = list(title = "Density"),
        legend = list(orientation = "v")
      )
    })

    # Panel 2 — pairwise correlation heatmap across all tenors
    output$plot_corr <- plotly::renderPlotly({
      shiny::req(input$ticker_vol)
      rw         <- returns_wide()
      tenor_cols <- setdiff(names(rw), "date")

      # Drop tenors with fewer than 30 non-NA return observations — they produce NA
      # correlations (white cells) and add no information to the heatmap
      tenor_cols <- tenor_cols[
        sapply(tenor_cols, function(col) sum(!is.na(rw[[col]]))) >= 30
      ]
      shiny::validate(shiny::need(length(tenor_cols) >= 2, "Insufficient data to compute correlations."))

      corr_mat <- cor(rw[, tenor_cols], use = "pairwise.complete.obs")

      plotly::plot_ly(
        x            = tenor_cols,
        y            = tenor_cols,
        z            = corr_mat,
        type         = "heatmap",
        colorscale   = "Spectral",
        reversescale = TRUE,
        zmin         = -1,
        zmax         = 1,
        hovertemplate = "X: %{x}<br>Y: %{y}<br>Corr: %{z:.3f}<extra></extra>"
      ) |>
        plotly::layout(
          xaxis = list(title = "Tenor"),
          yaxis = list(title = "Tenor")
        )
    })
  })
}
