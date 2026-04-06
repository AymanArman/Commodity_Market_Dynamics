# Forward Curves — Row 3: Monthly Forward Curve Overlays
# Renders 12 lines (one per calendar month) showing the average forward curve
# shape for each month across all available years for the selected ticker.
#
# Parameters:
#   id     - Shiny module ID
#   dflong - full RTL::dflong tibble (date, series, value), passed from server
#
# Example:
#   mod_fc_monthly_ui("fc_monthly")
#   mod_fc_monthly_server("fc_monthly", dflong = dflong)

# 12-color discrete palette (visually distinct, not viridis)
MONTHLY_PALETTE <- c(
  "#1f77b4", "#ff7f0e", "#2ca02c", "#d62728",
  "#9467bd", "#8c564b", "#e377c2", "#7f7f7f",
  "#bcbd22", "#17becf", "#aec7e8", "#ffbb78"
)

# ── UI ────────────────────────────────────────────────────────────────────────

mod_fc_monthly_ui <- function(id) {
  ns <- shiny::NS(id)

  shiny::fluidRow(
    shiny::column(
      width = 12,
      shiny::h4(
        "Seasonal Forward Curve Shapes",
        style = "color:#f9f9f9; margin-bottom:4px; text-align:center;"
      ),
      shiny::p(
        style = "color:#f9f9f9; font-style:italic; margin-bottom:10px; text-align:center;",
        "Average forward curve by calendar month — systematic differences
         between months reveal seasonal premia embedded in the curve."
      ),
      shinyWidgets::pickerInput(
        inputId  = ns("ticker"),
        label    = "Select commodity",
        choices  = c("CL", "BRN", "NG", "HO", "RB", "HTT"),
        selected = "CL",
        multiple = FALSE
      ),
      shinycssloaders::withSpinner(
        plotly::plotlyOutput(ns("chart"), height = "450px"),
        color = "#F87217"
      )
    )
  )
}

# ── Server ────────────────────────────────────────────────────────────────────

mod_fc_monthly_server <- function(id, dflong) {
  shiny::moduleServer(id, function(input, output, session) {

    output$chart <- plotly::renderPlotly({
      ticker <- input$ticker
      shiny::req(ticker)

      # Compute mean price per (calendar month x tenor) across all available years
      monthly_data <- dflong |>
        dplyr::filter(startsWith(series, ticker)) |>
        dplyr::mutate(
          tenor = paste0("M", sub("^[A-Za-z]+", "", series)),
          month = lubridate::month(date, label = TRUE, abbr = TRUE)
        ) |>
        dplyr::group_by(month, tenor) |>
        dplyr::summarise(mean_price = mean(value, na.rm = TRUE), .groups = "drop")

      shiny::req(nrow(monthly_data) > 0)

      # Sort tenors numerically for x-axis ordering
      all_tenors <- unique(monthly_data$tenor)
      all_tenors <- all_tenors[order(as.integer(sub("M0*", "", all_tenors)))]

      # Month ordering Jan -> Dec
      month_levels <- c("Jan","Feb","Mar","Apr","May","Jun",
                        "Jul","Aug","Sep","Oct","Nov","Dec")

      p <- plotly::plot_ly()

      for (i in seq_along(month_levels)) {
        m    <- month_levels[i]
        mdat <- monthly_data |>
          dplyr::filter(as.character(month) == m) |>
          dplyr::arrange(match(tenor, all_tenors))

        if (nrow(mdat) == 0) next

        p <- plotly::add_trace(
          p,
          data   = mdat,
          x      = ~factor(tenor, levels = all_tenors),
          y      = ~mean_price,
          type   = "scatter",
          mode   = "lines+markers",
          name   = m,
          line   = list(color = MONTHLY_PALETTE[i], width = 2),
          marker = list(color = MONTHLY_PALETTE[i], size = 4)
        )
      }

      p |>
        plotly::layout(
          xaxis = list(
            title     = "Tenor",
            tickangle = -45,
            type      = "category"
          ),
          yaxis     = list(title = "Average Price"),
          legend    = list(orientation = "h", y = -0.25),
          hovermode = "x unified"
        ) |>
        apply_theme()
    })
  })
}
