#!/usr/bin/env Rscript
# scripts/check_pkg_staleness.R — post-build check for stale package-source
# consumers (#753).
#
# A change to any file under packages/historicaldata/R/ does NOT invalidate
# the targets that call the changed function, UNLESS that call is tracked by
# one of the two mechanisms #753 added: tar_option_set(imports =
# "historicaldata") in docs/_targets.R (automatic, but only for BARE-name
# calls — targets' own documentation for `imports` states namespaced calls
# like `historicaldata::fn()` are ignored, a limitation of
# codetools::findGlobals()) or an explicit reference to the
# `pkg_source_digest` target (docs/_targets.R) in a target's own command
# (manual, opt-in, not yet adopted by any of the 22 files in this repo that
# call `historicaldata::` directly). A target that falls into neither
# bucket is invisible to `targets`' own dependency graph: tar_make() SKIPS
# it, scripts/build.sh reports PASS, and tar_read() silently serves the
# value computed by the PREVIOUS version of the package function. See
# issue #753 for the full incident (PR #752, CMR lookback window) that
# motivated this script.
#
# WHY THIS IS A SEPARATE SCRIPT, NOT A tar_target() GATE (like the S1-S22
# gates in R/plan_qa_gates.R): the check this script performs — "was some
# OTHER target skipped in a run where the package source actually changed"
# — needs targets::tar_meta()/targets::tar_progress() against the store
# belonging to the CURRENTLY RUNNING pipeline, and both are explicitly
# unsupported there. Confirmed empirically (2026-08-25, scratch pipeline
# under /private/tmp, both functions called from inside a target of the
# same store):
#
#   Error: target gate attempted to run targets::tar_meta() to during a
#   pipeline, which is unsupported except when format is "file" and
#   repository is "local", or if you are reading from a data store that
#   does not belong to the current pipeline. This is because functions
#   like tar_meta() attempt to access or modify the local data store,
#   which may not exist or be properly synced in certain situations. Also,
#   please be aware that some functions like tar_make() and tar_destroy()
#   should never run inside a target. Please find a different workaround
#   for your use case.
#
# (tar_progress() gives the identical error, substituting its own name.)
# So this check runs the same way scripts/check_pipeline_errors.R and
# scripts/check_dashboard_freshness.R already do: AFTER tar_make() has
# exited and the store is no longer "the pipeline currently running" — see
# R/plan_qa_gates.R's check_pkg_source_tracked() (S22) roxygen for the
# "guard the guard" sanity check that DOES live in the pipeline, and why it
# is a narrower, different property than what this script checks.
#
# HOW THE CHECK WORKS (avoiding both the same-run AND the cross-run
# scheduling-order trap -- #911 flaw 2): comparing a candidate target's
# tar_meta() build time against pkg_source_digest's OWN tar_meta() build
# time is unsound, because pkg_source_digest is itself just another target
# in the same DAG, scheduled by `targets` at whatever moment its own
# dependency (pkg_source_files) happens to be evaluated. Two real builds
# (2026-09-26, issue #911) reproduce this at two different scopes:
#   - SAME-RUN scheduling order: on a run where the package changed, an
#     unrelated target that also rebuilds this run (for its own, unrelated
#     reasons) may complete a fraction of a second BEFORE pkg_source_digest
#     finishes -- both see the identical, current package state (loaded
#     ONCE via pkgload::load_all() before the whole tar_make() invocation
#     begins), so this ordering is never actually meaningful.
#   - CROSS-RUN scheduling order (the flaw this script previously missed):
#     once that run is over, `tar_progress()` no longer distinguishes it --
#     the NEXT invocation reports the target as "skipped" (correctly -- it
#     has nothing new to do), and the ONLY remaining signal is the two raw
#     tar_meta() times, which can still disagree by a couple of seconds
#     purely because of the earlier run's internal scheduling order. This is
#     exactly what happened to `art_vignette_seed` (built 11:13:30) and
#     `qa_legacy_leaderboard_sentinel` (11:13:32), both moments BEFORE
#     `pkg_source_digest` (11:13:32.135217) completed in that SAME run --
#     the next build's tar_progress() showed them "skipped" and a naive
#     time comparison flagged them stale, though both were computed from
#     the already-current package.
#
# The fix: stop comparing against pkg_source_digest's build time at all.
# Compare instead against the moment the package source *content* actually
# changed on disk -- the maximum on-disk mtime across the exact file paths
# `pkg_source_files` (the #753 format="file" target) recorded, read via
# .cps_pkg_source_changed_at(). That moment necessarily PRECEDES the entire
# tar_make() invocation that reacts to it (the files must already be on
# disk before `tar_make()` can even start evaluating the DAG), so it can
# never race against any target's build time from within that invocation --
# eliminating the same-run trap -- and, because it is read fresh from disk
# rather than from another target's stored metadata, it is unaffected by
# which run produced the LAST current value of `pkg_source_digest` --
# eliminating the cross-run trap. See .cps_pkg_source_changed_at() below.
# `tar_progress()` is still read for the human-readable annotation in a
# [STALE-PKG] line (was it skipped or did it complete this run) but is no
# longer part of the correctness decision -- see .cps_evaluate_staleness().
#
# WHICH TARGETS ARE CHECKED (the registry, target-level attribution, and its
# honest limits):
#
# An EARLIER version of this script attributed at FILE level: any file
# containing `historicaldata::` anywhere had EVERY tar_target() in it
# flagged, regardless of whether that specific target's own body called the
# package. PR #757 review (2026-08-25) caught this against the real store:
# 147 [STALE-PKG] lines, including `xgb_vs_enet` (R/plan_xgb_signal.R) --
# whose entire body is `library(dplyr); ... inner_join(...) ...`, calling NO
# package function at all. It was flagged solely because 8 OTHER targets in
# the same file call `historicaldata::`. That is not merely noisy: a
# wrongly-flagged target is SKIPPED precisely because nothing it depends on
# changed, so it predates pkg_source_digest FOREVER once flagged, on every
# subsequent build -- there is no path back to green. A gate that is
# unconditionally red conveys no information (this repo has already
# documented that a check nobody can action becomes a check nobody reads --
# see the roborev-resolution family of rules for the same shape of lesson).
#
# The fix: .cps_discover_consuming_targets() now attributes at TARGET level,
# using base::parse() to build a real AST for each R/*.R file -- NOT line
# regex (this repo prefers AST inspection for exactly this reason; see e.g.
# check_no_lead_ym() and friends in R/plan_qa_gates.R's look-ahead-bias
# gate). A target is flagged only if:
#   (a) its OWN tar_target()/tar_target_raw() call, walked as a language
#       object (.cps_contains_pkg_call()), directly contains a
#       `historicaldata::fn()` or `historicaldata:::fn()` call anywhere in
#       its own subtree (command, pattern, any argument) -- NOT anywhere
#       else in the file; or
#   (b) it calls a LOCAL helper function (a `name <- function(...) ...`
#       defined elsewhere in the SAME file) that itself, directly or
#       transitively through further local helpers, satisfies (a)
#       (.cps_helper_touches_pkg()) -- the deliberately conservative,
#       PROVABLY-over-flagging-not-whole-file case review point 1 asked to
#       keep: a target calling a thin local wrapper around a package call is
#       still correctly flagged, but a target's unrelated SIBLING in the
#       same file is not.
# `xgb_vs_enet` under this logic: neither (a) nor (b) hold (it references no
# package function and no local helper that does) -- not flagged. Confirmed
# by test-check-pkg-staleness.R's dedicated sibling-attribution regression
# test, modelled directly on this incident.
#
# POPULATION SPLIT (so the union of the two #753 mechanisms is visibly
# complete, per review point 2):
#   - tar_option_set(imports = "historicaldata") in docs/_targets.R covers
#     BARE-name calls (`hd_fn()`) automatically -- those targets are
#     deliberately OUT OF SCOPE for this script's registry (re-flagging them
#     here would be redundant, not wrong, but the registry is scoped to the
#     population `imports` provably cannot reach, per its own documented
#     codetools::findGlobals() limitation, so the two registries do not
#     overlap by construction).
#   - THIS script's registry covers NAMESPACED calls
#     (`historicaldata::fn()` / `historicaldata:::fn()`), which is exactly
#     what `imports` cannot reach.
#   - Together: every DIRECT (bare or namespaced) package call site is
#     covered by one mechanism or the other, PROVIDED `imports` itself is
#     working (i.e. `historicaldata` is actually attached in the session
#     evaluating docs/_targets.R -- true today via pkgload::load_all() at
#     parse time). An INDIRECT call neither mechanism can see --
#     do.call()/Reduce()/a stored function reference that
#     codetools::findGlobals() cannot statically resolve -- is not caught by
#     either; nothing in this repo currently exercises that pattern for
#     `historicaldata::`, but it is worth naming as a known gap rather than
#     implying full coverage neither mechanism actually has.
#
# Usage (from anywhere inside the repo, after a real docs/ build):
#   nix develop --command Rscript -e \
#     'targets::tar_make(script = "docs/_targets.R", store = "docs/_targets")'
#   nix develop --command Rscript scripts/check_pkg_staleness.R
#
# Exit codes:
#   0  no stale package-consuming target found. Two DISTINCT, labelled forms
#      (checks-must-distinguish-unknown -- "0 examined" must never read like
#      "examined and clean"; every outcome prints a machine-readable
#      `EXAMINED: <n>` line that build.sh surfaces in its summary):
#        - `PASS: ... (N checked)`, N >= 1: N targets were examined, none stale.
#        - `VACUOUS-PASS (0 examined)`: no target body calls
#          historicaldata::/::: (all calls are bare since #922), so nothing was
#          examined. Exit 0 ONLY because the mechanism covering the
#          complementary population is verified in place on this run:
#          tar_option_set(imports = "historicaldata") found by AST in
#          docs/_targets.R (.cps_imports_declared()). Not evidence of freshness.
#   3  INDETERMINATE: 0 targets examined AND the covering `imports=` declaration
#      was not found (or discovered consumers had no build record), so nothing
#      demonstrably covers the gap. NOT a pass; build.sh maps it to its exit 2.
#   1  one or more known package-consuming targets have a recorded build
#      time older than the package source's last on-disk change (#911:
#      compared against max(file.mtime(pkg_source_files)), never against
#      pkg_source_digest's own build time)
#   2  could not run the check at all (no store, pkg_source_digest not yet
#      built in this store, pkg_source_files unreadable or none of its
#      recorded paths exist on disk, tar_meta()/tar_progress() failed or
#      returned a truncated read — see #730) — this is NOT a pass, never
#      treat it as one

