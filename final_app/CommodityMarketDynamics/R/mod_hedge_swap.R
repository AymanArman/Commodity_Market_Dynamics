# Hedging Analytics Page — Row 1: CMA Swap Pricer
# Renders a forward curve chart with a horizontal flat swap price line and
# direction-dependent shading revealing the embedded carry structure.
# Supports CL, BRN, NG, HO, RB, HTT plus BRN-CL and HO×42-RB×42 spreads.
#
# Parameters:
#   id     - Shiny module ID
#   dflong - full RTL::dflong tibble (date, series, value)
#
# Example:
#   mod_hedge_swap_ui("hedge_swap")
#   mod_hedge_swap_server("hedge_swap", dflong = dflong)

# ── Constants ─────────────────────────────────────────────────────────────────

# Maps each display ticker to the expiry_table prefix and multiplier
SWAP_PREFIX_MAP <- list(
  CL  = list(prefix = "CL",  mult = 1),
  BRN = list(prefix = "LCO", mult = 1),
  NG  = list(prefix = "NG",  mult = 1),
  HO  = list(prefix = "HO",  mult = 42),
  RB  = list(prefix = "RB",  mult = 42),
  HTT = list(prefix = "CL",  mult = 1)   # CL expiry as proxy for HTT spread
)

# For dflong series filter: dflong uses "BRN" label, prefix for expiry is "LCO"
SWAP_DFLONG_PREFIX <- c(CL="CL", BRN="BRN", NG="NG", HO="HO", RB="RB", HTT="HTT")

# ── Helpers ───────────────────────────────────────────────────────────────────

# Returns available dates in dflong for a given outright ticker or spread.
# Spread instruments use the intersection of both legs' available dates.
#
# Parameters:
#   dflong - full dflong tibble
#   instrument - one of the 8 instrument choices
# Returns: sorted Date vector
#
# Example: swap_available_dates(RTL::dflong, "CL")
swap_available_dates <- function(dflong, instrument) {
  if (instrument == "BRN-CL") {
    d_brn <- dflong |> dplyr::filter(series == "BRN01") |> dplyr::pull(date) |> unique()
    d_cl  <- dflong |> dplyr::filter(series == "CL01")  |> dplyr::pull(date) |> unique()
    return(sort(intersect(d_brn, d_cl)))
  }
  if (instrument == "HO-RB") {
    d_ho <- dflong |> dplyr::filter(series == "HO01") |> dplyr::pull(date) |> unique()
    d_rb <- dflong |> dplyr::filter(series == "RB01") |> dplyr::pull(date) |> unique()
    return(sort(intersect(d_ho, d_rb)))
  }
  # Outright: use M01 series
  ticker <- instrument
  dflong |> dplyr::filter(series == paste0(ticker, "01")) |>
    dplyr::pull(date) |> unique() |> sort()
}

# Maps tenors M01, M02, ... on a reference date to delivery month/year using
# expiry_table. Returns a tibble with columns: tenor, Year, Month, delivery_date.
# Only returns rows covered by expiry_table.
#
# Parameters:
#   ref_date   - Date; the pricing reference date
#   tick_prefix - expiry_table tick.prefix (e.g., "CL", "LCO")
# Returns: tibble(tenor, Year, Month, delivery_date, last_trade)
#
# Example: swap_tenor_map(as.Date("2023-01-15"), "CL")
swap_tenor_map <- function(ref_date, tick_prefix) {
  RTL::expiry_table |>
    dplyr::filter(tick.prefix == tick_prefix, Last.Trade >= ref_date) |>
    dplyr::arrange(Last.Trade) |>
    dplyr::mutate(
      tenor_idx     = dplyr::row_number(),
      tenor         = sprintf("M%02d", tenor_idx),
      delivery_date = lubridate::make_date(Year, Month, 1L)
    ) |>
    dplyr::select(tenor, Year, Month, delivery_date, last_trade = Last.Trade)
}

# Generates valid delivery period choices from a tenor map and available prices.
# Bal[year] = all remaining months of the M01 delivery year.
# Cal[year+1..year+3] = full 12-month years fully covered by the forward curve.
#
# Parameters:
#   tenor_map       - tibble from swap_tenor_map()
#   available_tenors - character vector of tenors with prices on ref_date
# Returns: named list; each element is a character vector of tenor strings
#
# Example:
#   tm <- swap_tenor_map(as.Date("2023-10-01"), "CL")
#   swap_valid_periods(tm, c("M01","M02","M03","M04","M05"))
swap_valid_periods <- function(tenor_map, available_tenors) {
  if (nrow(tenor_map) == 0 || length(available_tenors) == 0) return(list())
  m1_year  <- tenor_map$Year[1]
  m1_month <- tenor_map$Month[1]

  periods <- list()

  # Bal[year]: remaining months of M01's delivery year (including M01 month)
  bal <- tenor_map |> dplyr::filter(Year == m1_year, Month >= m1_month)
  if (nrow(bal) > 0 && all(bal$tenor %in% available_tenors)) {
    periods[[paste0("Bal ", m1_year)]] <- bal$tenor
  }

  # Cal[year+1..year+3]
  for (y in (m1_year + 1):(m1_year + 3)) {
    cal <- tenor_map |> dplyr::filter(Year == y)
    if (nrow(cal) == 12 && all(cal$tenor %in% available_tenors)) {
      periods[[paste0("Cal ", y)]] <- cal$tenor
    }
  }

  periods
}

