# OLMAR-1: Online Moving Average Reversion (Li & Hoi, 2012)
#
# Passive-aggressive portfolio update using the SMA/price ratio as a
# predicted price-relative.  Pure functions only — no network, no side
# effects, no library() calls.  All deps qualified with pkg::.
#
# References:
#   Li & Hoi (2012). "Online portfolio selection: A survey."
#   Duchi et al. (2008). "Efficient projections onto the l1-ball..."

# ── 1. Simplex projection ────────────────────────────────────────────────────

#' Project a real vector onto the probability simplex
#'
#' Computes the Euclidean projection of \code{v} onto the set
#' \eqn{\{w \ge 0 : \sum w_i = 1\}}.  Uses the algorithm of Duchi et al.
#' (2008): sort descending, find the largest \eqn{\rho} such that
#' \eqn{u_\rho - (\sum_{j \le \rho} u_j - 1)/\rho > 0}, compute the
#' threshold, and clip.
#'
#' @param v Numeric vector of any length \eqn{\ge 1}.
#' @return Numeric vector of the same length with all elements \eqn{\ge 0}
#'   summing to 1.
#' @family olmar
#' @export
olmar_simplex_project <- function(v) {
  if (!is.numeric(v) || length(v) == 0L) {
    cli::cli_abort(c(
      "x" = "{.arg v} must be a non-empty numeric vector.",
      "i" = "Got class {.cls {class(v)}} of length {length(v)}."
    ))
  }
  n  <- length(v)
  u  <- sort(v, decreasing = TRUE)
  cs <- cumsum(u)
  rho <- max(which(u - (cs - 1) / seq_len(n) > 0))
  theta <- (cs[rho] - 1) / rho
  pmax(v - theta, 0)
}

# ── 2. One passive-aggressive update ────────────────────────────────────────

#' One OLMAR-1 passive-aggressive weight update
#'
#' Given the current portfolio weights \code{b_prev} and the predicted price
#' relatives \code{x_pred} (each element = SMA/price for that asset), performs
#' one step of the passive-aggressive update and projects the result back onto
#' the probability simplex.
#'
#' @param b_prev Numeric vector of current weights (non-negative, sums to 1).
#' @param x_pred Numeric vector of predicted price relatives (same length as
#'   \code{b_prev}).
#' @param epsilon Numeric scalar; mean-reversion threshold (must be > 0).
#'   Default 10.
#' @return Numeric weight vector in the probability simplex.
#' @family olmar
#' @export
olmar_update <- function(b_prev, x_pred, epsilon = 10) {
  if (!is.numeric(b_prev) || !is.numeric(x_pred)) {
    cli::cli_abort(c(
      "x" = "{.arg b_prev} and {.arg x_pred} must be numeric vectors.",
      "i" = "Got {.cls {class(b_prev)}} and {.cls {class(x_pred)}}."
    ))
  }
  n <- length(b_prev)
  if (n != length(x_pred)) {
    cli::cli_abort(c(
      "x" = "Length mismatch: {.arg b_prev} has {n}, {.arg x_pred} has {length(x_pred)}."
    ))
  }
  if (!is.numeric(epsilon) || length(epsilon) != 1L || epsilon <= 0) {
    cli::cli_abort(c(
      "x" = "{.arg epsilon} must be a positive scalar.",
      "i" = "Got {.val {epsilon}}."
    ))
  }

  x_bar  <- mean(x_pred)
  dev    <- x_pred - x_bar
  denom  <- sum(dev^2)
  lambda <- if (denom <= 1e-12) 0 else max(0, (epsilon - sum(b_prev * x_pred)) / denom)
  b_raw  <- b_prev + lambda * dev
  olmar_simplex_project(b_raw)
}

# ── 3. Full backtest ─────────────────────────────────────────────────────────