suppressPackageStartupMessages({
  library(targets)
  library(here)
})

# .cps_read_meta()/.cps_read_progress() — same truncation-promotion pattern
# as .cpe_read_meta() in scripts/check_pipeline_errors.R (#730): a
# data.table::fread() truncation warning on a malformed/interleaved-write
# meta or progress file must not be allowed to pass silently as a smaller,
# but valid, result. See that script's header comment for the full
# rationale; duplicated here (not source()'d from there) to keep each
# check script independently runnable, matching this repo's existing
# convention (check_dashboard_freshness.R does not source
# check_pipeline_errors.R either).
.cps_promote_truncation_warning <- function(expr) {
  truncation_warning <- NULL
  result <- withCallingHandlers(
    expr,
    warning = function(w) {
      msg <- conditionMessage(w)
      if (grepl("Stopped early|fill=", msg)) {
        truncation_warning <<- msg
        invokeRestart("muffleWarning")
      }
    }
  )
  if (!is.null(truncation_warning)) {
    stop(
      "a data.table::fread() truncation warning fired while reading the ",
      "store -- the rows fread() DID manage to parse are an INCOMPLETE ",
      "view, not a complete one with fewer rows (#730). Treating this as ",
      "fatal rather than silently passing on a partial read. Original ",
      "warning: ", truncation_warning,
      call. = FALSE
    )
  }
  result
}

