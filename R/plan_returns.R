# Phase B of #389 — per-asset monthly returns + covariance infrastructure
#
# Provides three targets consumed by phase B and downstream phases:
#
#   asset_monthly_returns      — long tibble (date, ticker, ret)
#   asset_monthly_returns_wide — wide tibble (date, SPY, TLT, GLD, DBC, ...)
#   cov_annual                 — annualised covariance matrix (n_assets × n_assets)
#   cov_rolling_60m            — list of 60-month rolling covariance matrices
#
# Asset universe: SPY (US equity), TLT (long bonds), GLD (gold), DBC (commodities).
# Sourced via hd_ohlcv() → adjusted_close column (canonical post-#325 name).
#
# Design choices documented here (ambiguities flagged for PR review):
#   [CHOICE A] Universe is {SPY, TLT, GLD, DBC}. Matches what plan_cross_asset_corr.R
#              already references. Smallest set that spans equity/bond/commodity/currency
#              without adding illiquid assets. Expand in Phase C if needed.
#   [CHOICE B] Monthly returns = simple (arithmetic) returns from last-trading-day
#              adjusted_close per month. Consistent with plan_backtest.R and
#              plan_strategy_correlation.R. Log returns would differ by ~1 bps/month.
#   [CHOICE C] cov_annual is computed over the FULL common-date window (inner join).
#              No start-date filter: use all available history, let the min-obs gate
#              catch short samples. Change to a fixed window in Phase C if needed.
#   [CHOICE D] Rolling window = 60 months. Matches audit spec.
#   [CHOICE E] Annualisation factor = 12 (monthly → annual). Scales both variance and
#              covariance by 12 (not by sqrt(12) — covariance scales linearly with
#              time under iid assumption; sqrt scaling would apply only to vol).

# ── Constants ──────────────────────────────────────────────────────────────────

# Minimum fraction of non-NA observations required in a rolling window.
# 60m × 0.7 = 42 months minimum; below that, window returns NA matrix.
RETURNS_ROLL_MIN_FRAC <- 0.70

# Minimum absolute observations for the full-sample covariance.
RETURNS_MIN_OBS <- 24L

# Asset universe for Phase B cross-asset analysis.
RETURNS_ASSETS <- c("SPY", "TLT", "GLD", "DBC")

# Monthly periods per year.
PERIODS_PER_YEAR <- 12L

