# Market Dynamics — Refined Products Group (all 3 rows)
# Row 1: Seasonal Demand Patterns — STL decomposition of HO and RB prices
# Row 2: Crack Spread — reactive selector; HO / RB / 3-2-1; stats card; event shapes
# Row 3: Product Inventories vs. 5-Year Average — 3-panel subplot
#
# Parameters:
#   id     - Shiny module ID
#   dflong - full RTL::dflong tibble
#   r      - shared reactiveValues; reads r$eia_distillate_stocks,
#            r$eia_gasoline_stocks
#
# Example:
#   mod_md_refined_ui("refined")
#   mod_md_refined_server("refined", dflong = dflong, r = r)

# Event date ranges for Row 2 crack spread background shading
CRACK_EVENT_RANGES <- list(
  list(
    label     = "Hurricane Harvey",
    x0        = "2017-07-25", x1 = "2017-09-25",
    fillcolor = "rgba(248,114,23,0.14)"   # orange
  ),
  list(
    label     = "COVID-19 / Oil Price War",
    x0        = "2020-01-01", x1 = "2020-06-30",
    fillcolor = "rgba(200,0,0,0.12)"       # red
  ),
  list(
    label     = "Russia-Ukraine War",
    x0        = "2022-01-01", x1 = "2023-12-31",
    fillcolor = "rgba(23,157,248,0.12)"    # blue
  ),
  list(
    label     = "Iran War",
    x0        = "2026-03-01", x1 = format(Sys.Date()),
    fillcolor = "rgba(150,0,200,0.12)"     # purple
  )
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

mod_md_refined_ui <- function(id) {
  ns <- shiny::NS(id)

  tagList(
    # ── Row 1 — Seasonal Demand Patterns ────────────────────────────────────
    # Layout: col(1) | col_b(6) visualization | col_c(4) narrative | col(1)
    shiny::fluidRow(
      shiny::column(width = 1),
      shiny::column(
        width = 6,
        shiny::tags$h6("HO & RB Seasonal Patterns \u2014 STL Decomposition",
                        style = "text-align:center; margin-bottom:8px;"),
        shinycssloaders::withSpinner(
          plotly::plotlyOutput(ns("stl_chart"), height = "500px"),
          color = "#F87217"
        )
      ),
      shiny::column(
        width = 4,
        bslib::card(
          bslib::card_body(
            shiny::tags$strong("Heating Oil (HO)"),
            shiny::p("Winter heating demand peaks December\u2013February; northeast US residential
              demand drives prices higher through fall in anticipation."),
            shiny::tags$strong("Gasoline (RB)"),
            shiny::p("Summer driving season peaks Memorial Day through Labor Day. EPA summer
              blend specs are more expensive to produce; prices typically peak April\u2013May ahead
              of the season."),
            shiny::p("Both products come from the same crude barrel \u2014 refiners adjust the
              distillation cut to favour distillates (HO, diesel) ahead of winter or lighter
              products (RB) ahead of summer; inventory is built in advance of each seasonal peak."),
            shiny::p("The forward curve embeds these premia directly \u2014 winter HO contracts trade
              at a premium to summer months, summer RB contracts at a premium to winter months.
              Hedgers who understand the cycle can time curve entries before the seasonal premium
              builds rather than after it is already priced in.")
          )
        )
      ),
      shiny::column(width = 1)
    ),

    # ── Row 2 — Crack Spread ─────────────────────────────────────────────────
    shiny::fluidRow(
      # col_a (width=4): stats card + narrative
      shiny::column(
        width = 4,
        shiny::uiOutput(ns("crack_stats_card")),
        bslib::card(
          bslib::card_body(
            shiny::p("Crack spreads represent the refinery gross margin \u2014 the difference between
              the value of refined products and the cost of crude input. Wide cracks = fat margins,
              refiners incentivised to run hard. Narrow or negative cracks = refiners squeezed,
              run rates cut."),
            shiny::p("Refiners are naturally long the crack spread. When cracks are wide, they lock
              in that margin by selling the crack: short refined product futures (HO/RB), long crude
              futures (CL)."),
            shiny::p("Heating oil and diesel consumers are naturally short the crack. They offset
              that exposure by going long HO or RB futures to lock in prices.")
          )
        )
      ),
      # col_b (width=8): crack spread selector + chart with event shading
      shiny::column(
        width = 8,
        shinyWidgets::prettyRadioButtons(
          inputId  = ns("crack"),
          label    = NULL,
          choices  = c("HO Crack" = "ho", "RB Crack" = "rb", "3-2-1" = "321"),
          selected = "ho",
          status   = "primary",
          inline   = TRUE,
          fill     = FALSE
        ),
        shinycssloaders::withSpinner(
          plotly::plotlyOutput(ns("crack_chart"), height = "400px"),
          color = "#F87217"
        )
      )
    ),

    # ── Row 3 — Product Inventories vs. 5-Year Average ──────────────────────
    shiny::fluidRow(
      shiny::column(
        width = 6,
        shinyWidgets::prettyRadioButtons(
          inputId  = ns("product"),
          label    = NULL,
          choices  = c("Distillate (HO)" = "ho", "Gasoline (RB)" = "rb"),
          selected = "ho",
          status   = "primary",
          inline   = TRUE,
          fill     = FALSE
        ),
        shinycssloaders::withSpinner(
          plotly::plotlyOutput(ns("stocks_chart"), height = "520px"),
          color = "#F87217"
        ),
        shiny::uiOutput(ns("stocks_range_ui"))
      ),
      shiny::column(
        width = 6,
        bslib::card(
          bslib::card_body(
            shiny::p("EIA weekly product inventory levels are the primary supply/demand balance
              signal for refined products. The weekly report is one of the most market-moving
              data releases in energy."),
            shiny::p("Below the 5-year average signals tighter supply \u2014 prices and crack spreads
              are bid up. Above average signals oversupply \u2014 margins compress and prices soften."),
            shiny::p("Distillate inventories draw sharply in winter as heating demand peaks.
              Gasoline inventories tighten ahead of the summer driving season.")
          )
        )
      )
    )
  )
}

# ── Server ───────────────────────────────────────────────────────────────────

mod_md_refined_server <- function(id, dflong, r) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # ── Row 1: STL of HO01 and RB01 weekly prices ─────────────────────────
    weekly_prices <- shiny::reactive({
      ho_raw <- dplyr::filter(dflong, series == "HO01") |>
        dplyr::select(date, value) |> dplyr::arrange(date)
      rb_raw <- dplyr::filter(dflong, series == "RB01") |>
        dplyr::select(date, value) |> dplyr::arrange(date)

      to_weekly <- function(df) {
        df |>
          dplyr::mutate(week_key = paste(
            lubridate::isoyear(date),
            sprintf("%02d", lubridate::isoweek(date)), sep = "-"
          )) |>
          dplyr::group_by(week_key) |>
          dplyr::slice_tail(n = 1) |>
          dplyr::ungroup() |>
          dplyr::select(date, value)
      }
      list(ho = to_weekly(ho_raw), rb = to_weekly(rb_raw))
    })

    output$stl_chart <- plotly::renderPlotly({
      wp <- weekly_prices()

      build_stl <- function(series_df, label) {
        shiny::req(nrow(series_df) > 104)
        series_df$value <- zoo::na.approx(series_df$value, na.rm = FALSE)
        series_df <- dplyr::filter(series_df, !is.na(value))
        stl_fit <- stats::stl(
          stats::ts(series_df$value, frequency = 52L),
          s.window = "periodic"
        )
        data.frame(
          date      = series_df$date,
          trend     = as.numeric(stl_fit$time.series[, "trend"]),
          seasonal  = as.numeric(stl_fit$time.series[, "seasonal"])
        )
      }

      ho_comp <- build_stl(wp$ho, "HO")
      rb_comp <- build_stl(wp$rb, "RB")

      # 4 panels: HO trend, HO seasonal, RB trend, RB seasonal
      p1 <- plotly::plot_ly(ho_comp, x = ~date, y = ~trend,
        type = "scatter", mode = "lines", name = "HO Trend",
        line = list(color = "#800020", width = 1.5),
        hovertemplate = "HO Trend %{x|%b %Y}: %{y:.4f}<extra></extra>")

      p2 <- plotly::plot_ly(ho_comp, x = ~date, y = ~seasonal,
        type = "scatter", mode = "lines", name = "HO Seasonal",
        line = list(color = "#CC5500", width = 1.2),
        hovertemplate = "HO Seasonal %{x|%b %Y}: %{y:.4f}<extra></extra>")

      p3 <- plotly::plot_ly(rb_comp, x = ~date, y = ~trend,
        type = "scatter", mode = "lines", name = "RB Trend",
        line = list(color = "#4169E1", width = 1.5),
        hovertemplate = "RB Trend %{x|%b %Y}: %{y:.4f}<extra></extra>")

      p4 <- plotly::plot_ly(rb_comp, x = ~date, y = ~seasonal,
        type = "scatter", mode = "lines", name = "RB Seasonal",
        line = list(color = "#179df8", width = 1.2),
        hovertemplate = "RB Seasonal %{x|%b %Y}: %{y:.4f}<extra></extra>")

      plotly::subplot(p1, p2, p3, p4, nrows = 4, shareX = TRUE,
                      heights = c(0.3, 0.2, 0.3, 0.2)) |>
        plotly::layout(
          xaxis  = list(title = "Date"),
          legend = list(orientation = "h", y = 1.04, xanchor = "left", x = 0),
          hovermode = "x unified"
        ) |>
        apply_theme()
    })

    # ── Row 2: Crack Spread ───────────────────────────────────────────────

    crack_spread_data <- shiny::reactive({
      ho_d <- dplyr::filter(dflong, series == "HO01") |> dplyr::select(date, ho = value)
      rb_d <- dplyr::filter(dflong, series == "RB01") |> dplyr::select(date, rb = value)
      cl_d <- dplyr::filter(dflong, series == "CL01") |> dplyr::select(date, cl = value)

      joined    <- dplyr::inner_join(ho_d, rb_d, by = "date") |>
        dplyr::inner_join(cl_d, by = "date")
      n_ho_rb   <- nrow(dplyr::inner_join(ho_d, rb_d, by = "date"))
      n_dropped <- n_ho_rb - nrow(joined)
      if (n_dropped > 0) {
        warning(sprintf(
          "crack_spread_data: inner join dropped %d rows due to missing leg(s).",
          n_dropped
        ))
      }

      dplyr::mutate(joined,
        ho_crack  = ho * 42 - cl,
        rb_crack  = rb * 42 - cl,
        crack_321 = (2 * rb * 42 + ho * 42 - 3 * cl) / 3
      ) |> dplyr::arrange(date)
    })

    active_crack <- shiny::reactive({
      switch(input$crack,
        ho    = crack_spread_data() |> dplyr::select(date, value = ho_crack),
        rb    = crack_spread_data() |> dplyr::select(date, value = rb_crack),
        `321` = crack_spread_data() |> dplyr::select(date, value = crack_321)
      )
    })

    # 3-box stats card with dynamic title
    output$crack_stats_card <- shiny::renderUI({
      d <- active_crack()
      shiny::req(nrow(d) > 0)

      latest    <- d$value[nrow(d)]
      latest_dt <- d$date[nrow(d)]
      yoy_row   <- d[which.min(abs(d$date - (latest_dt - 365L))), ]
      yoy_chg   <- if (nrow(yoy_row) == 1) latest - yoy_row$value else NA_real_
      pctile    <- round(mean(d$value <= latest, na.rm = TRUE) * 100, 1)

      label <- switch(input$crack,
        ho = "HO Crack", rb = "RB Crack", `321` = "3-2-1 Crack")

      bslib::card(
        bslib::card_header(paste(label, "Stats")),
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

    output$crack_chart <- plotly::renderPlotly({
      d <- active_crack()
      shiny::req(nrow(d) > 0)

      # Background shapes for event periods
      shapes <- lapply(CRACK_EVENT_RANGES, function(ev) {
        list(type = "rect",
             x0 = ev$x0, x1 = ev$x1,
             y0 = 0, y1 = 1, yref = "paper",
             fillcolor = ev$fillcolor,
             line = list(width = 0))
      })

      # Annotations labeling each shaded region
      annots <- lapply(CRACK_EVENT_RANGES, function(ev) {
        mid_date <- as.character(
          as.Date(ev$x0) + as.integer(as.Date(ev$x1) - as.Date(ev$x0)) / 2L
        )
        list(x = mid_date, y = 0.97, yref = "paper",
             text = ev$label, showarrow = FALSE,
             font = list(size = 9, color = "#000000"),
             xanchor = "center")
      })

      plotly::plot_ly(
        data          = d,
        x             = ~date,
        y             = ~value,
        type          = "scatter",
        mode          = "lines",
        line          = list(color = "#800020", width = 1.5),
        name          = switch(input$crack,
                               ho = "HO Crack", rb = "RB Crack", `321` = "3-2-1"),
        hovertemplate = "%{x|%b %d, %Y}: %{y:.2f} $/bbl<extra></extra>"
      ) |>
        plotly::layout(
          xaxis       = list(title = "Date"),
          yaxis       = list(title = "$/bbl"),
          shapes      = shapes,
          annotations = annots,
          showlegend  = FALSE,
          hovermode   = "x unified"
        ) |>
        apply_theme()
    })

    # ── Row 3: Product Inventories vs. 5-Year Average ─────────────────────

    active_stocks <- shiny::reactive({
      if (input$product == "ho") r$eia_distillate_stocks
      else                       r$eia_gasoline_stocks
    })

    active_price_series <- shiny::reactive({
      ticker <- if (input$product == "ho") "HO01" else "RB01"
      dplyr::filter(dflong, series == ticker) |>
        dplyr::select(date, price = value) |>
        dplyr::arrange(date)
    })

    stocks_with_avg <- shiny::reactive({
      stocks <- active_stocks()
      shiny::req(!is.null(stocks), nrow(stocks) > 0)

      stocks <- dplyr::arrange(stocks, date) |>
        dplyr::mutate(year = lubridate::year(date), week_num = lubridate::week(date))

      min_yr    <- min(stocks$year)
      cutoff_yr <- min_yr + 5L

      stocks |>
        dplyr::group_by(week_num) |>
        dplyr::arrange(year) |>
        dplyr::mutate(
          roll5       = zoo::rollapplyr(value, width = 5L, FUN = mean, fill = NA, align = "right"),
          five_yr_avg = dplyr::case_when(
            year < cutoff_yr ~ NA_real_,
            TRUE             ~ dplyr::lag(roll5, 1L)
          )
        ) |>
        dplyr::select(-roll5) |>
        dplyr::ungroup() |>
        dplyr::arrange(date) |>
        dplyr::mutate(surplus = value - five_yr_avg)
    })

    output$stocks_range_ui <- shiny::renderUI({
      sw <- stocks_with_avg()
      shiny::req(nrow(sw) > 0)
      d_max <- max(sw$date)
      d_min <- min(sw$date)
      shiny::sliderInput(
        inputId    = ns("stocks_range"),
        label      = NULL,
        min        = as.Date("2007-01-01"), max = d_max,
        value      = c(as.Date("2007-01-01"), d_max),
        step       = 7, timeFormat = "%b %Y"
      )
    })

    output$stocks_chart <- plotly::renderPlotly({
      sw <- stocks_with_avg()
      pr <- active_price_series()
      shiny::req(nrow(sw) > 0)

      # Apply date range slider if available
      if (!is.null(input$stocks_range)) {
        sw <- dplyr::filter(sw, date >= input$stocks_range[1], date <= input$stocks_range[2])
        pr <- dplyr::filter(pr, date >= input$stocks_range[1], date <= input$stocks_range[2])
      }
      shiny::req(nrow(sw) > 0)

      price_label <- if (input$product == "ho") "HO Front Month ($/gal)" else "RB Front Month ($/gal)"
      bar_colors  <- ifelse(sw$surplus >= 0, "#2e7d32", "#c62828")
      sw_has_avg  <- dplyr::filter(sw, !is.na(five_yr_avg))
      sw_has_sur  <- dplyr::filter(sw, !is.na(surplus))

      # Panel 1: price only — navy blue
      p_price <- plotly::plot_ly(
        data = pr, x = ~date, y = ~price,
        type = "scatter", mode = "lines",
        name = price_label,
        line = list(color = "#000080", width = 1.5),
        hovertemplate = "%{x|%b %d, %Y}: %{y:.4f}<extra></extra>"
      )

      # Panel 2: actual stocks + 5-year average
      p_stocks <- plotly::plot_ly() |>
        plotly::add_lines(
          data = sw, x = ~date, y = ~value,
          name = "Actual Stocks (k bbl)",
          line = list(color = "#210000", width = 1.2),
          hovertemplate = "%{x|%b %d, %Y}: %{y:,.0f}<extra></extra>"
        ) |>
        plotly::add_lines(
          data = sw_has_avg, x = ~date, y = ~five_yr_avg,
          name = "5-Year Average (k bbl)",
          line = list(color = "#4169E1", width = 1.2, dash = "dash"),
          hovertemplate = "%{x|%b %d, %Y}: %{y:,.0f}<extra></extra>"
        )

      # Panel 3: surplus/deficit bars
      p_bars <- plotly::plot_ly(
        data = sw_has_sur,
        x = ~date, y = ~surplus,
        type = "bar",
        name = "Surplus / Deficit (k bbl)",
        marker = list(color = bar_colors[!is.na(sw$surplus)]),
        hovertemplate = "%{x|%b %d, %Y}: %{y:,.0f} k bbl<extra></extra>"
      )

      plotly::subplot(p_price, p_stocks, p_bars,
                      nrows = 3, shareX = TRUE,
                      heights = c(0.3, 0.4, 0.3)) |>
        plotly::layout(
          xaxis     = list(title = "Date"),
          yaxis     = list(title = "Price ($/gal)"),
          yaxis2    = list(title = "Stocks (k bbl)"),
          yaxis3    = list(title = "Surplus / Deficit"),
          legend    = list(orientation = "h", y = 1.04,
                           xanchor = "left", x = 0),
          hovermode = "x unified"
        ) |>
        apply_theme()
    })
  })
}
