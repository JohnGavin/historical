# Strategy Value Gate — Advisory Governance Scorer (#496, supersedes PR #511)
#
# Scores a candidate strategy's marginal value against an existing portfolio.
# Implements the governance framework from #496, extended per the #511
# review (issue #496 comment, 2026-09-26) to:
#   (a) distinguish a DETERMINATE mixed result from an INDETERMINATE one
#       (a required check could not be computed) instead of collapsing both
#       into a single "research_only" label -- see
#       .claude/rules/checks-must-distinguish-unknown.md;
#   (b) add a detection-power check (.claude/rules/detection-power-required.md)
#       so a candidate is never admitted on a sample too short to detect the
#       Sharpe it is claiming, using hd_detection_power();
#   (c) reference the single canonical redundancy threshold (HD_REDUNDANCY_THRESH,
#       below) instead of re-typing the literal 0.80 that R/plan_strategy_correlation.R
#       already defines as REDUNDANCY_THRESH.
#
# This is ADVISORY: a failing strategy produces a tibble of "fail" rows and
# an overall verdict of "reject", "mixed", or "indeterminate". It never
# stops/errors on a failing check -- only on invalid inputs.
#
# The incremental Sharpe definition matches strat_corr_augment in
# plan_strategy_correlation.R:
#   Sharpe(equal-weight candidate + existing) - Sharpe(equal-weight existing)
# where Sharpe = CAGR / (sd * sqrt(periods_per_year)), i.e. annualise_returns().

# ── Canonical redundancy threshold (single home, #496 review) ──────────────
#
# R/plan_strategy_correlation.R's REDUNDANCY_THRESH is a bare object in root
# R/, which the *package* cannot see (packages/historicaldata is loaded via
# pkgload::load_all() from docs/_targets.R; root R/ plan files are sourced
# separately into the targets pipeline environment -- see this project's
# CLAUDE.md "Package source not tracked" note). The package is the more
# stable, independently-testable surface, so this constant's single home is
# HERE; R/plan_strategy_correlation.R reads it back via
# `historicaldata::HD_REDUNDANCY_THRESH` rather than re-declaring 0.80.
#
#' Canonical strategy-similarity redundancy threshold
#'
#' The `|Pearson rho|` above which one strategy is considered redundant with
#' another (higher-Sharpe) one. Single source of truth for this value --
#' both [hd_strategy_value_gate()]'s `corr_threshold` default and
#' `R/plan_strategy_correlation.R`'s `REDUNDANCY_THRESH` read this constant
#' rather than each hardcoding `0.80` independently.
#'
#' @format A length-1 numeric.
#' @family governance
#' @export
HD_REDUNDANCY_THRESH <- 0.80

# ── Private helpers ────────────────────────────────────────────────────────────

# Annualised Sharpe for an equal-weight portfolio over a return matrix.
# Matches annualise_returns() in R/utils_metrics.R (geometric CAGR / ann vol).
.sharpe_ew_gate <- function(ret_matrix, periods_per_year) {
  n_col <- ncol(ret_matrix)
  if (n_col < 1L) return(NA_real_)
  w       <- rep(1 / n_col, n_col)
  r       <- as.numeric(ret_matrix %*% w)
  r       <- r[!is.na(r)]
  n       <- length(r)
  if (n < 2L) return(NA_real_)
  equity  <- cumprod(1 + r)
  cagr    <- equity[n]^(periods_per_year / n) - 1
  vol     <- stats::sd(r) * sqrt(periods_per_year)
  if (vol <= 0) NA_real_ else cagr / vol
}

# Equal-weight portfolio variance over a return matrix (annualised).
.var_ew_gate <- function(ret_matrix, periods_per_year) {
  n_col <- ncol(ret_matrix)
  if (n_col < 1L) return(NA_real_)
  w <- rep(1 / n_col, n_col)
  r <- as.numeric(ret_matrix %*% w)
  r <- r[!is.na(r)]
  if (length(r) < 2L) return(NA_real_)
  stats::var(r) * periods_per_year
}

