# Forward Curves — Row 2: 3D Forward Curve Surface
# Renders a 3D plotly surface (X=tenor, Y=date, Z=price) with viridis color
# scale on the surface and a contango/backwardation regime floor.
# Regime is smoothed via a 5-day centered rolling majority vote.
#
# Parameters:
#   id     - Shiny module ID
#   dflong - full RTL::dflong tibble (date, series, value), passed from server
#
# Example:
#   mod_fc_surface_ui("fc_surface")
#   mod_fc_surface_server("fc_surface", dflong = dflong)

# ── Helpers (non-reactive, exported for testing) ──────────────────────────────

# Classify each date as "contango" or "backwardation" from a wide price matrix.
# Contango  = last available tenor priced above M01 on that date.
# Backwardation = M01 priced above last available tenor.
#
# Parameters:
#   wide_df - data.frame with date column + one column per tenor (M01, M02, ...)
# Returns: data.frame(date, regime) — one row per date
classify_regime <- function(wide_df) {
  tenor_cols <- setdiff(names(wide_df), "date")
  # Sort tenors numerically so last column is the furthest available tenor
  tenor_cols <- tenor_cols[order(as.integer(sub("M0*", "", tenor_cols)))]
  last_tenor <- tenor_cols[length(tenor_cols)]

  wide_df |>
    dplyr::mutate(
      regime = dplyr::if_else(
        .data[["M01"]] < .data[[last_tenor]],
        "contango",
        "backwardation"
      )
    ) |>
    dplyr::select(date, regime)
}

# Apply a 5-day centered rolling majority vote to smooth regime classification.
# Uses a window of 5 (2 days before, current, 2 days after).
# Ties broken in favour of "contango".
#
# Parameters:
#   regime_df - data.frame(date, regime) sorted by date
# Returns: data.frame(date, regime) with smoothed regime
smooth_regime <- function(regime_df) {
  n <- nrow(regime_df)
  smoothed <- character(n)
  for (i in seq_len(n)) {
    lo  <- max(1, i - 2)
    hi  <- min(n, i + 2)
    win <- regime_df$regime[lo:hi]
    smoothed[i] <- ifelse(sum(win == "contango") >= sum(win == "backwardation"),
                          "contango", "backwardation")
  }
  regime_df$regime <- smoothed
  regime_df
}

# ── UI ────────────────────────────────────────────────────────────────────────

