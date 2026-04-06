# Volatility Page — Row 3: Rolling Realised Volatility
# Renders a 21-day rolling annualised volatility line chart for the selected
# ticker + tenor. Adds 3 locked event markers; silently omits any marker
# whose date falls outside the series' available date range.
#
# Parameters:
#   id     - Shiny module ID
#   dflong - full RTL::dflong tibble (date, series, value), passed from server
#
# Example:
#   mod_vol_rolling_ui("vol_rolling")
#   mod_vol_rolling_server("vol_rolling", dflong = dflong)

# Geopolitical event periods for background shading
ROLL_VOL_EVENTS <- list(
  list(label="Crimea Annexation",        x0=as.Date("2014-02-01"), x1=as.Date("2014-09-30"), fillcolor="rgba(200,50,50,0.12)"),
  list(label="COVID-19 / Oil Price War", x0=as.Date("2020-01-01"), x1=as.Date("2020-06-30"), fillcolor="rgba(248,114,23,0.14)"),
  list(label="Russia-Ukraine War",       x0=as.Date("2022-01-01"), x1=as.Date("2023-12-31"), fillcolor="rgba(23,157,248,0.12)"),
  list(label="Iran War",                 x0=as.Date("2026-03-01"), x1=Sys.Date(),            fillcolor="rgba(150,0,200,0.12)")
)

# ── UI ───────────────────────────────────────────────────────────────────────

mod_vol_rolling_ui <- function(id) {
  ns <- shiny::NS(id)

  tagList(
    # Controls: ticker + tenor selectors
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
        width = 3,
        shiny::selectInput(
          inputId  = ns("tenor"),
          label    = "Tenor",
          choices  = paste0("M", sprintf("%02d", 1:36)),
          selected = "M01"
        )
      )
    ),
    # Chart row
    shiny::fluidRow(
      # col_a — narrative card
      shiny::column(
        width = 6,
        bslib::card(
          bslib::card_body(
            shiny::p(
              "Rolling realised volatility surfaces the episodic nature of ",
              "commodity risk. Extended calm periods are punctuated by sharp ",
              "spikes driven by supply shocks, geopolitical events, and demand ",
              "collapses. The events marked here are a curated shortlist of ",
              "the most significant moves in the data."
            ),
            shiny::p(
              "Volatility spikes when uncertainty around supply and demand is ",
              "high — markets reprice rapidly when the outlook becomes unclear. ",
              "Importantly, these spikes tend to be sharp and short-lived: the ",
              "largest vol readings typically occur at the onset of an event, ",
              "as the market digests the shock, not over its full duration. ",
              "Once a new supply/demand equilibrium is priced in, volatility ",
              "subsides even if the underlying event is still unfolding."
            )
          )
        )
      ),
      # col_b — rolling vol chart
      shiny::column(
        width = 6,
        plotly::plotlyOutput(ns("roll_chart"), height = "450px")
      )
    )
  )
}

# ── Server ───────────────────────────────────────────────────────────────────

mod_vol_rolling_server <- function(id, dflong) {
  shiny::moduleServer(id, function(input, output, session) {

    # Available tenors for selected ticker — drives tenor selector choices
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

    # Update tenor selector when ticker changes
    shiny::observeEvent(available_tenors(), {
      tenors <- available_tenors()
      shiny::updateSelectInput(
        session  = session,
        inputId  = "tenor",
        choices  = tenors,
        selected = tenors[1]
      )
    }, ignoreInit = FALSE)

    # TRUE when HTT is selected — switches axis labels
    is_spread <- shiny::reactive({
      shiny::req(input$ticker)
      input$ticker == "HTT"
    })

    # Rolling vol reactive: 21-day window, annualised
    roll_vol_data <- shiny::reactive({
      shiny::req(input$ticker, input$tenor)

      # Returns for the selected ticker (all tenors)
      returns_all <- dflong |>
        dplyr::filter(startsWith(series, input$ticker)) |>
        compute_returns()

      # Filter to selected tenor
      tenor_returns <- returns_all |>
        dplyr::filter(tenor == input$tenor) |>
        dplyr::arrange(date)

      shiny::req(nrow(tenor_returns) > 21)

      # 21-day rolling sd, annualised (tests 2.14, 2.15)
      roll_sd <- zoo::rollapply(
        tenor_returns$return,
        width = 21L,
        FUN   = stats::sd,
        fill  = NA,
        align = "right"
      ) * sqrt(252)

      dplyr::tibble(
        date   = tenor_returns$date,
        roll_vol = roll_sd
      ) |>
        dplyr::filter(!is.na(roll_vol))
    })

    output$roll_chart <- plotly::renderPlotly({
      shiny::req(nrow(roll_vol_data()) > 0)

      rv        <- roll_vol_data()
      spread    <- is_spread()
      y_label   <- if (spread) "Annualised Volatility (Level Diff)" else "Annualised Volatility"
      date_min  <- min(rv$date)
      date_max  <- max(rv$date)

      # Base line chart
      p <- plotly::plot_ly(
        data          = rv,
        x             = ~date,
        y             = ~roll_vol,
        type          = "scatter",
        mode          = "lines",
        name          = paste(input$ticker, input$tenor),
        line          = list(color = "#F87217", width = 1.5),
        hovertemplate = "%{x|%b %d, %Y}: %{y:.4f}<extra></extra>"
      )

      # Build event shading shapes + annotations (omit if outside date range)
      in_evs  <- Filter(function(ev) ev$x1 >= date_min && ev$x0 <= date_max, ROLL_VOL_EVENTS)
      ev_shapes <- lapply(in_evs, function(ev) {
        list(type="rect",
             x0=format(max(ev$x0, date_min)), x1=format(min(ev$x1, date_max)),
             y0=0, y1=1, xref="x", yref="paper",
             fillcolor=ev$fillcolor, line=list(width=0), layer="below")
      })
      ev_annots <- lapply(in_evs, function(ev) {
        x0c <- max(ev$x0, date_min); x1c <- min(ev$x1, date_max)
        list(x=format(x0c + as.integer(x1c - x0c) %/% 2L), y=0.97, yref="paper",
             text=ev$label, showarrow=FALSE,
             font=list(size=9, color="#000000"), xanchor="center")
      })

      p |>
        plotly::layout(
          xaxis       = list(title = "Date"),
          yaxis       = list(title = y_label),
          shapes      = ev_shapes,
          annotations = ev_annots,
          legend      = list(orientation = "h", y = -0.2),
          hovermode   = "x unified"
        ) |>
        apply_theme()
    })
  })
}
