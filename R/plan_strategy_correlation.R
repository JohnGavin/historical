# Plan: Strategy Correlation Matrix, Redundancy Flag, and Incremental Sharpe
#
# Pillar 7 of issue #143 — addressed by #268.
#
# CONTRACT for downstream consumers (especially issue #160 K_eff / deflated Sharpe):
#   strat_corr_matrix: base R matrix
#     - Square, symmetric, diag = 1
#     - Dimensions: N x N where N = number of strategies with ≥12 observations of
#       monthly returns in the common (inner-joined) date window
#     - rownames and colnames: strategy code_names from strategy_names tibble
#       (e.g. "stk_max", "stk_drif", "fac_max", "fac_drif")
#     - Element [i, j]: Pearson correlation of monthly return series aligned on
#       common dates (inner join on date column, rows with any NA dropped)
#     - Computed over the "Full Period" common to all strategies (no partition filter)
#
# Three outputs consumed by plan_leaderboard (joined to leaderboard target):
#   strat_corr_augment: tibble with columns (strategy, correlation_max, redundant, incremental_sharpe)
#     - strategy      : character matching leaderboard$strategy labels
#     - correlation_max: max |r| with any other strategy (Pearson, Full Period)
#     - redundant     : TRUE if |r| >= REDUNDANCY_THRESH with ANY strategy that has
#                       a higher Sharpe (Full Period) — i.e. this strategy is the
#                       "redundant" / dominated one in a highly-correlated pair
#     - incremental_sharpe: Sharpe(equal-weight all N) − Sharpe(equal-weight N−1
#                       excluding this strategy). Positive = this strategy adds
#                       diversification value; negative = portfolio improves without it.

# ── Parameters ────────────────────────────────────────────────────────────────
# Minimum observations required before including a series in the correlation.
CORR_MIN_OBS  <- 12L
# Redundancy threshold: |r| >= this with a better-Sharpe peer → flag as redundant
REDUNDANCY_THRESH <- 0.80