.cps_read_meta <- function(store_path) {
  .cps_promote_truncation_warning(
    targets::tar_meta(store = store_path, fields = c(name, time), targets_only = TRUE)
  )
}

.cps_read_progress <- function(store_path) {
  .cps_promote_truncation_warning(
    targets::tar_progress(store = store_path)
  )
}

# ---------------------------------------------------------------------------
# #911 flaw 2 fix: derive "when did the package source last change" from the
# on-disk files themselves, never from another target's tar_meta() build
# time (see header comment "HOW THE CHECK WORKS" for the full same-run /
# cross-run rationale this replaces).
# ---------------------------------------------------------------------------

# .cps_source_files_paths(store_path, pkg_files_target) -- the exact file
# paths tracked by the #753 file-hash mechanism, read from the STORE'S OWN
# recorded value for `pkg_files_target` (default "pkg_source_files") via
# tar_read_raw() -- never re-derived by re-globbing
# packages/historicaldata/R here, which would silently drift from whatever
# docs/_targets.R actually defines that target as. Returns NULL (not an
# error) if the target has never been built in this store, or if reading it
# fails for any reason -- callers decide how to report that (see
# .cps_pkg_source_changed_at(), which treats NULL the same as "no paths").
.cps_source_files_paths <- function(store_path, pkg_files_target = "pkg_source_files") {
  tryCatch(
    targets::tar_read_raw(pkg_files_target, store = store_path),
    error = function(e) NULL
  )
}

