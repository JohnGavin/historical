# Combinatorial Purged Cross-Validation (CPCV) helpers
#
# Implements the resampling primitives from López de Prado (2018) AFML Ch. 7 + 12:
#   - hd_cpcv_purge()  — drop training obs whose label-window overlaps test
#   - hd_cpcv_embargo() — drop training obs within embargo_n after test
#   - hd_cpcv_paths()  — enumerate all C(n_groups, n_test_groups) train/test pairs
#   - hd_pbo()         — Probability of Backtest Overfitting (Bailey et al. 2014)
#
# All index arguments are integer positions (1-based), not dates.
# See knowledge/wiki/cpcv-purged-embargo.md for the mathematical formulation.


# ── 1. Purge ─────────────────────────────────────────────────────────────────

#' Purge training indices whose label-window overlaps the test fold
#'
#' Removes from \code{train_idx} any observation at position \code{t} such
#' that \code{t + label_horizon >= min(test_idx)}.  This prevents label-window
#' leakage when the outcome variable is computed over a forward-looking window
#' (e.g., a one-month-ahead return).
#'
#' @param train_idx Integer vector of training observation indices.
#' @param test_idx  Integer vector of test observation indices.
#' @param label_horizon Non-negative integer.  Number of periods forward that
#'   the label window extends from each observation.  For a 1-period-ahead
#'   return this is \code{1}; for a 21-day-ahead return on daily data this is
#'   \code{21}.  Default \code{1L}.
#'
#' @return Integer vector: \code{train_idx} with the contaminated observations
#'   removed.  Preserves the original order and class of \code{train_idx}.
#'
#' @details
#' The purge condition is: drop \code{t} from training if
#' \code{t + label_horizon >= min(test_idx)}.  Equivalently, retain training
#' observations only if their label window ends strictly before the start of
#' the test fold.
#'
#' @references
#' López de Prado, M. (2018). \emph{Advances in Financial Machine Learning},
#' Wiley, Ch. 7 (Purging and Embargoing Cross-Validation Folds).
#'
#' @family cpcv
#' @export
#'
#' @examples
#' # 20 monthly observations; months 16-20 are test; label horizon 1 month
#' hd_cpcv_purge(train_idx = 1:15, test_idx = 16:20, label_horizon = 1L)
#' # Returns 1:14 (month 15 + 1 = 16 = test start → purged)
hd_cpcv_purge <- function(train_idx, test_idx, label_horizon = 1L) {
  if (!is.integer(train_idx)) train_idx <- as.integer(train_idx)
  if (!is.integer(test_idx))  test_idx  <- as.integer(test_idx)
  if (!is.numeric(label_horizon) || length(label_horizon) != 1L) {
    cli::cli_abort(c(
      "x" = "{.arg label_horizon} must be a single non-negative number.",
      "i" = "Got {.val {label_horizon}} (length {length(label_horizon)})."
    ))
  }
  label_horizon <- as.integer(label_horizon)
  if (label_horizon < 0L) {
    cli::cli_abort(c(
      "x" = "{.arg label_horizon} must be >= 0.",
      "i" = "Got {.val {label_horizon}}."
    ))
  }
  if (length(train_idx) == 0L || length(test_idx) == 0L) return(train_idx)

  test_start <- min(test_idx)
  # Retain t only if t + label_horizon < test_start
  train_idx[train_idx + label_horizon < test_start]
}


# ── 2. Embargo ───────────────────────────────────────────────────────────────

#' Embargo training indices within a gap after the test fold
#'
#' Removes from \code{train_idx} any observation within \code{embargo_n}
#' periods of the test fold's end, to prevent serial-correlation leakage from
#' training observations immediately following the test period.
#'
#' @param train_idx Integer vector of training observation indices.
#' @param test_idx  Integer vector of test observation indices.
#' @param embargo_n Non-negative integer.  Number of periods after
#'   \code{max(test_idx)} to exclude from training.  Default \code{1L}.
#'
#' @return Integer vector: \code{train_idx} with the embargoing observations
#'   removed.
#'
#' @details
#' The embargo condition is: drop \code{t} from training if
#' \code{max(test_idx) < t <= max(test_idx) + embargo_n}.
#'
#' @references
#' López de Prado, M. (2018). \emph{Advances in Financial Machine Learning},
#' Wiley, Ch. 7.
#'
#' @family cpcv
#' @export
#'
#' @examples
#' # 25 monthly observations; months 16-20 are test; 2-month embargo
#' hd_cpcv_embargo(train_idx = c(1:15, 21:25), test_idx = 16:20, embargo_n = 2L)
#' # Returns c(1:15, 23:25) — months 21, 22 are in the embargo zone
hd_cpcv_embargo <- function(train_idx, test_idx, embargo_n = 1L) {
  if (!is.integer(train_idx)) train_idx <- as.integer(train_idx)
  if (!is.integer(test_idx))  test_idx  <- as.integer(test_idx)
  if (!is.numeric(embargo_n) || length(embargo_n) != 1L) {
    cli::cli_abort(c(
      "x" = "{.arg embargo_n} must be a single non-negative number.",
      "i" = "Got {.val {embargo_n}} (length {length(embargo_n)})."
    ))
  }
  embargo_n <- as.integer(embargo_n)
  if (embargo_n < 0L) {
    cli::cli_abort(c(
      "x" = "{.arg embargo_n} must be >= 0.",
      "i" = "Got {.val {embargo_n}}."
    ))
  }
  if (length(train_idx) == 0L || length(test_idx) == 0L) return(train_idx)

  if (embargo_n == 0L) return(train_idx)
  test_end <- max(test_idx)
  embargo_zone <- seq.int(test_end + 1L, test_end + embargo_n)
  train_idx[!(train_idx %in% embargo_zone)]
}


