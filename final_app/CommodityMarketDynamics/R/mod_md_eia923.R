# Market Dynamics — EIA-923 lazy loader
# Reads and binds all EIA-923 annual files on first NG group click.
# Filters to coal fuel types, pivots to long format, and writes r$eia923_coal.
#
# Parameters:
#   r       - shared reactiveValues; writes r$eia923_coal
#   trigger - reactive() that fires when NG group becomes active (truthy = load)
#
# Example:
#   mod_md_eia923_server(r = r, trigger = reactive(input$group == "ng"))

mod_md_eia923_server <- function(r, trigger) {
  shiny::observe({
    shiny::req(isTRUE(trigger()))
    # Only load once
    if (!is.null(r$eia923_coal)) return()

    # List all EIA-923 annual files in inst/extdata/
    extdata_dir <- system.file("extdata", package = "CommodityMarketDynamics")
    files <- list.files(
      extdata_dir,
      pattern     = "EIA923|eia923",
      ignore.case = TRUE,
      full.names  = TRUE
    )

    shiny::req(length(files) > 0)

    # Read and bind all annual files
    all_data <- purrr::map_dfr(files, read_eia923_file)

    # Coal fuel type codes (test 3.21)
    coal_codes <- c("ANT", "BIT", "LIG", "RC", "SUB", "WC")
    coal_data  <- dplyr::filter(all_data, fuel_type_code %in% coal_codes)

    # Map census division code to full US Census Bureau division name
    coal_data <- dplyr::mutate(
      coal_data,
      region = division_full_name(census_region)
    )

    # Pivot Netgen columns to long format: one row per plant × year × month
    netgen_cols <- paste0("netgen_", c("jan","feb","mar","apr","may","jun",
                                       "jul","aug","sep","oct","nov","dec"))
    month_nums  <- setNames(1:12, c("jan","feb","mar","apr","may","jun",
                                    "jul","aug","sep","oct","nov","dec"))

    long_data <- tidyr::pivot_longer(
      coal_data,
      cols      = dplyr::all_of(netgen_cols),
      names_to  = "month_name",
      values_to = "mwh"
    ) |>
      dplyr::mutate(
        month_name = sub("netgen_", "", month_name),
        month      = month_nums[month_name],
        date       = as.Date(paste(year, month, "01", sep = "-"))
      ) |>
      dplyr::filter(!is.na(mwh), !is.na(date))

    # Aggregate by Census Region + date (for View 1 region selector)
    region_monthly <- long_data |>
      dplyr::group_by(region, date) |>
      dplyr::summarise(mwh = sum(mwh, na.rm = TRUE), .groups = "drop")

    # Aggregate by Plant State + date (for View 2 choropleth)
    state_monthly <- long_data |>
      dplyr::group_by(plant_state, date) |>
      dplyr::summarise(mwh = sum(mwh, na.rm = TRUE), .groups = "drop")

    r$eia923_coal <- list(
      region_monthly = region_monthly,
      state_monthly  = state_monthly
    )
  })
}