# Computes the flat CMA swap price as the arithmetic mean of forward prices for
# the selected period. For spread instruments, computes each leg separately and
# subtracts. For HO and RB, the ×42 conversion is applied before averaging.
#
# Parameters:
#   prices_wide - wide tibble: one row per tenor, columns tenor + one per leg
#   tenors      - character vector of tenors in the period
#   instrument  - instrument identifier string
# Returns: single numeric flat swap price
#
# Example:
#   prices_wide <- tibble(tenor=c("M01","M02"), CL=c(80,81))
#   compute_flat_swap_price(prices_wide, c("M01","M02"), "CL")
compute_flat_swap_price <- function(prices_wide, tenors, instrument) {
  sub <- prices_wide |> dplyr::filter(tenor %in% tenors)

  if (instrument == "BRN-CL") {
    brn_avg <- mean(sub$BRN, na.rm = TRUE)
    cl_avg  <- mean(sub$CL,  na.rm = TRUE)
    return(brn_avg - cl_avg)
  }
  if (instrument == "HO-RB") {
    ho_avg <- mean(sub$HO * 42, na.rm = TRUE)
    rb_avg <- mean(sub$RB * 42, na.rm = TRUE)
    return(ho_avg - rb_avg)
  }

  # Outright
  mult <- SWAP_PREFIX_MAP[[instrument]]$mult
  mean(sub[[instrument]] * mult, na.rm = TRUE)
}

# ── UI ────────────────────────────────────────────────────────────────────────

