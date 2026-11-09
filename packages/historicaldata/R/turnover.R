# Portfolio turnover: one definition (#567 A1, #663 Phase 1)
#
# Before this file, four call sites computed turnover four ways (one-way /2,
# per-day vector, vs-drifted weights, L1 without the /2). hd_turnover() is the
# single definition; hd_turnover_series() applies it period by period to a
# long table of weights, completing the (period x name) grid so a name that
# EXITS the book counts as a trade (the #567 A2 grid-completion fix).
#
# Measurement only: nothing here alters a weight, a return or a cost.

#' Turnover between two weight vectors
#'
#' @title Portfolio Turnover (`hd_turnover`)
#'
#' @description
#' Turnover is the amount traded to move from the weights held at the end of
#' the previous period to the weights wanted now:
#' \deqn{\tau = \tfrac{1}{2}\sum_i |w_i - \tilde w_{i}|}{tau = 0.5 * sum(abs(w - w_drifted))}
#' where \eqn{\tilde w} is the previous weight vector, optionally **drifted**
#' by the returns earned since it was set. `side = "one"` (default) reports
#' the one-way figure above (value bought, which equals value sold in a
#' self-financing book); `side = "two"` reports the two-way figure
#' \eqn{\sum_i |w_i - \tilde w_i|} (bought plus sold).
#'
#' **Why drift matters.** A book that holds equal weights and never trades
#' still sees its weights move with prices. Comparing the new target against
#' the *stale* previous weights counts that price drift as trading and
#' overstates turnover. With `drift_ret` supplied, the previous weights are
#' first moved to where the market left them,
#' \eqn{\tilde w_i = w^{prev}_i (1 + r_i) / (1 + \sum_j w^{prev}_j r_j)},
#' so a book that does not trade has turnover exactly 0. The denominator is
#' the portfolio's own gross return, so it is correct for long-only,
#' long-short and partly-in-cash books. Cash that is not listed is treated
#' as earning 0 and its trades are not counted; to count moves into and out
#' of cash, list it as a name (for example `CASH`) with its own return, so
#' that the weights sum to the book's whole value.
#'
#' **Names that enter or exit.** Weights are aligned by name over the union
#' of both vectors; a name missing from one side has weight 0 there. An exit
#' (present before, absent now) therefore counts as a sale. Unnamed vectors
#' are aligned by position and must have the same length. Mixing named and
#' unnamed input is an error.
#'
#' @param w Numeric vector of the new (target) weights. May be negative
#'   (shorts). No `NA`, `NaN` or infinite values. Either fully named (unique,
#'   non-empty names) or fully unnamed. Length 0 means an all-cash book.
#' @param w_prev Numeric vector of the previous weights, same naming rules as
#'   `w`, or `NULL` / length 0 for "nothing held before" (the first period:
#'   turnover is then the cost of entering, `sum(abs(w)) / 2`).
#' @param drift_ret Optional numeric vector of the returns each previous
#'   holding earned over the period just ended. Named like `w_prev` and
#'   covering every name in it (extra names are ignored), or unnamed with the
#'   same length as `w_prev`. Must be finite, and the previous book's gross
#'   return must leave a positive value (`1 + sum(w_prev * drift_ret) > 0`).
#'   `NULL` (default) compares against the previous weights as given.
#' @param side `"one"` (default) for one-way turnover, `"two"` for two-way.
#'
#' @return A single non-negative number.
#'
#' @examples
#' # Sell A, buy B: one-way turnover is the 50% that changed hands.
#' hd_turnover(c(A = 0, B = 1), c(A = 1, B = 0))
#'
#' # A name that exits (C is absent from `w`) still counts as a sale.
#' hd_turnover(c(A = 0.5, B = 0.5), c(A = 0.4, B = 0.4, C = 0.2))
#'
#' # A book that does not trade has zero turnover once drift is applied,
#' # even though prices moved its weights: A rose 20%, B was flat.
#' w_prev <- c(A = 0.6, B = 0.4)
#' w_now  <- w_prev * c(1.2, 1) / sum(w_prev * c(1.2, 1))
#' hd_turnover(w_now, w_prev)                                        # stale: > 0
#' hd_turnover(w_now, w_prev, drift_ret = c(A = 0.2, B = 0))         # drifted: 0
#'
#' @family risk_metrics
#' @export
hd_turnover <- function(w, w_prev = NULL, drift_ret = NULL,
                        side = c("one", "two")) {
  if (identical(side, c("one", "two"))) side <- "one"
  if (!is.character(side) || length(side) != 1L || is.na(side) ||
      !side %in% c("one", "two")) {
    cli::cli_abort(c(
      "{.arg side} must be {.val one} or {.val two}.",
      "x" = "Got {.val {side}}."
    ))
  }

  .hd_turnover_check_weights(w, "w")
  if (is.null(w_prev)) w_prev <- numeric(0)
  .hd_turnover_check_weights(w_prev, "w_prev")

  if (!is.null(drift_ret)) {
    if (length(w_prev) == 0L) {
      cli::cli_abort(c(
        "{.arg drift_ret} needs a previous book to drift.",
        "x" = "{.arg w_prev} is {.code NULL} or empty, but {.arg drift_ret} was supplied.",
        "i" = "For the first period pass {.code drift_ret = NULL}."
      ))
    }
    w_prev <- .hd_turnover_drift(w_prev, drift_ret)
  }

  aligned <- .hd_turnover_align(w, w_prev)

  total <- sum(abs(aligned$new - aligned$prev))
  if (side == "one") total / 2 else total
}

