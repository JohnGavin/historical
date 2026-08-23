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

# ── Leaderboard-wide return alignment (#728 items 1+2) ──────────────────────
#
# strat_corr_matrix above (and the K_eff it feeds, strat_keff_vertox) is
# scoped to a 5-strategy FAMILY: stk_max, stk_drif, fac_max, fac_drif, ltr.
# #728 found that this family scope is what the leaderboard's
# `deflated_sharpe`/`dsr_pvalue`/k_eff columns actually correct for -- not
# the 17-strategy leaderboard itself -- which understates the true
# multiple-testing multiplicity for every strategy on the board.
#
# STRAT_RETURNS_WIDE_CODES names every strategy this widened alignment
# covers, using the same code_name vocabulary as port_returns/strat_cols
# above. Deliberately NOT all 17 leaderboard strategies -- two genuine,
# documented data constraints (#728 item 1: "if it is a genuine data
# constraint... say so precisely and leave those NA rather than fabricating
# inputs"):
#
#   1. DAILY-frequency strategies (CMR, OLMAR-1, TOM, Risk State, Avoid
#      Worst; ann_factor = 252 in STRATEGY_OBS_ANN_FACTOR,
#      R/plan_leaderboard.R) are excluded, same reason
#      strat_returns_aligned above already excludes avoid_worst/risk_state:
#      mixing daily and monthly series into one correlation matrix requires
#      an aggregation step that risks the look-ahead bias described in #215.
#      A future daily-frequency alignment target is a separate project.
#   2. PSO Optimal is excluded: it is not an independent data source. It is
#      port_optimal_weights %*% c(stk_max, stk_drif, fac_max, fac_drif) (see
#      the "PSO Optimal" block in plan_leaderboard.R's `leaderboard`
#      target) -- a linear combination of four series already in this
#      matrix. Including a near-collinear combination alongside its own
#      components adds no independent information and risks a near-singular
#      correlation matrix in hd_strat_keff_vertox()'s Cholesky step.
#
# That leaves 11 of 17 strategies covered here (up from the family's 4-5).
STRAT_RETURNS_WIDE_CODES <- c(
  "stk_max", "stk_drif", "fac_max", "fac_drif", "ltr", "xgb_drif",
  "mom_prepeak", "mom_postpeak", "mom_combined", "value_hml",
  "managed_futures"
)

#' Full-join a list of per-strategy return tables onto a common `ym` spine
#' (#728 items 1+2)
#'
#' Split out as a plain, unit-testable function for the same reason as
#' \code{.build_wide_corr_matrix()} below: it is the exact mechanism that
#' fixes the fail-loud-not-null.md "inner_join across strategy series"
#' defect for strat_returns_wide -- each element of \code{parts} is joined
#' with \code{dplyr::full_join(by = "ym")}, so a `ym` present in one part but
#' absent from another produces an NA cell for the missing part, never a
#' dropped row for the parts that DO have data that month.
#'
#' @param parts List of tibbles, each with a `ym` column plus exactly one
#'   strategy return column.
#' @return A single tibble with one `ym` column (the union of every part's
#'   `ym` values) plus one column per part.
#' @noRd
.full_join_return_spine <- function(parts) {
  Reduce(function(x, y) dplyr::full_join(x, y, by = "ym"), parts)
}


