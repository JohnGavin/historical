testthat::local_edition(3)

# Regression test for #691 -- PARTIAL, read this before trusting a green run.
#
# What this test DOES catch: `ann_rf` was added to 11 metrics targets (#677
# slice 4, #686) without being added to the corresponding hand-maintained
# `<prefix>_units` maps the registry writers pass to
# historicaldata::hd_metric_record(). Because hd_metric_record() aborts on
# any column with no declared unit (#640), every one of those writers began
# erroring -- hidden by `error = "continue"` in docs/_targets.R (see #691).
# Removing an entry from any unit map covered below (as #691 removed none,
# but as a future edit could) makes this test fail.
#
# What this test does NOT catch, even after the fix below: as originally
# written, `required` was a hardcoded list living in this test file, so the
# test failed only when a units map REMOVED a covered column -- not when a
# metrics target ADDED a new one. #691's actual defect was the addition of
# `ann_rf` to a metrics target with no matching addition to the units map,
# and at the time `ann_rf` was added, this test's hardcoded `required` would
# not have listed it either: the same hand-maintenance that failed for the
# units map fails identically for a hardcoded expectation. Flagged in review
# on #692 (https://github.com/JohnGavin/historical/pull/692#issuecomment,
# see also #693): "this test would not have caught #691."
#
# The fix (#693 follow-up): for 9 of the 11 cases below, `required` is no
# longer hand-maintained here -- it is derived at test time from the same
# plan-file source that builds the metrics row, via the AST extractors
# below (`.derive_required_from_tibble()`, `.extract_intersect_allowlist()`).
# Adding a numeric column to one of those 9 metrics-computing functions now
# flows straight into `required` and the test fails until the matching unit
# is added -- closing the gap named above for those cases. Two cases remain
# hand-declared (`mode = "declared"`) because deriving them would need a
# cross-file AST walk or type inference this test does not attempt; see the
# per-case comments for exactly why, and #668 for the general problem this
# is one concrete instance of.
#
# The units maps themselves are locals inside each writer's helper function,
# so they cannot be imported and inspected directly -- this test statically
# parses each plan file's AST (parse(), no evaluation of target bodies, no
# store build -- a worktree must not build the store, see .claude/CLAUDE.md
# "Verifying a change") to extract the literal `<prefix>_units <- c(...)`
# assignment and the metrics-computing source it must cover.
#
# `hd_metric_record()`'s wide-form path
# (.normalise_metric_long(), packages/historicaldata/R/registry_metrics.R:
# 408-431) only requires a unit for NUMERIC, non-NA columns of the selected
# metric_cols -- character columns (e.g. `strategy`) and Date columns (e.g.
# `window_start`) are auto-skipped regardless of whether the map covers
# them. Each tibble-derived case below therefore names a small, stable
# `exclude` set of the non-numeric columns its constructor emits (an
# UNRECOGNISED excluded column added later would make `required` include it
# and the test would fail asking for a unit that isn't actually needed --
# loud and wrong-in-the-safe-direction, not silent, per
# .claude/rules/fail-loud-not-null.md).

# ── AST-based extractor for a local `<varname> <- c(...)` assignment ──────
# Walks the parsed (unevaluated) expression tree of `file` looking for an
# assignment whose LHS is the symbol `varname` and whose RHS is a call
# (almost always `c(...)`). Returns the evaluated RHS -- safe here because
# every `<prefix>_units` map in this repo is a literal named character
# vector with no external references (verified by inspection for all 11
# call sites this test covers).
.extract_units_map <- function(file, varname) {
  exprs <- parse(file, keep.source = FALSE)
  found <- NULL
  # Calls like `full_row[, metric_cols, drop = FALSE]` leave an empty
  # (missing) argument slot in their parse tree; as.list() surfaces it as
  # R's internal missing-arg sentinel, and merely referencing that binding
  # (even to test its class) raises "argument is missing, with no default".
  # tryCatch() around every touch of a list element guards against it.
  is_call_safe <- function(x) tryCatch(is.call(x), error = function(err) FALSE)
  walk <- function(e) {
    if (!is.null(found) || !is_call_safe(e)) {
      return(invisible())
    }
    if (identical(e[[1]], as.symbol("<-")) &&
      is.symbol(e[[2]]) && identical(as.character(e[[2]]), varname)) {
      found <<- eval(e[[3]])
      return(invisible())
    }
    for (part in as.list(e)) {
      if (!is.null(found)) break
      if (is_call_safe(part)) walk(part)
    }
  }
  for (e in exprs) {
    if (!is.null(found)) break
    walk(e)
  }
  if (is.null(found)) {
    # basename(), not the full path -- keeps the abort message (and its
    # snapshot) portable across checkouts/CI per portable-build-artifacts.
    cli::cli_abort(c(
      "x" = "Could not find {.code {varname} <- c(...)} in {.file {basename(file)}}.",
      "i" = "The unit map may have been renamed or restructured."
    ))
  }
  found
}

