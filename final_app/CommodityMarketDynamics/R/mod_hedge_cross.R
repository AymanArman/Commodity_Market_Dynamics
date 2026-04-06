# Hedging Analytics Page — Row 5: Cross-Market Kalman Beta Matrix
# Renders a 6×6 reactable beta matrix from r$kalman_cross_betas.
# Rows = exposure ticker (what you're hedging); cols = hedge instrument.
# Cell background: RdBu diverging scale centered at 0.
# Diagonal cells greyed out (not a hedge relationship).
# Hover tooltip shows R² for each off-diagonal cell.
#
# Parameters:
#   id - Shiny module ID
#   r  - shiny::reactiveValues; reads r$kalman_cross_betas
#         (date, from_ticker, to_ticker, beta, r_squared)
#
# Example:
#   mod_hedge_cross_ui("hedge_cross")
#   mod_hedge_cross_server("hedge_cross", r = r)

# Canonical ticker order for the 6×6 matrix
CROSS_TICKERS <- c("CL", "BRN", "NG", "HO", "RB", "HTT")

# ── Helpers ───────────────────────────────────────────────────────────────────

# Maps a beta value to an RdBu hex color centered at 0.
# Negative betas → red; positive → blue; white at 0.
# Magnitude drives intensity up to max_abs saturation.
#
# Parameters:
#   val     - numeric beta value (may be NA)
#   max_abs - numeric; value at which color reaches full saturation
# Returns: hex color string
#
# Example: beta_to_rdbu(0.8, 1.5)
beta_to_rdbu <- function(val, max_abs) {
  if (is.na(val)) return("#d0d0d0")
  ramp <- grDevices::colorRampPalette(c("#d73027", "#f46d43", "#fdae61",
                                         "#ffffff",
                                         "#abd9e9", "#74add1", "#4575b4"))
  norm <- (val / max_abs + 1) / 2   # maps [-max_abs, +max_abs] to [0, 1]
  norm <- pmax(0, pmin(1, norm))
  ramp(201)[round(norm * 200) + 1]
}

# Slices r$kalman_cross_betas at a single date and pivots to 6×6 matrix.
# Returns a list: betas (6×6 matrix, rows=from, cols=to) and
#                 r_squareds (same shape).
#
# Parameters:
#   kalman_cross - tibble(date, from_ticker, to_ticker, beta, r_squared)
#   sel_date     - Date
# Returns: list(betas = df, r_squareds = df, max_abs = numeric)
#
# Example:
#   build_cross_matrix(r$kalman_cross_betas, as.Date("2024-01-15"))
build_cross_matrix <- function(kalman_cross, sel_date) {
  slice <- kalman_cross |>
    dplyr::filter(date == sel_date)

  # Build 6×6 data frames filled with NA (diagonal stays NA)
  n   <- length(CROSS_TICKERS)
  mat_b <- matrix(NA_real_, n, n, dimnames = list(CROSS_TICKERS, CROSS_TICKERS))
  mat_r <- matrix(NA_real_, n, n, dimnames = list(CROSS_TICKERS, CROSS_TICKERS))

  for (i in seq_len(nrow(slice))) {
    fr <- slice$from_ticker[i]
    to <- slice$to_ticker[i]
    if (fr %in% CROSS_TICKERS && to %in% CROSS_TICKERS) {
      mat_b[fr, to] <- slice$beta[i]
      mat_r[fr, to] <- slice$r_squared[i]
    }
  }

  max_abs <- max(abs(mat_b), na.rm = TRUE)
  max_abs <- if (is.finite(max_abs) && max_abs > 0) max_abs else 1

  list(
    betas      = as.data.frame(mat_b),
    r_squareds = as.data.frame(mat_r),
    max_abs    = max_abs
  )
}

# ── UI ────────────────────────────────────────────────────────────────────────

mod_hedge_cross_ui <- function(id) {
  ns <- shiny::NS(id)

  shiny::tagList(
    # Descriptor text row — no divider below
    shiny::fluidRow(
      style = "border-bottom:none; margin-bottom:4px; padding-bottom:0;",
      shiny::column(
        width = 12,
        shiny::p(
          style = "font-style:italic; text-align:center;",
          "Row = exposure ticker (what you're hedging); Column = hedge instrument."
        )
      )
    ),
    # Slider row — directly above matrix, centered within width=4 middle column
    shiny::fluidRow(
      style = "border-bottom:none; margin-bottom:4px; padding-bottom:0;",
      shiny::column(width = 4),
      shiny::column(
        width = 4,
        shiny::sliderInput(
          inputId = ns("sel_date"),
          label   = "Reference date",
          min     = as.Date("2009-01-01"),
          max     = as.Date("2024-12-31"),
          value   = as.Date("2024-12-31"),
          timeFormat = "%b %Y",
          step    = 1
        )
      ),
      shiny::column(width = 4)
    ),
    # Matrix row with width=4 buffers on each side — no divider below
    shiny::fluidRow(
      style = "border-bottom:none; margin-bottom:4px; padding-bottom:0;",
      shiny::column(width = 4),
      shiny::column(
        width = 4,
        reactable::reactableOutput(ns("cross_matrix"))
      ),
      shiny::column(width = 4)
    ),
    # Narrative row with width=3 buffers on each side
    shiny::fluidRow(
      shiny::column(width = 3),
      shiny::column(
        width = 6,
        bslib::card(
          bslib::card_body(
            shiny::p(
              shiny::strong("Asymmetry:"),
              " \u03b2(CL\u2192BRN) \u2260 \u03b2(BRN\u2192CL) — the hedge ratio depends ",
              "on which side of the trade you're on; the table reads differently ",
              "row-by-row vs. column-by-column."
            ),
            shiny::p(
              shiny::strong("HTT note:"),
              " As a spread instrument, betas vs. flat price tickers will be small — ",
              "near-zero cells are analytically meaningful, not missing data."
            ),
            shiny::p(
              shiny::strong("Stress periods:"),
              " Moving the date picker to 2008, COVID (2020), or 2022 reveals how ",
              "cross-market hedge ratios shift under pressure. The Kalman filter's ",
              "time-varying property, established in Row 4, is directly applied here."
            )
          )
        )
      ),
      shiny::column(width = 3)
    )
  )
}