#' Turnover period by period from a long table of weights
#'
#' @title Turnover Series (`hd_turnover_series`)
#'
#' @description
#' Applies [hd_turnover()] to each consecutive pair of periods in a long
#' table of weights, one row per held name per period. The (period x name)
#' grid is completed implicitly: a name present in one period and absent in
#' the next is a sale, and a period with no rows at all (listed in `periods`)
#' is an all-cash book.
#'
#' @param weights A data frame with columns `date` (any orderable type),
#'   `name` (character) and `weight` (numeric, finite). At most one row per
#'   `date` and `name`.
#' @param returns Optional data frame with columns `date`, `name`, `ret`: the
#'   return each name earned over the period labelled `date` (the period in
#'   which the weights of `date` were held). When supplied, the previous
#'   period's weights are drifted by these returns before comparison
#'   (see [hd_turnover()]); every name with non-zero weight in the previous
#'   period must have a finite return. `NULL` (default) compares against the
#'   previous weights as given.
#' @param side `"one"` (default) or `"two"`; see [hd_turnover()].
#' @param first What to report for the first period, which has no previous
#'   book: `"entry"` (default) treats it as bought from nothing
#'   (`sum(abs(w)) / 2`); `"na"` reports `NA` so the cost of initial funding
#'   is not averaged in as if it were a rebalance.
#' @param periods Optional vector of every period to report, in any order
#'   (sorted internally). Defaults to the sorted unique `weights$date`. Use
#'   it when a group (a scheme, a strategy) has no rows in some period that
#'   its siblings do, so that the gap counts as an all-cash book rather than
#'   being skipped. Must contain every date in `weights`.
#'
#' @return A [tibble::tibble()] with columns `date` and `turnover`, one row
#'   per period, ascending.
#'
#' @examples
#' w <- data.frame(
#'   date = as.Date(rep(c("2024-01-31", "2024-02-29"), each = 2)),
#'   name = c("A", "B", "B", "C"),
#'   weight = c(0.5, 0.5, 0.5, 0.5)
#' )
#' hd_turnover_series(w)
#'
#' @family risk_metrics
#' @export
hd_turnover_series <- function(weights, returns = NULL, side = c("one", "two"),
                               first = c("entry", "na"), periods = NULL) {
  if (identical(side, c("one", "two"))) side <- "one"
  if (identical(first, c("entry", "na"))) first <- "entry"
  if (!is.character(first) || length(first) != 1L || is.na(first) ||
      !first %in% c("entry", "na")) {
    cli::cli_abort(c(
      "{.arg first} must be {.val entry} or {.val na}.",
      "x" = "Got {.val {first}}."
    ))
  }
  .hd_turnover_check_table(weights, c("date", "name", "weight"), "weights")
  if (!is.numeric(weights$weight) || anyNA(weights$weight) ||
      !all(is.finite(weights$weight))) {
    cli::cli_abort(c(
      "{.field weight} in {.arg weights} must be finite numbers.",
      "i" = "Resolve missingness upstream; {.fn hd_turnover_series} does not drop rows."
    ))
  }
  if (anyNA(weights$date) || anyNA(weights$name)) {
    cli::cli_abort("{.field date} and {.field name} in {.arg weights} must not contain {.val NA}.")
  }
  if (anyDuplicated(weights[c("date", "name")]) > 0L) {
    cli::cli_abort(c(
      "{.arg weights} must have at most one row per {.field date} and {.field name}.",
      "x" = "Found {sum(duplicated(weights[c('date', 'name')]))} duplicated pair{?s}."
    ))
  }
  if (!is.null(returns)) {
    .hd_turnover_check_table(returns, c("date", "name", "ret"), "returns")
  }

  all_periods <- if (is.null(periods)) sort(unique(weights$date)) else sort(unique(periods))
  if (!all(weights$date %in% all_periods)) {
    cli::cli_abort(c(
      "{.arg periods} must contain every {.field date} in {.arg weights}.",
      "x" = "{sum(!unique(weights$date) %in% all_periods)} date{?s} in {.arg weights} not in {.arg periods}."
    ))
  }

  # Rows of weights / returns for each period, by position in all_periods.
  w_by <- split(seq_len(nrow(weights)), factor(match(weights$date, all_periods),
                                               levels = seq_along(all_periods)))
  r_by <- if (is.null(returns)) NULL else {
    split(seq_len(nrow(returns)), factor(match(returns$date, all_periods),
                                         levels = seq_along(all_periods)))
  }
  vec_at <- function(i) {
    rows <- w_by[[i]]
    stats::setNames(weights$weight[rows], weights$name[rows])
  }

  out <- numeric(length(all_periods))
  prev <- NULL
  for (i in seq_along(all_periods)) {
    cur <- vec_at(i)
    if (i == 1L) {
      out[i] <- if (first == "na") NA_real_ else hd_turnover(cur, NULL, side = side)
    } else {
      dr <- NULL
      if (!is.null(r_by)) {
        held <- prev[prev != 0]
        if (length(held) > 0L) {
          rr <- returns[r_by[[i - 1L]], , drop = FALSE]
          dr <- stats::setNames(rr$ret, rr$name)
          miss <- setdiff(names(held), names(dr))
          if (length(miss) > 0L) {
            cli::cli_abort(c(
              "{.arg returns} is missing {length(miss)} held name{?s} for period {.val {all_periods[i - 1L]}}.",
              "x" = "Missing: {.val {utils::head(miss, 5L)}}.",
              "i" = "Drift needs a return for every name with non-zero weight in the previous period."
            ))
          }
          prev_use <- held
          dr <- dr[names(held)]
          out[i] <- hd_turnover(cur, prev_use, drift_ret = dr, side = side)
          prev <- cur
          next
        }
      }
      out[i] <- hd_turnover(cur, prev, side = side)
    }
    prev <- cur
  }
  tibble::tibble(date = all_periods, turnover = out)
}