# .cps_pkg_source_changed_at(paths) -- the TRUE moment the package source
# last changed, independent of any `targets` scheduling: the maximum
# on-disk mtime among `paths`. This is the ground truth this script
# compares candidate targets' build times against. It necessarily precedes
# the entire tar_make() invocation that reacts to a source change (the
# files must already be on disk before that invocation can even start
# evaluating the DAG), so it never races against any target's build time
# from within that invocation, and it is read fresh from disk each time
# this script runs rather than from another target's stored metadata -- so
# it is unaffected by which specific run last updated pkg_source_digest.
#
# Returns a length-1 POSIXct. If `paths` is NULL/empty, or every path is
# missing/moved (file.mtime() returns NA for each), returns an NA POSIXct --
# callers MUST treat that as INDETERMINATE, never as "no change" (silently
# treating NA as "the source never changed" would pass every candidate
# target as current regardless of its actual age -- the exact silent-pass
# failure mode this repo's checks-must-distinguish-unknown rule forbids).
.cps_pkg_source_changed_at <- function(paths) {
  na_time <- as.POSIXct(NA_real_, origin = "1970-01-01", tz = "UTC")
  if (is.null(paths) || length(paths) == 0L) {
    return(na_time)
  }
  mtimes <- file.mtime(paths)
  if (all(is.na(mtimes))) {
    return(na_time)
  }
  max(mtimes, na.rm = TRUE)
}

# .cps_evaluate_staleness(meta, known_names, pkg_source_changed_at, progress)
# -- the sole home of the STALE/NOT-STALE decision rule, factored out as a
# pure function of already-read data so it can be exercised directly with
# SYNTHETIC tar_meta()-shaped data in tests (#911 regression tests), with no
# real store or real tar_make() scheduling race required. `progress` is
# optional (may be NULL) and is used ONLY for the human-readable annotation
# in each [STALE-PKG] line -- it plays no role in the stale/not-stale
# decision itself (see header comment for why: a target's own build time
# compared against the package source's on-disk change time is sufficient
# and immune to both the same-run and cross-run scheduling traps that made
# tar_progress() necessary in the pre-#911 version of this check).
# Returns list(stale = character(), stale_detail = character()).
.cps_evaluate_staleness <- function(meta, known_names, pkg_source_changed_at, progress = NULL) {
  stale <- character(0)
  stale_detail <- character(0)
  for (nm in known_names) {
    t <- meta$time[match(nm, meta$name)]
    if (is.na(t) || t >= pkg_source_changed_at) {
      next
    }
    prog_val <- NA_character_
    if (!is.null(progress)) {
      prog_row <- match(nm, progress$name)
      if (!is.na(prog_row)) {
        prog_val <- progress$progress[prog_row]
      }
    }
    stale <- c(stale, nm)
    stale_detail <- c(stale_detail, sprintf(
      "  [STALE-PKG] %s -- last built %s (progress this run: %s), predates the package source's last on-disk change (%s)",
      nm, format(t, tz = "UTC"), if (is.na(prog_val)) "<unknown>" else prog_val,
      format(pkg_source_changed_at, tz = "UTC")
    ))
  }
  list(stale = stale, stale_detail = stale_detail)
}

# ---------------------------------------------------------------------------
# AST helpers for target-level attribution (#753 / PR #757 review). All of
# these operate on unevaluated R language objects (the output of
# base::parse()), never on source text -- see the header comment above for
# why (the file-level regex version this replaced was the defect).
# ---------------------------------------------------------------------------

# .cps_call_head_name(expr) -- the name of the function being called, for
# both a bare call (`tar_target(...)`, head is a symbol) and a namespaced
# call (`targets::tar_target(...)`, head is itself a `::`/`:::` call). NA
# for anything else (not a call, or a head this repo doesn't use, e.g. a
# call through a variable).
.cps_call_head_name <- function(expr) {
  if (!is.call(expr)) {
    return(NA_character_)
  }
  head <- expr[[1]]
  if (is.symbol(head)) {
    return(as.character(head))
  }
  if (is.call(head) && length(head) == 3L &&
      (identical(head[[1]], as.symbol("::")) || identical(head[[1]], as.symbol(":::")))) {
    return(as.character(head[[3]]))
  }
  NA_character_
}

# .cps_is_pkg_call(expr, pkg) -- TRUE iff `expr` is ITSELF a call of the
# form `pkg::fn(...)` / `pkg:::fn(...)` (not a general recursive search --
# see .cps_contains_pkg_call() for that).
.cps_is_pkg_call <- function(expr, pkg) {
  if (!is.call(expr)) {
    return(FALSE)
  }
  head <- expr[[1]]
  is.call(head) && length(head) == 3L &&
    (identical(head[[1]], as.symbol("::")) || identical(head[[1]], as.symbol(":::"))) &&
    identical(head[[2]], as.symbol(pkg))
}