# ── AST-based extractor for a local `<varname> <- <call>` assignment,
# returning the RHS UNEVALUATED (unlike .extract_units_map above, which
# evals). Used by .extract_intersect_allowlist() below, where the RHS is an
# `intersect(...)` call and only its first argument should be evaluated.
.extract_assignment_rhs <- function(file, varname) {
  exprs <- parse(file, keep.source = FALSE)
  found <- NULL
  is_call_safe <- function(x) tryCatch(is.call(x), error = function(err) FALSE)
  walk <- function(e) {
    if (!is.null(found) || !is_call_safe(e)) {
      return(invisible())
    }
    if (identical(e[[1]], as.symbol("<-")) &&
      is.symbol(e[[2]]) && identical(as.character(e[[2]]), varname)) {
      found <<- e[[3]]
      return(invisible())
    }
    for (part in as.list(e)) {
      if (!is.null(found)) break
      if (is_call_safe(part)) walk(part)
    }
  }
  for (e in exprs) {
    if (!is.null(found)) break
    walk(e)
  }
  if (is.null(found)) {
    cli::cli_abort(c(
      "x" = "Could not find {.code {varname} <- ...} in {.file {basename(file)}}.",
      "i" = "The assignment may have been renamed or restructured."
    ))
  }
  found
}

# ── AST-based extractor for a top-level `<fn_name> <- function(...) {...}`
# assignment. Returns the function's BODY, unevaluated -- the caller walks
# it to find the tibble() call(s) that construct the metrics row. Scoped to
# one function: nested function definitions inside the body are walked too
# (so a tibble() built via a helper called from an early return, e.g.
# .compute_cmr_metrics()'s NA-row branch, is still found), but tibble()
# calls in unrelated top-level functions elsewhere in the file are not,
# because the walk never leaves the matched function's body.
.extract_function_body <- function(file, fn_name) {
  exprs <- parse(file, keep.source = FALSE)
  found <- NULL
  is_call_safe <- function(x) tryCatch(is.call(x), error = function(err) FALSE)
  walk <- function(e) {
    if (!is.null(found) || !is_call_safe(e)) {
      return(invisible())
    }
    if (identical(e[[1]], as.symbol("<-")) &&
      is.symbol(e[[2]]) && identical(as.character(e[[2]]), fn_name) &&
      is_call_safe(e[[3]]) && identical(e[[3]][[1]], as.symbol("function"))) {
      found <<- e[[3]][[3]] # body of `function(formals) body`
      return(invisible())
    }
    for (part in as.list(e)) {
      if (!is.null(found)) break
      if (is_call_safe(part)) walk(part)
    }
  }
  for (e in exprs) {
    if (!is.null(found)) break
    walk(e)
  }
  if (is.null(found)) {
    cli::cli_abort(c(
      "x" = "Could not find {.code {fn_name} <- function(...) {{...}}} in {.file {basename(file)}}.",
      "i" = "The function may have been renamed or restructured."
    ))
  }
  found
}

# Matches a call headed by the symbol `tibble` (e.g. `tibble(...)`, after
# `library(tibble)`/`library(dplyr)`) or by any `<pkg>::tibble` namespaced
# call (`tibble::tibble(...)`, `dplyr::tibble(...)`).
.is_tibble_call <- function(e) {
  if (!is.call(e)) {
    return(FALSE)
  }
  head <- e[[1]]
  if (is.symbol(head) && identical(as.character(head), "tibble")) {
    return(TRUE)
  }
  if (is.call(head) && length(head) == 3 &&
    identical(head[[1]], as.symbol("::")) &&
    identical(as.character(head[[3]]), "tibble")) {
    return(TRUE)
  }
  FALSE
}

