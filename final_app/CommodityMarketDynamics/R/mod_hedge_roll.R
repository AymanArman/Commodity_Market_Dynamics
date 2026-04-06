# Hedging Analytics Page — Row 2: Rolling Hedge Simulator
# Renders a cascading reactable table showing 12 consecutive front-month
# futures rolls from a reference date. Each roll: entry → expiry → next entry.
# P&L colored green/red per selected direction (Producer/Consumer).
#
# Parameters:
#   id     - Shiny module ID
#   dflong - full RTL::dflong tibble (date, series, value)
#
# Example:
#   mod_hedge_roll_ui("hedge_roll")
#   mod_hedge_roll_server("hedge_roll", dflong = dflong)

# Unit labels per ticker
ROLL_UNITS <- c(
  CL  = "$/bbl",
  BRN = "$/bbl",
  HTT = "$/bbl",
  NG  = "$/MMBtu",
  HO  = "$/gal",
  RB  = "$/gal"
)

# expiry_table tick.prefix per ticker (HTT uses CL as proxy)
ROLL_PREFIX <- c(CL="CL", BRN="LCO", NG="NG", HO="HO", RB="RB", HTT="CL")

# ── Helpers ───────────────────────────────────────────────────────────────────

# Looks up the M1 price for a given ticker on a given date.
# If no price on exact date, steps back to the nearest prior available date.
#
# Parameters:
#   dflong - full dflong tibble
#   ticker - character ticker (e.g. "CL")
#   date   - Date to look up
# Returns: numeric price or NA if no prior date found
#
# Example: roll_m1_price(RTL::dflong, "CL", as.Date("2023-12-25"))
roll_m1_price <- function(dflong, ticker, date) {
  series_name <- paste0(ticker, "01")
  sub <- dflong |>
    dplyr::filter(series == series_name, date <= !!date) |>
    dplyr::arrange(dplyr::desc(date)) |>
    dplyr::slice(1)
  if (nrow(sub) == 0) return(NA_real_)
  sub$value[1]
}

# Builds up to max_rolls roll records starting from ref_date.
# Stops early if fewer than max_rolls expirations exist within dflong history.
#
# Parameters:
#   dflong    - full dflong tibble
#   ticker    - display ticker (CL, BRN, NG, HO, RB, HTT)
#   ref_date  - Date; start of the first roll
#   direction - "Producer" or "Consumer"
#   max_rolls - integer maximum (default 12)
# Returns: list with elements:
#   data - tibble with columns per roll_roll_build() schema
#   n_rolls - integer number of rolls completed
#
# Example:
#   res <- build_roll_table(RTL::dflong, "CL", as.Date("2022-01-01"), "Producer")
build_roll_table <- function(dflong, ticker, ref_date, direction, max_rolls = 12L) {
  prefix     <- ROLL_PREFIX[[ticker]]
  last_date  <- dflong |>
    dplyr::filter(series == paste0(ticker, "01")) |>
    dplyr::pull(date) |> max()

  # All expiry dates for this prefix from ref_date onward
  expiries <- RTL::expiry_table |>
    dplyr::filter(tick.prefix == prefix, Last.Trade >= ref_date) |>
    dplyr::arrange(Last.Trade) |>
    dplyr::pull(Last.Trade)

  # Filter expiries that fall within dflong history (need price on that date)
  expiries <- expiries[expiries <= last_date]
  n_rolls  <- min(max_rolls, length(expiries))

  if (n_rolls == 0) {
    return(list(data = NULL, n_rolls = 0L))
  }

  rolls <- vector("list", n_rolls)
  entry_price <- roll_m1_price(dflong, ticker, ref_date)
  entry_date  <- ref_date

  for (i in seq_len(n_rolls)) {
    exit_date  <- expiries[i]
    exit_price <- roll_m1_price(dflong, ticker, exit_date)

    # Roll yield: (Entry - Exit) / Entry × 100 (positive in backwardation)
    roll_yield <- if (!is.na(entry_price) && entry_price != 0) {
      (entry_price - exit_price) / entry_price * 100
    } else NA_real_

    # Monthly P&L
    monthly_pnl <- if (direction == "Producer") {
      entry_price - exit_price   # short hedge: gain when price falls
    } else {
      exit_price - entry_price   # long hedge: gain when price rises
    }

    # Contract label from expiry_table month/year
    exp_row <- RTL::expiry_table |>
      dplyr::filter(tick.prefix == prefix, Last.Trade == exit_date)
    contract_label <- if (nrow(exp_row) > 0) {
      paste0(ticker, " ",
             format(lubridate::make_date(exp_row$Year[1], exp_row$Month[1], 1L), "%b %Y"))
    } else paste0("Roll ", i)

    rolls[[i]] <- list(
      roll          = i,
      contract      = contract_label,
      entry_date    = entry_date,
      entry_price   = entry_price,
      exit_date     = exit_date,
      exit_price    = exit_price,
      roll_yield    = roll_yield,
      monthly_pnl   = monthly_pnl
    )

    # Next roll: exit of this = entry of next
    entry_date  <- exit_date
    entry_price <- exit_price
  }

  df <- dplyr::bind_rows(rolls) |>
    dplyr::mutate(cumulative_pnl = cumsum(monthly_pnl))

  list(data = df, n_rolls = n_rolls)
}

