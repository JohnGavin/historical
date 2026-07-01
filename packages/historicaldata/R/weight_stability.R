#' Walk-forward weight-stability diagnostic across portfolio construction methods
#'
#' @title OOS Weight-Stability Diagnostic (`hd_weight_stability_diagnostic`)
#'
#' @description
#' Evaluates six portfolio construction methods in a walk-forward
#' out-of-sample (OOS) backtest, focusing on **weight stability** and OOS
#' performance. For each rolling training window (periods 1 through t), each
#' method's portfolio weights are computed and applied to the **next period's**
#' (t+1) realised returns to produce an OOS portfolio return.
#'
#' The diagnostic tests the central claim of the MVO-breakdown literature:
#' plug-in mean-variance (raw MVO) is an *error maximiser* that amplifies
#' estimation noise in expected returns, producing high turnover, concentrated
#' positions, and poor OOS Sharpe. Regularised alternatives (GMV, shrunk-mu,
#' Black-Litterman, HRP) are more stable.
#'
#' **Look-ahead discipline (mandatory):** weights are estimated exclusively from
#' data in the training window (periods 1 through t). The OOS return for each
#' origin t is the portfolio return at period t+1 — strictly the first period
#' *not* in the training set. The function never reads `returns[t+1, ]` when
#' constructing weights. This mirrors the `alpha-decay-min-t+1` rule.
#'
#' **Methods compared:**
#' * **`raw_mvo`** — Plug-in tangency portfolio `w ∝ Σ⁻¹μ` using **sample** Σ
#'   and **sample** μ (the article's error-maximiser worst case). Fails
#'   with high frequency when p ≥ train_window (singular sample Σ).
#' * **`gmv`** — Global minimum-variance `w ∝ Σ⁻¹1` via [hd_min_var_weights()]
#'   using a regularised Σ from [hd_cov_estimate()]. No expected-return input.
#' * **`shrunk_mu`** — Tangency portfolio using Bayes-Stein (James-Stein / Jorion
#'   1986) shrinkage on μ via [hd_returns_shrink()] with `method = "james_stein"`
#'   and a regularised Σ. Documented method choice: `"james_stein"` (data-driven
#'   shrinkage intensity, no tuning required).
#' * **`black_litterman`** — Tangency portfolio from the Black-Litterman (1992)
#'   posterior μ̂ and Σ\_BL using [hd_black_litterman()]. No investor views
#'   (P = NULL); posterior collapses to the equilibrium prior Π = λ·Σ·w\_mkt.
#'   Documented defaults: `w_mkt = 1/p` (equal weight) and `risk_aversion = 2.5`.
#'   Theoretical result: BL with equal w\_mkt and no views yields approximately
#'   equal-weight tangency weights (Σ\_BL⁻¹Π ∝ w\_mkt).
#' * **`equal_weight`** — 1/N portfolio (the robust benchmark). Zero turnover
#'   by construction.
#' * **`hrp`** — Hierarchical Risk Parity via [hrp_weights()]. Diversification
#'   without expected-return estimation.
#'
#' @param returns A numeric matrix or data frame with rows in **chronological
#'   order** and one column per asset. If a data frame, a column named `"date"`
#'   (case-insensitive) is silently dropped. All remaining columns must be
#'   numeric. Incomplete rows within each training window are dropped before
#'   estimation.
#' @param methods Character vector of weight methods to compare. Must be a
#'   non-empty subset of
#'   `c("raw_mvo", "gmv", "shrunk_mu", "black_litterman", "equal_weight", "hrp")`.
#'   Default: all six methods.
#' @param train_window Integer scalar. Number of periods in each rolling
#'   training window. Default `60L` (5 years of monthly data). Must satisfy
#'   `nrow(returns) > train_window + 1`. For raw_mvo the sample covariance is
#'   singular when `ncol(returns) >= train_window` — those windows are counted
#'   as `n_failed`.
#' @param cov_method Covariance estimator for the regularised Σ used by `gmv`,
#'   `shrunk_mu`, `black_litterman`, and `hrp`. Passed to [hd_cov_estimate()].
#'   Default `"ledoit_wolf"`. One of `"sample"`, `"ledoit_wolf"`,
#'   `"rmt_denoise"`, `"threshold"`.
#' @param ... Reserved for future arguments. Currently unused.
#'
#' @return A [tibble::tibble()] with one row per requested method and columns:
#'   \describe{
#'     \item{`method`}{Character — weight method name.}
#'     \item{`n_oos`}{Integer — number of OOS periods with non-NA portfolio
#'       returns (windows where weight construction succeeded and the OOS
#'       return row is complete).}
#'     \item{`n_failed`}{Integer — number of windows where weight construction
#'       failed (e.g. singular sample Σ for `raw_mvo`; solve failure for
#'       tangency methods). Failed windows produce `NA` OOS returns and are
#'       excluded from all other metrics.}
#'     \item{`oos_mean`}{Numeric — mean non-NA OOS portfolio return.}
#'     \item{`oos_vol`}{Numeric — standard deviation of non-NA OOS portfolio
#'       returns.}
#'     \item{`oos_sharpe`}{Numeric — annualised Sharpe ratio
#'       (`mean / sd * sqrt(12)`) over non-NA OOS returns. `NA` if fewer than
#'       2 non-NA OOS returns.}
#'     \item{`avg_turnover`}{Numeric — mean L1 weight change between consecutive
#'       non-failed windows: mean(‖w\_t − w\_{t-1}‖₁). The article's primary
#'       instability metric. `NA` if fewer than 2 non-failed windows.}
#'     \item{`max_abs_weight`}{Numeric — mean across non-failed windows of the
#'       largest absolute weight: mean(max|w\_j|). Measures concentration.
#'       Equal-weight → 1/p; raw_mvo → values often >1 (short positions).}
#'     \item{`mean_eff_n`}{Numeric — mean effective number of holdings
#'       (1/Σw\_j²) across non-failed windows. Herfindahl-based diversification
#'       measure. Equal-weight → p; concentrated → near 1.}
#'   }
#'   The returned tibble carries four attributes:
#'   \describe{
#'     \item{`train_window`}{The `train_window` argument value.}
#'     \item{`n_periods`}{Total number of rows in the returns matrix.}
#'     \item{`n_assets`}{Number of assets (columns).}
#'     \item{`cov_method`}{The covariance method used for regularised Σ.}
#'   }
#'
#' @references
#' Michaud, R. O. (1989). The Markowitz optimization enigma: Is 'optimized'
#' optimal? *Financial Analysts Journal*, 45(1), 31–42.
#' \doi{10.2469/faj.v45.n1.31}
#'
#' Jorion, P. (1986). Bayes-Stein Estimation for Portfolio Analysis.
#' *Journal of Financial and Quantitative Analysis*, 21(3), 279–292.
#' \doi{10.2307/2331042}
#'
#' Black, F. & Litterman, R. (1992). Global Portfolio Optimization.
#' *Financial Analysts Journal*, 48(5), 28–43.
#' \doi{10.2469/faj.v48.n5.28}
#'
#' Lopez de Prado, M. (2016). Building diversified portfolios that outperform
#' out-of-sample. *Journal of Portfolio Management*, 42(4), 59–69.
#' \doi{10.3905/jpm.2016.42.4.059}
#'
#' DeMiguel, V., Garlappi, L. & Uppal, R. (2009). Optimal versus naive
#' diversification: How inefficient is the 1/N portfolio strategy?
#' *Review of Financial Studies*, 22(5), 1915–1953.
#' \doi{10.1093/rfs/hhm075}
#'
#' @family covariance
#' @export
#'
#' @examples
#' set.seed(42)
#' X <- matrix(rnorm(120 * 6), nrow = 120, ncol = 6)
#' colnames(X) <- paste0("A", seq_len(6))
#' result <- hd_weight_stability_diagnostic(X, train_window = 60L)
#' result[, c("method", "n_oos", "avg_turnover", "oos_sharpe")]
hd_weight_stability_diagnostic <- function(
    returns,
    methods = c(
      "raw_mvo", "gmv", "shrunk_mu", "black_litterman",
      "equal_weight", "hrp"
    ),
    train_window = 60L,
    cov_method   = "ledoit_wolf",
    ...
) {

  # ---- Valid method registry -------------------------------------------
  valid_methods <- c(
    "raw_mvo", "gmv", "shrunk_mu", "black_litterman",
    "equal_weight", "hrp"
  )

  # ---- Input validation ------------------------------------------------
  if (!is.matrix(returns) && !is.data.frame(returns)) {
    cli::cli_abort(
      c(
        "{.arg returns} must be a numeric matrix or data frame.",
        "x" = "Got {.cls {class(returns)}}."
      )
    )
  }

  # Coerce data frame: drop date column, convert to matrix
  if (is.data.frame(returns)) {
    date_col <- which(tolower(names(returns)) == "date")
    if (length(date_col) > 0L) {
      returns <- returns[, -date_col, drop = FALSE]
    }
    asset_names_from_df <- names(returns)
    returns <- as.matrix(returns)
    colnames(returns) <- asset_names_from_df
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
        "i" = paste0(
          "Require nrow(returns) > train_window + 1 ",
          "(training window + at least 1 OOS period)."
        )
      )
    )
  }

  if (!is.character(methods) || length(methods) < 1L) {
    cli::cli_abort(
      "{.arg methods} must be a non-empty character vector."
    )
  }

  bad_methods <- setdiff(methods, valid_methods)
  if (length(bad_methods) > 0L) {
    cli::cli_abort(
      c(
        "Unknown weight method{?s}: {.val {bad_methods}}.",
        "i" = "Valid methods: {.val {valid_methods}}."
      )
    )
  }

  cov_method <- match.arg(
    cov_method,
    c("sample", "ledoit_wolf", "rmt_denoise", "threshold")
  )

  # ---- Asset names --------------------------------------------------------
  asset_names <- colnames(returns)
  if (is.null(asset_names)) {
    asset_names <- paste0("A", seq_len(p))
    colnames(returns) <- asset_names
  }

  # ---- Walk-forward setup -------------------------------------------------
  # Origins: t = train_window, ..., n-1 (1-indexed last training row)
  # Training window for origin t: rows (t - train_window + 1) through t
  # OOS return: row t+1 (NEVER read before weights are computed)
  n_origins <- n - train_window

  # Pre-allocate storage per method
  weights_store  <- setNames(
    lapply(methods, function(m) matrix(NA_real_, nrow = n_origins, ncol = p)),
    methods
  )
  oos_rets_store <- setNames(
    lapply(methods, function(m) rep(NA_real_, n_origins)),
    methods
  )
  failed_store   <- setNames(
    lapply(methods, function(m) rep(FALSE, n_origins)),
    methods
  )

  # Which methods require a regularised covariance matrix?
  needs_reg_sigma <- c("gmv", "shrunk_mu", "black_litterman", "hrp")

  # ---- Walk-forward loop --------------------------------------------------
  for (i in seq_len(n_origins)) {

    # Last training row (1-indexed)
    t <- train_window + i - 1L

    # Training data: rows (t - train_window + 1) through t — NO look-ahead
    train_rows <- seq.int(t - train_window + 1L, t)
    train_mat  <- returns[train_rows, , drop = FALSE]

    # Drop incomplete rows within the training window
    cc <- stats::complete.cases(train_mat)
    train_cc   <- train_mat[cc, , drop = FALSE]
    n_train_cc <- nrow(train_cc)

    # OOS return at t+1 — read only for evaluation, never for weight construction
    # (This assignment happens AFTER the training subset is defined to make
    #  the look-ahead discipline explicit in code layout.)
    next_row <- returns[t + 1L, , drop = TRUE]

    # Regularised covariance (computed once per origin, shared across methods)
    Sigma_reg <- NULL
    if (any(needs_reg_sigma %in% methods) && n_train_cc >= 2L) {
      Sigma_reg <- tryCatch(
        suppressWarnings(
          hd_cov_estimate(train_cc, method = cov_method)
        ),
        error = function(e) NULL
      )
      # Ensure consistent dimnames for hrp_weights()
      if (!is.null(Sigma_reg)) {
        colnames(Sigma_reg) <- rownames(Sigma_reg) <- asset_names
      }
    }

    # Sample covariance for raw_mvo (no regularisation — the instability source)
    Sigma_sample <- NULL
    if ("raw_mvo" %in% methods && n_train_cc >= 2L) {
      Sigma_sample <- tryCatch(
        stats::cov(train_cc),
        error = function(e) NULL
      )
    }

    # Compute weights for each method at this origin
    for (meth in methods) {

      w <- tryCatch({
        switch(meth,

          raw_mvo = {
            # Plug-in tangency: w ∝ Sigma_sample⁻¹ · mu_sample
            # The article's "error maximiser" — no regularisation on Sigma or mu
            if (is.null(Sigma_sample) || n_train_cc < 2L) {
              stop("insufficient complete training observations for sample cov")
            }
            mu_s <- colMeans(train_cc)
            .wstab_tangency(Sigma_sample, mu_s)
          },

          gmv = {
            # Global minimum-variance via regularised Sigma (no mu needed)
            if (is.null(Sigma_reg)) {
              stop("regularised covariance estimation failed or insufficient data")
            }
            hd_min_var_weights(Sigma_reg)
          },

          shrunk_mu = {
            # Tangency with James-Stein shrinkage on mu + regularised Sigma
            # Method choice: "james_stein" (Jorion 1986) — data-driven intensity,
            # no tuning required, consistent with portfolio-level regularisation
            if (is.null(Sigma_reg) || n_train_cc < 2L) {
              stop("regularised covariance estimation failed or insufficient data")
            }
            mu_s <- colMeans(train_cc)
            mu_sh <- hd_returns_shrink(
              mu_s,
              method = "james_stein",
              sigma  = Sigma_reg,
              n_obs  = n_train_cc
            )
            .wstab_tangency(Sigma_reg, mu_sh)
          },

          black_litterman = {
            # BL tangency with equal-weight market portfolio and no views
            # Documented defaults:
            #   w_mkt = 1/p (equal weight — documented; no market-cap data assumed)
            #   risk_aversion = 2.5 (explicit, suppresses the info message)
            # No-views result: posterior_mu = Π = λΣw_mkt, so
            #   tangency w ∝ Σ_BL⁻¹Π = ((1+τ)Σ)⁻¹λΣw_mkt ∝ w_mkt (= equal weight)
            # This is mathematically expected and documented in hd_black_litterman().
            if (is.null(Sigma_reg)) {
              stop("regularised covariance estimation failed or insufficient data")
            }
            w_mkt_eq <- setNames(rep(1 / p, p), asset_names)
            bl <- hd_black_litterman(
              sigma         = Sigma_reg,
              w_mkt         = w_mkt_eq,
              risk_aversion = 2.5
            )
            .wstab_tangency(bl$posterior_sigma, bl$posterior_mu)
          },

          equal_weight = {
            # 1/N — the robust benchmark; zero turnover by construction
            setNames(rep(1 / p, p), asset_names)
          },

          hrp = {
            # Hierarchical Risk Parity (Lopez de Prado 2016)
            if (is.null(Sigma_reg)) {
              stop("regularised covariance estimation failed or insufficient data")
            }
            w_hrp <- hrp_weights(Sigma_reg)
            # Align to asset_names order (hrp_weights preserves Sigma rownames)
            w_hrp[asset_names]
          }
        )
      }, error = function(e) NULL)

      # Count as failed if weights are NULL or contain non-finite values
      if (is.null(w) || !all(is.finite(w))) {
        failed_store[[meth]][i] <- TRUE
        next  # weights_store and oos_rets_store remain NA for this origin
      }

      # Store weights (used later for turnover + concentration metrics)
      weights_store[[meth]][i, ] <- w

      # OOS portfolio return at t+1 (first period NOT in training set)
      # Only stored when OOS row is complete — missing OOS is not a weight failure
      if (all(is.finite(next_row))) {
        oos_rets_store[[meth]][i] <- sum(w * next_row)
      }
    }
  }

  # ---- Summary statistics per method ------------------------------------
  results_list <- vector("list", length(methods))
  names(results_list) <- methods

  for (meth in methods) {

    wts  <- weights_store[[meth]]    # n_origins × p
    ors  <- oos_rets_store[[meth]]   # n_origins
    fail <- failed_store[[meth]]     # logical n_origins

    n_failed <- sum(fail)

    # OOS performance on non-failed, non-NA returns
    oos_ok   <- ors[!fail & !is.na(ors)]
    n_oos    <- length(oos_ok)

    oos_mean   <- if (n_oos >= 1L) mean(oos_ok)          else NA_real_
    oos_vol    <- if (n_oos >= 2L) stats::sd(oos_ok)      else NA_real_
    oos_sharpe <- if (n_oos >= 2L && is.finite(oos_vol) && oos_vol > 0) {
      oos_mean / oos_vol * sqrt(12)
    } else NA_real_

    # Weight stability metrics: only over non-failed windows
    ok_idx <- which(!fail)
    wts_ok <- wts[ok_idx, , drop = FALSE]
    n_ok   <- nrow(wts_ok)

    # avg_turnover: mean L1 weight change between consecutive non-failed windows
    # ‖w_t − w_{t-1}‖₁ = sum(|w_t − w_{t-1}|)
    avg_turnover <- if (n_ok >= 2L) {
      diffs <- abs(
        wts_ok[-1L,         , drop = FALSE] -
        wts_ok[-n_ok, , drop = FALSE]
      )
      mean(rowSums(diffs))
    } else NA_real_

    # max_abs_weight: mean across windows of max|w_j|
    max_abs_weight <- if (n_ok >= 1L) {
      mean(apply(abs(wts_ok), 1L, max))
    } else NA_real_

    # mean_eff_n: mean of 1/sum(w_j²) — effective number of holdings (Herfindahl)
    mean_eff_n <- if (n_ok >= 1L) {
      eff_ns <- apply(wts_ok^2, 1L, function(x) {
        s <- sum(x)
        if (is.finite(s) && s > 0) 1 / s else NA_real_
      })
      finite_ens <- eff_ns[is.finite(eff_ns)]
      if (length(finite_ens) >= 1L) mean(finite_ens) else NA_real_
    } else NA_real_

    cli::cli_inform(
      c("i" = paste0(
        "method=", meth, ": ", n_oos, " OOS, ", n_failed, " failed, ",
        "avg_turnover=",
        if (is.finite(avg_turnover)) formatC(avg_turnover, format = "f", digits = 4)
        else "NA",
        ", max_w=",
        if (is.finite(max_abs_weight)) formatC(max_abs_weight, format = "f", digits = 4)
        else "NA"
      ))
    )

    results_list[[meth]] <- tibble::tibble(
      method         = meth,
      n_oos          = n_oos,
      n_failed       = n_failed,
      oos_mean       = oos_mean,
      oos_vol        = oos_vol,
      oos_sharpe     = oos_sharpe,
      avg_turnover   = avg_turnover,
      max_abs_weight = max_abs_weight,
      mean_eff_n     = mean_eff_n
    )
  }

  out <- dplyr::bind_rows(results_list)

  # ---- Attributes -------------------------------------------------------
  attr(out, "train_window") <- train_window
  attr(out, "n_periods")    <- n
  attr(out, "n_assets")     <- p
  attr(out, "cov_method")   <- cov_method

  out
}

