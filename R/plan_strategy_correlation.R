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

# ── Leaderboard-wide return alignment (#728 items 1+2, widened by #733) ─────
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
# above. #728 items 1+2 widened this from the 5-strategy family to 11 of 17
# by adding every OTHER monthly-frequency strategy. #733 widens it further
# to 16 of 17 by folding in the five DAILY-frequency strategies (CMR,
# OLMAR-1, TOM, Risk State, Avoid Worst; ann_factor = 252 in
# STRATEGY_OBS_ANN_FACTOR, R/plan_leaderboard.R) via monthly resampling --
# see strat_returns_daily_native and .resample_daily_to_monthly() below.
#
# Chosen mixed-frequency-spine design (#733, over the alternative of a
# separate daily spine combined post hoc): a single K_eff computed across
# every strategy the leaderboard actually ranks is a more faithful
# multiple-testing count than two K_effs that would need combining after
# the fact, and #728's own complaint was precisely that a narrower scope
# understates the true multiplicity. The five daily series are compounded
# to monthly (prod(1 + daily_ret) - 1 within each calendar month) and
# joined onto the SAME `ym` spine as the 11 already-monthly strategies --
# see .resample_daily_to_monthly()'s roxygen for why this does NOT
# reintroduce the #215 look-ahead-bias risk the pre-#733 comment here used
# to cite as the reason for excluding daily strategies outright: compounding
# ALREADY-REALISED daily returns into a monthly total is accounting, not a
# new signal-timing decision, so no future information crosses into an
# earlier trade.
#
# Only ONE genuine, documented exclusion remains after #733:
#
#   PSO Optimal is excluded: it is not an independent data source. It is
#   port_optimal_weights %*% c(stk_max, stk_drif, fac_max, fac_drif) (see
#   the "PSO Optimal" block in plan_leaderboard.R's `leaderboard`
#   target) -- a linear combination of four series already in this
#   matrix. Including a near-collinear combination alongside its own
#   components adds no independent information and risks a near-singular
#   correlation matrix in hd_strat_keff_vertox()'s Cholesky step.
#
# That leaves 16 of 17 strategies covered here (up from 11 after #728, and
# 4-5 in the original family).
STRAT_RETURNS_WIDE_CODES <- c(
  "stk_max", "stk_drif", "fac_max", "fac_drif", "ltr", "xgb_drif",
  "mom_prepeak", "mom_postpeak", "mom_combined", "value_hml",
  "managed_futures",
  # ── #733: daily strategies, monthly-resampled ──
  "cmr", "olmar_1", "tom", "risk_state", "avoid_worst"
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


#' Resample a daily return series to monthly by compounding within each
#' calendar month (#733 mixed-frequency spine)
#'
#' Extends the leaderboard-wide correlation spine (STRAT_RETURNS_WIDE_CODES)
#' to the five daily-frequency strategies (CMR, OLMAR-1, TOM, Risk State,
#' Avoid Worst) by converting each one's daily return series to a monthly
#' return series that can join the existing `ym` spine alongside the
#' already-monthly strategies. The conversion is plain compounding of
#' ALREADY-REALISED returns (\code{prod(1 + r) - 1} within each calendar
#' month) -- not a new signal or trading decision -- so it does not
#' reintroduce the #215 look-ahead-bias risk the pre-#733 STRAT_RETURNS_WIDE
#' comment cited as the reason daily strategies were excluded outright: no
#' information from later in the month is used to inform an earlier trade,
#' the month's return is simply re-stated at monthly granularity.
#'
#' Partial months (fewer than \code{min_days} trading-day observations) are
#' EXCLUDED from the output rather than silently compounded with whatever
#' days happen to be present. This is the fail-loud-not-null.md discipline
#' applied to a periodicity transformation (see that rule's "unexpected
#' value silently coerced" defect class, #637/#640/#641/#643, and its
#' explicit warning against exactly this kind of resampling going wrong): an
#' incomplete month's compounded return LOOKS like a normal monthly
#' observation but is actually built from a fraction of the month's trading
#' days, understating (or overstating) the true monthly move. Exclusions are
#' never silent -- \code{cli::cli_inform()} names every excluded month and
#' its day count so a reviewer can see exactly what was dropped and why,
#' satisfying the rule's "the drop must be observable" requirement.
#'
#' @param dates Date vector (or coercible via \code{as.Date()}), one entry
#'   per daily observation.
#' @param rets Numeric return vector, same length as \code{dates}, one entry
#'   per trading day. Entries where either `dates` or `rets` is `NA` are
#'   treated as no-observation days: excluded from both the compounding and
#'   the day count for that calendar month (never silently coerced into a
#'   0% contribution, which would understate the month's volatility).
#' @param min_days Minimum non-NA trading-day observations required in a
#'   calendar month for it to be included in the output (default `15L` --
#'   roughly 3/4 of a typical ~19-23 trading-day month; catches partial
#'   first/last months of a series without over-trimming genuinely short-
#'   but-complete months, e.g. a December with several holiday closures).
#' @param label Strategy label used only in the \code{cli_inform()} message,
#'   so a reviewer can tell which strategy's exclusions they are reading.
#' @return Tibble with columns \code{ym} (character, `"YYYY-MM"`) and
#'   \code{ret} (compounded monthly return), one row per COMPLETE month,
#'   sorted by \code{ym}. Zero rows (not an error) if every month is
#'   partial or no data was supplied -- the caller's downstream
#'   \code{.build_wide_corr_matrix()} / `CORR_MIN_OBS` check is what turns
#'   "too little data" into a loud failure, not this function.
#' @noRd
.resample_daily_to_monthly <- function(dates, rets, min_days = 15L, label = "strategy") {
  dates <- as.Date(dates)
  keep  <- !is.na(dates) & !is.na(rets)
  dates <- dates[keep]
  rets  <- rets[keep]

  if (length(dates) == 0L) {
    return(tibble::tibble(ym = character(0L), ret = numeric(0L)))
  }

  ym       <- format(dates, "%Y-%m")
  by_month <- split(rets, ym)
  n_days   <- vapply(by_month, length, integer(1L))

  complete <- names(by_month)[n_days >= min_days]
  excluded <- names(by_month)[n_days < min_days]

  if (length(excluded) > 0L) {
    excl_desc <- sprintf(
      "%s (%d day%s)", excluded, n_days[excluded],
      ifelse(n_days[excluded] == 1L, "", "s")
    )
    cli::cli_inform(c(
      "i" = paste0(
        "{label}: excluded {length(excluded)} partial month{?s} from the ",
        "monthly-resampled spine ({paste(excl_desc, collapse = ', ')}) -- ",
        "fewer than {min_days} trading days."
      )
    ))
  }

  if (length(complete) == 0L) {
    return(tibble::tibble(ym = character(0L), ret = numeric(0L)))
  }

  monthly_ret <- vapply(complete, function(m) prod(1 + by_month[[m]]) - 1, numeric(1L))

  tibble::tibble(ym = complete, ret = unname(monthly_ret)) |>
    dplyr::arrange(ym)
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
    #
    # Widened from the original 5-strategy family (stk_max/stk_drif/fac_max/
    # fac_drif/ltr, via strat_corr_matrix/strat_returns_aligned) to the same
    # 16-strategy STRAT_RETURNS_WIDE_CODES scope as strat_corr_matrix_leaderboard
    # (#728 items 1+2, #733) -- see docs/leaderboard.qmd's Rankings table,
    # Redundant/Incremental Sharpe columns. Before this widening, 12 of 17
    # leaderboard strategies showed "not computed" for both columns purely
    # because plan_strategy_correlation.R had not yet been pointed at the
    # wider matrix, even though that matrix (and the k_eff_leaderboard/
    # deflated_sharpe it feeds via strat_keff_vertox_leaderboard,
    # R/plan_leaderboard.R's strat_deflated_sharpe) already covers 16 of 17.
    #
    # Verified suitable before widening (not assumed): strat_returns_wide is
    # entirely a MONTHLY `ym` spine (the five daily-frequency strategies are
    # already resampled onto it by .resample_daily_to_monthly() -- see that
    # target's own comment), so periods_per_year = 12L below is correct for
    # every one of the 16 columns, unlike a naive mix of native frequencies.
    # A live-store check (2026, docs/_targets) found 193 rows with non-NA
    # data across all 16 STRAT_RETURNS_WIDE_CODES columns simultaneously --
    # NOT a further-shrunk window: 193 equals Factor MAX/Factor DRIF's own
    # individual non-NA count (193), i.e. the complete-case window is bounded
    # by the tightest-history strategy already on the leaderboard, not by
    # requiring 16-way agreement beyond what that strategy's own "Full
    # Period" Sharpe is already computed over. A shared common window (not
    # each strategy's own full individual history, unlike
    # strat_deflated_sharpe's naive_sharpe) is deliberate here: comparing two
    # strategies' Sharpe to decide which is "better" for the redundancy flag
    # is only valid if both are measured over the SAME dates.
    targets::tar_target(strat_corr_augment, {
      library(dplyr)

      # Map from code_name to the leaderboard display label. Matches the
      # SAME code_name -> label vocabulary as col_map_monthly/col_map_daily
      # in R/plan_leaderboard.R's strat_deflated_sharpe target, so a
      # strategy's Redundant/Incremental Sharpe badge and its Rigour badge
      # never disagree about which strategy a code_name refers to. (Not
      # reused from plan_strategy_names.R's strategy_names target: that
      # table's code_name vocabulary -- "drif", "rsc", "ev_ebit", "mf_tsm",
      # "olmar" -- is a DIFFERENT, pre-existing convention from
      # STRAT_RETURNS_WIDE_CODES's, an inconsistency out of scope to unify
      # here.)
      name_map <- tibble::tibble(
        code_name      = c("stk_max", "stk_drif", "fac_max", "fac_drif", "ltr",
                            "xgb_drif", "mom_prepeak", "mom_postpeak", "mom_combined",
                            "value_hml", "managed_futures",
                            "cmr", "olmar_1", "tom", "risk_state", "avoid_worst"),
        strategy_label = c("Stock MAX", "Stock DRIF", "Factor MAX", "Factor DRIF", "LTR",
                            "XGB DRIF", "Mom Pre-Peak", "Mom Post-Peak", "Mom 12-2",
                            "Value (HML)", "Managed Futures",
                            "CMR", "OLMAR-1", "TOM", "Risk State", "Avoid Worst")
      )

      strat_cols <- rownames(strat_corr_matrix_leaderboard)
      n_strat <- length(strat_cols)

      # ── Full-period Sharpe per strategy, on a SHARED complete-case window ──
      full_rets <- strat_returns_wide |>
        select(all_of(strat_cols)) |>
        filter(if_all(everything(), ~ !is.na(.x)))

      # fail-loud-not-null.md: a row that cannot be checked must abort, not
      # silently produce all-NA sharpe_full/incremental_sharpe values.
      if (nrow(full_rets) < 2L) {
        cli::cli_abort(c(
          "x" = paste0(
            "Only ", nrow(full_rets), " row(s) of strat_returns_wide have ",
            "non-NA data for all ", n_strat, " widened correlation strategies."
          ),
          "i" = paste0(
            "strat_corr_augment (Redundant/Incremental Sharpe) needs a shared ",
            "common window across: ", paste(strat_cols, collapse = ", "), "."
          ),
          "i" = "Check strat_returns_wide (R/plan_strategy_correlation.R) for a strategy whose history no longer overlaps the others."
        ))
      }

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
        max(abs(strat_corr_matrix_leaderboard[s, others]))
      }, numeric(1L))
      names(corr_max) <- strat_cols

      # ── redundant flag: |r| >= REDUNDANCY_THRESH with a higher-Sharpe peer ──
      redundant <- vapply(strat_cols, function(s) {
        peers <- setdiff(strat_cols, s)
        any(vapply(peers, function(p) {
          high_corr <- abs(strat_corr_matrix_leaderboard[s, p]) >= REDUNDANCY_THRESH
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

      # fail-loud-not-null.md: an un-mapped code_name must abort, not
      # silently produce an NA strategy_label that then fails to join onto
      # the leaderboard by "strategy" (indistinguishable from "outside the
      # correlation universe").
      if (anyNA(result$strategy_label)) {
        unmapped <- result$code_name[is.na(result$strategy_label)]
        cli::cli_abort(c(
          "x" = paste0(
            length(unmapped), " strategy code_name(s) in strat_corr_matrix_leaderboard ",
            "have no entry in strat_corr_augment's name_map: ", paste(unmapped, collapse = ", "), "."
          ),
          "i" = paste0(
            "Add the missing code_name -> display label mapping to name_map above -- it ",
            "must match col_map_monthly/col_map_daily in R/plan_leaderboard.R's ",
            "strat_deflated_sharpe target."
          )
        ))
      }

      result
    }),

    # ── Daily-native return series for the five daily strategies (#733) ──────
    # Kept SEPARATE from strat_returns_wide's monthly `ym` spine because
    # strat_deflated_sharpe (R/plan_leaderboard.R) needs each daily
    # strategy's return series at its OWN native frequency (ann_factor =
    # 252) to compute naive_sharpe/deflated_sharpe consistently with the
    # figures already published elsewhere on the leaderboard for these rows
    # (STRATEGY_OBS_ANN_FACTOR) -- resampling to monthly BEFORE computing
    # deflated_sharpe would shrink T_obs and change the statistic's
    # properties for no reason; only the CORRELATION matrix (which needs a
    # common spine across strategies of different native frequency) is
    # built from the monthly-RESAMPLED version, via .resample_daily_to_monthly()
    # in strat_returns_wide below.
    #
    # Returns a plain named list (not a joined tibble): each strategy's
    # dates generally do NOT align 1:1 with any other's (different trading
    # calendars, different history start dates), so there is no shared
    # `date` spine to join onto here -- unlike the monthly `ym` parts below,
    # which share a coarser key. Each element is a tibble with `date` and
    # `ret` columns.
    #
    # Source selection per strategy (matches R/plan_leaderboard.R's
    # .norm_cmr()/.norm_olmar()/.norm_tom()/.norm_rsc()/.norm_aw() so the
    # series feeding K_eff is the SAME series the leaderboard's own row is
    # scored on, not a lookalike):
    #   cmr:         best-Sharpe lookback among cmr_returns_1m/3m/6m, chosen
    #                the same way .norm_cmr() picks cmr_summary's best row
    #                (R/plan_commodities_mean_reversion.R).
    #   olmar_1:     olmar_portfolio$net_ret (R/plan_olmar.R).
    #   tom:         tom_portfolio$ret_net (R/plan_turn_of_month.R).
    #   risk_state:  rsc_portfolio$ret_strategy -- the SPY_overlay series
    #                (R/plan_risk_state.R; .norm_rsc() filters rsc_metrics
    #                to this same variant).
    #   avoid_worst: SPY daily returns with the worst 10 days (by return,
    #                over the WHOLE series) removed -- replicates aw_metrics'
    #                own "Remove 10 Worst" / "Full Period" construction
    #                (R/plan_avoid_worst.R's calc()) rather than
    #                re-deriving a different selection.
    targets::tar_target(strat_returns_daily_native, {
      library(dplyr)

      best_lookback <- cmr_summary |>
        filter(!is.na(sharpe)) |>
        arrange(desc(sharpe)) |>
        slice(1) |>
        pull(lookback)
      cmr_source <- switch(best_lookback,
        "1m" = cmr_returns_1m,
        "3m" = cmr_returns_3m,
        "6m" = cmr_returns_6m,
        cli::cli_abort(c(
          "x" = "Unrecognised CMR lookback {.val {best_lookback}} from cmr_summary.",
          "i" = "Expected one of '1m', '3m', '6m' (R/plan_commodities_mean_reversion.R)."
        ))
      )
      cmr_daily <- cmr_source |>
        transmute(date = as.Date(date), ret = strategy_ret)

      olmar_daily <- olmar_portfolio |>
        transmute(date = as.Date(date), ret = net_ret)

      tom_daily <- tom_portfolio |>
        transmute(date = as.Date(date), ret = ret_net)

      risk_state_daily <- rsc_portfolio |>
        transmute(date = as.Date(date), ret = ret_strategy)

      # Avoid Worst: worst-10-day removal over the full SPY series, same
      # selection as aw_metrics' calc(period = "Full Period", scenario =
      # "Remove 10 Worst") in R/plan_avoid_worst.R.
      spy <- aw_daily_returns |> filter(ticker == "SPY") |> arrange(date)
      ord <- order(spy$ret)
      worst_10 <- ord[seq_len(min(10L, nrow(spy) - 1L))]
      avoid_worst_daily <- spy[-worst_10, ] |>
        transmute(date = as.Date(date), ret = ret)

      list(
        cmr         = cmr_daily,
        olmar_1     = olmar_daily,
        tom         = tom_daily,
        risk_state  = risk_state_daily,
        avoid_worst = avoid_worst_daily
      )
    }),

    # ── Leaderboard-wide return alignment (#728 items 1+2, widened by #733) ──
    # Widens strat_returns_aligned's scope from 5 strategies to the 16 named
    # in STRAT_RETURNS_WIDE_CODES above. Deliberately uses full_join (spine =
    # union of every ym across all sources), NOT inner_join: an inner_join
    # across N series lets any one series' shorter history truncate every
    # other series to its overlap window -- the forbidden pattern in
    # .claude/rules/fail-loud-not-null.md ("One series' gap silently deletes
    # the period for all of them"). NA cells here are real (a strategy has
    # no return that month) and are handled downstream by
    # .build_wide_corr_matrix()'s pairwise-complete correlation, not by
    # dropping rows.
    #
    # #733: the five daily-frequency parts are built by resampling
    # strat_returns_daily_native's native series to monthly via
    # .resample_daily_to_monthly() (compounding, with partial months
    # excluded and reported -- see that function's roxygen) so they can
    # join the SAME `ym` spine as the 11 already-monthly parts below.
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

      # #733: monthly-resample each daily-native series and rename its
      # `ret` column to the strategy's code_name so it can enter
      # .full_join_return_spine() alongside the already-monthly parts
      # above. label = names(strat_returns_daily_native) so
      # .resample_daily_to_monthly()'s cli_inform() exclusion messages
      # name the actual strategy, not a generic placeholder.
      #
      # Base-R column rename (names<-), NOT dplyr::rename(!!nm := ret):
      # targets' tidy_eval feature (tar_option_get("tidy_eval"), default
      # TRUE) eagerly unquotes any `!!` found ANYWHERE in a target's command
      # body at PLAN-DEFINITION time (rlang::expr()'s AST walk does not
      # respect the enclosing function(nm) {...} closure's scope -- `nm` is
      # only bound at lapply()'s RUN time, so plan-definition-time unquoting
      # fails with "object 'nm' not found", confirmed via
      # targets:::tar_tidy_eval() -> rlang::expr() -> enexpr() in this
      # target's own call stack). base::names<-() has no unquoting syntax
      # for tidy_eval to misfire on.
      daily_monthly_cols <- lapply(names(strat_returns_daily_native), function(nm) {
        d <- strat_returns_daily_native[[nm]]
        out <- .resample_daily_to_monthly(d$date, d$ret, min_days = 15L, label = nm)
        names(out)[names(out) == "ret"] <- nm
        out
      })

      parts <- c(
        list(
          base, ltr_col, xgb_col, mom_prepeak_col, mom_postpeak_col,
          mom_combined_col, value_hml_col, managed_futures_col
        ),
        daily_monthly_cols
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