# Transposes the roll data tibble into the wide reactable format.
# Rows = labels; columns = Roll 1, Roll 2, ..., Roll N.
#
# Parameters:
#   roll_data - tibble from build_roll_table()$data
#   unit_lbl  - unit label for price rows (e.g. "$/bbl")
# Returns: data.frame with first col "Row" and one col per roll
#
# Example:
#   res <- build_roll_table(RTL::dflong, "CL", as.Date("2022-01-01"), "Producer")
#   roll_transpose(res$data, "$/bbl")
roll_transpose <- function(roll_data, unit_lbl) {
  n <- nrow(roll_data)
  col_names <- paste0("Roll_", seq_len(n))

  fmt_num <- function(x) formatC(x, format = "f", digits = 3)
  fmt_pct <- function(x) paste0(formatC(x, format = "f", digits = 2), "%")

  rows <- list(
    Contract      = as.character(roll_data$contract),
    `Entry Date`  = format(roll_data$entry_date, "%Y-%m-%d"),
    `Entry Price` = fmt_num(roll_data$entry_price),
    `Exit Date`   = format(roll_data$exit_date,  "%Y-%m-%d"),
    `Exit Price`  = fmt_num(roll_data$exit_price),
    `Roll Yield`  = fmt_pct(roll_data$roll_yield),
    `Monthly P&L` = fmt_num(roll_data$monthly_pnl),
    `Cumulative P&L` = fmt_num(roll_data$cumulative_pnl)
  )

  row_labels <- names(rows)
  mat <- do.call(rbind, lapply(rows, function(r) as.character(r)))
  df <- as.data.frame(mat, stringsAsFactors = FALSE)
  colnames(df) <- col_names
  rownames(df) <- NULL
  df <- cbind(data.frame(Row = row_labels, stringsAsFactors = FALSE), df)
  # Add row type for coloring
  attr(df, "pnl_rows") <- which(row_labels %in% c("Monthly P&L", "Cumulative P&L"))
  # Store raw numeric P&L for coloring
  attr(df, "monthly_pnl_raw")   <- roll_data$monthly_pnl
  attr(df, "cumulative_pnl_raw") <- roll_data$cumulative_pnl
  df
}

# ── UI ────────────────────────────────────────────────────────────────────────

