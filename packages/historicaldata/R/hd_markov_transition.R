# Markov transition-matrix diagnostic for discrete regime/state series.
#
# Origin: issue #838. The aligrithm article (Borrego Roldan 2024) estimates
# P(state_t+1 = j | state_t = i) over its 3-state vol regime classifier and
# reports the diagonal persistence probabilities (0.82-0.98 depending on
# window) as evidence the classifier is detecting real persistence, not
# noise. Neither R/plan_risk_state.R (rsc_regime$regime, #51) nor
# R/plan_regime.R (regime_classification$regime, #34) computes this -- both
# classify a state per period but never estimate how likely that state is
# to persist. This function fills that gap; check_markov_diagonal_dominance()
# (R/plan_qa_gates.R, QA gate S32) asserts diagonal dominance against it.

#' Estimate a first-order Markov transition matrix from a discrete state series
#'
#' Counts observed one-step transitions in `state` (in time order) and
#' returns the transition-probability matrix `P(state_t+1 = j | state_t =
#' i)` plus the diagonal persistence probabilities `P(stay in state i)`. Per
#' `.claude/rules/fail-loud-not-null.md`, an unrecognised or insufficient
#' state series aborts loudly rather than silently returning `NA` or
#' dropping rows without disclosure.
#'
#' @param state A character or factor vector of state labels, ordered in
#'   time (`state[t]` immediately precedes `state[t + 1]`). Must contain at
#'   least 2 distinct non-`NA` values.
#' @param states `NULL` (default), or a character vector declaring the
#'   allowed vocabulary. When `state` is a factor, `levels(state)` is used
#'   as the declared vocabulary UNLESS `states` is supplied explicitly, in
#'   which case `states` wins. When `state` is a plain character vector and
#'   `states` is `NULL`, the vocabulary is inferred from the observed
#'   non-`NA` values. Any observed value not in the declared vocabulary
#'   aborts -- this function never silently coerces an unrecognised state to
#'   `NA` or drops it.
#'
#' @return Named list:
#'   \describe{
#'     \item{transition_matrix}{`n_states` x `n_states` numeric matrix, rows
#'       sum to 1 (row/column named by state). Row `i`, column `j` is
#'       `P(state_t+1 = j | state_t = i)`. A row is entirely `NA` when that
#'       state was never observed as an origin (`state_t`) -- see
#'       `persistence$n_from`.}
#'     \item{counts}{Same shape, raw transition counts (integer matrix).}
#'     \item{persistence}{Tibble with columns `state`, `p_stay`, `n_from` --
#'       the diagonal of `transition_matrix`, one row per declared state, in
#'       declared order.}
#'     \item{states}{Character vector, the declared vocabulary in order.}
#'     \item{n_transitions}{Integer, the number of valid (non-`NA` origin
#'       AND destination) one-step transitions counted.}
#'     \item{n_dropped}{Integer, the number of adjacent pairs excluded
#'       because at least one side was `NA`.}
#'   }
#'
#' @examples
#' # Sticky 2-state series: state persists most of the time
#' s <- c("low", "low", "low", "high", "high", "low", "low", "low")
#' out <- hd_markov_transition(s)
#' out$persistence
#'
#' @family regime-diagnostics
#' @export
hd_markov_transition <- function(state, states = NULL) {
  if (!(is.character(state) || is.factor(state))) {
    cli::cli_abort(c(
      "x" = "{.arg state} must be a character or factor vector.",
      "i" = "Got class {.cls {class(state)}}."
    ))
  }
  if (length(state) < 2L) {
    cli::cli_abort(c(
      "x" = "{.arg state} must have at least 2 observations to estimate transitions.",
      "i" = "Got length {length(state)}."
    ))
  }

  is_factor_input <- is.factor(state)
  state_chr <- as.character(state)

  declared <- states
  if (is.null(declared)) {
    declared <- if (is_factor_input) {
      levels(state)
    } else {
      sort(unique(state_chr[!is.na(state_chr)]))
    }
  } else {
    if (!is.character(declared) || length(declared) == 0L ||
        anyDuplicated(declared) > 0L || anyNA(declared)) {
      cli::cli_abort(c(
        "x" = "{.arg states} must be a non-empty character vector with no duplicates or NAs.",
        "i" = "Got {.val {declared}}."
      ))
    }
  }

  if (length(declared) < 2L) {
    cli::cli_abort(c(
      "x" = "The declared state vocabulary has fewer than 2 distinct states.",
      "i" = "A Markov transition matrix needs >= 2 states to be meaningful. Got: {.val {declared}}.",
      "i" = "hd_markov_transition() (per fail-loud-not-null.md) aborts rather than returning a degenerate 1x1 matrix."
    ))
  }

  observed <- unique(state_chr[!is.na(state_chr)])
  unrecognised <- setdiff(observed, declared)
  if (length(unrecognised) > 0L) {
    cli::cli_abort(c(
      "x" = "{.arg state} contains value{?s} outside the declared vocabulary: {.val {unrecognised}}.",
      "i" = "Declared vocabulary: {.val {declared}}.",
      "i" = "hd_markov_transition() (per fail-loud-not-null.md) never silently drops or coerces an unrecognised state."
    ))
  }

  n_distinct_observed <- length(observed)
  if (n_distinct_observed < 2L) {
    cli::cli_abort(c(
      "x" = "{.arg state} has only {n_distinct_observed} distinct observed value{?s}.",
      "i" = "Observed: {.val {observed}}.",
      "i" = "A transition matrix over a constant series is degenerate -- hd_markov_transition() aborts rather than returning one."
    ))
  }

  from <- state_chr[-length(state_chr)]
  to   <- state_chr[-1]
  valid <- !is.na(from) & !is.na(to)
  n_dropped <- sum(!valid)
  if (n_dropped > 0L) {
    cli::cli_warn(c(
      "!" = "Dropped {n_dropped} adjacent pair{?s} with a missing state on either side.",
      "i" = paste0(
        "hd_markov_transition() excludes these from the transition count rather ",
        "than silently coercing them (fail-loud-not-null.md)."
      )
    ))
  }
  from <- from[valid]
  to   <- to[valid]

  from_f <- factor(from, levels = declared)
  to_f   <- factor(to,   levels = declared)
  counts_tbl <- table(from_f, to_f)
  counts <- matrix(
    as.integer(counts_tbl),
    nrow = length(declared), ncol = length(declared),
    dimnames = list(declared, declared)
  )

  row_sums <- rowSums(counts)
  has_origin <- row_sums > 0L
  probs <- matrix(
    NA_real_,
    nrow = length(declared), ncol = length(declared),
    dimnames = list(declared, declared)
  )
  probs[has_origin, ] <- counts[has_origin, , drop = FALSE] / row_sums[has_origin]

  persistence <- tibble::tibble(
    state  = declared,
    p_stay = unname(diag(probs)),
    n_from = unname(as.integer(row_sums))
  )

  list(
    transition_matrix = probs,
    counts            = counts,
    persistence       = persistence,
    states            = declared,
    n_transitions     = sum(counts),
    n_dropped         = as.integer(n_dropped)
  )
}
