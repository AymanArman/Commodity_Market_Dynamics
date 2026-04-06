# Hedging Analytics Page — Row 4: Hedge Ratio Dynamics Across Term Structure
# col_a: Static OLS beta curve (RTL::promptBeta-equivalent, computed manually).
# col_b: Animated Kalman beta curve (reads r$kalman_betas, monthly frames).
# HTT excluded — spread instrument; log returns invalid for Kalman estimation.
#
# Parameters:
#   id     - Shiny module ID
#   dflong - full RTL::dflong tibble (date, series, value)
#   r      - shiny::reactiveValues; reads r$kalman_betas (date,ticker,tenor,beta,r_squared)
#
# Example:
#   mod_hedge_term_ui("hedge_term")
#   mod_hedge_term_server("hedge_term", dflong = dflong, r = r)

# ── Helpers ───────────────────────────────────────────────────────────────────

# Computes OLS betas and R² for each back tenor vs M01 for a given ticker.
# Uses log returns from compute_returns(). Betas computed via lm().
#
# Parameters:
#   dflong - full dflong tibble
#   ticker - character (CL, BRN, NG, HO, RB)
# Returns: tibble(tenor, beta, r_squared) excluding M01
#
# Example: compute_ols_betas(RTL::dflong, "CL")
compute_ols_betas <- function(dflong, ticker) {
  ticker_data <- dflong |> dplyr::filter(startsWith(series, ticker))
  returns     <- compute_returns(ticker_data)

  wide <- returns |>
    tidyr::pivot_wider(names_from = tenor, values_from = return) |>
    dplyr::arrange(date)

  if (!"M01" %in% names(wide)) return(dplyr::tibble())

  m1          <- wide$M01
  back_tenors <- setdiff(names(wide), c("date", "M01"))

  purrr::map_dfr(back_tenors, function(tn) {
    mn       <- wide[[tn]]
    complete <- !is.na(m1) & !is.na(mn)
    if (sum(complete) < 30) return(NULL)
    fit     <- lm(mn[complete] ~ m1[complete])
    beta    <- coef(fit)[["m1[complete]"]]
    r_sq    <- summary(fit)$r.squared
    dplyr::tibble(tenor = tn, beta = beta, r_squared = r_sq)
  })
}

# Reduces r$kalman_betas to one snapshot per calendar month (last trading day).
# Adds a month_label column (e.g., "Jan 2010") for animation frame.
# X-axis is fixed to the maximum set of tenors present across the full series.
#
# Parameters:
#   kalman_betas - tibble(date, ticker, tenor, beta, r_squared)
#   ticker       - character
# Returns: list with elements:
#   monthly - tibble with month_label column added
#   max_tenors - character vector of all tenors this ticker ever had
#
# Example:
#   prep_kalman_animation(r$kalman_betas, "CL")
prep_kalman_animation <- function(kalman_betas, ticker) {
  sub <- kalman_betas |>
    dplyr::filter(ticker == !!ticker) |>
    dplyr::arrange(date)

  if (nrow(sub) == 0) return(list(monthly = dplyr::tibble(), max_tenors = character(0)))

  max_tenors <- sort(unique(sub$tenor))

  monthly <- sub |>
    dplyr::mutate(year_month = lubridate::floor_date(date, "month")) |>
    dplyr::group_by(year_month, tenor) |>
    dplyr::slice_max(date, n = 1, with_ties = FALSE) |>
    dplyr::ungroup() |>
    dplyr::mutate(
      # frame_key uses YYYY-MM format so plotly sorts frames chronologically
      frame_key   = format(year_month, "%Y-%m"),
      month_label = format(year_month, "%b %Y")
    ) |>
    dplyr::select(date, tenor, beta, r_squared, frame_key, month_label)

  list(monthly = monthly, max_tenors = max_tenors)
}

# Converts tenor string "M01", "M02", ... to integer for x-axis positioning.
# Returns: integer
tenor_to_int <- function(tn) as.integer(sub("^M0?", "", tn))

# ── UI ────────────────────────────────────────────────────────────────────────

