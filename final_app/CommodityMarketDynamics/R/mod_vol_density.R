# Volatility Page — Row 1: Return Distribution & Volatility Bar Chart
# Renders an overlaid density chart (one curve per tenor, back tenors more
# translucent) and a horizontal bar chart showing annualised volatility per
# tenor. Owns the ticker selector and tenor range slider for this row.
#
# Parameters:
#   id     - Shiny module ID
#   dflong - full RTL::dflong tibble (date, series, value), passed from server
#
# Example:
#   mod_vol_density_ui("vol_density")
#   mod_vol_density_server("vol_density", dflong = dflong)

# ── UI ───────────────────────────────────────────────────────────────────────

mod_vol_density_ui <- function(id) {
  ns <- shiny::NS(id)

  tagList(
    # Controls: ticker selector + tenor range slider
    shiny::fluidRow(
      shiny::column(
        width = 3,
        shinyWidgets::pickerInput(
          inputId  = ns("ticker"),
          label    = "Commodity",
          choices  = c("CL", "BRN", "NG", "HO", "RB", "HTT"),
          selected = "CL",
          multiple = FALSE
        )
      ),
      shiny::column(
        width = 9,
        shiny::sliderInput(
          inputId = ns("tenor_range"),
          label   = "Tenor range (density chart only)",
          min     = 1,
          max     = 36,
          value   = c(1, 36),
          step    = 1,
          width   = "100%",
          ticks   = FALSE
        )
      )
    ),
    # Charts row
    shiny::fluidRow(
      # col_a — overlaid density chart
      shiny::column(
        width = 6,
        plotly::plotlyOutput(ns("density_chart"), height = "400px")
      ),
      # col_b — horizontal volatility bar chart
      shiny::column(
        width = 4,
        plotly::plotlyOutput(ns("vol_bar"), height = "400px")
      ),
      # col_c — narrative card
      shiny::column(
        width = 2,
        bslib::card(
          bslib::card_body(
            shiny::p(
              "Return distributions stacked by tenor reveal how volatility ",
              "decays across the term structure. Front months carry the most ",
              "uncertainty; back months are anchored by slower-moving ",
              "supply/demand fundamentals."
            )
          )
        )
      )
    )
  )
}

# ── Server ───────────────────────────────────────────────────────────────────

