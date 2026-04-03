# Market Dynamics page module
# Group button navigation: Crude | Refined Products | Natural Gas
# Each group shows one representative chart plus stub cards for secondary panels
# Group switch between Crude/Refined requires modal confirmation; NG switches directly
# Parameters:
#   id     - module namespace id
#   dflong - full RTL::dflong tibble (passed from app_server)
#   r      - shared reactiveValues
# Example: mod_market_dynamics_ui("market_dynamics") / mod_market_dynamics_server("market_dynamics", dflong, r)

mod_market_dynamics_ui <- function(id) {
  ns <- shiny::NS(id)
  bslib::page_fluid(
    # Group selection buttons
    shiny::tags$div(
      style = "margin-bottom: 16px;",
      shiny::actionButton(ns("btn_crude"),   "Crude",            class = "btn btn-outline-primary me-2"),
      shiny::actionButton(ns("btn_refined"), "Refined Products", class = "btn btn-outline-primary me-2"),
      shiny::actionButton(ns("btn_ng"),      "Natural Gas",      class = "btn btn-outline-primary")
    ),
    # Dynamic panel area — driven by active group
    shiny::uiOutput(ns("group_panels"))
  )
}

mod_market_dynamics_server <- function(id, dflong, r) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Active group: NULL | "Crude" | "Refined" | "NG"
    active_group  <- shiny::reactiveVal(NULL)
    pending_group <- shiny::reactiveVal(NULL)

    # --- Group button handlers ---

    shiny::observeEvent(input$btn_crude, {
      if (identical(active_group(), "Crude")) return()
      pending_group("Crude")
      shiny::showModal(shiny::modalDialog(
        title     = "Switch to Crude?",
        "This will replace your current selection.",
        footer    = shiny::tagList(
          shiny::modalButton("Cancel"),
          shiny::actionButton(ns("modal_confirm"), "Confirm", class = "btn btn-primary")
        ),
        easyClose = TRUE
      ))
    })

    shiny::observeEvent(input$btn_refined, {
      if (identical(active_group(), "Refined")) return()
      pending_group("Refined")
      shiny::showModal(shiny::modalDialog(
        title     = "Switch to Refined Products?",
        "This will replace your current selection.",
        footer    = shiny::tagList(
          shiny::modalButton("Cancel"),
          shiny::actionButton(ns("modal_confirm"), "Confirm", class = "btn btn-primary")
        ),
        easyClose = TRUE
      ))
    })

    # NG switches directly — no modal, no group swap
    shiny::observeEvent(input$btn_ng, {
      if (identical(active_group(), "NG")) return()
      active_group("NG")
    })

    # Modal confirm — apply pending group and dismiss
    shiny::observeEvent(input$modal_confirm, {
      active_group(pending_group())
      shiny::removeModal()
    })

    # --- Panel area routing ---

    output$group_panels <- shiny::renderUI({
      grp <- active_group()
      if (is.null(grp)) {
        return(shiny::tags$p(
          "Select a market group above to begin.",
          style = "color: #888; margin-top: 16px;"
        ))
      }
      if (grp == "Crude")   return(md_crude_ui(ns))
      if (grp == "Refined") return(md_refined_ui(ns))
      if (grp == "NG")      return(md_ng_ui(ns))
    })

    # --- Crude: CL calendar spread (M1 - M2) ---
    # CL01 and CL02 are both in USD/bbl — no unit conversion required
    output$plot_crude_cal_spread <- plotly::renderPlotly({
      cl_wide <- pivot_ticker_wide(get_ticker(dflong, "CL"))
      spread  <- dplyr::transmute(cl_wide, date, spread = CL01 - CL02)
      spread  <- dplyr::filter(spread, !is.na(spread))

      plotly::plot_ly(
        spread,
        x             = ~date,
        y             = ~spread,
        type          = "scatter",
        mode          = "lines",
        line          = list(color = "#2196F3", width = 1.2),
        hovertemplate = "Date: %{x}<br>Spread: %{y:.3f}<extra></extra>"
      ) |>
        plotly::layout(
          xaxis  = list(title = "Date"),
          yaxis  = list(title = "CL M1\u2013M2 Spread (USD/bbl)"),
          shapes = list(list(
            type  = "line",
            xref  = "paper", x0 = 0, x1 = 1,
            yref  = "y",     y0 = 0, y1 = 0,
            line  = list(color = "black", width = 0.8, dash = "dot")
          ))
        )
    })

    # --- Refined Products: HO crack spread ---
    # HO trades in USD/gallon; CL in USD/bbl.
    # Multiply HO by 42 (gallons per barrel) to convert to USD/bbl before differencing.
    # Result is the heating oil crack spread in USD/bbl.
    output$plot_crack_spread <- plotly::renderPlotly({
      ho     <- get_front_month(dflong, "HO") |> dplyr::select(date, ho = value)
      cl     <- get_front_month(dflong, "CL") |> dplyr::select(date, cl = value)
      spread <- dplyr::inner_join(ho, cl, by = "date") |>
        dplyr::mutate(crack = ho * 42 - cl) |>
        dplyr::filter(!is.na(crack))

      plotly::plot_ly(
        spread,
        x             = ~date,
        y             = ~crack,
        type          = "scatter",
        mode          = "lines",
        line          = list(color = "#FF5722", width = 1.2),
        hovertemplate = "Date: %{x}<br>Crack Spread: %{y:.2f}<extra></extra>"
      ) |>
        plotly::layout(
          xaxis  = list(title = "Date"),
          yaxis  = list(title = "HO Crack Spread (USD/bbl)"),
          shapes = list(list(
            type  = "line",
            xref  = "paper", x0 = 0, x1 = 1,
            yref  = "y",     y0 = 0, y1 = 0,
            line  = list(color = "black", width = 0.8, dash = "dot")
          ))
        )
    })

    # --- Natural Gas: monthly return seasonality ---
    # Log returns on NG front month (M01), averaged by calendar month across all years.
    # Green bars = positive average return; red bars = negative average return.
    output$plot_ng_seasonality <- plotly::renderPlotly({
      ng_front <- get_front_month(dflong, "NG") |> dplyr::arrange(date)

      # Compute daily log returns then tag each observation with calendar month
      ng_ret <- ng_front |>
        dplyr::mutate(ret = log(value / dplyr::lag(value))) |>
        dplyr::filter(!is.na(ret)) |>
        dplyr::mutate(
          month_num   = as.integer(format(date, "%m")),
          month_label = factor(month.abb[month_num], levels = month.abb)
        )

      monthly <- ng_ret |>
        dplyr::group_by(month_label, month_num) |>
        dplyr::summarise(avg_ret = mean(ret, na.rm = TRUE), .groups = "drop") |>
        dplyr::arrange(month_num) |>
        dplyr::mutate(bar_color = ifelse(avg_ret >= 0, "#4CAF50", "#F44336"))

      plotly::plot_ly(
        monthly,
        x             = ~month_label,
        y             = ~avg_ret,
        type          = "bar",
        marker        = list(color = ~bar_color),
        hovertemplate = "Month: %{x}<br>Avg Log Return: %{y:.4f}<extra></extra>"
      ) |>
        plotly::layout(
          xaxis  = list(
            title         = "Month",
            categoryorder = "array",
            categoryarray = month.abb
          ),
          yaxis  = list(title = "Avg Log Return"),
          shapes = list(list(
            type  = "line",
            xref  = "paper", x0 = 0, x1 = 1,
            yref  = "y",     y0 = 0, y1 = 0,
            line  = list(color = "black", width = 0.8, dash = "dot")
          ))
        )
    })
  })
}

