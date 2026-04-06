# Forward Curves — Row 1: Scaled Comparison Chart
# Renders an index-normalised forward curve chart (M1 = 100 per ticker) for
# a selected date. Supports multi-ticker comparison mode and single-ticker
# historical overlay mode (up to 4 historical dates).
#
# Parameters:
#   id     - Shiny module ID
#   dflong - full RTL::dflong tibble (date, series, value), passed from server
#
# Example:
#   mod_fc_comparison_ui("fc_comp")
#   mod_fc_comparison_server("fc_comp", dflong = dflong)

# ── UI ───────────────────────────────────────────────────────────────────────

mod_fc_comparison_ui <- function(id) {
  ns <- shiny::NS(id)

  shiny::fluidRow(
    # Left margin
    shiny::column(width = 2),

    # Center — controls + chart
    shiny::column(
      width = 8,

      # Overlay mode toggle
      bslib::input_switch(
        id    = ns("overlay_mode"),
        label = "Historical overlay mode",
        value = FALSE
      ),

      # --- Comparison mode controls (hidden when overlay ON) ---
      shiny::conditionalPanel(
        condition = paste0("!input['", ns("overlay_mode"), "']"),
        shinyWidgets::pickerInput(
          inputId  = ns("tickers"),
          label    = "Select commodities to compare their forward curve structures",
          choices  = c("CL", "BRN", "NG", "HO", "RB", "HTT"),
          selected = c("CL", "BRN"),
          multiple = TRUE,
          options  = shinyWidgets::pickerOptions(
            actionsBox       = TRUE,
            selectedTextFormat = "count > 2"
          )
        )
      ),

      # --- Overlay mode controls (hidden when overlay OFF) ---
      shiny::conditionalPanel(
        condition = paste0("input['", ns("overlay_mode"), "']"),
        shinyWidgets::pickerInput(
          inputId  = ns("ticker_single"),
          label    = "Select commodity",
          choices  = c("CL", "BRN", "NG", "HO", "RB", "HTT"),
          selected = "CL",
          multiple = FALSE
        ),
        shiny::fluidRow(
          shiny::column(3, shiny::dateInput(ns("hist_date1"), label = "Date 1", value = as.Date("2010-06-01"))),
          shiny::column(3, shiny::dateInput(ns("hist_date2"), label = "Date 2", value = as.Date("2014-06-02"))),
          shiny::column(3, shiny::dateInput(ns("hist_date3"), label = "Date 3", value = as.Date("2020-06-01"))),
          shiny::column(3, shiny::dateInput(ns("hist_date4"), label = "Date 4", value = as.Date("2024-06-03")))
        )
      ),

      # Date slider (comparison mode only) — Date-typed so it displays dates natively
      shiny::conditionalPanel(
        condition = paste0("!input['", ns("overlay_mode"), "']"),
        shiny::sliderInput(
          inputId = ns("selected_date"),
          label   = NULL,
          min     = as.Date("2000-01-01"),
          max     = Sys.Date(),
          value   = Sys.Date(),
          step    = 1,
          width   = "100%",
          ticks   = FALSE
        )
      ),

      # Chart
      plotly::plotlyOutput(ns("chart"), height = "450px")
    ),

    # Right margin
    shiny::column(width = 2)
  )
}

# ── Server ───────────────────────────────────────────────────────────────────

