# Market Dynamics page — top-level group selector and conditional rendering.
# Owns the Crude | Refined Products | Natural Gas group toggle and conditionally
# shows/hides each group's module UI.
#
# Parameters:
#   id     - Shiny module ID
#   dflong - full RTL::dflong tibble
#   r      - shared reactiveValues
#
# Example:
#   mod_market_dynamics_ui("md")
#   mod_market_dynamics_server("md", dflong = dflong, r = r)

# ── UI ───────────────────────────────────────────────────────────────────────

mod_market_dynamics_ui <- function(id) {
  ns <- shiny::NS(id)

  tagList(
    # Group selector — fixed at top of Market Dynamics page
    shiny::fluidRow(
      shiny::column(
        width = 12,
        style = "text-align:center; padding: 12px 0;",
        shinyWidgets::radioGroupButtons(
          inputId  = ns("group"),
          label    = NULL,
          choices  = c("Crude" = "crude", "Refined Products" = "refined",
                       "Natural Gas" = "ng"),
          selected = "crude",
          status   = "primary",
          size     = "lg"
        )
      )
    ),
    # Conditional group panels
    shiny::conditionalPanel(
      condition = sprintf("input['%s'] === 'crude'", ns("group")),
      mod_md_crude_ui(ns("crude"))
    ),
    shiny::conditionalPanel(
      condition = sprintf("input['%s'] === 'refined'", ns("group")),
      mod_md_refined_ui(ns("refined"))
    ),
    shiny::conditionalPanel(
      condition = sprintf("input['%s'] === 'ng'", ns("group")),
      mod_md_ng_ui(ns("ng"))
    )
  )
}

# ── Server ───────────────────────────────────────────────────────────────────

mod_market_dynamics_server <- function(id, dflong, r) {
  shiny::moduleServer(id, function(input, output, session) {

    # ng_trigger fires TRUE the first time NG group is selected — drives lazy
    # EIA-923 load in mod_md_ng_server
    ng_trigger <- shiny::reactive({
      isTRUE(input$group == "ng")
    })

    mod_md_crude_server("crude",   dflong = dflong, r = r)
    mod_md_refined_server("refined", dflong = dflong, r = r)
    mod_md_ng_server("ng",          dflong = dflong, r = r, ng_trigger = ng_trigger)
  })
}
