pkgs <- c('readxl','tidyquant','vars','zoo','purrr','lubridate','bslib','plotly',
          'shinycssloaders','shinyjs','shinyWidgets','reactable')
missing <- pkgs[!sapply(pkgs, requireNamespace, quietly=TRUE)]
if (length(missing) > 0) {
  cat('Missing packages:', paste(missing, collapse=', '), '\n')
  install.packages(missing, repos='https://cloud.r-project.org')
  cat('Done\n')
} else {
  cat('All packages already installed\n')
}