# .cps_contains_pkg_call(expr, pkg) -- recursively TRUE iff `expr`'s OWN
# subtree (a call, a pairlist of function formals, or any nested element of
# either) contains a `pkg::fn()`/`pkg:::fn()` call ANYWHERE within it. This
# is the sole source of truth for "does this call touch the package
# directly" -- no line- or file-level heuristics.
.cps_contains_pkg_call <- function(expr, pkg = "historicaldata") {
  if (.cps_is_pkg_call(expr, pkg)) {
    return(TRUE)
  }
  if (is.call(expr) || is.pairlist(expr)) {
    return(any(vapply(as.list(expr), .cps_contains_pkg_call, logical(1), pkg = pkg)))
  }
  FALSE
}

# .cps_called_names(expr) -- the set of BARE (non-namespaced) function-call
# names referenced anywhere in `expr`'s subtree. Used only to resolve calls
# to LOCAL same-file helper functions -- namespaced calls are already fully
# covered by .cps_contains_pkg_call() and are not needed here.
#
# Iterates by INDEX (`parts[[i]]`), never `for (part in as.list(expr))`.
# Confirmed empirically (2026-08-25): a parsed function's formals pairlist,
# or an omitted call argument (e.g. `x[i, ]`'s empty third slot), can
# contain R's special missing-argument symbol. Binding that value to a
# plain loop variable and then referencing the variable (`for (part in ...)
# ... part ...`) raises "argument is missing, with no default" the moment
# the variable is evaluated -- the same error a genuinely unsupplied
# function argument raises, because R's evaluator treats ANY symbol lookup
# resolving to that special value this way, regardless of how the binding
# was created. Passing `parts[[i]]` directly into a call, with no
# intermediate named binding, does not go through that symbol-lookup path
# and is safe -- confirmed with both patterns side by side on the same
# missing-argument fixture.
.cps_called_names <- function(expr) {
  out <- character(0)
  if (is.call(expr) && is.symbol(expr[[1]])) {
    out <- c(out, as.character(expr[[1]]))
  }
  if (is.call(expr) || is.pairlist(expr)) {
    parts <- as.list(expr)
    for (i in seq_along(parts)) {
      out <- c(out, .cps_called_names(parts[[i]]))
    }
  }
  out
}

# .cps_local_helpers(top_exprs) -- named list mapping helper-function-name
# to its full `function(...) {...}` definition, for every top-level
# `name <- function(...) ...` / `name = function(...) ...` assignment among
# `top_exprs` (the parsed top-level expressions of one file). This is the
# LOCAL, same-file call graph the conservative "ambiguous case" (review
# point 1) walks -- cross-file helper resolution is out of scope (this
# script already treats an unresolvable indirect call as a known gap, see
# header comment).
.cps_local_helpers <- function(top_exprs) {
  helpers <- list()
  for (e in top_exprs) {
    if (is.call(e) && length(e) == 3L &&
        (identical(e[[1]], as.symbol("<-")) || identical(e[[1]], as.symbol("="))) &&
        is.symbol(e[[2]]) &&
        identical(.cps_call_head_name(e[[3]]), "function")) {
      helpers[[as.character(e[[2]])]] <- e[[3]]
    }
  }
  helpers
}

# .cps_helper_touches_pkg(helpers, pkg) -- named logical vector: for each
# local helper, does it contain a pkg call directly OR transitively (via a
# call to another local helper that does), by fixed-point iteration over the
# local call graph. Terminates: the helper set is finite and each iteration
# can only flip an entry FALSE -> TRUE, never back.
.cps_helper_touches_pkg <- function(helpers, pkg = "historicaldata") {
  nms <- names(helpers)
  if (length(nms) == 0L) {
    return(stats::setNames(logical(0), character(0)))
  }
  touches <- stats::setNames(
    vapply(helpers, .cps_contains_pkg_call, logical(1), pkg = pkg),
    nms
  )
  changed <- TRUE
  while (changed) {
    changed <- FALSE
    for (nm in nms) {
      if (touches[[nm]]) next
      called <- intersect(.cps_called_names(helpers[[nm]]), nms)
      if (length(called) > 0L && any(touches[called])) {
        touches[[nm]] <- TRUE
        changed <- TRUE
      }
    }
  }
  touches
}