# Walks a (sub)expression tree collecting the NAMED argument names of every
# tibble()-constructor call found anywhere inside it -- across multiple
# tibble() calls if the function has more than one (e.g. an early-return
# NA-row plus the main row), the union is returned, since either shape may
# be what actually reaches hd_metric_record().
.extract_tibble_column_names <- function(body_expr) {
  all_names <- character(0)
  is_call_safe <- function(x) tryCatch(is.call(x), error = function(err) FALSE)
  walk <- function(e) {
    if (!is_call_safe(e)) {
      return(invisible())
    }
    if (.is_tibble_call(e)) {
      args <- as.list(e)[-1]
      nms <- names(args)
      if (!is.null(nms)) {
        all_names <<- union(all_names, nms[nzchar(nms)])
      }
    }
    for (part in as.list(e)) {
      if (is_call_safe(part)) walk(part)
    }
  }
  walk(body_expr)
  all_names
}

# Combines the two extractors above: the numeric-column set a metrics-
# computing function emits, minus its known non-numeric/excluded columns.
.derive_required_from_tibble <- function(file, fn_name, exclude = character(0)) {
  body <- .extract_function_body(file, fn_name)
  all_cols <- .extract_tibble_column_names(body)
  setdiff(all_cols, exclude)
}

# For the one writer (pso_optimal) that uses an explicit intersect()
# allow-list instead of a setdiff()-based exclusion (R/plan_portfolio_opt.R):
# `pso_cols <- intersect(c("months", "opt_cagr", ...), names(full_row))`.
# The literal first argument to intersect() IS the required set -- it is
# the same allow-list the writer itself uses to select what reaches
# hd_metric_record(), so this extractor and the writer can never disagree.
.extract_intersect_allowlist <- function(file, varname) {
  rhs <- .extract_assignment_rhs(file, varname)
  if (!is.call(rhs) || !identical(rhs[[1]], as.symbol("intersect"))) {
    cli::cli_abort(c(
      "x" = "{.code {varname}} in {.file {basename(file)}} is not an {.code intersect(...)} call.",
      "i" = "This extractor only handles the explicit allow-list pattern; the case may need re-classifying."
    ))
  }
  eval(rhs[[2]])
}

plan_dir <- here::here("R")

# One entry per registry writer's unit map.
#
# mode = "tibble":    `required` is derived at test time from the named
#                      columns of `fn_name`'s tibble() constructor(s) in
#                      `plan_file`, minus `exclude` (its known non-numeric
#                      columns -- character/Date, auto-skipped by
#                      hd_metric_record() regardless of unit coverage).
# mode = "intersect":  `required` is derived from the literal allow-list
#                      argument to `intersect()` assigned to
#                      `allowlist_varname` in `plan_file`.
# mode = "declared":   `required` is hand-maintained here because deriving
#                      it would need more than a single-function AST walk
#                      (see the case's comment for why).
unit_map_cases <- list(
  list(
    plan_file = "plan_ltr_momentum.R", varname = "ltr_units",
    mode = "tibble", fn_name = "compute_ltr_metrics",
    exclude = c("period")
  ),
  list(
    plan_file = "plan_avoid_worst.R", varname = "aw_units",
    mode = "tibble", fn_name = "metrics_for",
    # strategy/period/scenario are character; window_start/window_end are
    # Date -- all auto-skipped by hd_metric_record()'s numeric-only path.
    exclude = c("strategy", "period", "scenario", "window_start", "window_end")
  ),
  list(
    plan_file = "plan_turn_of_month.R", varname = "tom_units",
    mode = "tibble", fn_name = "calc",
    exclude = c("period")
  ),
  list(
    plan_file = "plan_risk_state.R", varname = "rsc_units",
    mode = "tibble", fn_name = "calc_metrics",
    exclude = c("strategy", "period", "window_start", "window_end")
  ),
  list(
    plan_file = "plan_commodities_mean_reversion.R", varname = "cmr_units",
    mode = "tibble", fn_name = ".compute_cmr_metrics",
    exclude = c("lookback")
  ),
  list(
    plan_file = "plan_factormax.R", varname = "fm_units",
    mode = "tibble", fn_name = "calc_metrics",
    exclude = c("period")
  ),
  list(
    plan_file = "plan_drif.R", varname = "drif_units",
    mode = "tibble", fn_name = "calc_metrics",
    exclude = c("period")
  ),
  list(
    plan_file = "plan_stock_backtest.R", varname = "stk_units",
    mode = "tibble", fn_name = "calc_backtest_metrics",
    exclude = c("period")
  ),
  list(
    plan_file = "plan_xgb_signal.R", varname = "xgb_units",
    # calc_backtest_metrics() is defined once in plan_stock_backtest.R and
    # shared by both stk_units and xgb_units (R/plan_xgb_signal.R:320-324
    # cites the same function) -- derive from the file that actually
    # defines it, not the file whose unit map is being checked.
    mode = "tibble", fn_name = "calc_backtest_metrics",
    fn_file = "plan_stock_backtest.R",
    exclude = c("period")
  ),
  list(
    plan_file = "plan_portfolio_opt.R", varname = "pso_units",
    # `ann_rf` exists on port_metrics but `pso_cols` (R/plan_portfolio_opt.R,
    # an explicit intersect() allow-list, unlike the setdiff()-based
    # exclusion every other writer here uses) never selects it, so this
    # writer does not currently attempt to write ann_rf -- see the comment
    # at its call site for why. Deriving from the same allow-list means
    # this case and the writer can never drift apart.
    mode = "intersect", allowlist_varname = "pso_cols"
  ),
  list(
    plan_file = "plan_mom_prepeak.R", varname = "mom_prepeak_units",
    mode = "declared",
    # NOT derived. .mom_prepeak_compute_metrics()'s tibble() (packages/
    # historicaldata/R/utils_mom_prepeak_metrics.R:124-138) lives in a
    # DIFFERENT FILE from the plan file that owns mom_prepeak_units, and
    # `ann_rf` is appended to the result AFTER that tibble() returns, via
    # `m$ann_rf <- round(.mom_prepeak_ann_rf(...) * 100, 2)`
    # (R/plan_mom_prepeak.R:157/165/173) -- a `$<-` mutation, not a tibble()
    # argument, so .extract_tibble_column_names() cannot see it. Deriving
    # this case would need a cross-file AST walk PLUS `$<-`-mutation
    # tracking -- meaningfully more machinery than the single-function
    # walk the other 9 cases use, for one case. Left hand-declared per the
    # judgement call in #693 (blown_up/loss_clustered are logical, auto-
    # skipped).
    required = c(
      "n_months", "sharpe", "cagr", "vol", "max_dd",
      "bankrupt_month", "avg_dd_days", "max_dd_days",
      "max_cons_losses", "ann_rf"
    )
  )
)