mod_vol_density_server <- function(id, dflong) {
  shiny::moduleServer(id, function(input, output, session) {

    # All available tenors for the selected ticker, sorted ("M01", "M02", ...)
    available_tenors <- shiny::reactive({
      shiny::req(input$ticker)
      dflong |>
        dplyr::filter(startsWith(series, input$ticker)) |>
        dplyr::pull(series) |>
        unique() |>
        (\(s) paste0("M", sub("^[A-Za-z]+", "", s)))() |>
        unique() |>
        sort()
    })

    # Update tenor slider max when ticker changes
    shiny::observeEvent(available_tenors(), {
      tenors <- available_tenors()
      n      <- length(tenors)
      shiny::updateSliderInput(
        session = session,
        inputId = "tenor_range",
        min     = 1,
        max     = n,
        value   = c(1, n)
      )
    }, ignoreInit = FALSE)

    # TRUE when selected ticker is a spread (HTT) — affects axis labels
    is_spread <- shiny::reactive({
      shiny::req(input$ticker)
      input$ticker == "HTT"
    })

    # All returns for the selected ticker (long: date, tenor, return)
    all_returns <- shiny::reactive({
      shiny::req(input$ticker)
      dflong |>
        dplyr::filter(startsWith(series, input$ticker)) |>
        compute_returns()
    })

    # ── Density chart ──────────────────────────────────────────────────────────
    output$density_chart <- plotly::renderPlotly({
      shiny::req(input$tenor_range, nrow(all_returns()) > 0)

      tenors  <- available_tenors()
      rng     <- input$tenor_range
      x_label <- if (is_spread()) "Level Difference" else "Log Return"

      sel_tenors <- tenors[seq(rng[1], rng[2])]
      n_sel      <- length(sel_tenors)

      # Pull return vectors per selected tenor
      ret_list <- lapply(sel_tenors, function(t) {
        v <- all_returns() |> dplyr::filter(tenor == t) |> dplyr::pull(return)
        v[!is.na(v)]
      })
      names(ret_list) <- sel_tenors

      # Shared x-axis clip: pool all selected tenors, take [p01, p99] once,
      # pass from/to into density() so all curves share the same x domain
      all_vals <- unlist(ret_list)
      x_lo     <- stats::quantile(all_vals, 0.01, na.rm = TRUE)
      x_hi     <- stats::quantile(all_vals, 0.99, na.rm = TRUE)

      # Turbo colors: one per selected tenor, index 1 = front tenor
      colors <- viridisLite::turbo(n_sel)

      # Alpha: back tenors more opaque (0.45), front tenor least opaque (0.08).
      # Front tenor rendered last so it sits on top regardless of fill opacity.
      alphas <- if (n_sel == 1L) 0.45 else seq(0.08, 0.45, length.out = n_sel)
      # alphas[1]=0.08 (front tenor M01), alphas[n]=0.45 (back tenor)

      p <- plotly::plot_ly()

      # Render back to front: back tenors first (behind), front tenor last (on top)
      for (i in rev(seq_along(sel_tenors))) {
        t    <- sel_tenors[i]
        vals <- ret_list[[t]]
        if (length(vals) < 10L) next

        dens      <- stats::density(vals, from = x_lo, to = x_hi, n = 512L)
        col       <- colors[i]
        rgb_vals  <- grDevices::col2rgb(col)
        fill_rgba <- sprintf("rgba(%d,%d,%d,%.2f)",
                             rgb_vals[1L], rgb_vals[2L], rgb_vals[3L], alphas[i])

        p <- plotly::add_lines(
          p,
          x             = dens$x,
          y             = dens$y,
          name          = t,
          fill          = "tozeroy",
          fillcolor     = fill_rgba,
          line          = list(color = col, width = 1.5),
          showlegend    = (n_sel <= 12L),
          hovertemplate = paste0(t, "<br>", x_label, ": %{x:.5f}<br>Density: %{y:.4f}<extra></extra>")
        )
      }

      p |>
        plotly::layout(
          xaxis     = list(title = x_label, range = c(x_lo, x_hi)),
          yaxis     = list(title = "Density"),
          legend    = list(orientation = "v"),
          hovermode = "closest"
        ) |>
        apply_theme()
    })

    # ── Volatility bar chart ───────────────────────────────────────────────────
    # Always shows ALL available tenors regardless of the density slider (test 2.5)
    output$vol_bar <- plotly::renderPlotly({
      shiny::req(nrow(all_returns()) > 0)

      tenors <- available_tenors()

      # Annualised vol per tenor: sd(returns) × sqrt(252) (test 2.6)
      vol_data <- all_returns() |>
        dplyr::filter(tenor %in% tenors) |>
        dplyr::group_by(tenor) |>
        dplyr::summarise(
          vol    = stats::sd(return, na.rm = TRUE) * sqrt(252),
          .groups = "drop"
        ) |>
        # Reverse levels so M01 appears at top of horizontal bar chart
        dplyr::mutate(tenor = factor(tenor, levels = rev(tenors)))

      shiny::req(nrow(vol_data) > 0)

      # turbo colors indexed by tenor position (same palette as density chart)
      n_all      <- length(tenors)
      all_colors <- viridisLite::turbo(n_all)
      names(all_colors) <- tenors
      bar_colors <- all_colors[as.character(vol_data$tenor)]

      plotly::plot_ly(
        data          = vol_data,
        x             = ~vol,
        y             = ~tenor,
        type          = "bar",
        orientation   = "h",
        marker        = list(color = bar_colors),
        hovertemplate = "%{y}: %{x:.4f}<extra></extra>",
        showlegend    = FALSE
      ) |>
        plotly::layout(
          xaxis = list(title = "Annualised Volatility"),
          yaxis = list(title = "Tenor")
        ) |>
        apply_theme()
    })
  })
}
