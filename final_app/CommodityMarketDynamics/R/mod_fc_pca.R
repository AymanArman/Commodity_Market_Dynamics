# Forward Curves — Row 4: PCA Decomposition
# Computes PCA on the forward curve (date x tenor price matrix) for the
# selected ticker. Plots PC loadings vs. tenor for all PCs explaining >= 2%
# of variance. Results are lazily cached in r$[ticker]_pca on first selection.
#
# Parameters:
#   id     - Shiny module ID
#   dflong - full RTL::dflong tibble (date, series, value), passed from server
#   r      - shared reactiveValues; PCA results cached as r$[ticker]_pca
#
# Example:
#   mod_fc_pca_ui("fc_pca")
#   mod_fc_pca_server("fc_pca", dflong = dflong, r = r)

# ── UI ────────────────────────────────────────────────────────────────────────

mod_fc_pca_ui <- function(id) {
  ns <- shiny::NS(id)

  shiny::fluidRow(
    # col_a — narrative card
    shiny::column(
      width = 6,
      bslib::card(
        bslib::card_header("What PCA Reveals About the Forward Curve"),
        bslib::card_body(
          shiny::p(
            shiny::strong("What PCA is:"),
            " PCA identifies the directions along which the forward curve has
             historically varied the most. It does not model prices — it models
             the ", shiny::em("shape changes"), " of the curve over time."
          ),
          shiny::p(
            shiny::strong("Loadings:"),
            " Each principal component represents a recurring pattern of forward
             curve movement. The components reveal how tenors co-move — which
             parts of the curve move together and which move independently."
          ),
          shiny::tags$ul(
            shiny::tags$li(
              shiny::strong("PC1"), " describes the most common historical
              pattern of forward curve movement across tenors — typically a
              near-parallel shift."
            ),
            shiny::tags$li(
              shiny::strong("PC2"), " describes the second most common pattern —
              often a tilt (front moves opposite to back)."
            ),
            shiny::tags$li(
              shiny::strong("PC3"), " describes the third most common pattern —
              often a curvature (middle moves opposite to both ends)."
            )
          ),
          shiny::p(
            style = "font-style:italic; color:#f9f9f9; margin-top:8px;",
            "PCA decomposes the same covariance structure shown in the
             correlation heatmap on the Volatility page."
          )
        )
      )
    ),

    # col_b — PCA chart
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
        plotly::plotlyOutput(ns("chart"), height = "420px"),
        color = "#F87217"
      )
    )
  )
}

# ── Server ────────────────────────────────────────────────────────────────────

mod_fc_pca_server <- function(id, dflong, r) {
  shiny::moduleServer(id, function(input, output, session) {

    # Compute or retrieve cached PCA for the selected ticker
    pca_result <- shiny::reactive({
      ticker <- input$ticker
      shiny::req(ticker)

      cache_key <- paste0(ticker, "_pca")

      # Return cached result if already computed
      if (!is.null(r[[cache_key]])) {
        return(r[[cache_key]])
      }

      # Pivot to wide (date x tenor); drop rows with any NA
      wide <- dflong |>
        dplyr::filter(startsWith(series, ticker)) |>
        dplyr::mutate(
          tenor = paste0("M", sub("^[A-Za-z]+", "", series))
        ) |>
        dplyr::select(date, tenor, value) |>
        tidyr::pivot_wider(names_from = tenor, values_from = value) |>
        tidyr::drop_na() |>
        dplyr::arrange(date)

      shiny::req(nrow(wide) > 2)

      # Sort tenor columns numerically
      tenor_cols <- setdiff(names(wide), "date")
      tenor_cols <- tenor_cols[order(as.integer(sub("M0*", "", tenor_cols)))]
      price_mat  <- as.matrix(wide[, tenor_cols])

      # Run PCA with scaling
      pca_obj <- stats::prcomp(price_mat, scale. = TRUE)

      # Variance explained per component
      var_explained <- pca_obj$sdev^2 / sum(pca_obj$sdev^2)

      result <- list(pca = pca_obj, var_explained = var_explained,
                     tenors = tenor_cols)

      # Cache result in shared reactive values
      r[[cache_key]] <- result
      result
    })

    output$chart <- plotly::renderPlotly({
      res <- pca_result()
      shiny::req(!is.null(res))

      pca_obj      <- res$pca
      var_exp      <- res$var_explained
      tenors       <- res$tenors

      # Show top 3 PCs by variance explained
      qualifying   <- seq_len(min(3, length(var_exp)))
      shiny::req(length(qualifying) > 0)

      # Viridis palette for qualifying PCs (up to ~10 in practice)
      pal <- grDevices::colorRampPalette(
        c("#440154", "#31688e", "#35b779", "#fde725")
      )(length(qualifying))

      p <- plotly::plot_ly()

      for (i in seq_along(qualifying)) {
        pc_idx    <- qualifying[i]
        loadings  <- pca_obj$rotation[, pc_idx]
        pct_label <- paste0("PC", pc_idx, ": ",
                            round(var_exp[pc_idx] * 100, 1), "%")

        p <- plotly::add_trace(
          p,
          x    = tenors,
          y    = loadings,
          type = "scatter",
          mode = "lines+markers",
          name = pct_label,
          line = list(color = pal[i], width = 2),
          marker = list(color = pal[i], size = 4)
        )
      }

      p |>
        plotly::layout(
          xaxis = list(
            title     = "Tenor",
            tickangle = -45,
            type      = "category"
          ),
          yaxis = list(title = "Loading"),
          shapes = list(list(
            type = "line", x0 = 0, x1 = 1, xref = "paper",
            y0 = 0, y1 = 0,
            line = list(color = "#343d46", dash = "dash", width = 1)
          )),
          legend    = list(orientation = "h", y = -0.25),
          hovermode = "x unified"
        ) |>
        apply_theme()
    })
  })
}