#' OLMAR-1 backtest on a price matrix
#'
#' Runs a daily OLMAR-1 backtest on the adjusted-close price matrix supplied.
#' Start with equal weights, then for each day \eqn{t}:
#' \enumerate{
#'   \item Compute SMA(\code{window}) for each asset using prices up to and
#'     including day \eqn{t} (look-ahead-safe: no future prices used).
#'   \item Predict price relative \eqn{x_{pred,i} = SMA_i / p_{t,i}}.
#'   \item Run the passive-aggressive update to get next-day weights
#'     \eqn{b_{t+1}}.
#'   \item Apply leverage tilt around equal weight (default 0.2).
#'   \item Realise the return on day \eqn{t+1} using actual returns
#'     \eqn{r_{t+1}} — strictly post-formation.
#'   \item Subtract turnover transaction cost.
#' }
#'
#' Assets with \code{NA} prices on day \eqn{t} are excluded from the active
#' universe on that day; their weight is redistributed proportionally to the
#' remaining assets.  Days with fewer than 2 active assets are skipped
#' (return = 0).
#'
#' @param prices Numeric matrix or data frame with rows = dates and
#'   columns = assets.  Values should be adjusted close prices.  If
#'   \code{prices} has a \code{Date} or \code{POSIXct} column named
#'   \code{date}, it is stripped before computation and re-attached to the
#'   output.
#' @param window Positive integer; SMA look-back window (inclusive of current
#'   day).  Default \code{25L}.
#' @param epsilon Positive numeric; mean-reversion threshold.  Default 10.
#' @param leverage Numeric in \eqn{[0, 1]}; fraction of the OLMAR tilt to
#'   apply.  1 = pure OLMAR; 0.2 = 20\% tilt, 80\% equal-weight.
#'   Default \code{0.2}.
#' @param cost_bps Numeric; one-way turnover transaction cost in basis points.
#'   Default \code{10}.
#' @param signal_null Logical; if \code{TRUE}, the predicted price relative
#'   \eqn{x_{pred}} is randomly permuted across the active assets on each day
#'   before the passive-aggressive update runs (#718 signal-null
#'   falsification). Every other piece of machinery — universe, active-asset
#'   handling, leverage tilt, turnover costs, t+1 execution — is left
#'   identical to the real backtest; only the correspondence between an
#'   asset's SMA/price ratio and that asset is destroyed. Default
#'   \code{FALSE}.
#' @param seed Integer or \code{NULL}; random seed for the \code{signal_null}
#'   permutation, set once via \code{set.seed()} before the daily loop so the
#'   run is reproducible. Ignored when \code{signal_null = FALSE}. Default
#'   \code{NULL}.
#' @return A \link[tibble]{tibble} with columns:
#'   \describe{
#'     \item{date}{Date or integer row index (if no date column supplied).}
#'     \item{gross_ret}{Daily portfolio gross return (before costs).}
#'     \item{net_ret}{Daily portfolio return net of transaction costs.}
#'     \item{turnover}{One-way portfolio turnover on that day.}
#'   }
#' @family olmar
#' @export
olmar_backtest <- function(prices,
                            window      = 25L,
                            epsilon     = 10,
                            leverage    = 0.2,
                            cost_bps    = 10,
                            signal_null = FALSE,
                            seed        = NULL) {
  # ── Input validation ──────────────────────────────────────────────────────
  if (!is.numeric(window) || length(window) != 1L || window < 2L) {
    cli::cli_abort(c(
      "x" = "{.arg window} must be an integer >= 2.",
      "i" = "Got {.val {window}}."
    ))
  }
  if (!is.numeric(epsilon) || length(epsilon) != 1L || epsilon <= 0) {
    cli::cli_abort(c(
      "x" = "{.arg epsilon} must be a positive scalar.",
      "i" = "Got {.val {epsilon}}."
    ))
  }
  if (!is.numeric(leverage) || length(leverage) != 1L || leverage < 0 || leverage > 1) {
    cli::cli_abort(c(
      "x" = "{.arg leverage} must be numeric in [0, 1].",
      "i" = "Got {.val {leverage}}."
    ))
  }
  if (!is.numeric(cost_bps) || length(cost_bps) != 1L || cost_bps < 0) {
    cli::cli_abort(c(
      "x" = "{.arg cost_bps} must be a non-negative numeric.",
      "i" = "Got {.val {cost_bps}}."
    ))
  }
  if (!is.logical(signal_null) || length(signal_null) != 1L || is.na(signal_null)) {
    cli::cli_abort(c(
      "x" = "{.arg signal_null} must be a single non-NA logical.",
      "i" = "Got {.val {signal_null}}."
    ))
  }
  if (!is.null(seed) && (!is.numeric(seed) || length(seed) != 1L)) {
    cli::cli_abort(c(
      "x" = "{.arg seed} must be NULL or a single numeric.",
      "i" = "Got {.cls {class(seed)}} of length {length(seed)}."
    ))
  }
  if (isTRUE(signal_null) && !is.null(seed)) set.seed(seed)

  # ── Extract date column if present ───────────────────────────────────────
  dates <- NULL
  if (is.data.frame(prices)) {
    date_col <- which(names(prices) %in% c("date", "Date"))
    if (length(date_col) > 0L) {
      dates  <- prices[[date_col[1L]]]
      prices <- prices[, -date_col[1L], drop = FALSE]
    }
    prices <- as.matrix(prices)
  }

  if (!is.matrix(prices) || !is.numeric(prices)) {
    cli::cli_abort(c(
      "x" = "{.arg prices} must be a numeric matrix or data frame.",
      "i" = "Got {.cls {class(prices)}}."
    ))
  }

  T_  <- nrow(prices)
  n   <- ncol(prices)

  if (T_ < window + 1L) {
    cli::cli_abort(c(
      "x" = "{.arg prices} has {T_} rows but {.arg window} = {window} requires at least {window + 1L}."
    ))
  }

  # ── Helper: restrict weight vector to active (non-NA) assets ─────────────
  active_ew <- function(active_idx) {
    w <- numeric(n)
    if (length(active_idx) > 0L) w[active_idx] <- 1 / length(active_idx)
    w
  }

  restrict_weights <- function(w, active_idx) {
    w2 <- numeric(n)
    if (length(active_idx) == 0L) return(w2)
    w2[active_idx] <- w[active_idx]
    s <- sum(w2)
    if (s > 1e-12) w2 / s else {
      w2[active_idx] <- 1 / length(active_idx)
      w2
    }
  }

  # ── Pre-allocate output ───────────────────────────────────────────────────
  gross_ret <- numeric(T_)
  net_ret   <- numeric(T_)
  turnover  <- numeric(T_)

  # Current weights (equal weight at t=0)
  ew_full <- rep(1 / n, n)
  b_lev   <- ew_full   # leveraged weights entering period t

  for (t in seq_len(T_)) {
    # Active assets on day t (non-NA price)
    active <- which(!is.na(prices[t, ]))
    n_active <- length(active)

    # Not enough history to form SMA or not enough assets — skip, earn 0
    if (t < window || n_active < 2L) {
      gross_ret[t] <- 0
      net_ret[t]   <- 0
      turnover[t]  <- 0
      # Weights unchanged; if t == window-1 transition to ew for active set
      if (t == window - 1L) {
        b_lev <- active_ew(active)
      }
      next
    }

    # SMA for each active asset using prices[t-window+1 : t, ]
    window_prices <- prices[(t - window + 1L):t, active, drop = FALSE]
    sma    <- colMeans(window_prices, na.rm = TRUE)
    p_t    <- prices[t, active]

    # Predicted price relatives (avoid division by zero)
    p_t_safe <- ifelse(abs(p_t) < 1e-12, 1e-12, p_t)
    x_pred   <- sma / p_t_safe

    # #718 signal null: destroy the asset <-> predicted-price-relative
    # correspondence by permuting x_pred across the active assets. Everything
    # downstream (PA update, simplex projection, leverage tilt, turnover
    # cost, t+1 realisation) runs unchanged on the shuffled vector -- only
    # the claimed edge (SMA/price is informative FOR THAT ASSET) is removed.
    if (isTRUE(signal_null) && n_active > 1L) {
      x_pred <- x_pred[sample.int(n_active)]
    }

    # Restrict previous weights to current active set
    b_prev_active <- b_lev[active]
    b_prev_active_sum <- sum(b_prev_active)
    if (b_prev_active_sum < 1e-12) {
      b_prev_active <- rep(1 / n_active, n_active)
    } else {
      b_prev_active <- b_prev_active / b_prev_active_sum
    }

    # PA update → new OLMAR weights for active assets
    b_olmar_active <- olmar_update(b_prev_active, x_pred, epsilon)

    # Equal-weight baseline for active assets
    ew_active <- rep(1 / n_active, n_active)

    # Leverage tilt
    b_new_active <- ew_active + leverage * (b_olmar_active - ew_active)

    # Reconstruct full weight vector
    b_new <- numeric(n)
    b_new[active] <- b_new_active

    # Turnover (one-way)
    tv <- sum(abs(b_new - b_lev)) / 2

    # Realize return on day t+1 (look-ahead safety: weights formed at end of t)
    # Look-ahead guard: we never read prices[t+1, ] here.
    if (t < T_) {
      p_next  <- prices[t + 1L, active]
      p_cur   <- prices[t, active]
      r_t1    <- ifelse(!is.na(p_next) & !is.na(p_cur) & abs(p_cur) > 1e-12,
                        p_next / p_cur - 1, 0)
      gr      <- sum(b_new[active] * r_t1)
      cost    <- (cost_bps / 1e4) * tv
      gross_ret[t] <- gr
      net_ret[t]   <- gr - cost
      turnover[t]  <- tv
    } else {
      # Last day: weights are formed but no t+1 return to realize
      gross_ret[t] <- 0
      net_ret[t]   <- 0
      turnover[t]  <- tv
    }

    # Advance weights
    b_lev <- b_new
  }

  # ── Assemble output ───────────────────────────────────────────────────────
  out_date <- if (!is.null(dates)) dates else seq_len(T_)
  tibble::tibble(
    date      = out_date,
    gross_ret = gross_ret,
    net_ret   = net_ret,
    turnover  = turnover
  )
}
