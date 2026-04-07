# Volatility Page — Row 2: Correlation Matrix Heatmap
# Renders a symmetric correlation matrix heatmap of tenor returns for the
# selected ticker. HTT automatically routes through level differences via
# compute_returns(). Static beyond ticker selection.
#
# Parameters:
#   id     - Shiny module ID
#   dflong - full RTL::dflong tibble (date, series, value), passed from server
#
# Example:
#   mod_vol_heatmap_ui("vol_heatmap")
#   mod_vol_heatmap_server("vol_heatmap", dflong = dflong)

# ── UI ───────────────────────────────────────────────────────────────────────

mod_vol_heatmap_ui <- function(id) {
  ns <- shiny::NS(id)

  shiny::fluidRow(
    # col_a — narrative card
    shiny::column(
      width = 6,
      bslib::card(
        bslib::card_body(
          shinyWidgets::pickerInput(
            inputId  = ns("ticker"),
            label    = "Commodity",
            choices  = c("CL", "BRN", "NG", "HO", "RB", "HTT"),
            selected = "CL",
            multiple = FALSE
          ),
          shiny::p(
            "Seasonality is visible in the matrix for NG and RB — tenors that ",
            "span different demand seasons (e.g. summer vs. winter) decorrelate ",
            "from each other, reflecting structurally different price drivers ",
            "across the curve."
          ),
          shiny::p(
            "HTT is the most structurally segmented curve in the dataset. The ",
            "front month moves largely on its own — driven by real-time pipeline ",
            "congestion, Cushing inventory, and prompt storage arbitrage — and ",
            "decorrelates sharply from the rest of the curve. Beyond M01, the ",
            "back end coheres as a bloc anchored by longer-run structural ",
            "expectations. Reference the PC2 and PC3 loadings on the Forward ",
            "Curves page to see how these segments shift together and understand ",
            "their relationship with the correlation structure shown here."
          ),
          shiny::p(
            "Crude (CL, BRN) tends to show a matrix that is predominantly one ",
            "colour — front month price changes propagate across the entire curve; ",
            "correlation decays slightly toward the back but remains high ",
            "throughout, reflecting that crude supply shocks reprice the whole ",
            "forward curve, not just the front."
          )
        )
      )
    ),
    # col_b — heatmap
    shiny::column(
      width = 6,
      plotly::plotlyOutput(ns("heatmap"), height = "500px")
    )
  )
}

# ── Server ───────────────────────────────────────────────────────────────────

mod_vol_heatmap_server <- function(id, dflong) {
  shiny::moduleServer(id, function(input, output, session) {

    output$heatmap <- plotly::renderPlotly({
      shiny::req(input$ticker)

      # Compute returns — compute_returns() handles HTT automatically (test 2.12)
      returns_long <- dflong |>
        dplyr::filter(startsWith(series, input$ticker)) |>
        compute_returns()

      shiny::req(nrow(returns_long) > 0)

      # Pivot to wide (date × tenor).
      # values_fn = mean guards against any duplicate (date, tenor) pairs in the
      # source data (e.g. RTL series with repeated observations on the same date).
      # No drop_na() here — pairwise.complete.obs in cor() handles missingness
      # correctly without forcing every tenor to share the same date window,
      # which would silently exclude back tenors with shorter history (fixes RB M02).
      returns_wide <- returns_long |>
        tidyr::pivot_wider(
          names_from  = tenor,
          values_from = return,
          values_fn   = mean
        ) |>
        dplyr::select(-date)

      shiny::req(ncol(returns_wide) >= 2)

      # Sort tenors M01 → M_last for consistent axis ordering
      tenor_order  <- sort(colnames(returns_wide))
      returns_wide <- returns_wide[, tenor_order, drop = FALSE]

      # Correlation matrix — pairwise.complete.obs uses all available date pairs
      # per tenor combination, so tenors with different start dates still correlate
      # correctly (tests 2.9 – 2.11)
      cor_matrix <- stats::cor(as.matrix(returns_wide), use = "pairwise.complete.obs")

      # Replace NaN (zero-variance tenor) with NA so plotly renders as blank cell
      cor_matrix[is.nan(cor_matrix)] <- NA

      # Reverse y-axis so M01 appears at top-left (conventional matrix orientation)
      plotly::plot_ly(
        z            = cor_matrix,
        x            = tenor_order,
        y            = tenor_order,
        type         = "heatmap",
        colorscale   = "Spectral",
        reversescale = TRUE,
        zmin         = -1,
        zmax         = 1,
        hovertemplate = "%{y} / %{x}: %{z:.3f}<extra></extra>"
      ) |>
        plotly::layout(
          xaxis = list(title = "Tenor", tickangle = -45),
          yaxis = list(title = "Tenor", autorange = "reversed")
        ) |>
        apply_theme()
    })
  })
}