mod_hedge_term_ui <- function(id) {
  ns <- shiny::NS(id)

  shiny::tagList(
    # Shared inputs row
    shiny::fluidRow(
      style = "border-bottom:none; margin-bottom:4px; padding-bottom:0;",
      shiny::column(
        width = 6,
        shiny::selectInput(
          inputId  = ns("ticker"),
          label    = "Ticker",
          choices  = c("CL", "BRN", "NG", "HO", "RB"),
          selected = "CL"
        )
      ),
      shiny::column(
        width = 6,
        shinyWidgets::prettyRadioButtons(
          inputId  = ns("anim_speed"),
          label    = "Animation speed",
          choices  = c("Slow" = "1000", "Medium" = "500", "Fast" = "250"),
          selected = "500",
          status   = "primary",
          inline   = TRUE
        )
      )
    ),
    # Chart rows
    shiny::fluidRow(
      style = "border-bottom:none; margin-bottom:4px; padding-bottom:0;",
      # col_a: Static OLS beta curve
      shiny::column(
        width = 6,
        plotly::plotlyOutput(ns("ols_chart"), height = "360px")
      ),
      # col_b: Animated Kalman beta curve
      shiny::column(
        width = 6,
        plotly::plotlyOutput(ns("kalman_chart"), height = "360px")
      )
    ),
    # Narrative row
    shiny::fluidRow(
      # col_c: OLS narrative
      shiny::column(
        width = 6,
        bslib::card(
          bslib::card_body(
            shiny::p(
              "The beta curve shows structural decay: as the tenor mismatch between ",
              "physical exposure and hedge instrument grows, \u03b2 declines. A 1:1 hedge ",
              "of a back-month exposure with front-month futures leaves residual basis ",
              "risk proportional to the gap between \u03b2 and 1.0. The OLS curve is the ",
              "long-run average — use it as the baseline hedge ratio before checking ",
              "how far current conditions have drifted."
            )
          )
        )
      ),
      # col_d: Kalman narrative
      shiny::column(
        width = 6,
        bslib::card(
          bslib::card_body(
            shiny::p(
              "At each point in history, this was the best available estimate of the ",
              "hedge ratio given only data up to that date — no hindsight. The curve ",
              "deforming over time reflects genuine regime shifts in the basis ",
              "relationship. The relationship breaks down most visibly during supply ",
              "shocks, storage dislocations, and structural shifts."
            )
          )
        )
      )
    )
  )
}

# ── Server ────────────────────────────────────────────────────────────────────