# .cps_target_touches_pkg(target_call, helper_touches, pkg) -- TRUE iff the
# target's own call (a) directly contains a pkg call, or (b) calls a local
# helper (from `helper_touches`, already resolved transitively) that does.
.cps_target_touches_pkg <- function(target_call, helper_touches, pkg = "historicaldata") {
  if (.cps_contains_pkg_call(target_call, pkg)) {
    return(TRUE)
  }
  if (length(helper_touches) == 0L) {
    return(FALSE)
  }
  called <- intersect(.cps_called_names(target_call), names(helper_touches))
  length(called) > 0L && any(helper_touches[called])
}

# .cps_find_target_calls(expr) -- recursively collects every
# tar_target()/tar_target_raw() call (bare or `targets::`-qualified)
# anywhere in `expr`'s subtree (typically a file's parsed top-level
# expressions, where target definitions usually sit inside a
# `plan_x <- function() { list( tar_target(...), ... ) }` wrapper -- not at
# the top level itself, hence the recursion). Does not descend further once
# a target call is found -- a target definition never contains another one
# in this codebase.
# Iterates by INDEX -- see .cps_called_names() roxygen just above for why
# `for (part in as.list(expr))` is unsafe here.
.cps_find_target_calls <- function(expr) {
  found <- list()
  nm <- .cps_call_head_name(expr)
  if (!is.na(nm) && nm %in% c("tar_target", "tar_target_raw")) {
    found[[length(found) + 1L]] <- expr
    return(found)
  }
  if (is.call(expr) || is.pairlist(expr)) {
    parts <- as.list(expr)
    for (i in seq_along(parts)) {
      found <- c(found, .cps_find_target_calls(parts[[i]]))
    }
  }
  found
}

# .cps_target_call_name(call_expr) -- the target's own name: the first
# UNNAMED argument, matching this repo's style (name is always written
# first and positionally, confirmed via grep across every plan_*.R file).
# For `tar_target(name, ...)` this is a bare symbol, deparsed to a string;
# for `tar_target_raw("name", ...)` it is already a string literal.
.cps_target_call_name <- function(call_expr) {
  args <- as.list(call_expr)[-1]
  arg_names <- names(args)
  if (is.null(arg_names)) {
    arg_names <- rep("", length(args))
  }
  unnamed <- args[arg_names == ""]
  if (length(unnamed) == 0L) {
    return(NA_character_)
  }
  first <- unnamed[[1]]
  if (is.character(first)) {
    return(first)
  }
  if (is.symbol(first)) {
    return(as.character(first))
  }
  NA_character_
}

# .cps_discover_consuming_targets() — see the header comment above for the
# full design (target-level attribution, the population split, and the
# xgb_vs_enet incident this replaced a file-level version to fix). Returns
# a tibble(file, target_name), one row per (file, target) pair FLAGGED --
# i.e. that target's own call, or a local helper it calls, touches
# `historicaldata::`/`historicaldata:::` directly. A file that fails to
# parse is skipped with a loud [NOTE] rather than silently dropped (#753's
# whole point is that silence about coverage gaps is the failure mode).
.cps_discover_consuming_targets <- function(r_dir = here::here("R"), pkg = "historicaldata") {
  files <- list.files(r_dir, pattern = "\\.R$", full.names = TRUE)
  out_files <- character(0)
  out_names <- character(0)
  for (f in files) {
    top_exprs <- tryCatch(as.list(parse(f, keep.source = FALSE)), error = function(e) {
      message("!!! .cps_discover_consuming_targets(): ", basename(f), " failed to parse -- ", conditionMessage(e), " !!!")
      message("!!! This file's targets are NOT included in the staleness registry -- fix the parse error. !!!")
      NULL
    })
    if (is.null(top_exprs) || length(top_exprs) == 0L) next

    target_calls <- unlist(lapply(top_exprs, .cps_find_target_calls), recursive = FALSE)
    if (length(target_calls) == 0L) next

    helpers <- .cps_local_helpers(top_exprs)
    helper_touches <- .cps_helper_touches_pkg(helpers, pkg = pkg)

    for (tc in target_calls) {
      if (!.cps_target_touches_pkg(tc, helper_touches, pkg = pkg)) next
      nm <- .cps_target_call_name(tc)
      if (is.na(nm) || !nzchar(nm)) next
      out_files <- c(out_files, basename(f))
      out_names <- c(out_names, nm)
    }
  }
  tibble::tibble(file = out_files, target_name = out_names)
}

