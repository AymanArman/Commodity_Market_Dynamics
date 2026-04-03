# Golem app configuration — reads from config.yml if present, falls back to defaults
# get_golem_config(value) retrieves a named config value
# Example: get_golem_config("app_prod")
get_golem_config <- function(
  value,
  config = Sys.getenv("R_CONFIG_ACTIVE", "default"),
  use_parent = TRUE,
  ...
) {
  config::get(
    value = value,
    config = config,
    file = app_sys("golem-config.yml"),
    use_parent = use_parent,
    ...
  )
}

# Returns path to a file inside inst/app/
# app_sys("www/style.css") -> inst/app/www/style.css
app_sys <- function(...) {
  system.file(..., package = "CommodityMarketDynamics")
}
