#' Out-of-sample min-variance / covariance-conditioning diagnostic
#'
#' @title OOS Min-Variance Conditioning Diagnostic (`hd_cov_oos_diagnostic`)
#'
#' @description
#' Evaluates multiple covariance estimators (sample, Ledoit-Wolf, RMT-denoise)
#' in a walk-forward out-of-sample (OOS) backtest. For each rolling training
#' window, each method's covariance estimate is used to compute unconstrained
#' global minimum-variance (GMV) portfolio weights via [hd_min_var_weights()].
#' The resulting weights are applied to the **next period's** (t+1) realised
#' returns to produce an OOS portfolio return.
#'
#' **Look-ahead discipline (mandatory):** weights are estimated exclusively
#' from data in the training window (periods 1 through t). The OOS return for
#' each origin t is the portfolio return at period t+1 — strictly the first
#' period *not* in the training set. This mirrors the `alpha-decay-min-t+1`
#' rule: t+0 execution is impossible, and any use of t+0 information in weight
#' construction constitutes look-ahead bias. The function never reads
#' `returns[t+1, ]` when computing covariances.
#'
#' **Wide-regime demonstration:** when the number of assets p approaches or
#' exceeds the training window n (p ≥ train_window), the sample covariance
#' matrix is singular and `solve()` fails. These failures are counted as
#' `n_failed` in the output. Regularised estimators (Ledoit-Wolf, RMT-denoise)
#' remain invertible and produce finite GMV weights regardless of the p/n ratio.
#'
#' @param returns A numeric matrix or data frame with rows in **chronological
#'   order** and one column per asset. If a data frame, a `date` column (any
#'   column whose name equals `"date"`, case-insensitively) is dropped before
#'   estimation and retained only for output labelling. All remaining columns
#'   must be numeric.
#' @param methods Character vector of covariance methods to compare. Passed to
#'   [hd_cov_estimate()]. Default `c("sample", "ledoit_wolf", "rmt_denoise")`.
#' @param train_window Integer scalar. Number of periods in each rolling
#'   training window. Default `60L` (5 years of monthly data). Must satisfy
#'   `nrow(returns) > train_window + 1`.
#' @param lw_target Ledoit-Wolf shrinkage target. Passed to [hd_cov_estimate()]
#'   when `"ledoit_wolf"` is in `methods`. One of `"const_cor"` or
#'   `"identity"`. Default `"const_cor"`.
#'
#' @return A [tibble::tibble()] with one row per method and columns:
#'   \describe{
#'     \item{`method`}{Character — covariance method name.}
#'     \item{`n_oos`}{Integer — number of OOS periods with non-NA returns
#'       (i.e. windows where the covariance solve succeeded).}
#'     \item{`n_failed`}{Integer — number of windows where `solve()` failed
#'       (singular or ill-conditioned covariance); results in `NA` OOS return.}
#'     \item{`oos_mean`}{Numeric — mean of non-NA OOS returns.}
#'     \item{`oos_vol`}{Numeric — standard deviation of non-NA OOS returns.}
#'     \item{`oos_sharpe`}{Numeric — annualised Sharpe ratio
#'       (`mean / sd * sqrt(12)`) over non-NA OOS returns. `NA` if fewer than
#'       2 non-NA OOS returns.}
#'     \item{`mean_cond`}{Numeric — mean condition number of the estimated
#'       covariance across all training windows.}
#'     \item{`median_cond`}{Numeric — median condition number across all
#'       training windows.}
#'   }
#'   The returned tibble carries three attributes:
#'   \describe{
#'     \item{`train_window`}{The `train_window` argument value.}
#'     \item{`n_periods`}{Total number of rows in the (date-stripped) returns
#'       matrix.}
#'     \item{`n_assets`}{Number of assets (columns).}
#'   }
#'
#' @references
#' Raviv, E. (2026). Covariance estimation for wide data. *WIREs Computational
#' Statistics*, 18(2). \doi{10.1002/wics.70068}
#'
#' Ledoit, O. & Wolf, M. (2004). A well-conditioned estimator for
#' large-dimensional covariance matrices. *Journal of Multivariate Analysis*,
#' 88(2), 365–411. \doi{10.1016/S0047-259X(03)00096-4}
#'
#' Laloux, L., Cizeau, P., Bouchaud, J.-P. & Potters, M. (1999). Noise
#' dressing of financial correlation matrices. *Physical Review Letters*,
#' 83(7), 1467–1470. \doi{10.1103/PhysRevLett.83.1467}
#'
#' @family covariance
#' @export
#'
#' @examples
#' set.seed(42)
#' X <- matrix(rnorm(100 * 5), nrow = 100, ncol = 5)
#' colnames(X) <- paste0("A", seq_len(5))
#' result <- hd_cov_oos_diagnostic(X, train_window = 60L)
#' result
hd_cov_oos_diagnostic <- function(
    returns,
    methods      = c("sample", "ledoit_wolf", "rmt_denoise"),
    train_window = 60L,
    lw_target    = "const_cor"
) {

  # ---- Input validation -----------------------------------------------
  if (!is.matrix(returns) && !is.data.frame(returns)) {
    cli::cli_abort(
      c(
        "{.arg returns} must be a numeric matrix or data frame.",
        "x" = "Got {.cls {class(returns)}}."
      )
    )
  }

  # Coerce data frame: drop date column, keep asset columns
  if (is.data.frame(returns)) {
    date_col <- which(tolower(names(returns)) == "date")
    if (length(date_col) > 0L) {
      returns <- returns[, -date_col, drop = FALSE]
    }
    asset_names <- names(returns)
    returns <- as.matrix(returns)
    colnames(returns) <- asset_names
  }

  if (!is.numeric(returns)) {
    cli::cli_abort(
      c(
        "{.arg returns} must be numeric after removing any date column.",
        "x" = "Got {.cls {typeof(returns)}}."
      )
    )
  }

  n <- nrow(returns)
  p <- ncol(returns)

  if (is.null(p) || p < 2L) {
    cli::cli_abort(
      c(
        "{.arg returns} must have at least 2 asset columns.",
        "x" = "Got {p %||% 0L} column{?s}."
      )
    )
  }

  if (!is.integer(train_window)) {
    train_window <- as.integer(train_window)
  }
  if (length(train_window) != 1L || is.na(train_window) || train_window < 2L) {
    cli::cli_abort(
      c(
        "{.arg train_window} must be a single integer >= 2.",
        "x" = "Got {train_window}."
      )
    )
  }

  if (n <= train_window + 1L) {
    cli::cli_abort(
      c(
        "{.arg returns} does not have enough rows for walk-forward evaluation.",
        "x" = "Need more than {train_window + 1L} rows; got {n}.",
        "i" = "Require nrow(returns) > train_window + 1 (training window + at least 1 OOS period)."
      )
    )
  }

  if (!is.character(methods) || length(methods) < 1L) {
    cli::cli_abort(
      "{.arg methods} must be a non-empty character vector."
    )
  }

  valid_methods <- c("sample", "ledoit_wolf", "rmt_denoise", "threshold")
  bad <- setdiff(methods, valid_methods)
  if (length(bad) > 0L) {
    cli::cli_abort(
      c(
        "Unknown covariance method{?s}: {.val {bad}}.",
        "i" = "Valid methods: {.val {valid_methods}}."
      )
    )
  }

  lw_target <- match.arg(lw_target, c("const_cor", "identity"))

  # ---- Walk-forward loop ----------------------------------------------
  # Origins: t = train_window, ..., n-1
  # Train window: rows (t - train_window + 1) through t  (1-indexed)
  # OOS period: row t+1  (NEVER t, to prevent look-ahead bias)

  n_origins <- n - train_window   # number of OOS evaluation points

  # Pre-allocate storage: one row per origin per method
  results_list <- vector("list", length(methods))
  names(results_list) <- methods

  for (meth in methods) {
    oos_rets  <- numeric(n_origins)
    cond_nums <- numeric(n_origins)
    failed    <- logical(n_origins)

    for (i in seq_len(n_origins)) {
      t <- train_window + i - 1L   # last training row (1-indexed)

      # Training window: rows (t - train_window + 1) through t
      train_rows <- seq.int(t - train_window + 1L, t)
      train_mat  <- returns[train_rows, , drop = FALSE]

      # Drop incomplete rows within the training window
      cc <- stats::complete.cases(train_mat)
      train_cc <- train_mat[cc, , drop = FALSE]

      # Covariance estimation — may warn on NA drops (already handled above)
      Sigma <- tryCatch(
        suppressWarnings(
          hd_cov_estimate(train_cc, method = meth, lw_target = lw_target)
        ),
        error = function(e) NULL
      )

      if (is.null(Sigma)) {
        cond_nums[i] <- NA_real_
        oos_rets[i]  <- NA_real_
        failed[i]    <- TRUE
        next
      }

      cond_nums[i] <- attr(Sigma, "condition_number")

      # GMV weights from training data (no look-ahead: uses rows 1..t only)
      w <- tryCatch(
        hd_min_var_weights(Sigma),
        error = function(e) NULL
      )

      if (is.null(w)) {
        oos_rets[i] <- NA_real_
        failed[i]   <- TRUE
        next
      }

      # OOS return at t+1 (first period NOT in training set)
      next_row <- returns[t + 1L, , drop = TRUE]
      if (any(is.na(next_row))) {
        oos_rets[i] <- NA_real_
        # Not a "failure" per se — OOS data is missing; don't count as failed
      } else {
        oos_rets[i] <- sum(w * next_row)
      }
    }

    n_failed   <- sum(failed)
    oos_finite <- oos_rets[!failed & !is.na(oos_rets)]
    n_oos      <- length(oos_finite)

    oos_mean   <- if (n_oos >= 1L) mean(oos_finite) else NA_real_
    oos_vol    <- if (n_oos >= 2L) stats::sd(oos_finite) else NA_real_
    oos_sharpe <- if (n_oos >= 2L && is.finite(oos_vol) && oos_vol > 0) {
      oos_mean / oos_vol * sqrt(12)
    } else NA_real_

    cond_finite   <- cond_nums[is.finite(cond_nums)]
    mean_cond   <- if (length(cond_finite) > 0L) mean(cond_finite)   else NA_real_
    median_cond <- if (length(cond_finite) > 0L) stats::median(cond_finite) else NA_real_

    cli::cli_inform(
      c("i" = paste0(
        "method={meth}: {n_oos} OOS returns, {n_failed} failed solve{?s}, ",
        "mean_cond={if (is.finite(mean_cond)) formatC(mean_cond, format='g', digits=4) else 'Inf/NA'}"
      ))
    )

    results_list[[meth]] <- tibble::tibble(
      method      = meth,
      n_oos       = n_oos,
      n_failed    = n_failed,
      oos_mean    = oos_mean,
      oos_vol     = oos_vol,
      oos_sharpe  = oos_sharpe,
      mean_cond   = mean_cond,
      median_cond = median_cond
    )
  }

  out <- dplyr::bind_rows(results_list)

  # ---- Attributes ------------------------------------------------------
  attr(out, "train_window") <- train_window
  attr(out, "n_periods")    <- n
  attr(out, "n_assets")     <- p

  out
}
