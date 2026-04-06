FROM rocker/r-ver:4.4.2

# System libraries required by R package dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    libgit2-dev \
    libfontconfig1-dev \
    libharfbuzz-dev \
    libfribidi-dev \
    libfreetype6-dev \
    libpng-dev \
    libtiff5-dev \
    libjpeg-dev \
    pandoc \
  && rm -rf /var/lib/apt/lists/*

# pak for fast parallel dependency resolution
RUN Rscript -e "install.packages('pak', repos = 'https://cloud.r-project.org')"

# Install all CRAN dependencies declared in DESCRIPTION.
# Kept as a separate layer so it caches independently of app source changes —
# this layer only rebuilds when dependencies change, not on every code push.
RUN Rscript -e "pak::pak(c( \
    'config', 'golem', 'shiny', 'bslib', 'plotly', \
    'dplyr', 'tidyr', 'purrr', 'lubridate', 'readxl', \
    'tidyquant', 'vars', 'zoo', 'RTL', \
    'htmltools', 'shinycssloaders', 'shinyjs', \
    'shinyWidgets', 'reactable', 'viridisLite' \
  ))"

# Copy package source — includes inst/extdata EIA data files
COPY final_app/CommodityMarketDynamics /app

# Install the Golem package from source
RUN Rscript -e "install.packages('/app', repos = NULL, type = 'source')"

EXPOSE 3838

CMD ["Rscript", "-e", \
  "CommodityMarketDynamics::run_app(options = list(host = '0.0.0.0', port = 3838))"]