# ── 3. Combinatorial paths ───────────────────────────────────────────────────

#' Enumerate all C(n_groups, n_test_groups) train/test index pairs
#'
#' Divides \code{1:n_groups} into groups and returns every combination of
#' \code{n_test_groups} groups as the test set, with the remaining groups as
#' the complementary training set.  This produces the \eqn{C(N,k)} paths used
#' in Combinatorial Purged Cross-Validation (CPCV).
#'
#' @param n_groups     Positive integer.  Total number of equal-sized groups
#'   (the \eqn{N} in \eqn{C(N,k)}).
#' @param n_test_groups Positive integer \eqn{\le} \code{n_groups - 1}.
#'   Number of groups to assign to the test set in each combination.
#'
#' @return A list of length \code{choose(n_groups, n_test_groups)}.  Each
#'   element is a named list:
#'   \describe{
#'     \item{train}{Integer vector of group indices in the training set.}
#'     \item{test}{Integer vector of group indices in the test set.}
#'   }
#'
#' @details
#' Group indices are 1-based integers from \code{1} to \code{n_groups}.
#' The caller is responsible for mapping group indices to actual observation
#' indices (e.g., by pre-dividing the timeline into groups and looking up
#' which observations belong to each group).
#'
#' @references
#' López de Prado, M. (2018). \emph{Advances in Financial Machine Learning},
#' Wiley, Ch. 12 (Combinatorial Purged Cross-Validation).
#'
#' Bailey, D., Borwein, J., López de Prado, M., & Zhu, Q. (2014).
#' "The Probability of Backtest Overfitting."
#' \emph{Journal of Computational Finance}, 20(4), 39–70.
#'
#' @family cpcv
#' @export
#'
#' @examples
#' paths <- hd_cpcv_paths(n_groups = 6L, n_test_groups = 2L)
#' length(paths)  # 15 = C(6,2)
#' paths[[1]]$train  # group indices in training set
#' paths[[1]]$test   # group indices in test set
hd_cpcv_paths <- function(n_groups, n_test_groups) {
  if (!is.numeric(n_groups) || length(n_groups) != 1L || n_groups < 2L) {
    cli::cli_abort(c(
      "x" = "{.arg n_groups} must be an integer >= 2.",
      "i" = "Got {.val {n_groups}}."
    ))
  }
  if (!is.numeric(n_test_groups) || length(n_test_groups) != 1L) {
    cli::cli_abort(c(
      "x" = "{.arg n_test_groups} must be a single positive integer.",
      "i" = "Got {.val {n_test_groups}}."
    ))
  }
  n_groups      <- as.integer(n_groups)
  n_test_groups <- as.integer(n_test_groups)
  if (n_test_groups < 1L || n_test_groups >= n_groups) {
    cli::cli_abort(c(
      "x" = "{.arg n_test_groups} must be between 1 and {n_groups - 1L}.",
      "i" = "Got {.val {n_test_groups}} with {.arg n_groups} = {.val {n_groups}}."
    ))
  }

  all_groups  <- seq_len(n_groups)
  test_combos <- utils::combn(all_groups, n_test_groups, simplify = FALSE)

  lapply(test_combos, function(test_grps) {
    list(
      train = sort(setdiff(all_groups, test_grps)),
      test  = sort(test_grps)
    )
  })
}


# ── 4. Probability of Backtest Overfitting ───────────────────────────────────

