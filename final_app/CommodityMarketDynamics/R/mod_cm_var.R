# Cross-Market Relationships Page — Row 2: VAR + Impulse Response Functions
# Reads r$var_results (varest object written at startup by mod_var_server).
# Renders IRF chart for a selected shock ticker: all 5 responding tickers
# overlaid as lines with per-ticker viridis CI ribbons.
#
# Parameters:
#   id - Shiny module ID
#   r  - shiny::reactiveValues containing r$var_results (written by mod_var_server)
#
# Example:
#   mod_cm_var_ui("cm_var")
#   mod_cm_var_server("cm_var", r = r)

# Cholesky ordering — defines the canonical ticker sequence for colour assignment
CM_VAR_CHOL_ORDER <- c("BRN", "CL", "HO", "RB", "HTT", "NG")

# ── UI ───────────────────────────────────────────────────────────────────────

mod_cm_var_ui <- function(id) {
  ns <- shiny::NS(id)

  shiny::fluidRow(
    class = "mt-3 d-flex",
    # col_a: chart (width 8)
    shiny::column(
      width = 8,
      # Controls row: shock ticker left, line toggles right
      shiny::fluidRow(
        shiny::column(
          width = 3,
          shiny::selectInput(
            inputId  = ns("shock_ticker"),
            label    = "Shock ticker",
            choices  = CM_VAR_CHOL_ORDER,
            selected = "CL"
          )
        ),
        shiny::column(
          width = 9,
          shinyWidgets::prettyCheckboxGroup(
            inputId  = ns("visible_tickers"),
            label    = "Show lines",
            choices  = CM_VAR_CHOL_ORDER[CM_VAR_CHOL_ORDER != "CL"],
            selected = CM_VAR_CHOL_ORDER[CM_VAR_CHOL_ORDER != "CL"],
            status   = "primary",
            inline   = TRUE
          )
        )
      ),
      # Inline lag count text — rendered by server
      shiny::uiOutput(ns("lag_label")),
      plotly::plotlyOutput(ns("irf_chart"), height = "480px")
    ),
    # col_b: narrative card (width 4) — flex column, card pushed to bottom
    shiny::column(
      width = 4,
      style = "display: flex; flex-direction: column; justify-content: flex-end;",
      bslib::card(
        bslib::card_body(
          shiny::p(
            "VAR estimates predictive relationships between all markets ",
            "simultaneously using historical return data. Impulse response ",
            "functions (IRFs) trace how a one-standard-deviation shock in one ",
            "market propagates through the others over the following weeks. ",
            "Confidence bands are the signal — when the band straddles zero, ",
            "no meaningful relationship is distinguishable from noise."
          ),
          shiny::p(
            shiny::strong("Caveats:"),
            shiny::tags$ol(
              shiny::tags$li(
                "VAR is calibrated on historical return innovations. ",
                "Unprecedented shocks or structural regime changes mean ",
                "historical relationships may not hold forward."
              ),
              shiny::tags$li(
                "Cholesky ordering (BRN \u2192 CL \u2192 HO \u2192 RB \u2192 HTT \u2192 NG) ",
                "reflects the typical causal flow in refined-product markets. ",
                "Tickers above the shock ticker show zero contemporaneous ",
                "response by construction — their response appears from ",
                "Week 1 onward. This is standard VAR practice."
              )
            )
          )
        )
      )
    )
  )
}

# ── Server ───────────────────────────────────────────────────────────────────