# .cps_string_literals(expr) -- every character literal anywhere in `expr`
# (so `"a"` and `c("a", "b")` both work).
.cps_string_literals <- function(expr) {
  if (is.character(expr)) {
    return(expr)
  }
  out <- character(0)
  if (is.call(expr)) {
    parts <- as.list(expr)
    for (i in seq_along(parts)) {
      out <- c(out, .cps_string_literals(parts[[i]]))
    }
  }
  out
}

# .cps_imports_declared(targets_script, pkg) -- TRUE iff the pipeline script
# contains a real `tar_option_set(..., imports = <literal naming pkg>)` call
# (AST, not text: a comment or a string mentioning it is not a declaration).
# This is the mechanism that covers BARE-name package calls; the "0
# examined" outcome below is only a legitimate (labelled) VACUOUS-PASS when
# it is in place. A missing or unparsable script returns FALSE (the caller
# turns that into INDETERMINATE), never an error.
.cps_imports_declared <- function(targets_script = here::here("docs", "_targets.R"),
                                  pkg = "historicaldata") {
  exprs <- tryCatch(
    as.list(parse(targets_script, keep.source = FALSE)),
    error = function(e) NULL,
    warning = function(w) NULL
  )
  if (is.null(exprs)) {
    return(FALSE)
  }
  walk <- function(expr) {
    if (is.call(expr)) {
      if (identical(.cps_call_head_name(expr), "tar_option_set")) {
        nms <- names(expr)
        if (!is.null(nms) && "imports" %in% nms) {
          val <- expr[[which(nms == "imports")[1]]]
          if (pkg %in% .cps_string_literals(val)) {
            return(TRUE)
          }
        }
      }
      parts <- as.list(expr)
      for (i in seq_along(parts)) {
        if (isTRUE(walk(parts[[i]]))) {
          return(TRUE)
        }
      }
    }
    FALSE
  }
  any(vapply(exprs, walk, logical(1)))
}