# Aggregate one quantitative check's verdict into pass/fail/na for the
# overall-verdict vote (see .overall_verdict_gate() below). "n_a" (legit
# not-applicable, e.g. a non-positive Sharpe has no positive effect to test
# for detection power -- detection-power-required.md requirement 3) counts
# as "fail" for aggregation purposes: it is a determinate reason NOT to
# admit, distinct from "na" (could not be computed at all), which is the
# ONLY thing that should ever make the overall verdict "indeterminate".
.agg_verdict_gate <- function(v) {
  if (identical(v, "na")) "na"
  else if (identical(v, "pass")) "pass"
  else "fail"  # covers "fail" and "n_a"
}

# Overall verdict from the quantitative checks (similarity, incremental
# Sharpe, diversification_ew, detection_power). Never collapses "some pass,
# some fail" (mixed -- a determinate result) with "at least one could not be
# computed" (indeterminate -- an unknown) into the same label; see
# .claude/rules/checks-must-distinguish-unknown.md.
.overall_verdict_gate <- function(named_verdicts) {
  agg <- vapply(named_verdicts, .agg_verdict_gate, character(1))
  if (any(agg == "na")) {
    list(
      overall = "indeterminate",
      indeterminate_checks = names(named_verdicts)[agg == "na"]
    )
  } else if (all(agg == "pass")) {
    list(overall = "admit", indeterminate_checks = character())
  } else if (all(agg == "fail")) {
    list(overall = "reject", indeterminate_checks = character())
  } else {
    list(overall = "mixed", indeterminate_checks = character())
  }
}

# ── Exported function ──────────────────────────────────────────────────────────