# ---------------------------------------------------------------------------
# Internal helper: unconstrained tangency portfolio weights
# ---------------------------------------------------------------------------

# Computes the tangency portfolio w ∝ Sigma⁻¹ mu, normalised to sum to 1.
#
# Uses solve(Sigma, mu) (one linear solve) rather than explicit inversion.
# Returns NULL when:
#   - solve() fails (singular or ill-conditioned Sigma)
#   - the denominator 1'Sigma⁻¹mu ≈ 0 (degenerate, no finite tangency portfolio)
#   - the resulting weights are non-finite
#
# Note: tangency weights can be negative (unconstrained long-short portfolio).
# This is intentional for raw_mvo where short positions amplify instability.
#
#' @noRd
.wstab_tangency <- function(Sigma, mu) {
  # Solve Sigma w_raw = mu (equivalent to w_raw = Sigma⁻¹ mu)
  w_raw <- tryCatch(
    solve(Sigma, mu),
    error = function(e) NULL
  )
  if (is.null(w_raw)) return(NULL)

  denom <- sum(w_raw)
  if (!is.finite(denom) || abs(denom) < .Machine$double.eps^0.5) {
    return(NULL)
  }

  w <- w_raw / denom
  if (!all(is.finite(w))) return(NULL)

  names(w) <- names(mu)
  w
}