# .cps_main() -- orchestrates the check, printing a human-readable report and
# RETURNING (not quit()-ing) an exit-status integer -- same testable-without-
# terminating-the-session pattern as .cpe_main()/.cdf_main().
.cps_main <- function(store_path = here::here("docs", "_targets"),
                       r_dir = here::here("R"),
                       pkg_files_target = "pkg_source_files",
                       targets_script = here::here("docs", "_targets.R")) {
  if (!dir.exists(store_path)) {
    message("!!! No targets store found at '", store_path, "' !!!")
    message("!!! This script only READS an existing store -- run tar_make() first. !!!")
    message("!!! VERIFICATION DID NOT RUN. This is NOT a pass.                      !!!")
    return(2L)
  }

  meta <- tryCatch(.cps_read_meta(store_path), error = function(e) {
    message("!!! tar_meta() failed: ", conditionMessage(e), " !!!")
    NULL
  })
  if (is.null(meta)) {
    message("!!! VERIFICATION DID NOT RUN. This is NOT a pass. !!!")
    return(2L)
  }

  # tar_progress() is read only for the human-readable annotation on each
  # [STALE-PKG] line (#911: it is no longer part of the stale/not-stale
  # decision -- see .cps_evaluate_staleness()). A read failure is therefore
  # non-fatal here: fall back to NULL and let the annotation read
  # "<unknown>" rather than turning an unrelated progress-file hiccup into a
  # spurious INDETERMINATE for a check that no longer needs that file to be
  # correct.
  progress <- tryCatch(.cps_read_progress(store_path), error = function(e) {
    message("!!! tar_progress() failed (non-fatal -- used only for the this-run ")
    message("!!! annotation, not the stale/not-stale decision): ", conditionMessage(e), " !!!")
    NULL
  })

  digest_row <- match("pkg_source_digest", meta$name)
  if (is.na(digest_row)) {
    message("!!! pkg_source_digest not found in tar_meta() -- the #753 tracking ")
    message("!!! mechanism has never been built in this store. Run ")
    message("!!! scripts/build.sh (which calls tar_make()) first. !!!")
    message("!!! VERIFICATION DID NOT RUN. This is NOT a pass. !!!")
    return(2L)
  }

  source_paths <- .cps_source_files_paths(store_path, pkg_files_target)
  pkg_source_changed_at <- .cps_pkg_source_changed_at(source_paths)
  if (is.na(pkg_source_changed_at)) {
    message("!!! Could not determine when packages/historicaldata source last ")
    message("!!! changed -- '", pkg_files_target, "' has never been built in this ")
    message("!!! store, or none of its recorded file paths currently exist on ")
    message("!!! disk. !!!")
    message("!!! VERIFICATION DID NOT RUN. This is NOT a pass. !!!")
    return(2L)
  }

  cat(sprintf("Store: %s\n", store_path))
  cat(sprintf(
    "packages/historicaldata source last changed (max on-disk mtime of %s): %s\n",
    pkg_files_target, format(pkg_source_changed_at, tz = "UTC")
  ))

  registry <- .cps_discover_consuming_targets(r_dir)
  registry_names <- unique(registry$target_name)
  cat(sprintf(
    "Discovered %d package-consuming target name(s) across %d file(s) (target-level attribution -- direct or local-helper historicaldata:: use in that target's OWN body only; see header comment)\n",
    length(registry_names), length(unique(registry$file))
  ))

  present <- registry_names %in% meta$name
  unknown <- registry_names[!present]
  if (length(unknown) > 0L) {
    cat(sprintf(
      "  [NOTE] %d discovered target name(s) have no tar_meta() build record (never built, or a dynamically-generated name .cps_target_call_name() could not resolve statically): %s\n",
      length(unknown), paste(unknown, collapse = ", ")
    ))
  }

  known <- registry_names[present]
  result <- .cps_evaluate_staleness(meta, known, pkg_source_changed_at, progress = progress)
  stale <- result$stale
  stale_detail <- result$stale_detail

  # Machine-readable count for scripts/build.sh's summary line. Printed on
  # EVERY outcome that reaches this point so a reader can always see how many
  # targets this run actually examined (0 is visible, never implied).
  cat(sprintf("EXAMINED: %d\n", length(known)))

  if (length(known) == 0L) {
    # Nothing was examined. That is NOT evidence of cleanliness -- the check
    # output would be identical whether discovery works or is broken.
    # Determinate only when (a) discovery found no namespaced consumer at all
    # AND (b) the mechanism covering the complementary population (bare
    # calls: tar_option_set(imports=)) is verified in place right now.
    if (length(registry_names) == 0L && .cps_imports_declared(targets_script)) {
      cat(paste0(
        "VACUOUS-PASS (0 examined): no target body calls historicaldata:: / ",
        "historicaldata:::, so there was nothing for this backstop to check. ",
        "This is NOT evidence that any target is fresh. Coverage rests on ",
        "tar_option_set(imports = \"historicaldata\") in ", basename(targets_script),
        " (verified present), which tracks bare-name calls. If a namespaced ",
        "call is re-introduced this check examines it automatically.\n"
      ))
      return(0L)
    }
    cat(paste0(
      "INDETERMINATE (0 examined): ",
      if (length(registry_names) > 0L) {
        sprintf("%d discovered consumer(s) have no build record, so none could be checked. ", length(registry_names))
      } else {
        paste0("no namespaced consumer was discovered AND tar_option_set(imports = ",
               "\"historicaldata\") was not found in ", targets_script, ", so bare-name ",
               "calls are not known to be tracked either. ")
      },
      "Nothing was verified. This is NOT a pass.\n"
    ))
    return(3L)
  }

  if (length(stale) == 0L) {
    cat(sprintf(
      "PASS: no known package-consuming target is stale relative to the package source's last on-disk change (%d checked)\n",
      length(known)
    ))
    return(0L)
  }

  cat(sprintf("FAIL: %d target(s) predate the package source's last on-disk change:\n", length(stale)))
  cat(paste(stale_detail, collapse = "\n"), "\n", sep = "")
  cat(paste0(
    "!!! packages/historicaldata/R changed (the package source's last on-disk change is\n",
    "!!! newer than the target(s) above) but these targets are serving values computed\n",
    "!!! by an OLDER version of the package (#753). Force an invalidation and rebuild, e.g.:\n",
    "!!!   nix develop --command Rscript -e \\\n",
    "!!!     'targets::tar_invalidate(any_of(c(", paste(sprintf('\"%s\"', stale), collapse = ", "), ")), store = \"docs/_targets\", script = \"docs/_targets.R\")'\n",
    "!!! then re-run scripts/build.sh. If this keeps recurring for the same target(s),\n",
    "!!! wire it to depend on pkg_source_digest explicitly (reference the symbol in its\n",
    "!!! command) or convert its historicaldata:: call to a bare call so\n",
    "!!! tar_option_set(imports = \"historicaldata\") tracks it automatically.\n"
  ))
  return(1L)
}

# Only run when this file is the Rscript entry point (sys.nframe() == 0),
# never when source()'d for its functions -- same pattern as
# scripts/check_pipeline_errors.R and scripts/check_dashboard_freshness.R.
if (sys.nframe() == 0) {
  status <- .cps_main()
  quit(status = status, save = "no")
}