mod_hedge_swap_ui <- function(id) {
  ns <- shiny::NS(id)

  shiny::tagList(
    # Inputs row — side by side above the chart, no bottom divider
    shiny::fluidRow(
      style = "border-bottom:none; margin-bottom:4px; padding-bottom:0;",
      shiny::column(
        width = 3,
        shiny::selectInput(
          inputId  = ns("instrument"),
          label    = "Instrument",
          choices  = c("CL", "BRN", "NG", "HO", "RB", "HTT",
                       "BRN-CL" = "BRN-CL", "HO\u00d742\u2212RB\u00d742" = "HO-RB"),
          selected = "CL"
        )
      ),
      shiny::column(
        width = 3,
        shiny::dateInput(
          inputId = ns("ref_date"),
          label   = "Reference date",
          value   = Sys.Date() - 30
        )
      ),
      shiny::column(
        width = 3,
        shiny::selectInput(
          inputId  = ns("period"),
          label    = "Swap period",
          choices  = character(0)
        )
      ),
      shiny::column(
        width = 3,
        shinyWidgets::prettyRadioButtons(
          inputId  = ns("direction"),
          label    = "Direction",
          choices  = c("Producer", "Consumer"),
          selected = "Producer",
          status   = "primary",
          inline   = TRUE
        )
      )
    ),
    # Chart + narrative row
    shiny::fluidRow(
      # col_a: forward curve chart
      shiny::column(
        width = 6,
        plotly::plotlyOutput(ns("swap_chart"), height = "420px")
      ),
      # col_b: stat card + narrative only (inputs moved above)
      shiny::column(
        width = 6,
        bslib::card(
          bslib::card_body(
            shiny::uiOutput(ns("swap_stat"))
          )
        ),
        shiny::br(),
        bslib::card(
          bslib::card_body(
            shiny::p("A commodity swap fixes a flat price against the calendar month
              average (CMA) of daily settlement prices over the swap period —
              not the current front month price."),
            shiny::p("The shading reveals the embedded financing structure. Months
              where the forward sits above the swap line represent the bank
              subsidising that leg — effectively an implied loan built into the
              structure. The bank prices this cost of carry into the flat swap
              rate upfront."),
            shiny::p("In contango, fixing via swap costs more than rolling
              month-to-month — the carry premium is embedded in the flat price.
              In backwardation, fixing captures the discount — the swap is
              cheaper than rolling. The chart makes this trade-off concrete for
              any instrument and period.")
          )
        )
      )
    )
  )
}

# ── Server ────────────────────────────────────────────────────────────────────

mod_hedge_swap_server <- function(id, dflong) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # -- Available dates for selected instrument
    avail_dates <- shiny::reactive({
      swap_available_dates(dflong, input$instrument)
    })

    # -- Constrain reference date picker to instrument's available dates
    shiny::observe({
      dates <- avail_dates()
      if (length(dates) == 0) return()
      # Default to most recent available date
      shiny::updateDateInput(
        session  = session,
        inputId  = "ref_date",
        min      = min(dates),
        max      = max(dates),
        value    = max(dates)
      )
    }) |> shiny::bindEvent(input$instrument, ignoreInit = FALSE)

    # -- Expiry prefix for selected instrument
    expiry_prefix <- shiny::reactive({
      inst <- input$instrument
      if (inst %in% c("BRN-CL", "HO-RB")) "CL"  # use CL for period generation
      else SWAP_PREFIX_MAP[[inst]]$prefix
    })

    # -- Tenor delivery map on reference date
    tenor_map <- shiny::reactive({
      shiny::req(input$ref_date)
      swap_tenor_map(as.Date(input$ref_date), expiry_prefix())
    })

    # -- Forward prices on reference date for selected instrument
    fwd_prices_wide <- shiny::reactive({
      shiny::req(input$ref_date)
      ref <- as.Date(input$ref_date)
      inst <- input$instrument

      if (inst == "BRN-CL") {
        brn <- dflong |> dplyr::filter(startsWith(series, "BRN"), date == ref) |>
          dplyr::mutate(tenor = paste0("M", sub("^BRN", "", series))) |>
          dplyr::select(tenor, BRN = value)
        cl <- dflong |> dplyr::filter(startsWith(series, "CL"), date == ref) |>
          dplyr::mutate(tenor = paste0("M", sub("^CL", "", series))) |>
          dplyr::select(tenor, CL = value)
        dplyr::inner_join(brn, cl, by = "tenor")
      } else if (inst == "HO-RB") {
        ho <- dflong |> dplyr::filter(startsWith(series, "HO"), date == ref) |>
          dplyr::mutate(tenor = paste0("M", sub("^HO", "", series))) |>
          dplyr::select(tenor, HO = value)
        rb <- dflong |> dplyr::filter(startsWith(series, "RB"), date == ref) |>
          dplyr::mutate(tenor = paste0("M", sub("^RB", "", series))) |>
          dplyr::select(tenor, RB = value)
        dplyr::inner_join(ho, rb, by = "tenor")
      } else {
        dflong |>
          dplyr::filter(startsWith(series, inst), date == ref) |>
          dplyr::mutate(tenor = paste0("M", sub(paste0("^", inst), "", series))) |>
          dplyr::select(tenor, !!inst := value)
      }
    })

    # -- Valid periods
    valid_periods <- shiny::reactive({
      tm   <- tenor_map()
      pw   <- fwd_prices_wide()
      if (nrow(tm) == 0 || nrow(pw) == 0) return(list())
      swap_valid_periods(tm, pw$tenor)
    })

    # -- Update period selector when instrument or date changes
    shiny::observe({
      periods <- valid_periods()
      if (length(periods) == 0) {
        shiny::updateSelectInput(session, "period", choices = character(0))
        return()
      }
      # Preserve current selection if still valid
      cur <- isolate(input$period)
      sel <- if (!is.null(cur) && cur %in% names(periods)) cur else names(periods)[1]
      shiny::updateSelectInput(session, "period", choices = names(periods), selected = sel)
    })

    # -- Selected period tenors
    period_tenors <- shiny::reactive({
      shiny::req(input$period)
      periods <- valid_periods()
      if (length(periods) == 0 || !input$period %in% names(periods)) return(character(0))
      periods[[input$period]]
    })

    # -- Delivery month dates and labels for selected period tenors
    # Returns a list(dates = Date vector, labels = character vector)
    # Ordered by tenor so plotly x-axis is chronological
    delivery_info <- shiny::reactive({
      tenors <- period_tenors()
      tm     <- tenor_map()
      if (length(tenors) == 0 || nrow(tm) == 0) {
        return(list(dates = as.Date(character(0)), labels = character(0)))
      }
      sub <- tm |>
        dplyr::filter(tenor %in% tenors) |>
        dplyr::arrange(tenor)
      list(
        dates  = sub$delivery_date,
        labels = format(sub$delivery_date, "%b %Y")
      )
    })

    # -- Forward prices for selected period (adjusted by mult)
    period_fwd_prices <- shiny::reactive({
      tenors <- period_tenors()
      pw     <- fwd_prices_wide()
      inst   <- input$instrument
      if (length(tenors) == 0 || nrow(pw) == 0) return(numeric(0))

      sub <- pw |> dplyr::filter(tenor %in% tenors) |> dplyr::arrange(tenor)

      if (inst == "BRN-CL") return(sub$BRN - sub$CL)
      if (inst == "HO-RB")  return(sub$HO * 42 - sub$RB * 42)
      mult <- SWAP_PREFIX_MAP[[inst]]$mult
      sub[[inst]] * mult
    })

    # -- Flat swap price
    flat_swap <- shiny::reactive({
      prices <- period_fwd_prices()
      if (length(prices) == 0) return(NA_real_)
      mean(prices, na.rm = TRUE)
    })

    # -- Stat card
    output$swap_stat <- shiny::renderUI({
      fs <- flat_swap()
      inst <- input$instrument
      unit_lbl <- dplyr::case_when(
        inst %in% c("CL", "BRN", "HTT") ~ "$/bbl",
        inst == "NG"                      ~ "$/MMBtu",
        inst %in% c("HO", "RB")          ~ "$/gal",
        inst == "BRN-CL"                  ~ "$/bbl spread",
        inst == "HO-RB"                   ~ "$/gal spread",
        TRUE                              ~ ""
      )
      period_lbl <- if (!is.null(input$period) && nchar(input$period) > 0) input$period else ""
      shiny::tagList(
        shiny::h4(paste0("Flat Swap Price — ", period_lbl),
                  style = "margin-top:0; font-weight:bold;"),
        shiny::h2(
          if (is.na(fs)) "—" else paste0(formatC(fs, format = "f", digits = 3), " ", unit_lbl),
          style = "color:#F87217; margin:4px 0;"
        )
      )
    })

    # -- Chart
    output$swap_chart <- plotly::renderPlotly({
      prices  <- period_fwd_prices()
      fs      <- flat_swap()
      di      <- delivery_info()
      dates   <- di$dates    # Date objects — plotly orders these correctly
      lbls    <- di$labels   # "%b %Y" formatted for ticktext
      dir     <- input$direction
      inst    <- input$instrument

      shiny::req(length(prices) > 0, !is.na(fs), length(dates) > 0)

      # Colors: Producer: above = green, below = red; Consumer: reversed
      above_col <- if (dir == "Producer") "rgba(0,160,0,0.25)" else "rgba(200,0,0,0.25)"
      below_col <- if (dir == "Producer") "rgba(200,0,0,0.25)" else "rgba(0,160,0,0.25)"

      n     <- length(dates)
      above <- which(prices > fs)
      below <- which(prices <= fs)

      p <- plotly::plot_ly() |>
        # Forward curve line — Date x-axis ensures chronological order
        plotly::add_trace(
          x      = dates,
          y      = prices,
          type   = "scatter",
          mode   = "lines+markers",
          name   = "Forward curve",
          line   = list(color = "#210000", width = 2),
          marker = list(color = "#210000", size = 6),
          text   = paste0(lbls, "<br>", round(prices, 3)),
          hoverinfo = "text"
        ) |>
        # Flat swap horizontal line
        plotly::add_trace(
          x      = c(dates[1], dates[n]),
          y      = c(fs, fs),
          type   = "scatter",
          mode   = "lines",
          name   = "Flat swap",
          line   = list(color = "#F87217", width = 2, dash = "dash"),
          showlegend = TRUE
        )

      # Above-swap shading
      if (length(above) > 0) {
        p <- p |> plotly::add_ribbons(
          x          = dates[above],
          ymin       = rep(fs, length(above)),
          ymax       = prices[above],
          name       = if (dir == "Producer") "Carry gain" else "Carry cost",
          fillcolor  = above_col,
          line       = list(color = "transparent"),
          showlegend = TRUE
        )
      }

      # Below-swap shading
      if (length(below) > 0) {
        p <- p |> plotly::add_ribbons(
          x          = dates[below],
          ymin       = prices[below],
          ymax       = rep(fs, length(below)),
          name       = if (dir == "Producer") "Carry cost" else "Carry gain",
          fillcolor  = below_col,
          line       = list(color = "transparent"),
          showlegend = TRUE
        )
      }

      unit_lbl <- dplyr::case_when(
        inst %in% c("CL", "BRN", "HTT") ~ "$/bbl",
        inst == "NG"                      ~ "$/MMBtu",
        inst %in% c("HO", "RB")          ~ "$/gal",
        inst == "BRN-CL"                  ~ "$/bbl spread",
        inst == "HO-RB"                   ~ "$/gal spread",
        TRUE                              ~ ""
      )

      p |>
        plotly::layout(
          xaxis = list(
            title      = "Delivery month",
            tickformat = "%b %Y",
            tickangle  = -45,
            tickvals   = dates,
            ticktext   = lbls
          ),
          yaxis = list(title = unit_lbl),
          legend = list(orientation = "h", y = -0.25),
          hovermode = "x unified"
        ) |>
        apply_theme()
    })
  })
}
