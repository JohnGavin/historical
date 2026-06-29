# Strategy Value Gate — Advisory Governance Scorer (#496 Phase 1)
#
# Scores a candidate strategy's marginal value against an existing portfolio.
# Implements the 5-check governance framework from #496.
#
# This is ADVISORY: a failing strategy produces a tibble of "fail" rows and
# an overall verdict of "reject" or "research_only". It never stops/errors on
# a failing check — only on invalid inputs.
#
# The incremental Sharpe definition matches strat_corr_augment in
# plan_strategy_correlation.R:
#   Sharpe(equal-weight candidate + existing) - Sharpe(equal-weight existing)
# where Sharpe = CAGR / (sd * sqrt(periods_per_year)), i.e. annualise_returns().

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

# ── Exported function ──────────────────────────────────────────────────────────

#' Advisory value gate for a candidate strategy
#'
#' Scores a candidate strategy against an existing portfolio on five checks:
#' similarity (max |Pearson ρ|), incremental Sharpe, diversification (variance
#' reduction), crowding, and robustness. Returns a tidy tibble of verdicts plus
#' an overall advisory conclusion in `attr(result, "overall")`.
#'
#' @section Incremental Sharpe definition:
#' Matches `strat_corr_augment` in `plan_strategy_correlation.R`:
#' `Sharpe(equal-weight candidate + existing) − Sharpe(equal-weight existing)`,
#' where `Sharpe = CAGR / (sd(r) * sqrt(periods_per_year))` (geometric CAGR,
#' annualised vol). Positive = candidate adds value; negative = portfolio
#' improves without it.
#'
#' @section Overall verdict:
#' * `"reject"` — similarity fails **AND** incremental_sharpe ≤ 0 **AND**
#'   diversification fails.
#' * `"admit"` — all three quantitative checks 1–3 pass.
#' * `"research_only"` — all other cases (some pass, some fail; or any "na"
#'   in checks 1–3).
#'
#' @section Advisory stance:
#' Never calls [base::stop()] on a failing check. A strategy that fails every
#' check returns a tibble of `"fail"` rows with `overall = "reject"`. Input
#' validation errors (non-numeric inputs, empty existing, no shared rows) do
#' abort via [cli::cli_abort()].
#'
#' @param candidate Numeric vector of periodic returns for the candidate
#'   strategy. Must be numeric and length ≥ 2.
#' @param existing Numeric matrix or data frame of existing strategy returns.
#'   Each column is one strategy, rows are observations. Must have ≥ 1 column
#'   and ≥ 1 common complete row with `candidate` after alignment.
#' @param candidate_name Character label used in `attr(result, "candidate_name")`.
#'   Default `"candidate"`.
#' @param corr_threshold Numeric in (0, 1]. Similarity threshold: verdict is
#'   `"fail"` when `correlation_max >= corr_threshold`. Default `0.80`.
#' @param min_incr_sharpe Numeric. Minimum incremental Sharpe to pass. Default
#'   `0` (any positive increment passes). Strict inequality: `> min_incr_sharpe`.
#' @param periods_per_year Integer. Annualisation factor. Default `12L`
#'   (monthly). Use `252L` for daily, `4L` for quarterly.
#' @param crowding Optional numeric published-t or logical flag. `TRUE` / any
#'   value > 3 indicates high crowding (`"flag"`); `FALSE` / ≤ 3 → `"pass"`;
#'   `NA` → `"na"`. Default `NA`.
#' @param robustness_pass Optional logical from the CPCV/falsification gauntlet.
#'   `TRUE` → `"pass"`, `FALSE` → `"fail"`, `NA` → `"na"`. Default `NA`.
#'
#' @return A tibble with 6 rows (one per check/metric combination) and columns:
#'   \describe{
#'     \item{check}{Character. One of `"similarity"`, `"incremental_sharpe"`,
#'       `"diversification_ew"`, `"diversification_gmv"`, `"crowding"`,
#'       `"robustness"`.}
#'     \item{metric}{Character. Human-readable metric name.}
#'     \item{value}{Numeric. Computed value (or `NA` when not applicable).}
#'     \item{threshold}{Numeric. Decision threshold (or `NA` for advisory checks).}
#'     \item{verdict}{Factor with levels `"pass"`, `"fail"`, `"flag"`, `"na"`.}
#'   }
#'
#'   Two attributes are attached:
#'   * `attr(result, "overall")` — character: `"admit"`, `"research_only"`, or
#'     `"reject"`.
#'   * `attr(result, "candidate_name")` — the value of `candidate_name`.
#'
#' @family governance
#' @export
#' @examples
#' set.seed(42)
#' n <- 60L
#' existing <- matrix(rnorm(n * 2, mean = 0.005, sd = 0.04),
#'                    nrow = n, ncol = 2,
#'                    dimnames = list(NULL, c("strat_a", "strat_b")))
#' # Anti-correlated candidate
#' candidate <- -existing[, 1] + rnorm(n, sd = 0.01)
#' result <- hd_strategy_value_gate(candidate, existing,
#'                                  candidate_name = "anti_corr",
#'                                  periods_per_year = 12L)
#' attr(result, "overall")   # typically "admit"
#' result$verdict
hd_strategy_value_gate <- function(
    candidate,
    existing,
    candidate_name   = "candidate",
    corr_threshold   = 0.80,
    min_incr_sharpe  = 0,
    periods_per_year = 12L,
    crowding         = NA,
    robustness_pass  = NA) {

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
  n_exist   <- ncol(exist_use)

  # Combined matrix: existing columns + candidate as last column
  combined <- cbind(exist_use, candidate = cand_use)

  # ── Check 1: similarity ───────────────────────────────────────────────────
  corr_vals   <- abs(cor(cand_use, exist_use))   # 1 x n_exist
  corr_max    <- max(corr_vals, na.rm = TRUE)
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

  # ── Check 3b: diversification (GMV variance reduction, optional) ──────────
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

  # ── Check 4: crowding ─────────────────────────────────────────────────────
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

  # ── Check 5: robustness ───────────────────────────────────────────────────
  rob_verdict <- if (is.na(robustness_pass)) {
    "na"
  } else if (isTRUE(robustness_pass)) {
    "pass"
  } else {
    "fail"
  }
  rob_value <- if (is.na(robustness_pass)) NA_real_ else as.numeric(robustness_pass)

  # ── Assemble result tibble ────────────────────────────────────────────────
  verdict_levels <- c("pass", "fail", "flag", "na")

  result <- tibble::tibble(
    check = c(
      "similarity",
      "incremental_sharpe",
      "diversification_ew",
      "diversification_gmv",
      "crowding",
      "robustness"
    ),
    metric = c(
      "max |Pearson rho| vs existing strategies",
      "Sharpe(equal-weight with) - Sharpe(equal-weight without)",
      "equal-weight annualised variance reduction (without - with)",
      "GMV annualised variance reduction (without - with)",
      "crowding indicator (published-t or logical flag)",
      "robustness_pass (from CPCV/falsification gauntlet)"
    ),
    value = c(
      corr_max,
      incr_sharpe,
      var_reduc,
      gmv_reduc,
      crowd_value,
      rob_value
    ),
    threshold = c(
      corr_threshold,
      min_incr_sharpe,
      0,
      0,
      NA_real_,
      NA_real_
    ),
    verdict = factor(
      c(sim_verdict, is_verdict, div_ew_verdict, div_gmv_verdict, crowd_verdict, rob_verdict),
      levels = verdict_levels
    )
  )

  # ── Overall advisory verdict ──────────────────────────────────────────────
  # "reject"       if similarity fails AND incremental_sharpe <= 0 AND
  #                   diversification_ew fails (all three quantitative checks bad)
  # "admit"        if all three quantitative checks 1-3 pass (ew variant for divs)
  # "research_only" otherwise (mixed or any "na" in checks 1-3)
  sim_fail  <- sim_verdict  == "fail"
  is_fail   <- is_verdict   == "fail"
  div_fail  <- div_ew_verdict == "fail"
  sim_pass  <- sim_verdict  == "pass"
  is_pass   <- is_verdict   == "pass"
  div_pass  <- div_ew_verdict == "pass"

  overall <- if (sim_fail && is_fail && div_fail) {
    "reject"
  } else if (sim_pass && is_pass && div_pass) {
    "admit"
  } else {
    "research_only"
  }

  attr(result, "overall")        <- overall
  attr(result, "candidate_name") <- candidate_name

  result
}