mod_fc_surface_ui <- function(id) {
  ns <- shiny::NS(id)

  shiny::fluidRow(
    # col_a — 3D surface chart
    shiny::column(
      width = 6,
      shinyWidgets::pickerInput(
        inputId  = ns("ticker"),
        label    = "Select commodity",
        choices  = c("CL", "BRN", "NG", "HO", "RB", "HTT"),
        selected = "CL",
        multiple = FALSE
      ),
      shinycssloaders::withSpinner(
        plotly::plotlyOutput(ns("surface"), height = "520px"),
        color = "#F87217"
      )
    ),

    # col_b — narrative card
    shiny::column(
      width = 6,
      bslib::card(
        bslib::card_header("Reading the 3D Forward Curve Surface"),
        bslib::card_body(
          shiny::p(shiny::strong("X — Tenor:"),
            "How far out along the forward curve. M01 is the front month
             (nearest delivery); Mn is the furthest available contract."),
          shiny::p(shiny::strong("Y — Date:"),
            "The historical date on which that forward curve was observed.
             Each slice parallel to the X-axis is one day's curve."),
          shiny::p(shiny::strong("Z — Price:"),
            "The futures price for that tenor on that date. The surface
             colour follows a viridis scale mapped to price level — darker
             blues indicate lower prices, yellows indicate higher prices."),
          shiny::hr(),
          shiny::p(shiny::strong("Regime floor:"),
            "The floor of the plot is coloured by the prevailing market
             regime on each date.",
            shiny::span(style = "color:#35b779; font-weight:bold;", "Green"),
            " = Contango (back months priced above front — normal carry structure,
             reflecting storage costs and time value).",
            shiny::span(style = "color:#CC5500; font-weight:bold;", " Orange"),
            " = Backwardation (front months priced above back — signals supply
             tightness or a demand spike pulling near-term prices above longer-dated
             expectations). Regime is smoothed with a 5-day centered rolling
             majority vote to suppress one-day classification flickers."
          ),
          shiny::p(shiny::strong("Notice:"),
            "Forward curves tend to enter contango during periods of oversupply
             or weak demand — visible on the surface as lower price levels — while
             backwardation typically occurs when supply is tight and prices are
             elevated, appearing as peaks on the surface. This reflects a deeper
             property of energy markets: commodities such as crude oil and natural
             gas are fundamentally mean-reverting. Absent structural shifts in
             infrastructure, production technology, or consumption efficiency,
             prices are anchored by a long-run supply/demand equilibrium."
          )
        )
      )
    )
  )
}

# ── Server ────────────────────────────────────────────────────────────────────

mod_fc_surface_server <- function(id, dflong) {
  shiny::moduleServer(id, function(input, output, session) {

    output$surface <- plotly::renderPlotly({
      ticker <- input$ticker
      shiny::req(ticker)

      # Filter to selected ticker; extract all tenors and dates
      ticker_data <- dflong |>
        dplyr::filter(startsWith(series, ticker)) |>
        dplyr::mutate(
          tenor = paste0("M", sub("^[A-Za-z]+", "", series))
        )

      # Pivot to wide (date x tenor); drop rows with any NA tenor value
      wide <- ticker_data |>
        dplyr::select(date, tenor, value) |>
        tidyr::pivot_wider(names_from = tenor, values_from = value) |>
        dplyr::arrange(date) |>
        tidyr::drop_na()

      shiny::req(nrow(wide) > 0)

      # Sort tenor columns numerically
      tenor_cols <- setdiff(names(wide), "date")
      tenor_cols <- tenor_cols[order(as.integer(sub("M0*", "", tenor_cols)))]
      wide <- wide[, c("date", tenor_cols)]

      # Classify and smooth regime
      regime_raw      <- classify_regime(wide)
      regime_smoothed <- smooth_regime(regime_raw)

      # Build matrices for plotly surface
      # X = tenor index, Y = date index, Z = price
      z_matrix <- as.matrix(wide[, tenor_cols])
      y_vals   <- as.numeric(wide$date)   # numeric dates for plotly
      x_vals   <- seq_along(tenor_cols)   # tenor indices 1..n

      # Regime floor: project a flat surface at min(Z) - small offset,
      # coloured by regime. Use a 2-color scale: contango=green, backward=orange
      z_min   <- min(z_matrix, na.rm = TRUE)
      z_floor <- z_min - (max(z_matrix, na.rm = TRUE) - z_min) * 0.05

      # Regime color matrix: one column per tenor (all same value per row)
      regime_num <- ifelse(regime_smoothed$regime == "contango", 1, 0)
      floor_z    <- matrix(z_floor, nrow = nrow(wide), ncol = length(tenor_cols))
      floor_color <- matrix(
        rep(regime_num, length(tenor_cols)),
        nrow = nrow(wide), ncol = length(tenor_cols)
      )

      # Date tick formatting: sample ~8 evenly spaced dates for Y axis labels
      n_dates      <- length(y_vals)
      tick_indices <- round(seq(1, n_dates, length.out = min(8, n_dates)))
      tick_vals    <- y_vals[tick_indices]
      tick_text    <- format(wide$date[tick_indices], "%Y-%m")

      p <- plotly::plot_ly() |>
        # Main viridis surface
        plotly::add_surface(
          x          = tenor_cols,
          y          = y_vals,
          z          = z_matrix,
          colorscale = "Viridis",
          showscale  = TRUE,
          name       = "Price",
          colorbar   = list(title = "Price", x = 1.02)
        ) |>
        # Regime floor surface
        plotly::add_surface(
          x          = tenor_cols,
          y          = y_vals,
          z          = floor_z,
          surfacecolor = floor_color,
          colorscale = list(list(0, "#CC5500"), list(1, "#35b779")),
          showscale  = FALSE,
          opacity    = 0.85,
          name       = "Regime",
          hoverinfo  = "skip"
        ) |>
        plotly::layout(
          scene = list(
            xaxis = list(
              title      = "Tenor",
              tickvals   = tenor_cols,
              ticktext   = tenor_cols,
              tickangle  = -45,
              color      = "#343d46"
            ),
            yaxis = list(
              title    = "Date",
              tickvals = tick_vals,
              ticktext = tick_text,
              color    = "#343d46"
            ),
            zaxis = list(
              title = "Price",
              color = "#343d46"
            ),
            bgcolor = "#fffff2"
          ),
          margin = list(l = 0, r = 0, t = 20, b = 0)
        ) |>
        apply_theme()

      p
    })
  })
}