# --- Group panel UI layout helpers ---
# These are plain functions (not modules) — they return UI markup for use inside renderUI.
# ns is passed in so output IDs are correctly scoped to the parent module.

# Returns the Crude group panel layout
# Example: md_crude_ui(ns)
md_crude_ui <- function(ns) {
  bslib::layout_columns(
    col_widths = 12,
    bslib::card(
      bslib::card_header("CL Calendar Spread (M1 \u2013 M2)"),
      bslib::card_body(plotly::plotlyOutput(ns("plot_crude_cal_spread"), height = "350px"))
    ),
    bslib::layout_columns(
      col_widths = c(4, 4, 4),
      bslib::card(bslib::card_header("WTI / Brent Spread"),  bslib::card_body("Coming soon.")),
      bslib::card(bslib::card_header("HTT Differential"),    bslib::card_body("Coming soon.")),
      bslib::card(bslib::card_header("Cushing Inventory"),   bslib::card_body("Coming soon."))
    )
  )
}

# Returns the Refined Products group panel layout
# Example: md_refined_ui(ns)
md_refined_ui <- function(ns) {
  bslib::layout_columns(
    col_widths = 12,
    bslib::card(
      bslib::card_header("HO Crack Spread (HO01 \u00d7 42 \u2013 CL01, USD/bbl)"),
      bslib::card_body(plotly::plotlyOutput(ns("plot_crack_spread"), height = "350px"))
    ),
    bslib::layout_columns(
      col_widths = c(6, 6),
      bslib::card(bslib::card_header("RB Crack Spread"),           bslib::card_body("Coming soon.")),
      bslib::card(bslib::card_header("HO vs RB Seasonal Spread"),  bslib::card_body("Coming soon."))
    )
  )
}

# Returns the Natural Gas group panel layout
# Example: md_ng_ui(ns)
md_ng_ui <- function(ns) {
  bslib::layout_columns(
    col_widths = 12,
    bslib::card(
      bslib::card_header("Natural Gas \u2014 Monthly Return Seasonality"),
      bslib::card_body(plotly::plotlyOutput(ns("plot_ng_seasonality"), height = "350px"))
    ),
    bslib::layout_columns(
      col_widths = c(6, 6),
      bslib::card(bslib::card_header("Winter Forward Curve Premium"), bslib::card_body("Coming soon.")),
      bslib::card(bslib::card_header("Storage Cycle"),                bslib::card_body("Coming soon."))
    )
  )
}