plan_strategy_correlation <- function() {
  list(

    # ── Return series registry ─────────────────────────────────────────────────
    # Collects all per-strategy monthly return vectors into one tibble aligned on
    # date. Uses inner_join so only common dates are kept.
    # Each strategy contributes a column named by code_name.
    #
    # NOTE: port_returns already inner-joins the four core monthly strategies
    # (stk_max, stk_drif, fac_max, fac_drif); we start from there and augment with
    # any additional monthly strategies (ltr_portfolio). Daily-frequency strategies
    # (avoid_worst, risk_state) are deliberately excluded — mixing daily and monthly
    # series into a single monthly correlation matrix would require aggregation that
    # introduces the look-ahead bias described in #215. Daily-only strategies can be
    # included in a future target that aligns at daily frequency.
    targets::tar_target(strat_returns_aligned, {
      library(dplyr)

      # Core four strategies already aligned in port_returns.
      # Columns: ym, stk_max, stk_drif, fac_max, fac_drif, rf_ret, date
      base <- port_returns |>
        select(date, stk_max, stk_drif, fac_max, fac_drif) |>
        filter(!is.na(stk_max), !is.na(stk_drif),
               !is.na(fac_max), !is.na(fac_drif))

      # LTR momentum: port_ret column, Date-typed date
      ltr_col <- ltr_portfolio |>
        filter(!is.na(port_ret)) |>
        select(date, ltr = port_ret) |>
        mutate(date = as.Date(date))  # ensure Date type (#147/#215)

      # Inner-join: only periods where both series are available
      aligned <- base |>
        mutate(date = as.Date(date)) |>
        inner_join(ltr_col, by = "date") |>
        arrange(date)

      aligned
    }),

    # ── Correlation matrix (the strat_corr_matrix CONTRACT) ───────────────────
    # Square base R matrix. See CONTRACT comment at top of file.
    targets::tar_target(strat_corr_matrix, {

      ret_tbl <- strat_returns_aligned
      strat_cols <- c("stk_max", "stk_drif", "fac_max", "fac_drif", "ltr")

      # Drop any strategy with fewer than CORR_MIN_OBS non-NA observations
      enough_obs <- vapply(
        strat_cols,
        function(col) sum(!is.na(ret_tbl[[col]])) >= CORR_MIN_OBS,
        logical(1L)
      )
      strat_cols <- strat_cols[enough_obs]

      if (length(strat_cols) < 2L) {
        cli::cli_abort(c(
          "x" = "Need at least 2 strategies with >= {CORR_MIN_OBS} observations to compute correlation.",
          "i" = "Got {length(strat_cols)} qualifying strategies."
        ))
      }

      ret_mat <- ret_tbl |>
        select(all_of(strat_cols)) |>
        filter(if_all(everything(), ~ !is.na(.x))) |>
        as.matrix()

      cor_mat <- cor(ret_mat, use = "pairwise.complete.obs")

      # Ensure names are code_names (already set via column names)
      rownames(cor_mat) <- strat_cols
      colnames(cor_mat) <- strat_cols

      cor_mat
    }),

    # ── Augmentation: correlation_max, redundant flag, incremental Sharpe ─────
    # Returns a tibble keyed by the leaderboard strategy label (short_name) so
    # plan_leaderboard can left_join by "strategy" (which uses short/display names).
    targets::tar_target(strat_corr_augment, {
      library(dplyr)

      # Map from code_name to the leaderboard display label
      # (leaderboard uses "Factor MAX", "Factor DRIF", etc.)
      name_map <- tibble::tibble(
        code_name     = c("stk_max", "stk_drif", "fac_max", "fac_drif", "ltr"),
        strategy_label = c("Stock MAX", "Stock DRIF", "Factor MAX",
                            "Factor DRIF", "LTR")
      )

      strat_cols <- rownames(strat_corr_matrix)
      n_strat <- length(strat_cols)

      # ── Full-period Sharpe per strategy (recompute for alignment) ─────────
      full_rets <- strat_returns_aligned |>
        select(all_of(strat_cols)) |>
        filter(if_all(everything(), ~ !is.na(.x)))

      sharpe_full <- vapply(strat_cols, function(col) {
        r <- full_rets[[col]]
        r <- r[!is.na(r)]
        if (length(r) < 2L) return(NA_real_)
        ann <- annualise_returns(r, periods_per_year = 12L)
        ann$sharpe
      }, numeric(1L))
      names(sharpe_full) <- strat_cols

      # ── correlation_max: max |r| with any OTHER strategy ─────────────────
      corr_max <- vapply(strat_cols, function(s) {
        others <- setdiff(strat_cols, s)
        max(abs(strat_corr_matrix[s, others]))
      }, numeric(1L))
      names(corr_max) <- strat_cols

      # ── redundant flag: |r| >= REDUNDANCY_THRESH with a higher-Sharpe peer ──
      redundant <- vapply(strat_cols, function(s) {
        peers <- setdiff(strat_cols, s)
        any(vapply(peers, function(p) {
          high_corr <- abs(strat_corr_matrix[s, p]) >= REDUNDANCY_THRESH
          better    <- !is.na(sharpe_full[[p]]) && !is.na(sharpe_full[[s]]) &&
                       sharpe_full[[p]] > sharpe_full[[s]]
          high_corr && better
        }, logical(1L)))
      }, logical(1L))
      names(redundant) <- strat_cols

      # ── incremental Sharpe: Sharpe(all N) − Sharpe(all N minus this one) ──
      #
      # Definition: each strategy receives an equal weight (1/N). The portfolio
      # is formed from the full-period aligned return matrix. Incremental Sharpe
      # measures how much the equal-weight portfolio Sharpe changes when the
      # strategy is included vs excluded.
      #
      # Positive incremental Sharpe → strategy improves the portfolio.
      # Negative incremental Sharpe → portfolio is better without it.
      #
      # Uses annualise_returns() (from utils_metrics.R) for consistency with the
      # rest of the leaderboard (geometric CAGR / annualised vol).
      ret_mat <- as.matrix(full_rets[, strat_cols])

      sharpe_ew <- function(ret_matrix) {
        n_col <- ncol(ret_matrix)
        if (n_col < 1L) return(NA_real_)
        w <- rep(1 / n_col, n_col)
        port_ret <- as.numeric(ret_matrix %*% w)
        ann <- annualise_returns(port_ret, periods_per_year = 12L)
        ann$sharpe
      }

      sharpe_all <- sharpe_ew(ret_mat)

      incr_sharpe <- vapply(strat_cols, function(s) {
        excluded <- setdiff(strat_cols, s)
        if (length(excluded) < 1L) return(NA_real_)
        sharpe_excl <- sharpe_ew(ret_mat[, excluded, drop = FALSE])
        sharpe_all - sharpe_excl
      }, numeric(1L))
      names(incr_sharpe) <- strat_cols

      # ── Assemble result tibble ─────────────────────────────────────────────
      result <- tibble::tibble(
        code_name         = strat_cols,
        correlation_max   = round(corr_max,    3L),
        redundant         = redundant,
        incremental_sharpe = round(incr_sharpe, 3L)
      ) |>
        left_join(name_map, by = "code_name") |>
        # Expose by both code_name (for programmatic use) and strategy_label (for
        # leaderboard join)
        select(code_name, strategy_label, correlation_max, redundant, incremental_sharpe)

      result
    })
  )
}
