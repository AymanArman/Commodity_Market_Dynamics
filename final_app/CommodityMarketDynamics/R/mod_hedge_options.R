# Hedging Analytics Page — Row 3: Options Pricer & Zero-Cost Collar
# Black-76 options pricer (RTL::GBSOption, b=0) with zero-cost collar.
# View 1: BS pricing curve + payoff diagram at expiry.
# View 2: Collar MTM over its life using FRED yield curve interpolation.
# Edit/Apply lock pattern: inputs locked on load; user unlocks to edit.
#
# Parameters:
#   id - Shiny module ID
#   r  - shiny::reactiveValues; reads r$yield_curves (date, series, rate)
#   dflong - full RTL::dflong tibble (date, series, value)
#
# Example:
#   mod_hedge_options_ui("hedge_options")
#   mod_hedge_options_server("hedge_options", r = r, dflong = dflong)

# ── Constants ─────────────────────────────────────────────────────────────────

# FRED series ordered by increasing maturity (years)
OPT_FRED_MATURITIES <- c(1/12, 3/12, 6/12, 1, 2, 5, 10, 30)
OPT_FRED_SERIES     <- c("DGS1MO", "DGS3MO", "DGS6MO",
                          "DGS1", "DGS2", "DGS5", "DGS10", "DGS30")

# Contract multipliers (units per contract)
OPT_MULTIPLIERS <- c(CL=1000, BRN=1000, HO=42000, RB=42000, NG=10000, HTT=1000)

# X-axis strike multiples per ticker group
OPT_STRIKE_MULT <- function(ticker) if (ticker == "NG") 3 else 2

# expiry_table prefix for BRN
OPT_EXPIRY_PREFIX <- c(CL="CL", BRN="LCO", NG="NG", HO="HO", RB="RB")

# ── Helpers ───────────────────────────────────────────────────────────────────

# Looks up FRED yield (as decimal, e.g., 0.05) for a given date and T_remaining.
# Forward-fills from r$yield_curves if missing. Returns NA if no data.
#
# Parameters:
#   yield_curves - long-format tibble (date, series, rate) from r$yield_curves
#   date_t       - Date to look up
#   t_remaining  - numeric years to expiry
# Returns: numeric risk-free rate in decimal form
#
# Example:
#   interp_yield(r$yield_curves, as.Date("2023-01-15"), 0.25)
interp_yield <- function(yield_curves, date_t, t_remaining) {
  day_rates <- yield_curves |>
    dplyr::filter(date <= date_t, series %in% OPT_FRED_SERIES) |>
    dplyr::group_by(series) |>
    dplyr::slice_max(date, n = 1, with_ties = FALSE) |>
    dplyr::ungroup()

  if (nrow(day_rates) == 0) return(0.05)  # fallback if no FRED data

  # Map series to maturity
  series_mat <- data.frame(
    series   = OPT_FRED_SERIES,
    maturity = OPT_FRED_MATURITIES,
    stringsAsFactors = FALSE
  )
  day_rates <- dplyr::left_join(day_rates, series_mat, by = "series") |>
    dplyr::arrange(maturity) |>
    dplyr::filter(!is.na(rate))

  if (nrow(day_rates) < 2) return(day_rates$rate[1] / 100)

  # Linear interpolation, clamped to boundary values
  approx(day_rates$maturity, day_rates$rate / 100,
         xout = t_remaining, rule = 2)$y
}

# Finds nearest futures expiry at >= T months after ref_date for a ticker.
# BRN maps to "LCO" prefix. Returns NA if no such expiry exists within dflong.
#
# Parameters:
#   ticker     - character ticker (CL, BRN, NG, HO, RB)
#   ref_date   - Date; pricing reference date
#   T_months   - numeric; time to maturity in months (1, 3, or 6)
#   last_dflong - Date; last available date in dflong for selected ticker
# Returns: Date or NA
#
# Example:
#   find_expiry(as.Date("2023-01-15"), "CL", 3, as.Date("2025-02-28"))
find_expiry <- function(ticker, ref_date, T_months, last_dflong) {
  prefix <- OPT_EXPIRY_PREFIX[[ticker]]
  target <- ref_date + lubridate::dmonths(T_months)
  exp_row <- RTL::expiry_table |>
    dplyr::filter(tick.prefix == prefix, Last.Trade >= target) |>
    dplyr::arrange(Last.Trade) |>
    dplyr::slice(1)
  if (nrow(exp_row) == 0) return(NA)
  expiry <- exp_row$Last.Trade[1]
  if (expiry > last_dflong) return(NA)
  expiry
}