# ── Server ────────────────────────────────────────────────────────────────────

mod_hedge_cross_server <- function(id, r, dflong) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # -- Set slider range from dflong date span on startup
    shiny::observe({
      all_dates <- sort(unique(dflong$date))
      if (length(all_dates) == 0) return()
      # Also respect available Kalman cross dates
      kalman_dates <- if (!is.null(r$kalman_cross_betas)) {
        sort(unique(r$kalman_cross_betas$date))
      } else all_dates
      shiny::updateSliderInput(
        session  = session,
        inputId  = "sel_date",
        min      = min(all_dates),
        max      = max(all_dates),
        value    = if (length(kalman_dates) > 0) max(kalman_dates) else max(all_dates)
      )
    })

    # -- Snap date to nearest available Kalman date
    snapped_date <- shiny::reactive({
      shiny::req(input$sel_date, !is.null(r$kalman_cross_betas))
      sel   <- as.Date(input$sel_date)
      valid <- sort(unique(r$kalman_cross_betas$date))
      if (length(valid) == 0) return(NULL)
      # Use the most recent Kalman date <= sel_date
      avail <- valid[valid <= sel]
      if (length(avail) == 0) return(min(valid))
      max(avail)
    })

    # -- Reactable matrix
    output$cross_matrix <- reactable::renderReactable({
      shiny::req(!is.null(r$kalman_cross_betas))
      sd <- snapped_date()
      shiny::req(!is.null(sd))

      cm      <- build_cross_matrix(r$kalman_cross_betas, sd)
      betas_df <- cm$betas
      rsq_df   <- cm$r_squareds
      max_abs  <- cm$max_abs

      # Add row label column; strip matrix row names to prevent reactable
      # rendering them as an extra unnamed column
      rownames(betas_df) <- NULL
      rownames(rsq_df)   <- NULL
      betas_df <- cbind(
        data.frame(Exposure = CROSS_TICKERS, stringsAsFactors = FALSE),
        betas_df
      )
      rsq_df_aug <- cbind(
        data.frame(Exposure = CROSS_TICKERS, stringsAsFactors = FALSE),
        rsq_df
      )

      # Build colDefs for each of the 6 ticker columns
      make_ticker_col <- function(col_ticker) {
        col_idx <- which(CROSS_TICKERS == col_ticker)
        reactable::colDef(
          name   = col_ticker,
          align  = "center",
          width  = 90,
          style  = function(value, index) {
            row_ticker <- CROSS_TICKERS[index]
            if (row_ticker == col_ticker) {
              # Diagonal — grey out
              return(list(background = "#a0a0a0", color = "#606060"))
            }
            bg <- beta_to_rdbu(value, max_abs)
            # Dark text for light colors (near white)
            list(background = bg, color = "#111111")
          },
          cell = function(value, index) {
            row_ticker <- CROSS_TICKERS[index]
            if (row_ticker == col_ticker) return("—")
            if (is.na(value)) return("NA")
            r2 <- rsq_df[row_ticker, col_ticker]
            r2_str <- if (!is.na(r2)) paste0(" (R\u00b2=", round(r2, 2), ")") else ""
            # Return formatted value with R² as title attribute for hover
            shiny::span(
              title = paste0("\u03b2 = ", round(value, 4), r2_str),
              round(value, 3)
            )
          }
        )
      }

      col_defs <- c(
        list(
          Exposure = reactable::colDef(
            name     = "Exposure \u2192 Hedge",
            align    = "left",
            width    = 110,
            style    = list(fontWeight = "bold", color = "#000000")
          )
        ),
        stats::setNames(
          lapply(CROSS_TICKERS, make_ticker_col),
          CROSS_TICKERS
        )
      )

      reactable::reactable(
        data      = betas_df,
        columns   = col_defs,
        bordered  = TRUE,
        highlight = TRUE,
        compact   = TRUE,
        theme     = reactable::reactableTheme(
          backgroundColor = "#fffff2",
          borderColor     = "rgba(33,0,0,0.15)",
          headerStyle = list(
            background = "#48495e",
            color      = "#f9f9f9",
            fontFamily = "Times New Roman",
            fontSize   = "13px"
          ),
          cellStyle = list(
            fontFamily = "Times New Roman",
            fontSize   = "13px"
          )
        )
      )
    })
  })
}