mod_fc_comparison_server <- function(id, dflong) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # All unique tickers and their series prefixes derived once from dflong
    all_tickers <- c("CL", "BRN", "NG", "HO", "RB", "HTT")

    # Helper: extract sorted unique dates for a given ticker prefix
    ticker_dates <- function(ticker) {
      dflong |>
        dplyr::filter(startsWith(series, ticker)) |>
        dplyr::pull(date) |>
        unique() |>
        sort()
    }

    # Pre-build date vectors for all tickers once (reactive would recompute on
    # every input change; these are static for the lifetime of the session)
    ticker_date_sets <- stats::setNames(
      lapply(all_tickers, ticker_dates),
      all_tickers
    )

    # ── Comparison mode: available dates reactive ────────────────────────────

    # Sorted intersection of dates across all selected tickers
    available_dates <- shiny::reactive({
      tickers <- input$tickers
      shiny::req(length(tickers) >= 1)
      Reduce(intersect, lapply(tickers, function(t) ticker_date_sets[[t]])) |>
        as.Date(origin = "1970-01-01") |>
        sort()
    })

    # Update slider min/max/value whenever ticker selection changes
    shiny::observeEvent(available_dates(), {
      dates <- available_dates()
      shiny::req(length(dates) > 0)
      shiny::updateSliderInput(
        session = session,
        inputId = "selected_date",
        min     = dates[1],
        max     = dates[length(dates)],
        value   = dates[length(dates)]
      )
    }, ignoreInit = FALSE)

    # ── Normalisation helper ─────────────────────────────────────────────────

    # Index-normalise: M1 = 100 for each ticker on the selected date.
    # Parameters:
    #   ticker  - character; e.g. "CL"
    #   sel_date - Date
    # Returns: tibble (tenor, indexed_price, ticker)
    normalise_ticker <- function(ticker, sel_date) {
      raw <- dflong |>
        dplyr::filter(
          startsWith(series, ticker),
          date == sel_date
        ) |>
        dplyr::mutate(
          tenor = paste0("M", sub("^[A-Za-z]+", "", series))
        ) |>
        dplyr::arrange(tenor)

      m1_price <- raw |>
        dplyr::filter(tenor == "M01") |>
        dplyr::pull(value)

      shiny::req(length(m1_price) == 1, m1_price > 0)

      raw |>
        dplyr::mutate(
          indexed_price = value / m1_price * 100,
          ticker        = ticker
        ) |>
        dplyr::select(tenor, indexed_price, ticker)
    }

    # ── Comparison mode chart ────────────────────────────────────────────────

    output$chart <- plotly::renderPlotly({
      if (isTRUE(input$overlay_mode)) {
        # --- Historical overlay mode ---
        ticker   <- input$ticker_single
        shiny::req(ticker)

        date_inputs <- list(
          input$hist_date1, input$hist_date2,
          input$hist_date3, input$hist_date4
        )

        # Keep only non-NULL, non-NA date inputs
        sel_dates <- Filter(Negate(is.null), date_inputs)
        sel_dates <- Filter(function(d) !is.na(d), sel_dates)
        sel_dates <- as.Date(unlist(lapply(sel_dates, as.character)))

        # Need at least 1 populated date to render
        shiny::req(length(sel_dates) >= 1)

        # Viridis-derived 4-color palette for up to 4 historical dates
        pal <- c("#440154", "#31688e", "#35b779", "#fde725")

        p <- plotly::plot_ly()

        for (i in seq_along(sel_dates)) {
          d <- sel_dates[i]
          curve_data <- tryCatch(
            normalise_ticker(ticker, d),
            error = function(e) NULL
          )
          if (is.null(curve_data) || nrow(curve_data) == 0) next

          p <- plotly::add_trace(
            p,
            data        = curve_data,
            x           = ~tenor,
            y           = ~indexed_price,
            type        = "scatter",
            mode        = "lines+markers",
            name        = format(d, "%b %d, %Y"),
            line        = list(color = pal[i], width = 2),
            marker      = list(color = pal[i], size = 5)
          )
        }

        p |>
          plotly::layout(
            xaxis  = list(title = "Tenor", tickangle = -45),
            yaxis  = list(title = "Indexed Price (M1 = 100)"),
            legend = list(orientation = "h", y = -0.2),
            hovermode = "x unified"
          ) |>
          apply_theme()

      } else {
        # --- Multi-ticker comparison mode ---
        tickers <- input$tickers
        dates   <- available_dates()
        shiny::req(length(tickers) >= 1, length(dates) > 0, !is.null(input$selected_date))

        # Snap slider value to nearest available date
        sel_date <- dates[which.min(abs(dates - input$selected_date))]

        # Viridis palette for up to 6 tickers
        pal <- c("#440154", "#3b528b", "#21918c", "#5ec962", "#fde725", "#CC5500")
        names(pal) <- c("CL", "BRN", "NG", "HO", "RB", "HTT")

        chart_data <- dplyr::bind_rows(lapply(tickers, function(t) {
          tryCatch(normalise_ticker(t, sel_date), error = function(e) NULL)
        }))

        shiny::req(nrow(chart_data) > 0)

        p <- plotly::plot_ly()

        for (t in tickers) {
          td <- chart_data |> dplyr::filter(ticker == t)
          if (nrow(td) == 0) next
          p <- plotly::add_trace(
            p,
            data   = td,
            x      = ~tenor,
            y      = ~indexed_price,
            type   = "scatter",
            mode   = "lines+markers",
            name   = t,
            line   = list(color = pal[t], width = 2),
            marker = list(color = pal[t], size = 5)
          )
        }

        p |>
          plotly::layout(
            xaxis  = list(title = "Tenor", tickangle = -45),
            yaxis  = list(title = "Indexed Price (M1 = 100)"),
            legend = list(orientation = "h", y = -0.2),
            hovermode = "x unified"
          ) |>
          apply_theme()
      }
    })
  })
}