# Computes last available date in dflong M01 for a ticker.
#
# Parameters:
#   dflong - full dflong tibble
#   ticker - character (CL, BRN, NG, HO, RB)
# Returns: Date
opt_last_dflong <- function(dflong, ticker) {
  dflong |> dplyr::filter(series == paste0(ticker, "01")) |>
    dplyr::pull(date) |> max()
}

# Computes the M1 price on a date for a ticker (prior available if gap).
#
# Parameters:
#   dflong - full dflong tibble
#   ticker - character ticker
#   date_t - Date
# Returns: numeric price or NA
opt_m1_price <- function(dflong, ticker, date_t) {
  sub <- dflong |>
    dplyr::filter(series == paste0(ticker, "01"), date <= date_t) |>
    dplyr::slice_max(date, n = 1, with_ties = FALSE)
  if (nrow(sub) == 0) return(NA_real_)
  sub$value[1]
}

# ── UI ────────────────────────────────────────────────────────────────────────

mod_hedge_options_ui <- function(id) {
  ns <- shiny::NS(id)

  shiny::tagList(
    shinyjs::useShinyjs(),
    shiny::fluidRow(
      style = "border-bottom:none; margin-bottom:4px; padding-bottom:0;",
      shiny::column(
        width = 12,
        shiny::h4(
          "Zero-Cost Collar Simulator",
          style = "text-align:center; font-family:'Times New Roman'; margin-bottom:4px;"
        ),
        shiny::p(
          "Generate zero-cost collars for producers and consumers at a given reference date.",
          " Switch to View 2 for MTM over option life.",
          style = "text-align:center; font-style:italic; margin-bottom:12px;"
        )
      )
    ),
    shiny::fluidRow(
      # col_a: inputs panel (width=3)
      shiny::column(
        width = 3,
        bslib::card(
          bslib::card_body(
            shiny::selectInput(
              ns("ticker"),
              label   = "Ticker",
              choices = c("CL", "BRN", "NG", "HO", "RB"),
              selected = "CL"
            ),
            shinyWidgets::prettyRadioButtons(
              ns("direction"),
              label    = "Direction",
              choices  = c("Producer", "Consumer"),
              selected = "Producer",
              status   = "primary",
              inline   = TRUE
            ),
            shiny::sliderInput(
              ns("sigma"),
              label = "Implied volatility",
              min   = 0.01, max = 1.00, step = 0.01, value = 0.30
            ),
            shinyWidgets::prettyRadioButtons(
              ns("ttm"),
              label    = "Time to maturity",
              choices  = c("1 month" = "1", "3 months" = "3", "6 months" = "6"),
              selected = "3",
              status   = "primary",
              inline   = FALSE
            ),
            shiny::dateInput(
              ns("ref_date"),
              label = "Reference date",
              value = as.Date("2019-12-01")
            ),
            shiny::uiOutput(ns("collar_strike_ui")),
            shiny::br(),
            shiny::actionButton(
              ns("edit_apply"),
              label = "Edit Inputs",
              class = "btn-warning btn-sm"
            ),
            shiny::br(),
            shiny::br(),
            bslib::tooltip(
              bslib::input_switch(ns("view2"), label = "View 2 — Collar MTM", value = FALSE),
              "Requires reference date + T months to fall within available price history"
            )
          )
        )
      ),
      # col_b: charts area (width=9)
      shiny::column(
        width = 9,
        # Banner shown in edit mode
        shinyjs::hidden(
          shiny::div(
            id    = ns("edit_banner"),
            style = paste0(
              "background:rgba(200,200,200,0.7); padding:12px; text-align:center;",
              "font-style:italic; margin-bottom:8px;"
            ),
            "Click Apply to update charts"
          )
        ),
        # View 1 (default)
        shiny::conditionalPanel(
          condition = paste0("!input['", ns("view2"), "']"),
          plotly::plotlyOutput(ns("bs_curve"),   height = "300px"),
          plotly::plotlyOutput(ns("payoff_plot"), height = "300px")
        ),
        # View 2
        shiny::conditionalPanel(
          condition = paste0("input['", ns("view2"), "']"),
          shinycssloaders::withSpinner(
            plotly::plotlyOutput(ns("mtm_plot"), height = "500px"),
            color = "#F87217"
          )
        ),
        # Narrative
        bslib::card(
          bslib::card_body(
            shiny::p(
              "A zero-cost collar pairs two options legs so that the premium on ",
              "the sold leg exactly offsets the cost of the bought leg — the ",
              "strike on the opposite leg is solved to achieve this."
            ),
            shiny::p(
              shiny::strong("Producer collar:"),
              " put purchased to floor downside; call sold to fund the put; upside capped."
            ),
            shiny::p(
              shiny::strong("Consumer collar:"),
              " call purchased to cap cost; put sold to fund the call; downside benefit surrendered."
            ),
            shiny::p(
              "View 2 shows the mark-to-market value of a single collar ",
              "over its life — worth zero at inception by construction; ",
              "evolves as the underlying moves and time decays."
            )
          )
        )
      )
    )
  )
}

