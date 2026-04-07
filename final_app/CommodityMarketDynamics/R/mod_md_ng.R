# Market Dynamics — Natural Gas Group (all 4 rows)
# Row 1: Storage Seasonality — one line per year overlay chart
# Row 2: Storage vs. Price — subplot with 5-year average and surplus/deficit
# Row 3: Fuel Switching (Coal-to-Gas) — HH price vs. coal generation changes + map
# Row 4: LNG Exports & Price Floor — 2-panel subplot + Sabine Pass annotation
#
# Parameters:
#   id         - Shiny module ID
#   dflong     - full RTL::dflong tibble
#   r          - shared reactiveValues; reads r$eia_ng_storage, r$eia_lng_exports,
#                r$eia923_coal; triggers lazy EIA-923 load
#   ng_trigger - reactive() that fires TRUE when NG group is selected
#
# Example:
#   mod_md_ng_ui("ng")
#   mod_md_ng_server("ng", dflong = dflong, r = r, ng_trigger = reactive(TRUE))

# ── UI ───────────────────────────────────────────────────────────────────────

mod_md_ng_ui <- function(id) {
  ns <- shiny::NS(id)

  tagList(
    # ── Row 1 — Storage Seasonality ─────────────────────────────────────────
    shiny::fluidRow(
      style = "border-bottom: none; margin-bottom: 0; padding-bottom: 0;",
      shiny::column(width = 3),
      shiny::column(
        width = 6,
        shiny::tags$h6("US Natural Gas Storage — Seasonal Overlay",
                        style = "text-align:center; margin-bottom:8px;"),
        shinycssloaders::withSpinner(
          plotly::plotlyOutput(ns("storage_seasonal"), height = "420px"),
          color = "#F87217"
        )
      ),
      shiny::column(width = 3)
    ),
    shiny::fluidRow(
      shiny::column(width = 2),
      shiny::column(
        width = 8,
        bslib::card(
          bslib::card_body(
            shiny::p("Natural gas demand is highly seasonal and weather-driven. Summer months
              are injection season — demand is low, production flows into storage in preparation
              for winter. Winter flips the dynamic: residential and commercial heating demand
              draws on those reserves, tightening supply and pushing prices higher."),
            shiny::p("Cold snaps amplify this further — extreme temperatures not only spike
              heating demand but can cause well freeze-offs and pipeline outages, simultaneously
              constraining supply at the moment demand peaks. The result is that winter price
              spikes in natural gas can be sharp and sudden, driven as much by weather as
              by fundamentals.")
          )
        )
      ),
      shiny::column(width = 2)
    ),

    # ── Row 2 — Storage vs. Price ────────────────────────────────────────────
    # Layout: margin(1) + slider(2) + chart(6) + narrative(3) = 12
    shiny::fluidRow(
      class = "mt-3",
      shiny::column(width = 1),  # left margin
      shiny::column(
        width = 2,
        shiny::uiOutput(ns("storage_slider_ui"))
      ),
      shiny::column(
        width = 6,
        shinycssloaders::withSpinner(
          plotly::plotlyOutput(ns("storage_vs_price"), height = "450px"),
          color = "#F87217"
        )
      ),
      shiny::column(
        width = 3,
        bslib::card(
          bslib::card_body(
            shiny::p("Storage is the heartbeat of the natural gas market. The 5-year average
              is the universal benchmark — above average means oversupply, prices suppressed;
              below average means tightness, prices spike."),
            shiny::p("The weekly EIA storage report is one of the most market-moving data
              releases in energy. Relevant for hedgers deciding when to lock in gas supply
              or sales.")
          )
        )
      )
    ),

    # ── Row 3 — Fuel Switching (Coal-to-Gas) ─────────────────────────────────
    # Layout: chart(7) + inputs(2) + narrative(3) = 12
    shiny::fluidRow(
      class = "mt-3",
      shiny::column(
        width = 7,
        shinycssloaders::withSpinner(
          shiny::uiOutput(ns("fuel_chart_ui")),
          color = "#F87217"
        )
      ),
      shiny::column(
        width = 2,
        # Static toggle at top of inputs column; dynamic selectors below
        bslib::input_switch(ns("view_toggle"), "State Coal Share Map", value = FALSE),
        shiny::uiOutput(ns("fuel_inputs_ui"))
      ),
      shiny::column(
        width = 3,
        bslib::card(
          bslib::card_body(
            shiny::p("When natural gas prices rise, utilities in coal-heavy regions switch back
              to coal, softening gas demand and acting as a price cap. The cap is not a fixed
              number — it is geographically distributed."),
            shiny::p("South and Midwest retain significant coal capacity (KY, WV, TX, IL, IN, OH).
              Northeast has largely retired coal so the switching mechanism is weaker. The map
              shows geographic distribution of coal dependency.")
          )
        )
      )
    ),

    # ── Row 4 — LNG Exports & Price Floor ────────────────────────────────────
    shiny::fluidRow(
      class = "mt-3",
      shiny::column(
        width = 4,
        bslib::card(
          bslib::card_body(
            shiny::p("Before 2016 the US gas market was largely isolated — prices determined
              by domestic supply and demand alone. Sabine Pass (2016) structurally changed this.
              Henry Hub now has a global floor linked to international LNG prices."),
            shiny::p("When domestic prices fall far enough below international levels, export
              demand absorbs the surplus. Hedgers can no longer treat Henry Hub as a purely
              domestic market.")
          )
        )
      ),
      shiny::column(
        width = 8,
        shinycssloaders::withSpinner(
          plotly::plotlyOutput(ns("lng_chart"), height = "420px"),
          color = "#F87217"
        )
      )
    )
  )
}

# ── Server ───────────────────────────────────────────────────────────────────

mod_md_ng_server <- function(id, dflong, r, ng_trigger) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # ── Row 1: Seasonal Storage Overlay ───────────────────────────────────

    output$storage_seasonal <- plotly::renderPlotly({
      shiny::req(!is.null(r$eia_ng_storage), nrow(r$eia_ng_storage) > 0)

      # Constrain to 2008–2025, add year + week-of-year (1-53)
      d <- dplyr::filter(
        r$eia_ng_storage,
        date >= as.Date("2008-01-01"),
        date <= as.Date("2025-12-31")
      ) |>
        dplyr::mutate(
          year     = lubridate::year(date),
          week_num = lubridate::week(date)
        ) |>
        dplyr::arrange(year, week_num)

      years <- sort(unique(d$year))
      n_yrs <- length(years)

      # Rainbow color scale: each year is clearly distinct
      yr_colors <- grDevices::rainbow(n_yrs, start = 0, end = 0.85)
      yr_color  <- setNames(yr_colors, as.character(years))

      p <- plotly::plot_ly()
      for (yr in years) {
        yr_data <- dplyr::filter(d, year == yr)
        p <- plotly::add_lines(
          p,
          data          = yr_data,
          x             = ~week_num,
          y             = ~value,
          name          = as.character(yr),
          line          = list(color = yr_color[as.character(yr)], width = 1.2),
          hovertemplate = paste0(yr, " Week %{x}: %{y:,.0f} Bcf<extra></extra>")
        )
      }

      p |>
        plotly::layout(
          xaxis     = list(title = "Week of Year", range = c(1, 53)),
          yaxis     = list(title = "Storage (Bcf)"),
          legend    = list(orientation = "h", y = -0.25, title = list(text = "Year")),
          hovermode = "closest"
        ) |>
        apply_theme()
    })

    # ── Row 2: Storage vs. Price ───────────────────────────────────────────

    # 5-year calendar average: mean of prior 5 years per week-of-year
    # (EIA standard: lag(rollapplyr(..., 5), 1) so year Y gets mean of Y-5:Y-1)
    storage_with_avg <- shiny::reactive({
      shiny::req(!is.null(r$eia_ng_storage))
      d <- dplyr::arrange(r$eia_ng_storage, date) |>
        dplyr::mutate(
          year     = lubridate::year(date),
          week_num = lubridate::week(date)
        )

      min_yr    <- min(d$year)
      cutoff_yr <- min_yr + 5L

      d <- d |>
        dplyr::group_by(week_num) |>
        dplyr::arrange(year) |>
        dplyr::mutate(
          roll5       = zoo::rollapplyr(value, width = 5L, FUN = mean,
                                        fill = NA, align = "right"),
          five_yr_avg = dplyr::case_when(
            year < cutoff_yr ~ NA_real_,
            TRUE             ~ dplyr::lag(roll5, 1L)
          )
        ) |>
        dplyr::select(-roll5) |>
        dplyr::ungroup() |>
        dplyr::arrange(date) |>
        dplyr::mutate(surplus = value - five_yr_avg)

      d
    })

    # Date range slider rendered in the inputs column (width=2)
    output$storage_slider_ui <- shiny::renderUI({
      d <- storage_with_avg()
      shiny::req(nrow(d) > 0)
      date_min <- min(d$date)
      date_max <- max(d$date)
      shiny::sliderInput(
        inputId    = ns("storage_range"),
        label      = "Date Range",
        min        = date_min,
        max        = date_max,
        value      = c(date_min, date_max),
        step       = 7,
        timeFormat = "%b %Y"
      )
    })

    # Enforce 5-week minimum range
    storage_range_validated <- shiny::reactive({
      shiny::req(input$storage_range)
      rng <- input$storage_range
      if (as.integer(rng[2] - rng[1]) < 35L) {
        rng[2] <- rng[1] + 35L
      }
      rng
    })

    output$storage_vs_price <- plotly::renderPlotly({
      sw <- storage_with_avg()
      shiny::req(nrow(sw) > 0, !is.null(input$storage_range))

      rng  <- storage_range_validated()
      sw_f <- dplyr::filter(sw, date >= rng[1], date <= rng[2])

      ng_price <- dplyr::filter(dflong, series == "NG01") |>
        dplyr::select(date, price = value) |>
        dplyr::filter(date >= rng[1], date <= rng[2]) |>
        dplyr::arrange(date)

      shiny::req(nrow(sw_f) > 0)

      # Green = surplus (current > 5yr avg), red = deficit (current < 5yr avg)
      bar_colors <- ifelse(sw_f$surplus >= 0, "#2e7d32", "#c62828")

      # Top panel: NG price + actual storage + 5yr avg
      p_top <- plotly::plot_ly() |>
        plotly::add_lines(
          data          = ng_price,
          x             = ~date,
          y             = ~price,
          name          = "NG Front Month ($/MMBtu)",
          line          = list(color = "#000080", width = 1.5),
          hovertemplate = "%{x|%b %d, %Y}: %{y:.3f} $/MMBtu<extra></extra>"
        ) |>
        plotly::add_lines(
          data          = sw_f,
          x             = ~date,
          y             = ~value,
          yaxis         = "y2",
          name          = "Actual Storage (Bcf)",
          line          = list(color = "#800020", width = 1.2),
          hovertemplate = "%{x|%b %d, %Y}: %{y:,.0f} Bcf<extra></extra>"
        ) |>
        plotly::add_lines(
          data          = dplyr::filter(sw_f, !is.na(five_yr_avg)),
          x             = ~date,
          y             = ~five_yr_avg,
          yaxis         = "y2",
          name          = "5-Year Average (Bcf)",
          line          = list(color = "#4169E1", width = 1.2, dash = "dash"),
          hovertemplate = "%{x|%b %d, %Y}: %{y:,.0f} Bcf<extra></extra>"
        ) |>
        plotly::layout(
          yaxis  = list(title = "Price ($/MMBtu)"),
          yaxis2 = list(title = "Storage (Bcf)", overlaying = "y", side = "right")
        )

      # Bottom panel: surplus/deficit bars (green = surplus, red = deficit)
      sw_def <- dplyr::filter(sw_f, !is.na(surplus))
      p_bot <- plotly::plot_ly(
        data          = sw_def,
        x             = ~date,
        y             = ~surplus,
        type          = "bar",
        name          = "Surplus / Deficit (Bcf)",
        marker        = list(color = bar_colors[!is.na(sw_f$surplus)]),
        hovertemplate = "%{x|%b %d, %Y}: %{y:,.0f} Bcf<extra></extra>"
      )

      plotly::subplot(p_top, p_bot, nrows = 2, shareX = TRUE,
                      heights = c(0.6, 0.4)) |>
        plotly::layout(
          xaxis     = list(title = "Date"),
          legend    = list(orientation = "h", y = -0.15),
          hovermode = "x unified"
        ) |>
        apply_theme()
    })

    # ── Row 3: Fuel Switching ──────────────────────────────────────────────

    # Trigger EIA-923 lazy load when NG group first becomes active
    mod_md_eia923_server(r = r, trigger = ng_trigger)

    # Chart output — view toggle switches between subplot and choropleth
    output$fuel_chart_ui <- shiny::renderUI({
      if (isTRUE(input$view_toggle)) {
        plotly::plotlyOutput(ns("coal_map"), height = "420px")
      } else {
        plotly::plotlyOutput(ns("coal_gen_chart"), height = "420px")
      }
    })

    # Inputs column — dynamic selectors based on view toggle
    output$fuel_inputs_ui <- shiny::renderUI({
      coal <- r$eia923_coal

      if (isTRUE(input$view_toggle)) {
        # View 2: map month picker
        if (is.null(coal)) return(shiny::p("Loading EIA-923 data..."))
        shiny::sliderInput(
          inputId    = ns("map_month"),
          label      = "Month",
          min        = min(coal$state_monthly$date),
          max        = max(coal$state_monthly$date),
          value      = max(coal$state_monthly$date),
          step       = 30,
          timeFormat = "%b %Y"
        )
      } else {
        # View 1: region selector + date range slider
        if (is.null(coal)) return(shiny::p("Loading EIA-923 data..."))
        d_max     <- max(coal$region_monthly$date)
        # Start at the earliest NG price date so both series are present
        ng_start  <- dplyr::filter(dflong, series == "NG01") |> dplyr::pull(date) |> min()
        d_min     <- max(min(coal$region_monthly$date), as.Date(ng_start))
        tagList(
          shiny::selectInput(
            inputId  = ns("region"),
            label    = "Census Division",
            choices  = c("Overall", sort(unique(coal$region_monthly$region))),
            selected = "Overall"
          ),
          shiny::sliderInput(
            inputId    = ns("coal_range"),
            label      = "Date Range",
            min        = d_min,
            max        = d_max,
            value      = c(d_min, d_max),
            step       = 30,
            timeFormat = "%b %Y"
          )
        )
      }
    })

    # View 1: HH Price subplot + ΔCoal Generation bars with ±1.5 SD confidence band
    output$coal_gen_chart <- plotly::renderPlotly({
      coal <- r$eia923_coal
      shiny::req(!is.null(coal), !is.null(input$coal_range))

      region_sel <- input$region
      rng        <- input$coal_range

      # Aggregate full coal history by region (need lag before range filter)
      coal_full <- if (region_sel == "Overall") {
        coal$region_monthly |>
          dplyr::group_by(date) |>
          dplyr::summarise(mwh = sum(mwh, na.rm = TRUE), .groups = "drop") |>
          dplyr::arrange(date)
      } else {
        dplyr::filter(coal$region_monthly, region == region_sel) |>
          dplyr::arrange(date)
      }

      # Year-over-year change: same calendar month, prior year.
      # Removes both seasonality and the long-term coal decline trend in one step.
      coal_full <- coal_full |>
        dplyr::arrange(date) |>
        dplyr::mutate(delta_mwh = mwh - dplyr::lag(mwh, 12L))
      coal_d    <- dplyr::filter(coal_full,
                                 date >= rng[1], date <= rng[2],
                                 !is.na(delta_mwh))

      # Monthly NG price average
      ng_monthly <- dplyr::filter(dflong, series == "NG01") |>
        dplyr::mutate(month_date = as.Date(format(date, "%Y-%m-01"))) |>
        dplyr::group_by(month_date) |>
        dplyr::summarise(price = mean(value, na.rm = TRUE), .groups = "drop") |>
        dplyr::filter(month_date >= rng[1], month_date <= rng[2])

      shiny::req(nrow(coal_d) > 0, nrow(ng_monthly) > 0)

      # Confidence band: ±1.5 SD of delta over the filtered window
      sd_delta   <- stats::sd(coal_d$delta_mwh, na.rm = TRUE)
      bar_colors <- ifelse(coal_d$delta_mwh >= 0, "#2e7d32", "#c62828")

      # Top panel: HH price line
      p_price <- plotly::plot_ly() |>
        plotly::add_lines(
          data          = ng_monthly,
          x             = ~month_date,
          y             = ~price,
          name          = "HH Price ($/MMBtu)",
          line          = list(color = "#000080", width = 2),
          hovertemplate = "%{x|%b %Y}: %{y:.3f} $/MMBtu<extra></extra>"
        ) |>
        plotly::layout(yaxis = list(title = "HH Price ($/MMBtu)"))

      # Bottom panel: coal generation change bars (green=increase, red=decrease)
      p_coal <- plotly::plot_ly() |>
        plotly::add_bars(
          data          = coal_d,
          x             = ~date,
          y             = ~delta_mwh,
          name          = "Coal Gen YoY Change (MWh)",
          marker        = list(color = bar_colors),
          hovertemplate = "%{x|%b %Y}: %{y:+,.0f} MWh vs same month last year<extra></extra>"
        ) |>
        plotly::layout(yaxis = list(title = "Coal Gen YoY Change (MWh)"))

      x_min <- min(coal_d$date)
      x_max <- max(coal_d$date)

      plotly::subplot(p_price, p_coal, nrows = 2, shareX = TRUE,
                      heights = c(0.45, 0.55)) |>
        plotly::layout(
          xaxis     = list(title = "Month"),
          shapes    = list(list(
            type="rect", xref="x", yref="y2",
            x0=x_min, x1=x_max,
            y0=-1.5*sd_delta, y1=1.5*sd_delta,
            fillcolor="rgba(150,150,150,0.15)", line=list(color="transparent")
          )),
          legend    = list(orientation = "h", y = -0.15),
          hovermode = "x unified"
        ) |>
        apply_theme()
    })

    # View 2: State Coal Share Map (choropleth)
    output$coal_map <- plotly::renderPlotly({
      coal <- r$eia923_coal
      shiny::req(!is.null(coal), !is.null(input$map_month))

      target_month <- as.Date(format(input$map_month, "%Y-%m-01"))
      avail_months <- unique(coal$state_monthly$date)
      snap_month   <- avail_months[which.min(abs(avail_months - target_month))]

      state_d <- dplyr::filter(coal$state_monthly, date == snap_month)
      shiny::req(nrow(state_d) > 0)

      plotly::plot_ly(
        data          = state_d,
        type          = "choropleth",
        locationmode  = "USA-states",
        locations     = ~plant_state,
        z             = ~mwh,
        colorscale    = "Viridis",
        zmin          = min(state_d$mwh, na.rm = TRUE),
        zmax          = max(state_d$mwh, na.rm = TRUE),
        hovertemplate = paste0(
          "<b>%{location}</b><br>",
          format(snap_month, "%b %Y"), "<br>",
          "%{z:,.0f} MWh<extra></extra>"
        )
      ) |>
        plotly::layout(geo = list(scope = "usa")) |>
        apply_theme()
    })

    # ── Row 4: LNG Exports & Price Floor — 2-panel subplot ────────────────

    output$lng_chart <- plotly::renderPlotly({
      shiny::req(!is.null(r$eia_lng_exports), nrow(r$eia_lng_exports) > 0)

      # Monthly average NG price from dflong
      ng_monthly <- dplyr::filter(dflong, series == "NG01") |>
        dplyr::mutate(month_date = as.Date(format(date, "%Y-%m-01"))) |>
        dplyr::group_by(month_date) |>
        dplyr::summarise(price = mean(value, na.rm = TRUE), .groups = "drop")

      # LNG exports — round to first of month and aggregate
      lng <- r$eia_lng_exports |>
        dplyr::mutate(month_date = as.Date(format(date, "%Y-%m-01"))) |>
        dplyr::group_by(month_date) |>
        dplyr::summarise(exports = sum(value, na.rm = TRUE), .groups = "drop")

      joined <- dplyr::inner_join(ng_monthly, lng, by = "month_date") |>
        dplyr::arrange(month_date)

      shiny::req(nrow(joined) > 0)

      viridis_blue <- viridisLite::viridis(1, begin = 0.4, end = 0.4)
      sabine_date  <- as.Date("2016-02-24")

      # Top panel: HH monthly price line
      p_price <- plotly::plot_ly() |>
        plotly::add_lines(
          data          = joined,
          x             = ~month_date,
          y             = ~price,
          name          = "HH Monthly Avg ($/MMBtu)",
          line          = list(color = "#000080", width = 2),
          hovertemplate = "%{x|%b %Y}: %{y:.3f} $/MMBtu<extra></extra>"
        ) |>
        plotly::layout(yaxis = list(title = "HH Price ($/MMBtu)"))

      # Bottom panel: LNG export volume bars
      p_lng <- plotly::plot_ly() |>
        plotly::add_bars(
          data          = joined,
          x             = ~month_date,
          y             = ~exports,
          name          = "LNG Exports (MMcf/month)",
          marker        = list(color = viridis_blue),
          hovertemplate = "%{x|%b %Y}: %{y:,.0f} MMcf<extra></extra>"
        ) |>
        plotly::layout(yaxis = list(title = "LNG Exports (MMcf/month)"))

      # Sabine Pass vertical line spans full paper height — visible on both panels
      plotly::subplot(p_price, p_lng, nrows = 2, shareX = TRUE,
                      heights = c(0.5, 0.5)) |>
        plotly::layout(
          xaxis     = list(title = "Month"),
          legend    = list(orientation = "h", y = -0.15),
          hovermode = "x unified",
          shapes    = list(list(
            type = "line",
            x0   = sabine_date, x1 = sabine_date, y0 = 0, y1 = 1,
            xref = "x", yref = "paper",
            line = list(color = "#F87217", dash = "dash", width = 2)
          )),
          annotations = list(list(
            x=sabine_date, y=0.95, xref="x", yref="paper",
            text="Sabine Pass First Export", showarrow=TRUE,
            arrowhead=2, ax=60, ay=-20,
            font=list(color="#F87217", size=11)
          ))
        ) |>
        apply_theme()
    })
  })
}