mod_hedge_term_server <- function(id, dflong, r) {
  shiny::moduleServer(id, function(input, output, session) {

    # -- OLS betas (recomputed on ticker change)
    ols_betas <- shiny::reactive({
      shiny::req(input$ticker)
      compute_ols_betas(dflong, input$ticker)
    })

    # -- Kalman animation data (pre-computed in r$kalman_betas)
    kalman_anim <- shiny::reactive({
      shiny::req(input$ticker, !is.null(r$kalman_betas))
      prep_kalman_animation(r$kalman_betas, input$ticker)
    })

    # ── col_a: Static OLS beta curve ──────────────────────────────────────────
    output$ols_chart <- plotly::renderPlotly({
      betas <- ols_betas()
      shiny::req(nrow(betas) > 0)

      betas <- betas |>
        dplyr::mutate(tenor_num = tenor_to_int(tenor)) |>
        dplyr::arrange(tenor_num)

      n_tenors <- nrow(betas)

      plotly::plot_ly() |>
        # Reference line at β = 1.0
        plotly::add_trace(
          x    = c(2, max(betas$tenor_num, 3)),
          y    = c(1, 1),
          type = "scatter", mode = "lines",
          name = "\u03b2 = 1.0",
          line = list(color = "#4169E1", width = 1.5, dash = "dot"),
          showlegend = TRUE
        ) |>
        # OLS beta curve
        plotly::add_trace(
          x    = betas$tenor_num,
          y    = betas$beta,
          type = "scatter",
          mode = "lines+markers",
          name = "OLS \u03b2",
          line   = list(color = "#210000", width = 1.5, dash = "dot"),
          marker = list(color = "#210000", size = 6),
          text       = paste0(
            "Tenor: M", formatC(betas$tenor_num, width = 2, flag = "0"),
            "<br>\u03b2: ", round(betas$beta, 4),
            "<br>R\u00b2: ", round(betas$r_squared, 4)
          ),
          hoverinfo  = "text"
        ) |>
        plotly::layout(
          title  = list(text = "OLS Hedge Ratio vs Tenor", x = 0),
          xaxis  = list(title = "Tenor (months from front)"),
          yaxis  = list(title = "\u03b2 vs M01"),
          legend = list(orientation = "h", y = -0.2)
        ) |>
        apply_theme()
    })

    # ── col_b: Animated Kalman beta curve ─────────────────────────────────────
    output$kalman_chart <- plotly::renderPlotly({
      anim        <- kalman_anim()
      betas       <- ols_betas()
      speed_ms    <- as.numeric(input$anim_speed)

      shiny::req(nrow(anim$monthly) > 0)

      monthly    <- anim$monthly
      max_tenors <- anim$max_tenors
      max_tenor_num <- tenor_to_int(max_tenors[length(max_tenors)])

      # Expand each frame to include all max_tenors (NA where absent).
      # Use frame_key (YYYY-MM) so plotly sorts frames chronologically.
      # Derive ordered frame keys from the actual dates, not string sort.
      ordered_keys <- monthly |>
        dplyr::distinct(frame_key, month_label, date) |>
        dplyr::group_by(frame_key, month_label) |>
        dplyr::summarise(max_date = max(date), .groups = "drop") |>
        dplyr::arrange(max_date) |>
        dplyr::select(frame_key, month_label)

      expanded <- purrr::map_dfr(ordered_keys$frame_key, function(fk) {
        frame_data <- monthly |> dplyr::filter(frame_key == fk)
        lbl        <- ordered_keys$month_label[ordered_keys$frame_key == fk]
        base <- dplyr::tibble(tenor = max_tenors, frame_key = fk, month_label = lbl)
        dplyr::left_join(base,
                         frame_data |> dplyr::select(tenor, beta, r_squared),
                         by = "tenor") |>
          dplyr::mutate(tenor_num = tenor_to_int(tenor))
      })

      p <- plotly::plot_ly()

      # OLS reference trace with frame = NULL (static across all frames)
      if (nrow(betas) > 0) {
        betas_plot <- betas |>
          dplyr::mutate(tenor_num = tenor_to_int(tenor)) |>
          dplyr::arrange(tenor_num)
        p <- p |> plotly::add_trace(
          x          = betas_plot$tenor_num,
          y          = betas_plot$beta,
          frame      = NULL,
          type       = "scatter",
          mode       = "lines",
          name       = "OLS \u03b2 (static)",
          line       = list(color = "#210000", width = 1.5, dash = "dot"),
          opacity    = 0.25,
          showlegend = TRUE,
          inherit    = FALSE
        )
      }

      # Animated Kalman trace — markers only (no line between points)
      # frame = ~frame_key (YYYY-MM) ensures chronological playback order
      p <- p |>
        plotly::add_trace(
          data       = expanded,
          x          = ~tenor_num,
          y          = ~beta,
          frame      = ~frame_key,
          type       = "scatter",
          mode       = "markers",
          name       = "Kalman \u03b2",
          marker     = list(color = "#db243a", size = 8),
          text       = ~paste0(
            "Date: ", month_label,
            "<br>Tenor: ", tenor,
            "<br>\u03b2: ", round(beta, 4),
            "<br>R\u00b2: ", round(r_squared, 4)
          ),
          hoverinfo  = "text",
          showlegend = TRUE
        ) |>
        # Reference β = 1.0
        plotly::add_trace(
          x          = c(2, max_tenor_num),
          y          = c(1, 1),
          frame      = NULL,
          type       = "scatter",
          mode       = "lines",
          name       = "\u03b2 = 1.0",
          line       = list(color = "#4169E1", width = 1.5, dash = "dot"),
          showlegend = TRUE,
          inherit    = FALSE
        )

      p |>
        plotly::layout(
          title  = list(text = "Kalman Hedge Ratio vs Tenor (animated)", x = 0),
          xaxis  = list(
            title = "Tenor (months from front)",
            range = c(1.5, max_tenor_num + 0.5)
          ),
          yaxis  = list(title = "\u03b2 vs M01"),
          legend = list(orientation = "h", y = -0.2)
        ) |>
        plotly::animation_opts(
          frame   = speed_ms,
          redraw  = FALSE,
          easing  = "linear"
        ) |>
        plotly::animation_slider(
          currentvalue = list(prefix = "", font = list(color = "#f9f9f9"))
        ) |>
        apply_theme()
    })
  })
}