# ── Server ────────────────────────────────────────────────────────────────────

mod_hedge_options_server <- function(id, r, dflong) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # -- Disable all inputs on load (view mode)
    # Run directly; shinyjs queues JS calls safely during server init
    shinyjs::disable("ticker")
    shinyjs::disable("direction")
    shinyjs::disable("sigma")
    shinyjs::disable("ttm")
    shinyjs::disable("ref_date")
    shinyjs::disable("collar_strike")

    # -- Edit / Apply toggle
    edit_mode <- shiny::reactiveVal(FALSE)

    shiny::observeEvent(input$edit_apply, {
      if (!edit_mode()) {
        # Switch to edit mode
        edit_mode(TRUE)
        shiny::updateActionButton(session, "edit_apply", label = "Apply")
        shinyjs::enable("ticker")
        shinyjs::enable("direction")
        shinyjs::enable("sigma")
        shinyjs::enable("ttm")
        shinyjs::enable("ref_date")
        shinyjs::enable("collar_strike")
        shinyjs::show("edit_banner")
        shinyjs::disable("view2")
      } else {
        # Apply: switch back to view mode
        edit_mode(FALSE)
        shiny::updateActionButton(session, "edit_apply", label = "Edit Inputs")
        shinyjs::disable("ticker")
        shinyjs::disable("direction")
        shinyjs::disable("sigma")
        shinyjs::disable("ttm")
        shinyjs::disable("ref_date")
        shinyjs::disable("collar_strike")
        shinyjs::hide("edit_banner")
        update_view2_state()
      }
    })

    # -- Last available dflong date for selected ticker
    last_dflong_date <- shiny::reactive({
      opt_last_dflong(dflong, input$ticker)
    })

    # -- Last available yield curve date; falls back to last dflong date
    last_yield_date <- shiny::reactive({
      if (is.null(r$yield_curves)) return(last_dflong_date())
      max(r$yield_curves$date)
    })

    # -- Update reference date picker constraints when ticker or TTM changes
    shiny::observe({
      shiny::req(input$ticker, input$ttm)
      ticker  <- input$ticker
      T_mo    <- as.numeric(input$ttm)
      prefix  <- OPT_EXPIRY_PREFIX[[ticker]]
      last_d  <- last_dflong_date()
      last_yc <- last_yield_date()
      cutoff  <- min(last_d, last_yc)

      # Find the latest valid reference date: nearest expiry ≥ T months out ≤ cutoff
      # Walk back from (cutoff - T months) to find a date with valid expiry
      max_ref <- as.Date(cutoff) - lubridate::dmonths(T_mo)

      first_d <- dflong |>
        dplyr::filter(series == paste0(ticker, "01")) |>
        dplyr::pull(date) |> min()

      cur_ref <- suppressWarnings(as.Date(isolate(input$ref_date)))
      new_val <- if (!is.na(cur_ref) && cur_ref <= max_ref) cur_ref else max_ref

      shiny::updateDateInput(
        session = session,
        inputId = "ref_date",
        min     = first_d,
        max     = max_ref,
        value   = new_val
      )
    }) |> shiny::bindEvent(input$ticker, input$ttm, ignoreInit = FALSE)

    # -- Underlying price on reference date
    s0 <- shiny::reactive({
      shiny::req(input$ref_date, input$ticker)
      opt_m1_price(dflong, input$ticker, as.Date(input$ref_date))
    })

    # -- Collar strike UI (label updates with direction)
    output$collar_strike_ui <- shiny::renderUI({
      dir   <- input$direction
      label <- if (dir == "Producer") "Floor Strike (Put to Buy)" else "Cap Strike (Call to Buy)"
      s     <- shiny::req(s0())
      default_k <- if (dir == "Producer") round(s * 0.95, 2) else round(s * 1.05, 2)
      shiny::numericInput(
        inputId = ns("collar_strike"),
        label   = label,
        value   = default_k,
        min     = 0.01,
        step    = 0.01
      )
    })

    # -- Strike grid (~100 points, 0.5× to 1.5× S0)
    # X-axis spans ±50% around the reference date price for both View 1 charts
    strike_grid <- shiny::reactive({
      s <- shiny::req(s0())
      seq(0.5 * s, 1.5 * s, length.out = 100)
    })

    # -- T in years
    T_years <- shiny::reactive({
      as.numeric(input$ttm) / 12
    })

    # -- Yield at reference date and T
    # Falls back to 5% flat when FRED data is unavailable (e.g. container env)
    r_rate <- shiny::reactive({
      shiny::req(input$ref_date)
      if (is.null(r$yield_curves)) return(0.05)
      interp_yield(r$yield_curves, as.Date(input$ref_date), T_years())
    })

    # -- Call and put premiums across strike grid
    option_premiums <- shiny::reactive({
      shiny::req(s0(), input$sigma, T_years(), r_rate())
      s     <- s0()
      sigma <- input$sigma
      T_val <- T_years()
      r_val <- r_rate()
      grid  <- strike_grid()

      calls <- vapply(grid, function(k) {
        RTL::GBSOption(S = s, X = k, T2M = T_val, r = r_val, b = 0,
                       sigma = sigma, type = "call")$price
      }, numeric(1))

      puts <- vapply(grid, function(k) {
        RTL::GBSOption(S = s, X = k, T2M = T_val, r = r_val, b = 0,
                       sigma = sigma, type = "put")$price
      }, numeric(1))

      list(grid = grid, calls = calls, puts = puts)
    })

    # -- User's collar leg premium and zero-cost opposite strike
    collar_info <- shiny::reactive({
      shiny::req(input$collar_strike, s0(), input$direction)
      dir   <- input$direction
      k_user <- input$collar_strike
      s      <- s0()
      sigma  <- input$sigma
      T_val  <- T_years()
      r_val  <- r_rate()
      grid   <- strike_grid()
      prems  <- option_premiums()

      # Producer: buys put; sells call to fund
      # Consumer: buys call; sells put to fund
      if (dir == "Producer") {
        user_type     <- "put"
        opposite_type <- "call"
        user_prem <- RTL::GBSOption(S = s, X = k_user, T2M = T_val, r = r_val,
                                    b = 0, sigma = sigma, type = "put")$price
        # Zero-cost call strike: find call strike where call premium = user put premium
        opp_prems <- prems$calls
        k_long    <- k_user
        k_short   <- grid[which.min(abs(opp_prems - user_prem))]
      } else {
        user_type     <- "call"
        opposite_type <- "put"
        user_prem <- RTL::GBSOption(S = s, X = k_user, T2M = T_val, r = r_val,
                                    b = 0, sigma = sigma, type = "call")$price
        opp_prems <- prems$puts
        k_long  <- k_user
        k_short <- grid[which.min(abs(opp_prems - user_prem))]
      }

      list(
        k_long     = k_long,
        k_short    = k_short,
        user_prem  = user_prem,
        user_type  = user_type,
        direction  = dir
      )
    })

    # -- View 2 feasibility and toggle state
    update_view2_state <- function() {
      shiny::req(input$ref_date, input$ticker, input$ttm)
      T_mo   <- as.numeric(input$ttm)
      ticker <- input$ticker
      last_d <- last_dflong_date()
      last_yc <- last_yield_date()
      cutoff  <- min(last_d, last_yc)
      expiry  <- find_expiry(ticker, as.Date(input$ref_date), T_mo, cutoff)
      feasible <- !is.na(expiry)
      if (feasible) shinyjs::enable("view2")
      else          shinyjs::disable("view2")
    }

    shiny::observe({
      if (!edit_mode()) update_view2_state()
    })

    # ── View 1: BS Pricing Curve ───────────────────────────────────────────────

    output$bs_curve <- plotly::renderPlotly({
      shiny::req(!edit_mode() || TRUE)  # render even in edit mode (greyed by banner)
      prems  <- option_premiums()
      ci     <- collar_info()
      grid   <- prems$grid

      p <- plotly::plot_ly() |>
        plotly::add_trace(
          x = grid, y = prems$puts,
          type = "scatter", mode = "lines",
          name = "Put", line = list(color = "#4169E1", width = 2)
        ) |>
        plotly::add_trace(
          x = grid, y = prems$calls,
          type = "scatter", mode = "lines",
          name = "Call", line = list(color = "#db243a", width = 2)
        ) |>
        # Horizontal dashed line at user leg premium
        plotly::add_trace(
          x    = c(grid[1], grid[length(grid)]),
          y    = c(ci$user_prem, ci$user_prem),
          type = "scatter", mode = "lines",
          name = "Your leg premium",
          line = list(color = "#F87217", width = 1.5, dash = "dash")
        ) |>
        # Vertical lines at collar strikes
        plotly::layout(
          shapes = list(
            list(type = "line", x0 = ci$k_long, x1 = ci$k_long,
                 y0 = 0, y1 = 1, yref = "paper",
                 line = list(color = "#F87217", width = 1.5, dash = "dot")),
            list(type = "line", x0 = ci$k_short, x1 = ci$k_short,
                 y0 = 0, y1 = 1, yref = "paper",
                 line = list(color = "#F87217", width = 1.5, dash = "dot"))
          ),
          xaxis = list(
            title = paste0("Strike (", ROLL_UNITS[input$ticker], ")"),
            range = c(grid[1], grid[length(grid)])
          ),
          yaxis = list(title = "Option premium"),
          legend = list(orientation = "h", y = -0.25)
        ) |>
        apply_theme()

      p
    })

    # ── View 1: Payoff Diagram at Expiry ──────────────────────────────────────

    output$payoff_plot <- plotly::renderPlotly({
      s0_val <- shiny::req(s0())
      ci     <- collar_info()
      grid   <- strike_grid()
      dir    <- input$direction

      k_floor <- min(ci$k_long, ci$k_short)
      k_cap   <- max(ci$k_long, ci$k_short)

      # Unhedged P&L at expiry
      unhedged <- if (dir == "Producer") grid - s0_val else s0_val - grid

      # Collar payoff
      capped <- pmax(k_floor, pmin(k_cap, grid))
      collar <- if (dir == "Producer") capped - s0_val else s0_val - capped

      # Fixed Y-axis range
      y_min <- min(collar) - 0.1 * s0_val
      y_max <- max(collar) + 0.1 * s0_val

      plotly::plot_ly() |>
        plotly::add_trace(
          x = grid, y = unhedged,
          type = "scatter", mode = "lines",
          name = "Unhedged", line = list(color = "#343d46", width = 2)
        ) |>
        plotly::add_trace(
          x = grid, y = collar,
          type = "scatter", mode = "lines",
          name = "Collar payoff", line = list(color = "#F87217", width = 2.5)
        ) |>
        plotly::layout(
          xaxis = list(
            title = paste0("Underlying at expiry (", ROLL_UNITS[input$ticker], ")"),
            range = c(grid[1], grid[length(grid)])
          ),
          yaxis = list(
            title = paste0("Net P&L (", ROLL_UNITS[input$ticker], ")"),
            range = c(y_min, y_max)
          ),
          legend = list(orientation = "h", y = -0.25)
        ) |>
        apply_theme()
    })

    # ── View 2: Collar MTM over life ──────────────────────────────────────────

    output$mtm_plot <- plotly::renderPlotly({
      shiny::req(input$view2, !edit_mode())
      shiny::req(input$ref_date, input$ticker, input$ttm)

      ticker  <- input$ticker
      T_mo    <- as.numeric(input$ttm)
      ref     <- as.Date(input$ref_date)
      sigma   <- input$sigma
      ci      <- collar_info()
      mult    <- OPT_MULTIPLIERS[[ticker]]
      last_d  <- last_dflong_date()
      last_yc <- last_yield_date()
      cutoff  <- min(last_d, last_yc)

      expiry  <- find_expiry(ticker, ref, T_mo, cutoff)
      shiny::req(!is.na(expiry))

      # All M01 trading days from ref to expiry
      trading_dates <- dflong |>
        dplyr::filter(series == paste0(ticker, "01"),
                      date >= ref, date <= expiry) |>
        dplyr::pull(date) |> unique() |> sort()

      yc <- r$yield_curves  # may be NULL; interp_yield fallback handles it

      collar_pnl <- vapply(trading_dates, function(dt) {
        s_t       <- opt_m1_price(dflong, ticker, dt)
        if (is.na(s_t)) return(NA_real_)
        days_rem  <- as.numeric(expiry - dt)
        T_rem     <- if (days_rem <= 0) 0 else days_rem / 365
        r_t       <- if (is.null(yc)) 0.05 else interp_yield(yc, dt, max(T_rem, 1e-6))

        if (T_rem <= 0) {
          # At expiry: intrinsic value
          long_val  <- if (ci$user_type == "put") max(ci$k_long - s_t, 0)
                       else max(s_t - ci$k_long, 0)
          short_val <- if (ci$user_type == "put") max(s_t - ci$k_short, 0)
                       else max(ci$k_short - s_t, 0)
        } else {
          long_type  <- ci$user_type
          short_type <- if (ci$user_type == "put") "call" else "put"
          long_val   <- RTL::GBSOption(S = s_t, X = ci$k_long,  T2M = T_rem,
                                       r = r_t, b = 0, sigma = sigma,
                                       type = long_type)$price
          short_val  <- RTL::GBSOption(S = s_t, X = ci$k_short, T2M = T_rem,
                                       r = r_t, b = 0, sigma = sigma,
                                       type = short_type)$price
        }
        long_val - short_val
      }, numeric(1))

      # Reference date P&L = 0 by construction (zero-cost collar)
      collar_pnl[1] <- 0

      # M1 price path
      prices <- vapply(trading_dates, function(dt) {
        opt_m1_price(dflong, ticker, dt)
      }, numeric(1))

      unit_lbl <- ROLL_UNITS[[ticker]]

      # ── Dual-axis alignment: P&L zero aligned with floor strike ───────────────
      # Left axis range (price)
      p_min  <- min(prices, na.rm = TRUE)
      p_max  <- max(prices, na.rm = TRUE)
      p_pad  <- 0.05 * max(p_max - p_min, 1)
      left_lo <- p_min - p_pad
      left_hi <- p_max + p_pad

      # Reference date price fraction along left axis — aligns P&L = 0 with S0
      k_floor <- prices[1]
      k_cl    <- max(left_lo, min(left_hi, k_floor))
      f       <- (k_cl - left_lo) / (left_hi - left_lo)
      f       <- max(0.05, min(0.95, f))

      # Right axis range scaled so 0 sits at fraction f from the bottom
      pnl_valid <- collar_pnl[!is.na(collar_pnl)]
      pnl_lo <- if (length(pnl_valid) > 0) min(pnl_valid) else -1
      pnl_hi <- if (length(pnl_valid) > 0) max(pnl_valid) else  1
      pnl_pad <- 0.1 * max(abs(c(pnl_lo, pnl_hi)))
      pnl_lo  <- pnl_lo - pnl_pad
      pnl_hi  <- pnl_hi + pnl_pad

      pnl_span <- max(
        if (f   > 0) abs(pnl_lo) / f       else 0,
        if (1-f > 0) abs(pnl_hi) / (1 - f) else 0
      )
      right_lo <- -f       * pnl_span
      right_hi <- (1 - f) * pnl_span

      # Put and call strike levels for reference lines (on left/price axis)
      put_strike  <- if (ci$user_type == "put") ci$k_long  else ci$k_short
      call_strike <- if (ci$user_type == "put") ci$k_short else ci$k_long
      put_lbl     <- paste0("Put ", round(put_strike,  2))
      call_lbl    <- paste0("Call ", round(call_strike, 2))

      strike_shapes <- list(
        list(type = "line", xref = "paper", yref = "y",
             x0 = 0, x1 = 1, y0 = put_strike,  y1 = put_strike,
             line = list(color = "#000000", width = 1.5, dash = "dot")),
        list(type = "line", xref = "paper", yref = "y",
             x0 = 0, x1 = 1, y0 = call_strike, y1 = call_strike,
             line = list(color = "#000000", width = 1.5, dash = "dot"))
      )

      strike_annotations <- list(
        list(xref = "paper", yref = "y", x = 0.01, y = put_strike,
             text = put_lbl, showarrow = FALSE, xanchor = "left",
             font = list(color = "#000000", size = 11),
             bgcolor = "rgba(255,255,242,0.7)", borderpad = 2),
        list(xref = "paper", yref = "y", x = 0.01, y = call_strike,
             text = call_lbl, showarrow = FALSE, xanchor = "left",
             font = list(color = "#000000", size = 11),
             bgcolor = "rgba(255,255,242,0.7)", borderpad = 2)
      )

      plotly::plot_ly() |>
        # Left axis: underlying price
        plotly::add_trace(
          x = trading_dates, y = prices,
          type = "scatter", mode = "lines",
          name = paste0(ticker, " M1 (", unit_lbl, ")"),
          line = list(color = "#210000", width = 2),
          yaxis = "y"
        ) |>
        # Right axis: collar P&L
        plotly::add_trace(
          x = trading_dates, y = collar_pnl,
          type = "scatter", mode = "lines",
          name = paste0("Collar P&L (", unit_lbl, ")"),
          line = list(color = "#db243a", width = 2),
          yaxis = "y2"
        ) |>
        plotly::layout(
          xaxis  = list(title = "Date"),
          yaxis  = list(
            title = paste0(ticker, " price (", unit_lbl, ")"),
            range = c(left_lo, left_hi)
          ),
          yaxis2 = list(
            title         = paste0("Collar P&L (", unit_lbl, ")"),
            overlaying    = "y",
            side          = "right",
            range         = c(right_lo, right_hi),
            zeroline      = TRUE,
            zerolinecolor = "rgba(200,0,0,0.3)"
          ),
          shapes      = strike_shapes,
          annotations = strike_annotations,
          margin      = list(r = 80),
          legend      = list(orientation = "h", y = -0.15),
          hovermode   = "x unified"
        ) |>
        apply_theme()
    })
  })
}
