# EIA-923 utility — shared file reader used by mod_md_eia923.
#
# read_eia923_file: reads one EIA-923 annual file and returns a tidy tibble with
#   standardised column names. Handles skip differences between 2008-2010 (skip=6)
#   and 2011+ (skip=5). col_types="text" avoids coercion failures on mixed columns.
#   "." values in Netgen columns are treated as NA (EIA missing data marker).
#
# Parameters:
#   path - absolute path to an EIA-923 annual Excel file (.xls or .xlsx)
#
# Returns: tibble with columns plant_state, census_region, fuel_type_code,
#   netgen_jan..netgen_dec, year
#
# Example:
#   read_eia923_file("inst/extdata/EIA923_Schedules_2_3_4_5_M_12_2020_Final_Revision.xlsx")

read_eia923_file <- function(path) {
  # Year from filename drives skip: 2008-2010 have an extra header row
  yr <- as.integer(stringr::str_extract(basename(path), "\\d{4}"))
  sk <- if (yr <= 2010L) 6L else 5L

  df <- readxl::read_excel(
    path,
    sheet     = "Page 1 Generation and Fuel Data",
    skip      = sk,
    col_types = "text"
  )

  # Positional selection only — column names vary across years
  # Col 7=Plant State, 8=Census Region, 15=Fuel Type Code,
  # 80-91=Netgen Jan-Dec, 97=Year
  df <- df[, c(7L, 8L, 15L, 80L:91L, 97L)]

  names(df) <- c(
    "plant_state", "census_region", "fuel_type_code",
    "netgen_jan", "netgen_feb", "netgen_mar", "netgen_apr",
    "netgen_may", "netgen_jun", "netgen_jul", "netgen_aug",
    "netgen_sep", "netgen_oct", "netgen_nov", "netgen_dec",
    "year"
  )

  # "." is EIA's missing-data marker — convert to NA, not 0
  netgen_cols <- paste0("netgen_", c("jan","feb","mar","apr","may","jun",
                                     "jul","aug","sep","oct","nov","dec"))
  df[netgen_cols] <- lapply(df[netgen_cols], function(x) {
    x[x == "."] <- NA_character_
    as.numeric(x)
  })

  df$year <- as.integer(df$year)
  df
}

# map_census_region: maps EIA census division codes to the four broad regions.
#
# Parameters:
#   division - character vector of EIA census division codes
#
# Returns: character vector of region labels (Northeast/Midwest/South/West)
#
# Example:
#   map_census_region(c("NEW", "ENC", "WSC", "MTN"))
#   # [1] "Northeast" "Midwest"   "South"     "West"

map_census_region <- function(division) {
  region_map <- c(
    NEW  = "Northeast", MAT  = "Northeast",
    ENC  = "Midwest",  WNC  = "Midwest",
    SAT  = "South",    ESC  = "South",    WSC  = "South",
    MTN  = "West",     PACC = "West",     PACN = "West"
  )
  unname(region_map[division])
}

# division_full_name: maps EIA census division codes to full US Census Bureau
#   division names. Used for the fuel-switching region selector.
#
# Parameters:
#   division - character vector of EIA census division codes
#
# Returns: character vector of full division names
#
# Example:
#   division_full_name(c("NEW", "ENC", "WSC", "MTN"))
#   # [1] "New England" "East North Central" "West South Central" "Mountain"

division_full_name <- function(division) {
  name_map <- c(
    NEW  = "New England",
    MAT  = "Middle Atlantic",
    ENC  = "East North Central",
    WNC  = "West North Central",
    SAT  = "South Atlantic",
    ESC  = "East South Central",
    WSC  = "West South Central",
    MTN  = "Mountain",
    PACC = "Pacific Contiguous",
    PACN = "Pacific Non-Contiguous"
  )
  unname(name_map[division])
}