#' Probability of Backtest Overfitting (PBO) via CPCV path distribution
#'
#' Computes the fraction of CPCV paths on which the in-sample (IS) best
#' strategy ranks below the OOS median — the Probability of Backtest
#' Overfitting (PBO) of Bailey et al. (2014).
#'
#' @param is_scores  Numeric matrix or data frame with one row per path and
#'   one column per strategy.  Entry \code{[i, j]} is the in-sample
#'   performance of strategy \code{j} on path \code{i}'s training folds.
#' @param oos_scores Numeric matrix or data frame of the same dimensions as
#'   \code{is_scores}.  Entry \code{[i, j]} is the out-of-sample performance
#'   of strategy \code{j} on path \code{i}'s test folds.
#'
#' @return A named list with:
#'   \describe{
#'     \item{pbo}{Numeric scalar in \eqn{[0,1]}.  The estimated PBO.
#'       Values near 1 indicate strong evidence of overfitting; values near 0
#'       indicate the IS-best strategy tends to rank above median OOS.}
#'     \item{n_paths}{Integer.  Number of paths used.}
#'     \item{n_strategies}{Integer.  Number of strategies compared.}
#'     \item{is_best_idx}{Integer vector, length \code{n_paths}.  Column index
#'       (strategy index) of the IS-best strategy on each path.}
#'     \item{oos_rank_pct}{Numeric vector, length \code{n_paths}.  OOS
#'       percentile rank (0 to 1) of the IS-best strategy on each path, where
#'       1 = best OOS rank.}
#'   }
#'
#' @details
#' Algorithm:
#' \enumerate{
#'   \item For each path \code{i}, identify the IS-best strategy
#'     \code{j* = argmax(is_scores[i,])}.
#'   \item Compute the OOS percentile rank of strategy \code{j*} on path \code{i}
#'     relative to all strategies on the same path.
#'   \item \code{PBO = mean(oos_rank_pct < 0.5)} — the fraction of paths where
#'     the IS-best selection ranks below the OOS median.
#' }
#'
#' @references
#' Bailey, D., Borwein, J., López de Prado, M., & Zhu, Q. (2014).
#' "The Probability of Backtest Overfitting."
#' \emph{Journal of Computational Finance}, 20(4), 39–70.
#' \doi{10.21314/JCF.2015.322}
#'
#' @family cpcv
#' @export
#'
#' @examples
#' set.seed(42L)
#' n_paths <- 15L
#' n_strat <- 6L
#' # Anti-correlated IS/OOS → IS-best is always OOS-worst → PBO ≈ 1
#' is_scores  <- matrix(rnorm(n_paths * n_strat), n_paths, n_strat)
#' oos_scores <- -is_scores + matrix(rnorm(n_paths * n_strat, sd = 0.1), n_paths, n_strat)
#' hd_pbo(is_scores, oos_scores)$pbo  # near 1
#'
#' # Perfectly correlated IS/OOS → IS-best is always OOS-best → PBO ≈ 0
#' oos_scores_good <- is_scores + matrix(rnorm(n_paths * n_strat, sd = 0.1), n_paths, n_strat)
#' hd_pbo(is_scores, oos_scores_good)$pbo  # near 0
hd_pbo <- function(is_scores, oos_scores) {
  is_scores  <- as.matrix(is_scores)
  oos_scores <- as.matrix(oos_scores)

  if (!identical(dim(is_scores), dim(oos_scores))) {
    cli::cli_abort(c(
      "x" = "{.arg is_scores} and {.arg oos_scores} must have the same dimensions.",
      "i" = "is_scores: {.val {dim(is_scores)}}, oos_scores: {.val {dim(oos_scores)}}."
    ))
  }
  if (anyNA(is_scores) || anyNA(oos_scores)) {
    cli::cli_warn(c(
      "!" = "NA values found in score matrices.",
      "i" = "Paths with any NA are excluded from the PBO calculation."
    ))
  }

  n_paths      <- nrow(is_scores)
  n_strategies <- ncol(is_scores)

  if (n_paths < 2L) {
    cli::cli_abort(c(
      "x" = "At least 2 paths are required to compute PBO.",
      "i" = "Got {.val {n_paths}} path(s)."
    ))
  }
  if (n_strategies < 2L) {
    cli::cli_abort(c(
      "x" = "At least 2 strategies are required to compute PBO.",
      "i" = "Got {.val {n_strategies}} strategy/strategies."
    ))
  }

  # For each path, identify the IS-best strategy (column with highest IS score)
  is_best_idx <- apply(is_scores, 1L, function(row) {
    if (all(is.na(row))) return(NA_integer_)
    which.max(row)
  })

  # Compute OOS rank (as percentile) of the IS-best strategy on each path
  oos_rank_pct <- vapply(seq_len(n_paths), function(i) {
    if (is.na(is_best_idx[i])) return(NA_real_)
    oos_row    <- oos_scores[i, ]
    if (all(is.na(oos_row))) return(NA_real_)
    best_score <- oos_row[is_best_idx[i]]
    if (is.na(best_score)) return(NA_real_)
    # Fraction of strategies with OOS score <= best_score (1 = best)
    mean(oos_row <= best_score, na.rm = TRUE)
  }, numeric(1L))

  # PBO = fraction of paths where IS-best ranks below OOS median (rank < 0.5)
  valid       <- !is.na(oos_rank_pct)
  pbo_value   <- mean(oos_rank_pct[valid] < 0.5)

  list(
    pbo           = pbo_value,
    n_paths       = sum(valid),
    n_strategies  = n_strategies,
    is_best_idx   = is_best_idx,
    oos_rank_pct  = oos_rank_pct
  )
}
