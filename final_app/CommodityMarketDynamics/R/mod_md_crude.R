# Market Dynamics — Crude Group (all 4 rows)
# Row 1: Crude Benchmarks & Spreads — reactive line chart + stats card
# Row 2: Brent-WTI Spread vs. Cushing WoW Change — subplot, date range slider
# Row 3: HTT Spread + Cushing WoW Change — subplot, date range slider
# Row 4: STL Decomposition of US crude production and refinery inputs + slider
#
# Parameters:
#   id     - Shiny module ID
#   dflong - full RTL::dflong tibble
#   r      - shared reactiveValues; reads r$eia_crude_prod, r$eia_crude_inputs
#
# Example:
#   mod_md_crude_ui("crude")
#   mod_md_crude_server("crude", dflong = dflong, r = r)

# Geopolitical event periods for Row 1 background shading
CRUDE_EVENTS <- list(
  list(label="Crimea Annexation",        x0=as.Date("2014-02-01"), x1=as.Date("2014-09-30"), fillcolor="rgba(200,50,50,0.12)"),
  list(label="COVID-19 / Oil Price War", x0=as.Date("2020-01-01"), x1=as.Date("2020-06-30"), fillcolor="rgba(248,114,23,0.14)"),
  list(label="Russia-Ukraine War",       x0=as.Date("2022-01-01"), x1=as.Date("2023-12-31"), fillcolor="rgba(23,157,248,0.12)"),
  list(label="Iran War",                 x0=as.Date("2026-03-01"), x1=Sys.Date(),            fillcolor="rgba(150,0,200,0.12)")
)

# Helper: one orange stat box
stat_box <- function(label, value) {
  shiny::div(
    style = paste0(
      "flex:1; min-width:0; background:#F87217; color:#fff; ",
      "border-radius:6px; padding:12px 8px; text-align:center;"
    ),
    shiny::tags$div(
      style = "font-size:0.75em; opacity:0.88; margin-bottom:4px; text-transform:uppercase; letter-spacing:0.04em;",
      label
    ),
    shiny::tags$div(style = "font-size:1.15em; font-weight:bold; line-height:1.3;", value)
  )
}

# ── UI ───────────────────────────────────────────────────────────────────────