mod_hedge_roll_ui <- function(id) {
  ns <- shiny::NS(id)

  shiny::fluidRow(
    # col_a: narrative
    shiny::column(
      width = 6,
      bslib::card(
        bslib::card_body(
          shiny::h5("Producer — Short Hedge via Rolling Front Month"),
          shiny::p("A producer hedges by selling the front-month futures contract and
            rolling it forward at expiry. In backwardation (M1 > M2), each roll
            earns positive roll yield — the effective hedge price improves relative
            to locking in a flat swap. In contango, each roll costs — the producer
            pays to extend the hedge. Use this strategy when the term structure is
            in backwardation and you expect it to persist."),
          shiny::br(),
          shiny::h5("Consumer — Long Hedge via Rolling Front Month"),
          shiny::p("A consumer hedges by buying the front-month contract and rolling
            forward. In backwardation, the consumer buys each successive month at a
            lower price — roll yield is positive. In contango, extending the long
            position costs carry. When the curve is in steep contango, fixing via
            a swap is typically cheaper than rolling month-to-month.")
        )
      )
    ),
    # col_b: inputs (side by side) above reactable table
    shiny::column(
      width = 6,
      # Inputs row — ticker, ref_date, direction side by side
      shiny::fluidRow(
        shiny::column(
          width = 4,
          shiny::selectInput(
            inputId  = ns("ticker"),
            label    = "Ticker",
            choices  = c("CL", "BRN", "NG", "HO", "RB", "HTT"),
            selected = "CL"
          )
        ),
        shiny::column(
          width = 4,
          shiny::dateInput(
            inputId = ns("ref_date"),
            label   = "Reference date",
            value   = as.Date("2022-01-01")
          )
        ),
        shiny::column(
          width = 4,
          shinyWidgets::prettyRadioButtons(
            inputId  = ns("direction"),
            label    = "Direction",
            choices  = c("Producer", "Consumer"),
            selected = "Producer",
            status   = "primary",
            inline   = FALSE
          )
        )
      ),
      shiny::uiOutput(ns("roll_count_label")),
      reactable::reactableOutput(ns("roll_table"))
    )
  )
}

# ── Server ────────────────────────────────────────────────────────────────────

mod_hedge_roll_server <- function(id, dflong) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # -- Constrain reference date: must be ≥ 1 year before last available date
    shiny::observe({
      ticker <- input$ticker
      last_d <- dflong |>
        dplyr::filter(series == paste0(ticker, "01")) |>
        dplyr::pull(date) |> max()
      first_d <- dflong |>
        dplyr::filter(series == paste0(ticker, "01")) |>
        dplyr::pull(date) |> min()
      max_allowed <- last_d - 365L
      shiny::updateDateInput(
        session = session,
        inputId = "ref_date",
        min     = first_d,
        max     = max_allowed,
        value   = pmin(isolate(as.Date(input$ref_date)), max_allowed)
      )
    }) |> shiny::bindEvent(input$ticker, ignoreInit = FALSE)

    # -- Build roll table data
    roll_result <- shiny::reactive({
      shiny::req(input$ref_date, input$ticker, input$direction)
      ref <- as.Date(input$ref_date)
      build_roll_table(dflong, input$ticker, ref, input$direction)
    })

    # -- Roll count label
    output$roll_count_label <- shiny::renderUI({
      res <- roll_result()
      unit <- ROLL_UNITS[[input$ticker]]
      n    <- res$n_rolls
      shiny::p(
        style = "font-style: italic; margin-bottom: 6px;",
        paste0(n, " roll", if (n != 1) "s" else "", " available — prices in ", unit)
      )
    })

    # -- Reactable table
    output$roll_table <- reactable::renderReactable({
      res <- roll_result()
      shiny::req(!is.null(res$data), res$n_rolls > 0)

      df          <- roll_transpose(res$data, ROLL_UNITS[[input$ticker]])
      pnl_rows    <- attr(df, "pnl_rows")
      m_pnl_raw   <- attr(df, "monthly_pnl_raw")
      c_pnl_raw   <- attr(df, "cumulative_pnl_raw")
      n           <- res$n_rolls
      col_names   <- paste0("Roll_", seq_len(n))

      # Build colDef list with conditional P&L coloring
      make_col <- function(roll_idx) {
        reactable::colDef(
          name  = paste0("Roll ", roll_idx),
          align = "right",
          style = function(value, index) {
            # index = row number (1-based)
            if (index == pnl_rows[1]) {  # Monthly P&L row
              raw_val <- m_pnl_raw[roll_idx]
              if (!is.na(raw_val)) {
                if (raw_val > 0) return(list(background = "rgba(0,160,0,0.30)"))
                if (raw_val < 0) return(list(background = "rgba(200,0,0,0.30)"))
              }
            }
            if (index == pnl_rows[2]) {  # Cumulative P&L row
              raw_val <- c_pnl_raw[roll_idx]
              if (!is.na(raw_val)) {
                if (raw_val > 0) return(list(background = "rgba(0,160,0,0.30)"))
                if (raw_val < 0) return(list(background = "rgba(200,0,0,0.30)"))
              }
            }
            list()
          }
        )
      }

      col_defs <- c(
        list(Row = reactable::colDef(name = "", minWidth = 120, align = "left")),
        stats::setNames(lapply(seq_len(n), make_col), col_names)
      )

      reactable::reactable(
        data             = df,
        columns          = col_defs,
        striped          = FALSE,
        highlight        = TRUE,
        bordered         = TRUE,
        compact          = TRUE,
        defaultPageSize  = 8,
        theme            = reactable::reactableTheme(
          backgroundColor = "#fffff2",
          borderColor     = "rgba(33,0,0,0.15)",
          headerStyle     = list(
            background = "#48495e",
            color      = "#f9f9f9",
            fontFamily = "Times New Roman"
          ),
          cellStyle = list(fontFamily = "Times New Roman", fontSize = "12px", color = "#333333")
        )
      )
    })
  })
}