# ---- internals ---------------------------------------------------------

.hd_turnover_check_table <- function(x, cols, arg, call = rlang::caller_env()) {
  if (!is.data.frame(x)) {
    cli::cli_abort(c(
      "{.arg {arg}} must be a data frame.",
      "x" = "Got {.cls {class(x)}}."
    ), call = call)
  }
  miss <- setdiff(cols, names(x))
  if (length(miss) > 0L) {
    cli::cli_abort(c(
      "{.arg {arg}} is missing required column{?s} {.field {miss}}.",
      "i" = "Required: {.field {cols}}."
    ), call = call)
  }
  invisible(TRUE)
}

.hd_turnover_check_weights <- function(x, arg, call = rlang::caller_env()) {
  if (!is.numeric(x)) {
    cli::cli_abort(c(
      "{.arg {arg}} must be a numeric vector.",
      "x" = "Got {.cls {class(x)}}."
    ), call = call)
  }
  bad <- which(is.na(x) | !is.finite(x))
  if (length(bad) > 0L) {
    cli::cli_abort(c(
      "{.arg {arg}} must not contain {.val NA}, {.val NaN} or infinite values.",
      "x" = "Found {length(bad)} at position{?s} {bad}.",
      "i" = "Resolve missingness upstream; {.fn hd_turnover} does not {.code na.rm}."
    ), call = call)
  }
  nm <- names(x)
  if (!is.null(nm) && length(x) > 0L) {
    if (anyNA(nm) || !all(nzchar(nm)) || anyDuplicated(nm) > 0L) {
      cli::cli_abort(c(
        "Names of {.arg {arg}} must be unique and non-empty.",
        "i" = "Either name every element or none."
      ), call = call)
    }
  }
  invisible(TRUE)
}