for (case in unit_map_cases) {
  local({
    this_case <- case
    test_that(
      sprintf("%s covers its metrics target's numeric columns (#691, #693)", this_case$varname),
      {
        file <- file.path(plan_dir, this_case$plan_file)
        units_map <- .extract_units_map(file, this_case$varname)

        required <- switch(this_case$mode,
          tibble = {
            fn_file <- if (!is.null(this_case$fn_file)) {
              file.path(plan_dir, this_case$fn_file)
            } else {
              file
            }
            .derive_required_from_tibble(fn_file, this_case$fn_name, this_case$exclude)
          },
          intersect = .extract_intersect_allowlist(file, this_case$allowlist_varname),
          declared = this_case$required,
          cli::cli_abort("Unknown unit_map_cases mode: {this_case$mode}")
        )

        missing <- setdiff(required, names(units_map))
        expect_equal(
          missing, character(0),
          info = sprintf(
            "%s (%s) is missing unit declarations for: %s",
            this_case$varname, this_case$plan_file, paste(missing, collapse = ", ")
          )
        )
      }
    )
  })
}

test_that("mom_prepeak_units declares cagr/vol/max_dd as percent, not fraction (#691)", {
  # .mom_prepeak_compute_metrics() (packages/historicaldata/R/
  # utils_mom_prepeak_metrics.R:128-130) returns round(cagr * 100, 1) etc --
  # PERCENT -- and R/plan_leaderboard.R's .norm_mom_sibling() independently
  # confirms this by dividing cagr/vol/max_dd/ann_rf by 100. The unit map
  # previously declared these three as "fraction", writing values 100x too
  # large into bt.metric under a unit that claimed otherwise (#691's second
  # defect).
  file <- file.path(plan_dir, "plan_mom_prepeak.R")
  units_map <- .extract_units_map(file, "mom_prepeak_units")
  expect_equal(unname(units_map["cagr"]), "percent")
  expect_equal(unname(units_map["vol"]), "percent")
  expect_equal(unname(units_map["max_dd"]), "percent")
})

test_that(".extract_units_map aborts informatively when the variable is not found", {
  file <- file.path(plan_dir, "plan_ltr_momentum.R")
  expect_snapshot(error = TRUE, .extract_units_map(file, "nonexistent_units"))
})