mod_cm_var_server <- function(id, r) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Inline lag text: "Model estimated with N lags (criterion)"
    output$lag_label <- shiny::renderUI({
      shiny::req(r$var_results)
      n_lags    <- r$var_results$p
      criterion <- attr(r$var_results, "lag_criterion") %||% "BIC"
      shiny::tags$p(
        shiny::em(paste0("Model estimated with ", n_lags, " lags (", criterion, ")")),
        style = "font-size: 0.85em; color: #ccc; margin-top: -6px; margin-bottom: 8px;"
      )
    })

    # When shock ticker changes, update line toggle choices to the 5 responding
    # tickers (all pre-selected) — keeps the checkbox in sync without re-running
    # the expensive IRF bootstrap
    shiny::observeEvent(input$shock_ticker, {
      responding <- CM_VAR_CHOL_ORDER[CM_VAR_CHOL_ORDER != input$shock_ticker]
      shinyWidgets::updatePrettyCheckboxGroup(
        session  = session,
        inputId  = "visible_tickers",
        choices  = responding,
        selected = responding,
        prettyOptions = list(status = "primary", inline = TRUE)
      )
    }, ignoreInit = TRUE)

    # IRF computation — triggered by shock ticker selection only
    irf_data <- shiny::reactive({
      shiny::req(r$var_results, input$shock_ticker)

      shock <- input$shock_ticker
      shiny::req(shock %in% colnames(r$var_results$y))

      # Compute IRF (ortho Cholesky, 12-week horizon, 95% CI via bootstrap)
      irf_obj <- vars::irf(
        r$var_results,
        impulse  = shock,
        n.ahead  = 12L,
        ortho    = TRUE,
        ci       = 0.95,
        boot     = TRUE,
        runs     = 200L
      )

      # Responding tickers: all except shock, in Cholesky order
      responding <- CM_VAR_CHOL_ORDER[CM_VAR_CHOL_ORDER != shock]

      # Extract response matrix rows (horizon 0:12) for each responding ticker
      resp_mat  <- irf_obj$irf[[shock]]
      lower_mat <- irf_obj$Lower[[shock]]
      upper_mat <- irf_obj$Upper[[shock]]

      horizon   <- seq(0L, nrow(resp_mat) - 1L)

      # Assign distinct viridis colours to responding tickers (in order)
      colours <- viridisLite::viridis(length(responding), option = "D")
      names(colours) <- responding

      list(
        horizon    = horizon,
        responding = responding,
        resp_mat   = resp_mat,
        lower_mat  = lower_mat,
        upper_mat  = upper_mat,
        colours    = colours,
        shock      = shock
      )
    })

    output$irf_chart <- plotly::renderPlotly({
      cd      <- irf_data()
      visible <- input$visible_tickers
      shiny::req(!is.null(cd), length(visible) > 0)

      p <- plotly::plot_ly()

      # Only render traces for tickers the user has toggled on
      for (i in seq_along(cd$responding)) {
        ticker <- cd$responding[i]
        if (!ticker %in% visible) next
        col    <- cd$colours[ticker]

        resp  <- cd$resp_mat[,  ticker]
        lower <- cd$lower_mat[, ticker]
        upper <- cd$upper_mat[, ticker]

        # CI ribbon: filled polygon at 15% opacity
        p <- p |>
          plotly::add_trace(
            x           = c(cd$horizon, rev(cd$horizon)),
            y           = c(upper, rev(lower)),
            type        = "scatter",
            mode        = "none",
            fill        = "toself",
            fillcolor   = hex_to_rgba(col, 0.15),
            showlegend  = FALSE,
            hoverinfo   = "skip",
            name        = paste0(ticker, " CI")
          ) |>
          # Response line
          plotly::add_trace(
            x             = cd$horizon,
            y             = resp,
            type          = "scatter",
            mode          = "lines",
            name          = ticker,
            line          = list(color = col, width = 2),
            hovertemplate = paste0("Week %{x}: %{y:.4f}<extra>", ticker, "</extra>")
          )
      }

      # Horizontal reference at y = 0
      zero_shape <- list(
        type = "line",
        x0   = 0, x1 = 1, xref = "paper",
        y0   = 0, y1 = 0, yref = "y",
        line = list(color = "#444444", width = 1, dash = "dash")
      )

      p |>
        plotly::layout(
          xaxis  = list(title = "Weeks after shock",
                        tickmode = "linear", dtick = 1L),
          yaxis  = list(title = "Response (standard deviation units)"),
          shapes = list(zero_shape),
          legend = list(orientation = "h", y = -0.15),
          hovermode = "x unified"
        ) |>
        apply_theme()
    })
  })
}

# Null-coalescing operator (base R >= 4.4 has it; define for safety)
`%||%` <- function(a, b) if (!is.null(a)) a else b

# Converts a hex colour (e.g. "#440154FF") to an rgba() CSS string with the
# given alpha. Handles both 6-char (#RRGGBB) and 8-char (#RRGGBBAA) hex codes.
# Parameters:
#   hex   - character: hex colour string
#   alpha - numeric: opacity in [0, 1]
# Example:
#   hex_to_rgba("#440154FF", 0.15)  # "rgba(68,1,84,0.15)"
hex_to_rgba <- function(hex, alpha = 1) {
  hex <- sub("^#", "", hex)  # strip leading #
  r   <- strtoi(substr(hex, 1L, 2L), 16L)
  g   <- strtoi(substr(hex, 3L, 4L), 16L)
  b   <- strtoi(substr(hex, 5L, 6L), 16L)
  paste0("rgba(", r, ",", g, ",", b, ",", alpha, ")")
}