# Align new/previous weights; returns list(new, prev) of equal length.
.hd_turnover_align <- function(w, w_prev, call = rlang::caller_env()) {
  if (length(w) == 0L && length(w_prev) == 0L) {
    return(list(new = numeric(0), prev = numeric(0)))
  }
  if (length(w_prev) == 0L) {
    return(list(new = w, prev = stats::setNames(rep(0, length(w)), names(w))))
  }
  if (length(w) == 0L) {
    return(list(new = stats::setNames(rep(0, length(w_prev)), names(w_prev)), prev = w_prev))
  }
  named_w <- !is.null(names(w))
  named_p <- !is.null(names(w_prev))
  if (named_w != named_p) {
    cli::cli_abort(c(
      "{.arg w} and {.arg w_prev} must both be named or both be unnamed.",
      "x" = "{.arg w} is {if (named_w) 'named' else 'unnamed'}; {.arg w_prev} is {if (named_p) 'named' else 'unnamed'}."
    ), call = call)
  }
  if (!named_w) {
    if (length(w) != length(w_prev)) {
      cli::cli_abort(c(
        "Unnamed {.arg w} and {.arg w_prev} must have the same length.",
        "x" = "Got {length(w)} and {length(w_prev)}.",
        "i" = "Name the weights to align them over the union of names."
      ), call = call)
    }
    return(list(new = w, prev = w_prev))
  }
  all_names <- union(names(w_prev), names(w))
  new <- stats::setNames(rep(0, length(all_names)), all_names)
  prev <- new
  new[names(w)] <- w
  prev[names(w_prev)] <- w_prev
  list(new = new, prev = prev)
}

# Drift previous weights by the returns earned since they were set.
.hd_turnover_drift <- function(w_prev, drift_ret, call = rlang::caller_env()) {
  if (!is.numeric(drift_ret) || anyNA(drift_ret) || !all(is.finite(drift_ret))) {
    cli::cli_abort(c(
      "{.arg drift_ret} must be a numeric vector of finite returns.",
      "i" = "Resolve missingness upstream; {.fn hd_turnover} does not {.code na.rm}."
    ), call = call)
  }
  if (is.null(names(w_prev))) {
    if (!is.null(names(drift_ret)) || length(drift_ret) != length(w_prev)) {
      cli::cli_abort(c(
        "With unnamed {.arg w_prev}, {.arg drift_ret} must be unnamed with the same length.",
        "x" = "Got length {length(drift_ret)} for {length(w_prev)} previous weights."
      ), call = call)
    }
    r <- drift_ret
  } else {
    if (is.null(names(drift_ret)) || !all(names(w_prev) %in% names(drift_ret))) {
      cli::cli_abort(c(
        "{.arg drift_ret} must be named and cover every name in {.arg w_prev}.",
        "x" = "Missing: {.val {utils::head(setdiff(names(w_prev), names(drift_ret)), 5L)}}."
      ), call = call)
    }
    r <- drift_ret[names(w_prev)]
  }
  g <- 1 + sum(w_prev * r)
  if (!is.finite(g) || g <= 0) {
    cli::cli_abort(c(
      "The previous book's gross return leaves no positive value to drift.",
      "x" = "{.code 1 + sum(w_prev * drift_ret)} is {.val {g}}.",
      "i" = "Check {.arg drift_ret} is a per-period return (0.02 = +2%), not a level or a percentage."
    ), call = call)
  }
  w_prev * (1 + r) / g
}