mod_md_crude_ui <- function(id) {
  ns <- shiny::NS(id)

  tagList(
    # ── Row 1 — Crude Benchmarks & Spreads ──────────────────────────────────
    shiny::fluidRow(
      shiny::column(
        width = 4,
        style = "display:flex; flex-direction:column; gap:12px;",
        shiny::uiOutput(ns("stats_card")),
        bslib::card(
          style = "flex:1; overflow-y:auto;",
          bslib::card_body(
            shiny::p("Brent crude is the global benchmark, underpinning roughly two-thirds
              of international oil contracts. It is physically based on the BFOET basket
              (Brent, Forties, Oseberg, Ekofisk, Troll); US Midland WTI was added to the
              Dated Brent basket in 2023."),
            shiny::p("WTI is the US benchmark, with its delivery point at Cushing, Oklahoma —
              a landlocked pipeline hub. Its location limits export optionality; crude stranded
              at Cushing must find a domestic buyer or wait for pipeline capacity to move it south."),
            shiny::p("Houston sits on the Gulf Coast with direct access to export terminals and
              the largest refinery complex in North America. This gives Houston-delivered crude a
              structural premium over Cushing; Houston prices are reported by Argus. The HTT spread
              (Houston \u2212 Cushing) directly measures this location differential."),
            shiny::p("The Brent\u2212WTI spread reflects the global vs. landlocked premium \u2014 Brent
              typically trades at a premium, narrowing or inverting when US export infrastructure
              is unconstrained and Cushing inventory draws.")
          )
        )
      ),
      shiny::column(
        width = 8,
        shinyWidgets::prettyRadioButtons(
          inputId  = ns("series"),
          label    = NULL,
          choices  = c(
            "Brent\u2212WTI Spread" = "bwti_spread",
            "WTI"                   = "CL01",
            "Brent"                 = "BRN01",
            "HTT Spread"            = "HTT01"
          ),
          selected = "bwti_spread",
          status   = "primary",
          inline   = TRUE,
          fill     = FALSE
        ),
        shinycssloaders::withSpinner(
          plotly::plotlyOutput(ns("bench_chart"), height = "500px"),
          color = "#F87217"
        )
      )
    ),

    # ── Row 2 — Brent-WTI Spread vs. Cushing WoW ────────────────────────────
    shiny::fluidRow(
      shiny::column(
        width = 8,
        shinycssloaders::withSpinner(
          plotly::plotlyOutput(ns("bwti_cushing_chart"), height = "420px"),
          color = "#F87217"
        ),
        shiny::uiOutput(ns("row2_range_ui"))
      ),
      shiny::column(
        width = 4,
        bslib::card(
          bslib::card_body(
            shiny::p("When the Brent premium widens, US crude becomes cheap relative to
              international markets \u2014 export arbitrage opens. Crude flows from Cushing toward
              Houston, showing up as Cushing inventory draws."),
            shiny::p("Storage is the real-time supply/demand balance. Production is sticky;
              storage is where the signal surfaces first. For the spread specifically, the
              relationship runs opposite to raw price intuition: builds widen the Brent\u2212WTI
              spread as WTI weakens under storage pressure, while draws compress it as Cushing
              tightens and WTI recovers relative to Brent. The weekly EIA inventory report is
              the primary data release traders watch to gauge this balance."),
            shiny::p(shiny::strong("COVID SPIKE:"),
              "Brent, as a seaborne benchmark, retains export optionality during market-moving
              events \u2014 a cargo can be redirected or stored on tankers, creating an effective
              price floor that WTI does not have. WTI, priced at landlocked Cushing, has no
              such outlet. Large inventory builds in early 2020, driven by collapsing refinery
              demand and sustained shale production, left crude with nowhere to go. Cushing
              storage pressure discounted WTI aggressively relative to Brent, widening the
              spread sharply \u2014 a dynamic that culminated in the April 2020 negative price
              event.")
          )
        )
      )
    ),

    # ── Row 3 — HTT Spread + Cushing WoW Change ─────────────────────────────
    shiny::fluidRow(
      shiny::column(
        width = 6,
        shinycssloaders::withSpinner(
          plotly::plotlyOutput(ns("htt_cushing_chart"), height = "450px"),
          color = "#F87217"
        ),
        shiny::uiOutput(ns("row3_range_ui"))
      ),
      shiny::column(
        width = 6,
        bslib::card(
          bslib::card_body(
            shiny::p("Houston serves international customers (export terminal, Gulf Coast).
              Cushing is a landlocked regional hub. HTT is a location differential driven by
              pipeline congestion and export optionality \u2014 not a quality differential. Both legs
              are light sweet WTI-grade crude."),
            shiny::HTML('
              <div style="margin-top:16px;">
                <div style="display:flex; align-items:center; gap:8px; margin-bottom:8px;">
                  <div style="background:#2e7d32; color:#fff; padding:6px 10px; border-radius:4px; font-size:0.85em;">Cushing Draws</div>
                  <span style="font-size:1.2em;">&rarr;</span>
                  <div style="background:#2e7d32; color:#fff; padding:6px 10px; border-radius:4px; font-size:0.85em;">Inventory pressure relieved</div>
                  <span style="font-size:1.2em;">&rarr;</span>
                  <div style="background:#2e7d32; color:#fff; padding:6px 10px; border-radius:4px; font-size:0.85em;">HTT spread compresses</div>
                </div>
                <div style="display:flex; align-items:center; gap:8px;">
                  <div style="background:#c62828; color:#fff; padding:6px 10px; border-radius:4px; font-size:0.85em;">Cushing Builds</div>
                  <span style="font-size:1.2em;">&rarr;</span>
                  <div style="background:#c62828; color:#fff; padding:6px 10px; border-radius:4px; font-size:0.85em;">Bottleneck at hub</div>
                  <span style="font-size:1.2em;">&rarr;</span>
                  <div style="background:#c62828; color:#fff; padding:6px 10px; border-radius:4px; font-size:0.85em;">HTT spread widens</div>
                </div>
              </div>
            ')
          )
        )
      )
    ),

    # ── Row 4 — STL Decomposition ────────────────────────────────────────────
    shiny::fluidRow(
      style = "border-bottom: none; margin-bottom: 0; padding-bottom: 0;",
      shiny::column(
        width = 6,
        shiny::tags$h6("US Crude Production \u2014 STL Decomposition",
                        style = "text-align:center; margin-bottom:8px;"),
        shinycssloaders::withSpinner(
          plotly::plotlyOutput(ns("stl_prod_chart"), height = "420px"),
          color = "#F87217"
        ),
        shiny::uiOutput(ns("row4_range_ui"))
      ),
      shiny::column(
        width = 6,
        shiny::tags$h6("US Refinery Crude Inputs \u2014 STL Decomposition",
                        style = "text-align:center; margin-bottom:8px;"),
        shinycssloaders::withSpinner(
          plotly::plotlyOutput(ns("stl_inputs_chart"), height = "420px"),
          color = "#F87217"
        )
      )
    ),
    shiny::fluidRow(
      shiny::column(
        width = 12,
        bslib::card(
          bslib::card_body(
            shiny::p("US crude production has a structural upward trend (shale-driven) with
              modest seasonal variation. Refinery crude inputs are the demand proxy \u2014 EIA does
              not publish explicit demand. When production and demand cycles align the market is
              balanced; divergence shows up as inventory builds or draws, connecting back to the
              Cushing dynamics above."),
            shiny::p("Spring and fall refinery turnarounds suppress demand temporarily. The
              summer driving season and winter heating sustain runs. These seasonal patterns embed
              directly into the forward curve.")
          )
        )
      )
    )
  )
}

# ── Server ───────────────────────────────────────────────────────────────────

mod_md_crude_server <- function(id, dflong, r) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Brent-WTI spread reactive
    bwti_spread_data <- shiny::reactive({
      brn <- dplyr::filter(dflong, series == "BRN01") |> dplyr::select(date, brn = value)
      cl  <- dplyr::filter(dflong, series == "CL01")  |> dplyr::select(date, cl  = value)
      dplyr::inner_join(brn, cl, by = "date") |>
        dplyr::mutate(spread = brn - cl) |>
        dplyr::arrange(date)
    })

    # Cushing WoW inventory change
    cushing_wow_data <- shiny::reactive({
      RTL::cushing$storage |>
        dplyr::arrange(date) |>
        dplyr::mutate(wow_change = stocks - dplyr::lag(stocks)) |>
        dplyr::filter(!is.na(wow_change))
    })

    # HTT available date range
    htt_date_range <- shiny::reactive({
      htt <- dplyr::filter(dflong, series == "HTT01") |> dplyr::pull(date)
      list(min = min(htt), max = max(htt))
    })

    # ── Row 1 ─────────────────────────────────────────────────────────────

    selected_series_data <- shiny::reactive({
      shiny::req(input$series)
      if (input$series == "bwti_spread") {
        bwti_spread_data() |> dplyr::select(date, value = spread)
      } else {
        dplyr::filter(dflong, series == input$series) |>
          dplyr::select(date, value) |>
          dplyr::arrange(date)
      }
    })

    output$stats_card <- shiny::renderUI({
      shiny::req(nrow(selected_series_data()) > 0)
      d <- selected_series_data()
      latest    <- d$value[nrow(d)]
      latest_dt <- d$date[nrow(d)]
      yoy_row   <- d[which.min(abs(d$date - (latest_dt - 365L))), ]
      yoy_chg   <- if (nrow(yoy_row) == 1) latest - yoy_row$value else NA_real_
      pctile    <- round(mean(d$value <= latest, na.rm = TRUE) * 100, 1)
      series_label <- switch(input$series,
        bwti_spread = "Brent\u2212WTI Spread", CL01 = "WTI", BRN01 = "Brent", HTT01 = "HTT Spread")
      bslib::card(
        bslib::card_header(paste(series_label, "Stats")),
        bslib::card_body(
          shiny::div(
            style = "display:flex; gap:10px;",
            stat_box("Latest ($/bbl)", sprintf("%.2f", latest)),
            stat_box("YoY Change", sprintf("%+.2f", if (!is.na(yoy_chg)) yoy_chg else 0)),
            stat_box("Percentile", sprintf("%.0f%%", pctile))
          )
        )
      )
    })

    output$bench_chart <- plotly::renderPlotly({
      shiny::req(nrow(selected_series_data()) > 0)
      d        <- selected_series_data()
      date_min <- min(d$date)
      date_max <- max(d$date)

      # Event shading: filter to events overlapping the data range
      in_evs <- Filter(function(ev) ev$x1 >= date_min && ev$x0 <= date_max, CRUDE_EVENTS)
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

      plotly::plot_ly(
        data          = d,
        x             = ~date,
        y             = ~value,
        type          = "scatter",
        mode          = "lines",
        line          = list(color = "#000080", width = 1.5),
        hovertemplate = "%{x|%b %d, %Y}: %{y:.2f}<extra></extra>"
      ) |>
        plotly::layout(
          xaxis       = list(title = "Date"),
          yaxis       = list(title = "$/bbl"),
          shapes      = ev_shapes,
          annotations = ev_annots,
          legend      = list(orientation = "h", y = -0.2),
          hovermode   = "x unified"
        ) |>
        apply_theme()
    })

    # ── Row 2 sliders + chart ─────────────────────────────────────────────

    output$row2_range_ui <- shiny::renderUI({
      htt_rng <- htt_date_range()
      spread_d <- bwti_spread_data()
      shiny::req(nrow(spread_d) > 0)
      shiny::sliderInput(
        inputId    = ns("row2_range"),
        label      = NULL,
        min        = min(spread_d$date),
        max        = max(spread_d$date),
        value      = c(htt_rng$min, htt_rng$max),
        step       = 7, timeFormat = "%b %Y"
      )
    })

    output$bwti_cushing_chart <- plotly::renderPlotly({
      shiny::req(!is.null(input$row2_range))
      rng      <- input$row2_range
      spread_d <- dplyr::filter(bwti_spread_data(),   date >= rng[1], date <= rng[2])
      cush_d   <- dplyr::filter(cushing_wow_data(),   date >= rng[1], date <= rng[2])
      shiny::req(nrow(spread_d) > 0, nrow(cush_d) > 0)

      bar_colors <- ifelse(cush_d$wow_change < 0, "#c62828", "#2e7d32")
      p_top <- plotly::plot_ly(
        data = spread_d, x = ~date, y = ~spread,
        type = "scatter", mode = "lines",
        name = "Brent\u2212WTI Spread ($/bbl)",
        line = list(color = "#000080", width = 1.5),
        hovertemplate = "%{x|%b %d, %Y}: %{y:.2f} $/bbl<extra></extra>"
      )
      p_bot <- plotly::plot_ly(
        data = cush_d, x = ~date, y = ~wow_change,
        type = "bar", name = "Cushing WoW Change (kb)",
        marker = list(color = bar_colors),
        hovertemplate = "%{x|%b %d, %Y}: %{y:,.0f} kb<extra></extra>"
      )
      plotly::subplot(p_top, p_bot, nrows = 2, shareX = TRUE,
                      heights = c(0.55, 0.45)) |>
        plotly::layout(
          xaxis     = list(title = "Date"),
          yaxis     = list(title = "Brent\u2212WTI Spread ($/bbl)"),
          yaxis2    = list(title = "WoW Change (kb)"),
          legend    = list(orientation = "h", y = -0.15),
          hovermode = "x unified"
        ) |>
        apply_theme()
    })

    # ── Row 3 sliders + chart ─────────────────────────────────────────────

    output$row3_range_ui <- shiny::renderUI({
      htt_rng <- htt_date_range()
      shiny::sliderInput(
        inputId    = ns("row3_range"),
        label      = NULL,
        min        = htt_rng$min,
        max        = htt_rng$max,
        value      = c(htt_rng$min, htt_rng$max),
        step       = 7, timeFormat = "%b %Y"
      )
    })

    output$htt_cushing_chart <- plotly::renderPlotly({
      shiny::req(!is.null(input$row3_range))
      rng    <- input$row3_range
      htt_d  <- dplyr::filter(dflong, series == "HTT01") |>
        dplyr::select(date, value) |> dplyr::arrange(date) |>
        dplyr::filter(date >= rng[1], date <= rng[2])
      cush_d <- dplyr::filter(cushing_wow_data(), date >= rng[1], date <= rng[2])
      shiny::req(nrow(htt_d) > 0, nrow(cush_d) > 0)

      bar_colors <- ifelse(cush_d$wow_change < 0, "#c62828", "#2e7d32")
      p_top <- plotly::plot_ly(
        data = htt_d, x = ~date, y = ~value,
        type = "scatter", mode = "lines",
        name = "HTT Spread ($/bbl)",
        line = list(color = "#CC5500", width = 1.5),
        hovertemplate = "%{x|%b %d, %Y}: %{y:.2f} $/bbl<extra></extra>"
      )
      p_bot <- plotly::plot_ly(
        data = cush_d, x = ~date, y = ~wow_change,
        type = "bar", name = "Cushing WoW Change (kb)",
        marker = list(color = bar_colors),
        hovertemplate = "%{x|%b %d, %Y}: %{y:,.0f} kb<extra></extra>"
      )
      plotly::subplot(p_top, p_bot, nrows = 2, shareX = TRUE,
                      heights = c(0.55, 0.45)) |>
        plotly::layout(
          xaxis     = list(title = "Date"),
          yaxis     = list(title = "HTT Spread ($/bbl)"),
          yaxis2    = list(title = "WoW Change (kb)"),
          legend    = list(orientation = "h", y = -0.15),
          hovermode = "x unified"
        ) |>
        apply_theme()
    })

    # ── Row 4 STL + shared slider ─────────────────────────────────────────

    output$row4_range_ui <- shiny::renderUI({
      shiny::req(!is.null(r$eia_crude_prod), nrow(r$eia_crude_prod) > 0)
      d_min <- min(r$eia_crude_prod$date)
      d_max <- max(r$eia_crude_prod$date)
      shiny::sliderInput(
        inputId    = ns("row4_range"),
        label      = NULL,
        min        = d_min, max = d_max,
        value      = c(d_min, d_max),
        step       = 7, timeFormat = "%b %Y"
      )
    })

    build_stl_plot <- function(eia_df, y_title, date_range = NULL) {
      shiny::req(!is.null(eia_df), nrow(eia_df) > 0)
      d <- dplyr::filter(eia_df,
                         date >= as.Date("2008-01-01"),
                         date <= as.Date("2025-12-31")) |>
        dplyr::arrange(date)
      shiny::req(nrow(d) > 104)
      d$value <- zoo::na.approx(d$value, na.rm = FALSE)
      d <- dplyr::filter(d, !is.na(value))
      stopifnot(sum(is.na(d$value)) == 0)

      stl_fit <- stats::stl(stats::ts(d$value, frequency = 52L), s.window = "periodic")
      components <- data.frame(
        date      = d$date,
        trend     = as.numeric(stl_fit$time.series[, "trend"]),
        seasonal  = as.numeric(stl_fit$time.series[, "seasonal"]),
        remainder = as.numeric(stl_fit$time.series[, "remainder"])
      )

      # Apply display range after STL (decomp always on full history)
      if (!is.null(date_range)) {
        components <- dplyr::filter(components,
                                    date >= date_range[1],
                                    date <= date_range[2])
      }
      shiny::req(nrow(components) > 0)

      p_trend <- plotly::plot_ly(components, x = ~date, y = ~trend,
        type = "scatter", mode = "lines", name = "Trend",
        line = list(color = "#F87217", width = 1.5),
        hovertemplate = "%{x|%b %Y}: %{y:,.1f}<extra></extra>")
      p_seas <- plotly::plot_ly(components, x = ~date, y = ~seasonal,
        type = "scatter", mode = "lines", name = "Seasonal",
        line = list(color = "#4169E1", width = 1.2),
        hovertemplate = "%{x|%b %Y}: %{y:,.1f}<extra></extra>")
      p_rem <- plotly::plot_ly(components, x = ~date, y = ~remainder,
        type = "bar", name = "Remainder",
        marker = list(color = "#757a8a"),
        hovertemplate = "%{x|%b %Y}: %{y:,.1f}<extra></extra>")

      plotly::subplot(p_trend, p_seas, p_rem, nrows = 3, shareX = TRUE,
                      heights = c(0.4, 0.3, 0.3)) |>
        plotly::layout(
          xaxis     = list(title = "Date"),
          yaxis     = list(title = y_title),
          legend    = list(orientation = "h", y = -0.12),
          hovermode = "x unified"
        ) |>
        apply_theme()
    }

    output$stl_prod_chart <- plotly::renderPlotly({
      build_stl_plot(r$eia_crude_prod, "Thousand bbl/day", input$row4_range)
    })

    output$stl_inputs_chart <- plotly::renderPlotly({
      build_stl_plot(r$eia_crude_inputs, "Thousand bbl/day", input$row4_range)
    })
  })
}