plan_returns <- function() {
  list(

    # ── Long monthly returns per asset ────────────────────────────────────────
    #
    # Returns last-trading-day adjusted_close per month, then computes simple
    # return. Typed date discipline (#453): as.Date() applied to the date
    # column from hd_ohlcv() before any filter or join.
    targets::tar_target(asset_monthly_returns, {
      library(dplyr)

      raw <- hd_ohlcv(RETURNS_ASSETS, collect = TRUE) |>
        dplyr::mutate(date = as.Date(date))

      raw |>
        dplyr::mutate(ym = format(date, "%Y-%m")) |>
        dplyr::group_by(ticker, ym) |>
        dplyr::filter(date == max(date)) |>
        dplyr::ungroup() |>
        dplyr::select(ticker, date, adjusted_close) |>
        dplyr::arrange(ticker, date) |>
        dplyr::group_by(ticker) |>
        dplyr::mutate(ret = adjusted_close / dplyr::lag(adjusted_close) - 1) |>
        dplyr::filter(!is.na(ret)) |>
        dplyr::ungroup() |>
        dplyr::select(ticker, date, ret)
    }),

    # ── Wide monthly returns (one column per asset) ───────────────────────────
    #
    # Inner-joins all assets on date so every row has a complete observation.
    # This is the canonical feed for plan_cross_asset_corr.R's multi_asset_returns.
    targets::tar_target(asset_monthly_returns_wide, {
      library(dplyr)

      asset_monthly_returns |>
        tidyr::pivot_wider(names_from = ticker, values_from = ret) |>
        # Drop any row where ANY asset is NA (ensures cov() gets complete cases)
        dplyr::filter(if (ncol(dplyr::select(., -date)) > 0)
          rowSums(is.na(dplyr::select(., -date))) == 0
          else TRUE) |>
        dplyr::arrange(date)
    }),

    # ── Full-sample annualised covariance matrix ──────────────────────────────
    #
    # Σ_annual = 12 × Σ_monthly (linear scaling under iid; monthly returns).
    # Positive semi-definiteness: verified via eigenvalue check in tests.
    # Symmetry: enforced by (Σ + t(Σ)) / 2 after computation.
    targets::tar_target(cov_annual, {
      wide <- asset_monthly_returns_wide
      asset_cols <- setdiff(colnames(wide), "date")

      n_obs <- nrow(wide)
      if (n_obs < RETURNS_MIN_OBS) {
        cli::cli_abort(c(
          "x" = "cov_annual requires at least {RETURNS_MIN_OBS} complete observations.",
          "i" = "Got {n_obs} rows in asset_monthly_returns_wide."
        ))
      }

      ret_mat <- as.matrix(wide[, asset_cols])

      # Compute monthly covariance then annualise
      Sigma_monthly <- stats::cov(ret_mat, use = "complete.obs")

      # Enforce symmetry numerically (floating-point drift)
      Sigma_annual  <- PERIODS_PER_YEAR * ((Sigma_monthly + t(Sigma_monthly)) / 2)

      rownames(Sigma_annual) <- asset_cols
      colnames(Sigma_annual) <- asset_cols

      Sigma_annual
    }),

    # ── Rolling 60-month covariance sequence ──────────────────────────────────
    #
    # Returns a named list of length nrow(asset_monthly_returns_wide), where
    # element [[i]] is:
    #   - the annualised covariance matrix for the 60-month window ending at row i
    #     (if that window has >= 60 * RETURNS_ROLL_MIN_FRAC complete rows)
    #   - NULL otherwise (window has too few observations)
    #
    # The list is named by the date of the last row in each window.
    # This structure lets downstream code extract a specific window by date:
    #   cov_rolling_60m[["2020-12-31"]]
    #
    # Uses slider::slide() for right-aligned windows consistent with
    # roll_mean_safe() / roll_sd_safe() patterns in utils_rolling.R.
    targets::tar_target(cov_rolling_60m, {
      library(dplyr)

      wide       <- asset_monthly_returns_wide
      asset_cols <- setdiff(colnames(wide), "date")
      dates      <- wide$date
      ret_mat    <- as.matrix(wide[, asset_cols])

      window_n   <- 60L
      min_obs    <- ceiling(RETURNS_ROLL_MIN_FRAC * window_n)

      cov_list <- slider::slide(
        seq_len(nrow(ret_mat)),
        function(row_idx) {
          window <- ret_mat[row_idx, , drop = FALSE]
          # Count complete rows (no NA in any asset column)
          n_complete <- sum(rowSums(is.na(window)) == 0L)
          if (n_complete < min_obs) return(NULL)

          # Use complete-observation rows only
          window_cc  <- window[rowSums(is.na(window)) == 0L, , drop = FALSE]
          Sigma_m    <- stats::cov(window_cc, use = "complete.obs")
          Sigma_ann  <- PERIODS_PER_YEAR * ((Sigma_m + t(Sigma_m)) / 2)
          rownames(Sigma_ann) <- asset_cols
          colnames(Sigma_ann) <- asset_cols
          Sigma_ann
        },
        .before = window_n - 1L,
        .complete = FALSE
      )

      # Name by end-of-window date for indexing
      names(cov_list) <- as.character(dates)

      cov_list
    }),

    # ── Phase E: Historical monthly CPI changes (FRED CPIAUCSL) ──────────────
    #
    # Block-bootstrap pool for per-path-year CPI draws in hd_simulate_paths().
    # Returns a numeric vector of month-over-month CPI changes, filtered to
    # complete (non-NA) observations.
    targets::tar_target(cpi_monthly_changes, {
      library(dplyr)

      cpi_raw <- hd_lazy("macro_daily") |>
        dplyr::filter(.data$series_id == "CPIAUCSL") |>
        dplyr::mutate(date = as.Date(date)) |>
        dplyr::collect() |>
        dplyr::arrange(date) |>
        dplyr::mutate(ym = format(date, "%Y-%m")) |>
        dplyr::group_by(ym) |>
        dplyr::filter(date == max(date)) |>
        dplyr::ungroup() |>
        dplyr::select(date, value) |>
        dplyr::arrange(date)

      cpi_mom <- cpi_raw$value / dplyr::lag(cpi_raw$value) - 1
      cpi_mom[!is.na(cpi_mom)]
    }),

    # ── Phase C: Multivariate return simulation (#389) ───────────────────────
    #
    # 500 paths × 30 years, parametric (mvrnorm), fed by Phase B covariance.
    # Phase E: passes .cpi_monthly for block-bootstrapped CPI deflation.
    targets::tar_target(simulate_paths, {
      hd_simulate_paths(
        n_paths       = 500L,
        horizon_years = 30L,
        assets        = RETURNS_ASSETS,
        Sigma         = cov_annual,
        .returns_wide = asset_monthly_returns_wide,
        .cpi_monthly  = cpi_monthly_changes,
        method        = "parametric",
        seed          = 42L
      )
    }),

    # ── Phase D: Quantile fan (nominal) ──────────────────────────────────────
    targets::tar_target(path_quantiles, {
      hd_path_quantiles(simulate_paths, metric = "cum_nominal")
    }),

    # ── Phase D: Quantile fan (real) ─────────────────────────────────────────
    targets::tar_target(path_quantiles_real, {
      hd_path_quantiles(simulate_paths, metric = "cum_real")
    })
  )
}
