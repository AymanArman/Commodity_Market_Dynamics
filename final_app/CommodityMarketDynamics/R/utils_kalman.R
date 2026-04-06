# Scalar time-varying Kalman filter for estimating a rolling regression beta.
# Model: y_t = beta_t * x_t + epsilon_t
#        beta_t = beta_{t-1} + eta_t  (random walk state transition)
# Strictly causal — each beta estimate uses only data up to time t.
#
# R-squared is computed as rolling Pearson cor(x, y)^2 over the last 60
# observations (min 10 required; NA returned for earlier dates).
#
# Parameters:
#   x   - numeric vector, independent variable (e.g. M1 returns)
#   y   - numeric vector, dependent variable (e.g. Mn returns)
#   Q   - process noise variance (controls beta adaptation speed); default 1e-4
#   R   - observation noise variance; default = var(y, na.rm=TRUE)
# Returns: list with elements beta (numeric) and r_squared (numeric), length = length(x)
#
# Example:
#   res <- kalman_scalar(x = rnorm(200), y = rnorm(200))
#   plot(res$beta)
kalman_scalar <- function(x, y, Q = 1e-4, R = NULL) {
  n <- length(x)
  stopifnot(length(y) == n)

  if (is.null(R)) R <- var(y, na.rm = TRUE)
  if (is.na(R) || R <= 0) R <- 1e-4

  beta  <- numeric(n)
  P     <- numeric(n)
  r_sq  <- rep(NA_real_, n)

  # Initial state: beta = 0, large uncertainty
  beta[1] <- 0
  P[1]    <- 1

  for (t in seq(2, n)) {
    # Pass NA through without updating
    if (is.na(x[t]) || is.na(y[t])) {
      beta[t] <- beta[t - 1]
      P[t]    <- P[t - 1] + Q
      next
    }

    # Predict
    beta_pred <- beta[t - 1]
    P_pred    <- P[t - 1] + Q

    # Update (Kalman gain)
    S        <- P_pred * x[t]^2 + R
    K        <- P_pred * x[t] / S
    beta[t]  <- beta_pred + K * (y[t] - beta_pred * x[t])
    P[t]     <- (1 - K * x[t]) * P_pred

    # Rolling R² over last 60 observations
    start <- max(1L, t - 59L)
    if ((t - start + 1L) >= 10L) {
      r_sq[t] <- stats::cor(x[start:t], y[start:t], use = "complete.obs")^2
    }
  }

  list(beta = beta, r_squared = r_sq)
}