#' Correlation-aware effective-count matrix builder (#728 item 2)
#'
#' Shared by strat_corr_matrix_leaderboard below. Split out as a plain
#' function (rather than left inline in the tar_target()) so it is directly
#' unit-testable on synthetic data -- the embedded-in-tar_target() logic
#' elsewhere in this file has no test coverage today (grep confirms no
#' test file references strat_returns_aligned/strat_corr_matrix), and #728
#' item 2's leaderboard-wide correlation matrix is exactly the kind of
#' silent-NA-propagation risk fail-loud-not-null.md warns about.
#'
#' Uses `use = "pairwise.complete.obs"`, NOT a complete-case pre-filter,
#' because the caller's return table (strat_returns_wide) legitimately
#' contains NA where a strategy has no history for that month -- a
#' complete-case filter here would silently shrink the sample to the
#' shortest-history strategy's overlap window, the exact
#' fail-loud-not-null.md "inner_join across strategy series" defect shape,
#' just expressed as a filter instead of a join.
#'
#' @param ret_tbl Tibble with one column per strategy code_name (may contain
#'   NA) plus any other columns (e.g. `ym`); non-code_name columns are
#'   ignored.
#' @param cols Character vector of code_names (columns of `ret_tbl`) to
#'   include, subject to `min_obs` below.
#' @param min_obs Minimum non-NA observations required for a column to be
#'   included; columns below this are dropped rather than propagating NA
#'   into the correlation matrix.
#' @return A square, symmetric, unit-diagonal correlation matrix. Aborts
#'   (does not silently return NA cells) if a *pairwise* overlap between two
#'   included columns is too sparse for `stats::cor()` to compute a finite
#'   value -- see the fail-loud-not-null.md `cli_abort` requirement.
#' @noRd
.build_wide_corr_matrix <- function(ret_tbl, cols, min_obs = CORR_MIN_OBS) {
  enough_obs <- vapply(
    cols,
    function(col) sum(!is.na(ret_tbl[[col]])) >= min_obs,
    logical(1L)
  )
  cols <- cols[enough_obs]

  if (length(cols) < 2L) {
    cli::cli_abort(c(
      "x" = "Need at least 2 strategies with >= {min_obs} observations to compute the leaderboard-wide correlation matrix.",
      "i" = "Got {length(cols)} qualifying strategy/strategies: {paste(cols, collapse = ', ')}."
    ))
  }

  ret_mat <- as.matrix(ret_tbl[, cols, drop = FALSE])
  cor_mat <- stats::cor(ret_mat, use = "pairwise.complete.obs")
  rownames(cor_mat) <- cols
  colnames(cor_mat) <- cols

  if (anyNA(cor_mat)) {
    bad <- which(is.na(cor_mat), arr.ind = TRUE)
    bad_pairs <- unique(apply(bad, 1L, function(r) {
      paste(sort(cols[r]), collapse = " / ")
    }))
    cli::cli_abort(c(
      "x" = "Leaderboard-wide correlation matrix has {length(bad_pairs)} NA pairwise cell(s).",
      "i" = "Pair(s) with insufficient pairwise overlap: {paste(bad_pairs, collapse = '; ')}.",
      "i" = "stats::cor(use = 'pairwise.complete.obs') returns NA when two columns share fewer than 2 non-NA rows in common -- fix by widening the shared history or excluding the offending strategy (with a documented reason, per fail-loud-not-null.md), not by dropping the NA silently."
    ))
  }

  cor_mat
}

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
      # NOTE: port_returns\ is a synthetic ym-15 anchor (paste0(ym, "-15")),
      # while ltr_portfolio\ is the actual trading date from the parquet.
      # Joining on raw date produces an empty or near-empty result (#147/#215).
      # Fix: derive ym from both sides and join on ym; use port_returns\ as
      # the canonical date column.
      base <- port_returns |>
        select(ym, date, stk_max, stk_drif, fac_max, fac_drif) |>
        filter(!is.na(stk_max), !is.na(stk_drif),
               !is.na(fac_max), !is.na(fac_drif))

      # LTR momentum: derive ym for stable join key
      ltr_col <- ltr_portfolio |>
        filter(!is.na(port_ret)) |>
        mutate(ym = format(as.Date(date), "%Y-%m")) |>
        select(ym, ltr = port_ret)

      # Inner-join on ym (stable month key, not date) then drop ym
      aligned <- base |>
        inner_join(ltr_col, by = "ym") |>
        select(-ym) |>
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
    }),

    # ── Leaderboard-wide return alignment (#728 items 1+2) ───────────────────
    # Widens strat_returns_aligned's scope from 5 strategies to the 11 named
    # in STRAT_RETURNS_WIDE_CODES above. Deliberately uses full_join (spine =
    # union of every ym across all sources), NOT inner_join: an inner_join
    # across N series lets any one series' shorter history truncate every
    # other series to its overlap window -- the forbidden pattern in
    # .claude/rules/fail-loud-not-null.md ("One series' gap silently deletes
    # the period for all of them"). NA cells here are real (a strategy has
    # no return that month) and are handled downstream by
    # .build_wide_corr_matrix()'s pairwise-complete correlation, not by
    # dropping rows.
    targets::tar_target(strat_returns_wide, {
      library(dplyr)

      base <- port_returns |>
        select(ym, stk_max, stk_drif, fac_max, fac_drif) |>
        filter(if_any(c(stk_max, stk_drif, fac_max, fac_drif), ~ !is.na(.x)))

      # LTR: same ym-from-date derivation as strat_returns_aligned above.
      ltr_col <- ltr_portfolio |>
        filter(!is.na(port_ret)) |>
        mutate(ym = format(as.Date(date), "%Y-%m")) |>
        select(ym, ltr = port_ret)

      # XGB DRIF: xgb_drif_portfolio already carries ym (R/plan_xgb_signal.R
      # derives it from stk_monthly, same convention as port_returns).
      xgb_col <- xgb_drif_portfolio |>
        filter(!is.na(port_ret)) |>
        select(ym, xgb_drif = port_ret)

      # Mom Pre-Peak / Post-Peak / 12-2: returns tables key on exec_date
      # (the trade's actual execution date), not ym -- see
      # .mom_prepeak_compute_returns() in R/plan_mom_prepeak.R.
      mom_prepeak_col <- mom_prepeak_returns |>
        filter(!is.na(ret_ls)) |>
        mutate(ym = format(as.Date(exec_date), "%Y-%m")) |>
        select(ym, mom_prepeak = ret_ls)

      mom_postpeak_col <- mom_postpeak_returns |>
        filter(!is.na(ret_ls)) |>
        mutate(ym = format(as.Date(exec_date), "%Y-%m")) |>
        select(ym, mom_postpeak = ret_ls)

      mom_combined_col <- mom_combined_returns |>
        filter(!is.na(ret_ls)) |>
        mutate(ym = format(as.Date(exec_date), "%Y-%m")) |>
        select(ym, mom_combined = ret_ls)

      # Value (HML): ev_portfolios$ret_value_hml, keyed on date (R/plan_ev_ebit.R).
      value_hml_col <- ev_portfolios |>
        filter(!is.na(ret_value_hml)) |>
        mutate(ym = format(as.Date(date), "%Y-%m")) |>
        select(ym, value_hml = ret_value_hml)

      # Managed Futures: mf_portfolios$ret_ls (the canonical long-short MOP
      # 2012 series -- see mf_underperformance_periods's own comment,
      # R/plan_managed_futures.R), keyed on date.
      managed_futures_col <- mf_portfolios |>
        filter(!is.na(ret_ls)) |>
        mutate(ym = format(as.Date(date), "%Y-%m")) |>
        select(ym, managed_futures = ret_ls)

      parts <- list(
        base, ltr_col, xgb_col, mom_prepeak_col, mom_postpeak_col,
        mom_combined_col, value_hml_col, managed_futures_col
      )

      .full_join_return_spine(parts) |>
        arrange(ym)
    }),

    # ── Leaderboard-wide correlation matrix (#728 item 2 CONTRACT) ───────────
    # Same shape as strat_corr_matrix above (square, symmetric, unit
    # diagonal, code_name row/colnames) but scoped to
    # STRAT_RETURNS_WIDE_CODES instead of the 5-strategy family, and built
    # via .build_wide_corr_matrix() (pairwise-complete, NOT complete-case).
    targets::tar_target(strat_corr_matrix_leaderboard, {
      .build_wide_corr_matrix(
        strat_returns_wide, STRAT_RETURNS_WIDE_CODES, min_obs = CORR_MIN_OBS
      )
    }),

    # ── Leaderboard-wide Vertox K_eff (#728 items 1+2) ────────────────────────
    # Distinct from strat_keff_vertox (family-scoped, 5 strategies) above --
    # this is the number surfaced on the leaderboard as `k_eff_leaderboard`
    # (R/plan_leaderboard.R's strat_deflated_sharpe), named apart from the
    # family-scoped `k_eff_family` so no consumer can confuse "effective
    # tests within one family" with "effective tests across the whole
    # leaderboard" (#728's core finding). seed = 160 matches
    # strat_keff_vertox above for reproducibility (issue #160).
    targets::tar_target(strat_keff_vertox_leaderboard, {
      historicaldata::hd_strat_keff_vertox(
        strat_corr_matrix_leaderboard, n_sim = 20000L, seed = 160L
      )
    })
  )
}
