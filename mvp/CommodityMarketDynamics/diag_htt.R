library(dplyr)
library(tidyr)

source("R/utils_data.R")
source("R/mod_analysis_returns.R")

dflong <- RTL::dflong

cat("--- 1. pivot_ticker_wide column order ---\n")
wide <- pivot_ticker_wide(get_ticker(dflong, "HTT"))
cat(names(wide), "\n\n")

cat("--- 2. compute_returns column order ---\n")
ret <- compute_returns(get_ticker(dflong, "HTT"))
cat(names(ret), "\n\n")

cat("--- 3. non-NA counts per tenor ---\n")
tenor_cols <- setdiff(names(ret), "date")
counts <- sapply(tenor_cols, function(col) sum(!is.na(ret[[col]])))
print(counts)

cat("\n--- 4. cor() matrix names and NA count after 30-obs filter ---\n")
tenor_filtered <- tenor_cols[counts >= 30]
cat("Retained tenors:", tenor_filtered, "\n")
corr_mat <- cor(ret[, tenor_filtered], use = "pairwise.complete.obs")
cat("colnames:", colnames(corr_mat), "\n")
cat("Total NAs in corr_mat:", sum(is.na(corr_mat)), "\n")

cat("\n--- 5. Sample of corr_mat (first 3 rows/cols) ---\n")
print(round(corr_mat[1:min(3, nrow(corr_mat)), 1:min(3, ncol(corr_mat))], 3))