#' Advisory value gate for a candidate strategy
#'
#' Scores a candidate strategy against an existing portfolio on six checks:
#' similarity (max |Pearson rho|), incremental Sharpe, diversification
#' (variance reduction, EW and GMV variants), detection power, crowding, and
#' robustness. Returns a tidy tibble of verdicts plus an overall advisory
#' conclusion in `attr(result, "overall")`.
#'
#' @section Incremental Sharpe definition:
#' Matches `strat_corr_augment` in `plan_strategy_correlation.R`:
#' `Sharpe(equal-weight candidate + existing) - Sharpe(equal-weight existing)`,
#' where `Sharpe = CAGR / (sd(r) * sqrt(periods_per_year))` (geometric CAGR,
#' annualised vol). Positive = candidate adds value; negative = portfolio
#' improves without it.
#'
#' @section Detection power (#496 review, .claude/rules/detection-power-required.md):
#' Computes the candidate's OWN standalone annualised Sharpe (not the
#' incremental one) and asks, via [hd_detection_power()], whether the
#' available sample (`n_obs`, the number of complete overlapping
#' observations after alignment) is long enough to detect a Sharpe of that
#' size at `target_power`. A candidate is never admitted on a sample too
#' short to tell its claimed effect apart from noise -- see
#' `.claude/rules/detection-power-required.md` requirement 4.
#'
#' Three distinct outcomes, corresponding to the rule's three-state
#' requirement:
#' \itemize{
#'   \item `"pass"` -- own Sharpe is positive and `n_obs` clears the
#'     Bonferroni-corrected requirement (`min_n_periods_corrected`).
#'   \item `"fail"` -- own Sharpe is positive but `n_obs` is short of the
#'     corrected requirement (underpowered).
#'   \item `"n_a"` -- own Sharpe is zero or negative: there is no positive
#'     effect to test for (detection-power-required.md requirement 3 --
#'     this is a legitimate NOT-APPLICABLE state, distinct from "could not
#'     compute").
#'   \item `"na"` -- the candidate's own Sharpe itself could not be computed
#'     (e.g. zero variance, fewer than 2 observations). This is the ONLY
#'     detection_power outcome that can make the overall verdict
#'     `"indeterminate"`.
#' }
#'
#' @section Overall verdict:
#' The quantitative checks (similarity, incremental Sharpe,
#' diversification_ew, detection_power) vote on the overall verdict:
#' \itemize{
#'   \item `"indeterminate"` -- at least one of the four quantitative checks
#'     is `"na"` (could not be computed). NEVER collapsed with `"mixed"` --
#'     see `.claude/rules/checks-must-distinguish-unknown.md`. `verdict_reason`
#'     names which check(s).
#'   \item `"admit"` -- all four quantitative checks pass.
#'   \item `"reject"` -- all four quantitative checks fail (or are `"n_a"`,
#'     which counts as a determinate non-pass).
#'   \item `"mixed"` -- everything was computable, but the checks disagree
#'     (some pass, some fail/n_a). A determinate result -- unlike
#'     `"indeterminate"`, more analysis will not change this outcome, only a
#'     different candidate or existing portfolio would.
#' }
#' `diversification_gmv`, `crowding`, and `robustness` remain advisory
#' (reported, never voted).
#'
#' @section Advisory stance:
#' Never calls [base::stop()] on a failing check. A strategy that fails
#' every quantitative check returns a tibble of `"fail"` rows with
#' `overall = "reject"`. Input validation errors (non-numeric inputs, empty
#' existing, no shared rows) do abort via [cli::cli_abort()].
#'
#' @param candidate Numeric vector of periodic returns for the candidate
#'   strategy. Must be numeric and length >= 2.
#' @param existing Numeric matrix or data frame of existing strategy returns.
#'   Each column is one strategy, rows are observations. Must have >= 1 column
#'   and >= 1 common complete row with `candidate` after alignment.
#' @param candidate_name Character label used in `attr(result, "candidate_name")`.
#'   Default `"candidate"`.
#' @param corr_threshold Numeric in (0, 1]. Similarity threshold: verdict is
#'   `"fail"` when `correlation_max >= corr_threshold`. Default
#'   [HD_REDUNDANCY_THRESH] (0.80) -- the single canonical redundancy
#'   threshold, shared with `R/plan_strategy_correlation.R`.
#' @param min_incr_sharpe Numeric. Minimum incremental Sharpe to pass. Default
#'   `0` (any positive increment passes). Strict inequality: `> min_incr_sharpe`.
#' @param periods_per_year Integer. Annualisation factor. Default `12L`
#'   (monthly). Use `252L` for daily, `4L` for quarterly.
#' @param n_tests Numeric scalar >= 1. Effective number of tests this
#'   candidate's detection-power check is one of, passed through to
#'   [hd_detection_power()]'s Bonferroni correction. Default `1` (no
#'   correction). Use the leaderboard's effective-test count (e.g.
#'   `k_eff_leaderboard`) where available -- see
#'   `.claude/rules/detection-power-required.md` requirement 5.
#' @param correction One of `"none"` or `"bonferroni"`, passed to
#'   [hd_detection_power()]. Default `"none"`.
#' @param target_power Numeric scalar in (0, 1), passed to
#'   [hd_detection_power()]. Default `0.80` (Cohen, 1988 convention -- see
#'   that function's own documentation for why this is not fit to this
#'   repo's data).
#' @param crowding Optional numeric published-t or logical flag. `TRUE` / any
#'   value > 3 indicates high crowding (`"flag"`); `FALSE` / <= 3 -> `"pass"`;
#'   `NA` -> `"na"`. Default `NA`.
#' @param robustness_pass Optional logical from the CPCV/falsification gauntlet.
#'   `TRUE` -> `"pass"`, `FALSE` -> `"fail"`, `NA` -> `"na"`. Default `NA`.
#'
#' @return A tibble with 7 rows (one per check/metric combination) and columns:
#'   \describe{
#'     \item{check}{Character. One of `"similarity"`, `"incremental_sharpe"`,
#'       `"diversification_ew"`, `"diversification_gmv"`, `"detection_power"`,
#'       `"crowding"`, `"robustness"`.}
#'     \item{metric}{Character. Human-readable metric name.}
#'     \item{value}{Numeric. Computed value (or `NA` when not applicable).}
#'     \item{threshold}{Numeric. Decision threshold (or `NA` for advisory checks).}
#'     \item{verdict}{Factor with levels `"pass"`, `"fail"`, `"flag"`, `"na"`,
#'       `"n_a"`.}
#'   }
#'
#'   Three attributes are attached:
#'   * `attr(result, "overall")` -- character: `"admit"`, `"mixed"`,
#'     `"reject"`, or `"indeterminate"`.
#'   * `attr(result, "verdict_reason")` -- character vector naming which
#'     check(s) triggered `"indeterminate"` (empty for the other three
#'     outcomes).
#'   * `attr(result, "candidate_name")` -- the value of `candidate_name`.
#'   * `attr(result, "detection_power")` -- the full list returned by
#'     [hd_detection_power()] for the candidate's own Sharpe, or `NULL` when
#'     the candidate's own Sharpe was non-positive or uncomputable.
#'
#' @family governance
#' @export
#' @examples
#' set.seed(42)
#' n <- 240L  # 20 years of monthly data -- enough for detection power to pass
#' existing <- matrix(rnorm(n * 2, mean = 0.006, sd = 0.035),
#'                    nrow = n, ncol = 2,
#'                    dimnames = list(NULL, c("strat_a", "strat_b")))
#' # Anti-correlated, strong-effect candidate
#' candidate <- -0.3 * (existing[, 1] - mean(existing[, 1])) + 0.012 +
#'   rnorm(n, sd = 0.03)
#' result <- hd_strategy_value_gate(candidate, existing,
#'                                  candidate_name = "anti_corr",
#'                                  periods_per_year = 12L)
#' attr(result, "overall")   # typically "admit"
#' result$verdict
hd_strategy_value_gate <- function(
    candidate,
    existing,
    candidate_name   = "candidate",
    corr_threshold   = HD_REDUNDANCY_THRESH,
    min_incr_sharpe  = 0,
    periods_per_year = 12L,
    n_tests          = 1,
    correction       = c("none", "bonferroni"),
    target_power     = 0.80,
    crowding         = NA,
    robustness_pass  = NA) {

  correction <- match.arg(correction)

  # ── Input validation ──────────────────────────────────────────────────────
  if (!is.numeric(candidate)) {
    cli::cli_abort(c(
      "x" = "{.arg candidate} must be a numeric vector.",
      "i" = "Got {.cls {class(candidate)}}."
    ))
  }
  if (is.data.frame(existing)) {
    existing <- as.matrix(existing)
  }
  if (!is.matrix(existing) || !is.numeric(existing)) {
    cli::cli_abort(c(
      "x" = "{.arg existing} must be a numeric matrix or data frame of numeric columns.",
      "i" = "Got {.cls {class(existing)}}."
    ))
  }
  if (ncol(existing) < 1L) {
    cli::cli_abort(c(
      "x" = "{.arg existing} must have at least 1 column (strategy).",
      "i" = "Got {ncol(existing)} columns."
    ))
  }
  if (length(candidate) != nrow(existing)) {
    cli::cli_warn(c(
      "!" = "{.arg candidate} length ({length(candidate)}) differs from",
      " " = "{.arg existing} rows ({nrow(existing)}); using intersection of",
      " " = "complete observations."
    ))
  }

  # Align: take min length then drop rows with any NA
  n_common <- min(length(candidate), nrow(existing))
  cand_vec <- candidate[seq_len(n_common)]
  exist_mat <- existing[seq_len(n_common), , drop = FALSE]

  complete_rows <- complete.cases(cbind(cand_vec, exist_mat))
  if (sum(complete_rows) < 2L) {
    cli::cli_abort(c(
      "x" = "Fewer than 2 complete overlapping rows between {.arg candidate}",
      " " = "and {.arg existing} after dropping NAs.",
      "i" = "Got {sum(complete_rows)} complete row(s)."
    ))
  }

  cand_use  <- cand_vec[complete_rows]
  exist_use <- exist_mat[complete_rows, , drop = FALSE]
  n_obs     <- length(cand_use)

  # Combined matrix: existing columns + candidate as last column
  combined <- cbind(exist_use, candidate = cand_use)

  # ── Check 1: similarity ───────────────────────────────────────────────────
  corr_vals   <- abs(cor(cand_use, exist_use))   # 1 x n_exist
  # max(x, na.rm = TRUE) on an all-NA vector returns -Inf (with a warning),
  # NOT NA -- which would silently defeat the is.na(corr_max) "na" check
  # below whenever EVERY existing column has zero variance (e.g. a flat
  # series). Guard explicitly so this stays a genuine "could not compute"
  # (checks-must-distinguish-unknown.md), never an unnoticed -Inf.
  corr_max    <- if (all(is.na(corr_vals))) NA_real_ else max(corr_vals, na.rm = TRUE)
  sim_verdict <- if (is.na(corr_max)) "na" else if (corr_max >= corr_threshold) "fail" else "pass"

  # ── Check 2: incremental Sharpe ───────────────────────────────────────────
  sharpe_with    <- .sharpe_ew_gate(combined,   periods_per_year)
  sharpe_without <- .sharpe_ew_gate(exist_use,  periods_per_year)
  incr_sharpe    <- if (is.na(sharpe_with) || is.na(sharpe_without)) NA_real_ else sharpe_with - sharpe_without
  is_verdict <- if (is.na(incr_sharpe)) "na" else if (incr_sharpe > min_incr_sharpe) "pass" else "fail"

  # ── Check 3a: diversification (equal-weight variance reduction) ───────────
  var_with    <- .var_ew_gate(combined,  periods_per_year)
  var_without <- .var_ew_gate(exist_use, periods_per_year)
  var_reduc   <- if (is.na(var_with) || is.na(var_without)) NA_real_ else var_without - var_with
  div_ew_verdict <- if (is.na(var_reduc)) "na" else if (var_reduc > 0) "pass" else "fail"

  # ── Check 3b: diversification (GMV variance reduction, optional, advisory) ─
  gmv_reduc    <- tryCatch({
    cov_with    <- stats::cov(combined)
    cov_without <- stats::cov(exist_use)
    w_with    <- hd_min_var_weights(cov_with)
    w_without <- hd_min_var_weights(cov_without)
    gmv_var_with    <- as.numeric(t(w_with)    %*% cov_with    %*% w_with)    * periods_per_year
    gmv_var_without <- as.numeric(t(w_without) %*% cov_without %*% w_without) * periods_per_year
    gmv_var_without - gmv_var_with
  }, error = function(e) NA_real_)

  div_gmv_verdict <- if (is.na(gmv_reduc)) "na" else if (gmv_reduc > 0) "pass" else "fail"

  # ── Check 4: detection power (#496 review; detection-power-required.md) ──
  cand_sharpe <- .sharpe_ew_gate(matrix(cand_use, ncol = 1L), periods_per_year)
  dp_detail   <- NULL
  dp_min_years <- NA_real_
  dp_min_years_corrected <- NA_real_

  if (is.na(cand_sharpe)) {
    # Could not even compute the candidate's own Sharpe (e.g. zero variance).
    dp_verdict <- "na"
  } else if (cand_sharpe <= 0) {
    # Legitimate NOT-APPLICABLE: no positive effect to test for detection
    # power against (detection-power-required.md requirement 3). This is a
    # determinate reason not to admit -- NOT an unknown.
    dp_verdict <- "n_a"
  } else {
    dp_detail <- hd_detection_power(
      sharpe_annual = cand_sharpe,
      n_obs         = n_obs,
      ann_factor    = periods_per_year,
      target_power  = target_power,
      n_tests       = n_tests,
      correction    = correction
    )
    dp_min_years <- dp_detail$min_n_years
    dp_min_years_corrected <- dp_detail$min_n_years_corrected
    dp_verdict <- if (isTRUE(dp_detail$underpowered_corrected)) "fail" else "pass"
  }

  # ── Check 5: crowding (advisory) ──────────────────────────────────────────
  crowd_value <- if (is.logical(crowding) && length(crowding) == 1L && !is.na(crowding)) {
    as.numeric(crowding)
  } else if (is.numeric(crowding) && length(crowding) == 1L) {
    crowding
  } else {
    NA_real_
  }

  crowd_verdict <- if (is.na(crowd_value)) {
    "na"
  } else if (isTRUE(as.logical(crowding)) || (!is.logical(crowding) && crowd_value > 3)) {
    "flag"
  } else {
    "pass"
  }

  # ── Check 6: robustness (advisory) ────────────────────────────────────────
  rob_verdict <- if (is.na(robustness_pass)) {
    "na"
  } else if (isTRUE(robustness_pass)) {
    "pass"
  } else {
    "fail"
  }
  rob_value <- if (is.na(robustness_pass)) NA_real_ else as.numeric(robustness_pass)

  # ── Assemble result tibble ────────────────────────────────────────────────
  verdict_levels <- c("pass", "fail", "flag", "na", "n_a")

  result <- tibble::tibble(
    check = c(
      "similarity",
      "incremental_sharpe",
      "diversification_ew",
      "diversification_gmv",
      "detection_power",
      "crowding",
      "robustness"
    ),
    metric = c(
      "max |Pearson rho| vs existing strategies",
      "Sharpe(equal-weight with) - Sharpe(equal-weight without)",
      "equal-weight annualised variance reduction (without - with)",
      "GMV annualised variance reduction (without - with)",
      "candidate's own annualised Sharpe vs required sample (Lo/Mertens power calc)",
      "crowding indicator (published-t or logical flag)",
      "robustness_pass (from CPCV/falsification gauntlet)"
    ),
    value = c(
      corr_max,
      incr_sharpe,
      var_reduc,
      gmv_reduc,
      cand_sharpe,
      crowd_value,
      rob_value
    ),
    threshold = c(
      corr_threshold,
      min_incr_sharpe,
      0,
      0,
      dp_min_years_corrected,
      NA_real_,
      NA_real_
    ),
    verdict = factor(
      c(sim_verdict, is_verdict, div_ew_verdict, div_gmv_verdict, dp_verdict,
        crowd_verdict, rob_verdict),
      levels = verdict_levels
    )
  )

  # ── Overall advisory verdict (four quantitative checks vote) ─────────────
  vote <- .overall_verdict_gate(list(
    similarity          = sim_verdict,
    incremental_sharpe  = is_verdict,
    diversification_ew  = div_ew_verdict,
    detection_power     = dp_verdict
  ))

  if (identical(vote$overall, "indeterminate")) {
    cli::cli_warn(c(
      "!" = "{.val {candidate_name}}: overall verdict is {.val indeterminate} --",
      " " = "{length(vote$indeterminate_checks)} required check{?s} could not be computed:",
      " " = "{.field {vote$indeterminate_checks}}.",
      "i" = "This is distinct from a determinate {.val reject}/{.val mixed} result -- see",
      "i" = ".claude/rules/checks-must-distinguish-unknown.md"
    ))
  }

  attr(result, "overall")          <- vote$overall
  attr(result, "verdict_reason")   <- vote$indeterminate_checks
  attr(result, "candidate_name")   <- candidate_name
  attr(result, "detection_power")  <- dp_detail

  result
}
