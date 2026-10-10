testthat::local_edition(3)
source(here::here("scripts", "check_pkg_staleness.R"))

# Regression tests for scripts/check_pkg_staleness.R (#753).
#
# scripts/check_pkg_staleness.R defines its logic as `.cps_*` functions and
# only RUNS the check (calling quit()) when it is the Rscript entry point
# (sys.nframe() == 0 at its own top level -- see that file's final block).
# source()'ing it here (sys.nframe() > 0) loads the functions without
# triggering a live run against the real repo's docs/_targets store, exactly
# the pattern test-check-pipeline-errors.R uses for check_pipeline_errors.R.
#
# These tests build REAL, throwaway targets stores under withr::local_tempdir()
# -- never the real docs/_targets store (see .claude/CLAUDE.md and the
# worktree-location rule: a worktree must not build or touch the main
# checkout's store).

# .make_pkg_toy_store() -- builds a throwaway pipeline that mirrors the
# SHAPE of docs/_targets.R's #753 mechanism: a format = "file" target
# tracking one real file (`pkg_source_files` -- named to match production
# and what .cps_source_files_paths() looks for by default), a digest target
# depending on it (`pkg_source_digest` -- named to match what .cps_main()
# looks for), and a `consumer` target that does NOT reference the digest --
# i.e. the exact "unwired, namespaced-call-style" shape #753 is about.
# Returns the store path; `pkg_file_path` is the file callers mutate to
# trigger a rebuild.
.make_pkg_toy_store <- function(dir) {
  pkg_dir <- file.path(dir, "pkg_src")
  dir.create(pkg_dir)
  pkg_file_path <- file.path(pkg_dir, "fn.R")
  writeLines("f <- function() 1", pkg_file_path)

  script_path <- file.path(dir, "_targets.R")
  store_path <- file.path(dir, "_targets")
  writeLines(c(
    'targets::tar_option_set(error = "continue")',
    "list(",
    sprintf('  targets::tar_target(pkg_source_files, "%s", format = "file"),', pkg_file_path),
    "  targets::tar_target(pkg_source_digest, tools::md5sum(pkg_source_files)[[1]]),",
    "  targets::tar_target(consumer, \"unwired-value\")",
    ")"
  ), script_path)
  targets::tar_make(
    script = script_path, store = store_path,
    callr_function = NULL, reporter = "silent"
  )
  list(store_path = store_path, pkg_file_path = pkg_file_path, dir = dir)
}

# .make_registry_r_dir() -- a throwaway R/ directory whose single file
# mentions `historicaldata::` (the discovery trigger) and defines a
# `tar_target(consumer, ...)` call -- so .cps_discover_consuming_targets()
# finds exactly "consumer", matching .make_pkg_toy_store()'s unwired target.
.make_registry_r_dir <- function(dir) {
  r_dir <- file.path(dir, "R")
  dir.create(r_dir)
  writeLines(c(
    "plan_fake <- function() {",
    "  list(",
    "    targets::tar_target(consumer, historicaldata::fake_fn()),",
    "    targets::tar_target(other_target, 1 + 1)",
    "  )",
    "}"
  ), file.path(r_dir, "plan_fake.R"))
  r_dir
}

# ── .cps_discover_consuming_targets() ───────────────────────────────────────

test_that(".cps_discover_consuming_targets finds targets only in files mentioning historicaldata::", {
  dir <- withr::local_tempdir()
  r_dir <- file.path(dir, "R")
  dir.create(r_dir)
  writeLines(c(
    "plan_with_pkg <- function() {",
    "  list(",
    "    targets::tar_target(uses_pkg, historicaldata::fn()),",
    "    targets::tar_target_raw(\"uses_pkg_raw\", quote(historicaldata::fn2()))",
    "  )",
    "}"
  ), file.path(r_dir, "plan_with_pkg.R"))
  writeLines(c(
    "plan_no_pkg <- function() {",
    "  list(targets::tar_target(no_pkg_here, 1 + 1))",
    "}"
  ), file.path(r_dir, "plan_no_pkg.R"))

  reg <- .cps_discover_consuming_targets(r_dir)
  expect_setequal(reg$target_name, c("uses_pkg", "uses_pkg_raw"))
  expect_false("no_pkg_here" %in% reg$target_name)
})

test_that(".cps_discover_consuming_targets returns an empty tibble when no file mentions historicaldata::", {
  dir <- withr::local_tempdir()
  r_dir <- file.path(dir, "R")
  dir.create(r_dir)
  writeLines("plan_x <- function() list(targets::tar_target(x, 1))", file.path(r_dir, "plan_x.R"))
  reg <- .cps_discover_consuming_targets(r_dir)
  expect_equal(nrow(reg), 0L)
})

# ── #757 review regression: target-level, not file-level, attribution ──────
#
# The earlier version of .cps_discover_consuming_targets() flagged EVERY
# tar_target() in a file that mentioned `historicaldata::` ANYWHERE -- caught
# against the real store flagging `xgb_vs_enet` (R/plan_xgb_signal.R), whose
# own body calls no package function at all, solely because 8 OTHER targets
# in the same file do. This block reproduces that exact shape directly.

test_that("a target with no package call is NOT flagged even when a sibling in the SAME file calls historicaldata:: directly (xgb_vs_enet reproduction, #757 review)", {
  dir <- withr::local_tempdir()
  r_dir <- file.path(dir, "R")
  dir.create(r_dir)
  writeLines(c(
    "plan_xgb_signal_like <- function() {",
    "  list(",
    "    targets::tar_target(xgb_drif_register_runs, {",
    "      historicaldata::hd_registry_upsert(1)",
    "    }),",
    "    targets::tar_target(xgb_vs_enet, {",
    "      library(dplyr)",
    "      xgb  <- xgb_drif_portfolio  |> select(ym, xgb_ret  = port_ret)",
    "      enet <- stk_drif_portfolio |> select(ym, enet_ret = port_ret)",
    "      inner_join(xgb, enet, by = \"ym\") |> arrange(ym)",
    "    })",
    "  )",
    "}"
  ), file.path(r_dir, "plan_xgb_signal_like.R"))

  reg <- .cps_discover_consuming_targets(r_dir)
  expect_true("xgb_drif_register_runs" %in% reg$target_name)
  expect_false("xgb_vs_enet" %in% reg$target_name)
})

test_that("a target IS flagged when it calls a LOCAL helper that directly touches historicaldata:: (conservative ambiguous case, review point 1)", {
  dir <- withr::local_tempdir()
  r_dir <- file.path(dir, "R")
  dir.create(r_dir)
  writeLines(c(
    "helper_touches_pkg <- function(x) historicaldata::fn(x)",
    "plan_helper <- function() {",
    "  list(targets::tar_target(via_helper, helper_touches_pkg(1)))",
    "}"
  ), file.path(r_dir, "plan_helper.R"))

  reg <- .cps_discover_consuming_targets(r_dir)
  expect_true("via_helper" %in% reg$target_name)
})

test_that("a target IS flagged when it calls a local helper that TRANSITIVELY touches historicaldata:: via a second local helper (chain A -> B -> pkg)", {
  dir <- withr::local_tempdir()
  r_dir <- file.path(dir, "R")
  dir.create(r_dir)
  writeLines(c(
    "helper_b <- function(x) historicaldata::fn(x)",
    "helper_a <- function(x) helper_b(x)",
    "plan_chain <- function() {",
    "  list(targets::tar_target(via_chain, helper_a(1)))",
    "}"
  ), file.path(r_dir, "plan_chain.R"))

  reg <- .cps_discover_consuming_targets(r_dir)
  expect_true("via_chain" %in% reg$target_name)
})

test_that("a target calling a local helper that does NOT touch historicaldata:: is NOT flagged", {
  dir <- withr::local_tempdir()
  r_dir <- file.path(dir, "R")
  dir.create(r_dir)
  writeLines(c(
    "helper_clean <- function(x) x + 1",
    "plan_clean_helper <- function() {",
    "  list(",
    "    targets::tar_target(uses_pkg_directly, historicaldata::fn(1)),",
    "    targets::tar_target(uses_clean_helper, helper_clean(1))",
    "  )",
    "}"
  ), file.path(r_dir, "plan_clean_helper.R"))

  reg <- .cps_discover_consuming_targets(r_dir)
  expect_true("uses_pkg_directly" %in% reg$target_name)
  expect_false("uses_clean_helper" %in% reg$target_name)
})

test_that("a bare-name package call (imports= territory) is NOT flagged by this registry, even in a file that also has namespaced calls", {
  dir <- withr::local_tempdir()
  r_dir <- file.path(dir, "R")
  dir.create(r_dir)
  writeLines(c(
    "plan_mixed <- function() {",
    "  list(",
    "    targets::tar_target(bare_call_target, hd_commodity_mr_signal(1)),",
    "    targets::tar_target(namespaced_call_target, historicaldata::hd_registry_upsert(1))",
    "  )",
    "}"
  ), file.path(r_dir, "plan_mixed.R"))

  reg <- .cps_discover_consuming_targets(r_dir)
  expect_false("bare_call_target" %in% reg$target_name)
  expect_true("namespaced_call_target" %in% reg$target_name)
})

test_that(".cps_discover_consuming_targets does not crash on a file with functions that have arguments without defaults (regression: missing-arg symbol crash found while writing this fix)", {
  dir <- withr::local_tempdir()
  r_dir <- file.path(dir, "R")
  dir.create(r_dir)
  writeLines(c(
    "helper_no_default <- function(x, y) historicaldata::fn(x, y)",
    "plan_no_default <- function() {",
    "  list(targets::tar_target(uses_helper, helper_no_default(1, 2)))",
    "}"
  ), file.path(r_dir, "plan_no_default.R"))

  expect_no_error(reg <- .cps_discover_consuming_targets(r_dir))
  expect_true("uses_helper" %in% reg$target_name)
})

# ── .cps_main() -- store-existence / missing-digest / pass / fail paths ────

test_that(".cps_main returns 2 and reports when no store directory exists", {
  dir <- withr::local_tempdir()
  missing_store <- file.path(dir, "does_not_exist")
  status <- NA_integer_
  msgs <- character(0)
  withCallingHandlers(
    status <- .cps_main(store_path = missing_store, r_dir = withr::local_tempdir()),
    message = function(m) {
      msgs <<- c(msgs, conditionMessage(m))
      invokeRestart("muffleMessage")
    }
  )
  expect_equal(status, 2L)
  expect_true(any(grepl("No targets store found", msgs)))
  expect_true(any(grepl("VERIFICATION DID NOT RUN", msgs)))
})

test_that(".cps_main returns 2 when pkg_source_digest was never built in the store", {
  dir <- withr::local_tempdir()
  script_path <- file.path(dir, "_targets.R")
  store_path <- file.path(dir, "_targets")
  writeLines(c(
    'targets::tar_option_set(error = "continue")',
    "list(targets::tar_target(unrelated, 1 + 1))"
  ), script_path)
  targets::tar_make(script = script_path, store = store_path, callr_function = NULL, reporter = "silent")

  status <- NA_integer_
  msgs <- character(0)
  withCallingHandlers(
    status <- .cps_main(store_path = store_path, r_dir = withr::local_tempdir()),
    message = function(m) {
      msgs <<- c(msgs, conditionMessage(m))
      invokeRestart("muffleMessage")
    }
  )
  expect_equal(status, 2L)
  expect_true(any(grepl("pkg_source_digest not found", msgs)))
})

test_that(".cps_main returns 0 on a fresh build where everything completed together", {
  dir <- withr::local_tempdir()
  built <- .make_pkg_toy_store(dir)
  r_dir <- .make_registry_r_dir(dir)

  status <- NA_integer_
  out <- utils::capture.output(status <- .cps_main(store_path = built$store_path, r_dir = r_dir))
  expect_equal(status, 0L)
  txt <- paste(out, collapse = "\n")
  expect_match(txt, "PASS: no known package-consuming target is stale")
})

test_that(".cps_main returns 1 and names the stale target when a skipped consumer predates a rebuilt digest (#753 reproduction)", {
  dir <- withr::local_tempdir()
  built <- .make_pkg_toy_store(dir)
  r_dir <- .make_registry_r_dir(dir)

  # Confirm PASS on the fresh build first (same shape as the PASS test above).
  status0 <- NA_integer_
  utils::capture.output(status0 <- .cps_main(store_path = built$store_path, r_dir = r_dir))
  expect_equal(status0, 0L)

  # Mutate the tracked package file and rebuild -- `pkg_source_files`/`pkg_source_digest`
  # rebuild (format = "file" content-hash cue), but `consumer` does not
  # reference pkg_source_digest at all, so it is SKIPPED -- reproducing #753's
  # exact defect shape (confirmed empirically against this same toy-pipeline
  # design in a throwaway scratch session before writing this test).
  Sys.sleep(1.1) # ensure a distinguishable tar_meta() timestamp across builds
  writeLines("f <- function() 2", built$pkg_file_path)
  targets::tar_make(
    script = file.path(built$dir, "_targets.R"), store = built$store_path,
    callr_function = NULL, reporter = "silent"
  )

  status <- NA_integer_
  out <- utils::capture.output(status <- .cps_main(store_path = built$store_path, r_dir = r_dir))
  expect_equal(status, 1L)
  txt <- paste(out, collapse = "\n")
  expect_match(txt, "\\[STALE-PKG\\] consumer")
  expect_match(txt, "FAIL: 1 target")
})

# ── #911 flaw 2 regression: cross-run false positives from comparing a
# candidate target's build time against pkg_source_digest's OWN build time,
# rather than against the package source's actual on-disk change time ──────
#
# See scripts/check_pkg_staleness.R's header comment ("HOW THE CHECK WORKS")
# for the full incident: on 2026-09-26, `art_vignette_seed` (built 11:13:30)
# and `qa_legacy_leaderboard_sentinel` (11:13:32) were rebuilt AFTER the
# package source changed but a couple of seconds BEFORE `pkg_source_digest`
# itself completed in that SAME tar_make() run -- the NEXT run's
# tar_progress() correctly showed them "skipped" (nothing left to do), but a
# naive `t < pkg_source_digest_time` comparison read that as "stale" even
# though both were computed from the already-current package.
#
# These tests exercise .cps_evaluate_staleness() directly with SYNTHETIC
# tar_meta()-shaped data (per the #911 dispatch spec) -- no real store or
# real tar_make() scheduling race is needed to prove the decision rule
# itself is correct, now that the rule is a pure function of (meta,
# known_names, pkg_source_changed_at).

test_that("#911 (a): a target built after the real source change but BEFORE pkg_source_digest's own build time in the same historical run is NOT stale", {
  # Reproduces the exact 2026-09-26 ordering read from the real store
  # (docs/_targets/meta/meta, confirmed via targets::tar_meta() against the
  # main checkout's store while investigating this issue):
  #   packages/historicaldata source last on-disk change: 2026-09-26 11:12:16.669267
  #   pkg_source_digest's OWN tar_meta() build time:      2026-09-26 11:13:32.135217
  #   art_vignette_seed's tar_meta() build time (that run): ~2026-09-26 11:13:30
  #   qa_legacy_leaderboard_sentinel's build time (that run): ~2026-09-26 11:13:32
  # Both targets built AFTER the true source change (11:12:16) but BEFORE
  # pkg_source_digest's own recorded build time (11:13:32.135217) in that
  # same run -- the exact ordering that produced the false positive.
  pkg_source_changed_at <- as.POSIXct("2026-09-26 11:12:16.669267", tz = "UTC")
  meta <- tibble::tibble(
    name = c("art_vignette_seed", "qa_legacy_leaderboard_sentinel"),
    time = as.POSIXct(c("2026-09-26 11:13:30.500000", "2026-09-26 11:13:32.000000"), tz = "UTC")
  )
  # Both build times are BEFORE what pkg_source_digest itself recorded as
  # its own build time, demonstrating the fix does not merely get lucky --
  # it never consults pkg_source_digest's time at all.
  pkg_digest_time <- as.POSIXct("2026-09-26 11:13:32.135217", tz = "UTC")
  expect_true(all(meta$time < pkg_digest_time))

  result <- .cps_evaluate_staleness(meta, meta$name, pkg_source_changed_at)
  expect_equal(result$stale, character(0))
  expect_equal(result$stale_detail, character(0))
})

test_that("#911 (b): a target built BEFORE the real source change, skipped this run, IS stale", {
  pkg_source_changed_at <- as.POSIXct("2026-09-26 11:12:16.669267", tz = "UTC")
  meta <- tibble::tibble(
    name = "cmr_conditioned",
    time = as.POSIXct("2026-09-25 09:00:00", tz = "UTC")
  )
  progress <- tibble::tibble(name = "cmr_conditioned", progress = "skipped")

  result <- .cps_evaluate_staleness(meta, meta$name, pkg_source_changed_at, progress = progress)
  expect_equal(result$stale, "cmr_conditioned")
  expect_match(result$stale_detail, "\\[STALE-PKG\\] cmr_conditioned", all = FALSE)
  expect_match(result$stale_detail, "progress this run: skipped", all = FALSE)
})

test_that("#911 (c): .cps_pkg_source_changed_at() returns NA (indeterminate) when no tracked path exists on disk", {
  dir <- withr::local_tempdir()
  missing_path <- file.path(dir, "does-not-exist.R")
  expect_true(is.na(.cps_pkg_source_changed_at(missing_path)))
  expect_true(is.na(.cps_pkg_source_changed_at(character(0))))
  expect_true(is.na(.cps_pkg_source_changed_at(NULL)))
})

test_that("#911 (c): .cps_main returns 2 (indeterminate) when pkg_source_files' recorded paths no longer exist on disk", {
  dir <- withr::local_tempdir()
  built <- .make_pkg_toy_store(dir)
  r_dir <- .make_registry_r_dir(dir)

  # Confirm PASS first (same shape as the standard PASS test).
  status0 <- NA_integer_
  utils::capture.output(status0 <- .cps_main(store_path = built$store_path, r_dir = r_dir))
  expect_equal(status0, 0L)

  # Delete the tracked file AFTER the build -- pkg_source_files' recorded
  # path now points nowhere, so the source-changed-at moment cannot be
  # determined from disk.
  file.remove(built$pkg_file_path)

  status <- NA_integer_
  msgs <- character(0)
  withCallingHandlers(
    status <- .cps_main(store_path = built$store_path, r_dir = r_dir),
    message = function(m) {
      msgs <<- c(msgs, conditionMessage(m))
      invokeRestart("muffleMessage")
    }
  )
  expect_equal(status, 2L)
  expect_true(any(grepl("Could not determine when packages/historicaldata source last", msgs)))
  expect_true(any(grepl("VERIFICATION DID NOT RUN", msgs)))
})

test_that("#911 falsification: reverting to the pre-fix pkg_source_digest-time comparison DOES flag scenario (a) as stale", {
  # This is the falsification step required by #911's dispatch spec: prove
  # the NEW test would have caught the OLD bug, by re-implementing the
  # pre-fix decision rule inline (comparing against pkg_source_digest's own
  # build time, gated only by "completed this run") and showing it produces
  # exactly the false positive the issue reported, on the same synthetic
  # data test (a) uses.
  old_buggy_decision <- function(meta, known_names, pkg_digest_time, progress) {
    stale <- character(0)
    for (nm in known_names) {
      t <- meta$time[match(nm, meta$name)]
      prog_row <- match(nm, progress$name)
      prog_val <- if (is.na(prog_row)) NA_character_ else progress$progress[prog_row]
      completed_this_run <- identical(prog_val, "completed")
      if (!is.na(t) && t < pkg_digest_time && !completed_this_run) {
        stale <- c(stale, nm)
      }
    }
    stale
  }

  meta <- tibble::tibble(
    name = c("art_vignette_seed", "qa_legacy_leaderboard_sentinel"),
    time = as.POSIXct(c("2026-09-26 11:13:30.500000", "2026-09-26 11:13:32.000000"), tz = "UTC")
  )
  pkg_digest_time <- as.POSIXct("2026-09-26 11:13:32.135217", tz = "UTC")
  # A LATER run's tar_progress() correctly reports both as "skipped" --
  # nothing about them changed since the run in which they (and the digest)
  # were actually built.
  progress <- tibble::tibble(
    name = c("art_vignette_seed", "qa_legacy_leaderboard_sentinel"),
    progress = c("skipped", "skipped")
  )

  old_result <- old_buggy_decision(meta, meta$name, pkg_digest_time, progress)
  expect_equal(old_result, meta$name) # OLD algorithm: both wrongly flagged stale

  new_result <- .cps_evaluate_staleness(
    meta, meta$name,
    pkg_source_changed_at = as.POSIXct("2026-09-26 11:12:16.669267", tz = "UTC"),
    progress = progress
  )
  expect_equal(new_result$stale, character(0)) # NEW algorithm: correctly not stale
})

# ── Function signature stability (catches API drift, snapshot-test-policy.md) ──

test_that("key .cps_* function signatures are stable", {
  expect_snapshot(args(.cps_discover_consuming_targets))
  expect_snapshot(args(.cps_main))
  expect_snapshot(args(.cps_contains_pkg_call))
  expect_snapshot(args(.cps_target_touches_pkg))
  expect_snapshot(args(.cps_helper_touches_pkg))
  expect_snapshot(args(.cps_pkg_source_changed_at))
  expect_snapshot(args(.cps_evaluate_staleness))
  expect_snapshot(args(.cps_source_files_paths))
})

# ── Direct unit tests for the lowest-level AST primitives ──────────────────

test_that(".cps_call_head_name resolves bare and namespaced call heads", {
  expect_equal(.cps_call_head_name(quote(tar_target(x, 1))), "tar_target")
  expect_equal(.cps_call_head_name(quote(targets::tar_target(x, 1))), "tar_target")
  expect_true(is.na(.cps_call_head_name(quote(x))))
  expect_true(is.na(.cps_call_head_name(1)))
})

test_that(".cps_is_pkg_call / .cps_contains_pkg_call distinguish direct vs nested vs absent package calls", {
  expect_true(.cps_is_pkg_call(quote(historicaldata::fn()), "historicaldata"))
  expect_false(.cps_is_pkg_call(quote(fn()), "historicaldata"))
  expect_false(.cps_is_pkg_call(quote(otherpkg::fn()), "historicaldata"))

  expect_true(.cps_contains_pkg_call(quote({
    a <- 1
    historicaldata::fn(a)
  }), "historicaldata"))
  expect_false(.cps_contains_pkg_call(quote({
    a <- 1
    dplyr::select(a, x)
  }), "historicaldata"))
  # triple-colon internal-function access also counts
  expect_true(.cps_contains_pkg_call(quote(historicaldata:::internal_fn()), "historicaldata"))
})

# ── #753 / #693 follow-up: "0 checked" must be distinguishable from "checked
# and clean" (checks-must-distinguish-unknown). After #922 converted every
# `historicaldata::fn()` target-body call to a bare call, discovery legitimately
# finds 0 namespaced consumers, and the old PASS line read identically to a
# real clean result. Contract under test (script header documents it):
#   0  examined >= 1 and none stale         -> "PASS ... (N checked)"
#   0  examined == 0 AND imports= declared  -> "VACUOUS-PASS (0 examined)" (labelled)
#   3  examined == 0 AND imports= NOT declared -> INDETERMINATE
#   1  stale target found (positive control)
# Every outcome prints a machine-readable "EXAMINED: <n>" line for build.sh.

# .make_targets_script() -- a stand-in docs/_targets.R; `imports` NULL omits it.
.make_targets_script <- function(dir, imports = "historicaldata") {
  path <- file.path(dir, "fake_docs_targets.R")
  opt <- if (is.null(imports)) {
    "targets::tar_option_set(error = \"continue\")"
  } else {
    sprintf("targets::tar_option_set(error = \"continue\", imports = \"%s\")", imports)
  }
  writeLines(c(opt, "list()"), path)
  path
}

# .make_vacuous_r_dir() -- plan file whose ONLY historicaldata mentions are a
# comment and roxygen: no executable namespaced call.
.make_vacuous_r_dir <- function(dir) {
  r_dir <- file.path(dir, "R_vacuous")
  dir.create(r_dir)
  writeLines(c(
    "# historicaldata::commented_out() must not count as a consumer",
    "#' Docs mention historicaldata::roxy_fn() too",
    "plan_vac <- function() {",
    "  list(targets::tar_target(consumer, bare_call()))",
    "}"
  ), file.path(r_dir, "plan_vac.R"))
  r_dir
}

test_that("positive control: stale namespaced consumer -> exit 1, [STALE-PKG] names it, EXAMINED: 1", {
  dir <- withr::local_tempdir()
  built <- .make_pkg_toy_store(dir)
  r_dir <- .make_registry_r_dir(dir)
  Sys.sleep(1.1)
  writeLines("f <- function() 2", built$pkg_file_path)
  targets::tar_make(
    script = file.path(built$dir, "_targets.R"), store = built$store_path,
    callr_function = NULL, reporter = "silent"
  )
  status <- NA_integer_
  out <- utils::capture.output(status <- .cps_main(
    store_path = built$store_path, r_dir = r_dir,
    targets_script = .make_targets_script(dir)
  ))
  txt <- paste(out, collapse = "\n")
  expect_equal(status, 1L)
  expect_match(txt, "\\[STALE-PKG\\] consumer")
  expect_match(txt, "EXAMINED: 1")
})

test_that("clean case: consumer rebuilt after the source change -> exit 0, '1 checked', EXAMINED: 1, not labelled vacuous", {
  dir <- withr::local_tempdir()
  built <- .make_pkg_toy_store(dir)
  r_dir <- .make_registry_r_dir(dir)
  status <- NA_integer_
  out <- utils::capture.output(status <- .cps_main(
    store_path = built$store_path, r_dir = r_dir,
    targets_script = .make_targets_script(dir)
  ))
  txt <- paste(out, collapse = "\n")
  expect_equal(status, 0L)
  expect_match(txt, "PASS: .*\\(1 checked\\)")
  expect_match(txt, "EXAMINED: 1")
  expect_no_match(txt, "VACUOUS")
})

test_that("vacuous case: 0 namespaced consumers + imports= declared -> exit 0 but LABELLED VACUOUS-PASS, EXAMINED: 0, never 'PASS: ... (0 checked)'", {
  dir <- withr::local_tempdir()
  built <- .make_pkg_toy_store(dir)
  r_dir <- .make_vacuous_r_dir(dir)
  status <- NA_integer_
  out <- utils::capture.output(status <- .cps_main(
    store_path = built$store_path, r_dir = r_dir,
    targets_script = .make_targets_script(dir)
  ))
  txt <- paste(out, collapse = "\n")
  expect_equal(status, 0L)
  expect_match(txt, "VACUOUS-PASS")
  expect_match(txt, "0 examined")
  expect_match(txt, "EXAMINED: 0")
  expect_no_match(txt, "\\(0 checked\\)")
  expect_snapshot(cat(grep("VACUOUS-PASS", out, value = TRUE), sep = "\n"))
})

test_that("indeterminate case: 0 namespaced consumers and imports= NOT declared -> exit 3, not a pass", {
  dir <- withr::local_tempdir()
  built <- .make_pkg_toy_store(dir)
  r_dir <- .make_vacuous_r_dir(dir)
  status <- NA_integer_
  msgs <- character(0)
  out <- character(0)
  withCallingHandlers(
    out <- utils::capture.output(status <- .cps_main(
      store_path = built$store_path, r_dir = r_dir,
      targets_script = .make_targets_script(dir, imports = NULL)
    )),
    message = function(m) {
      msgs <<- c(msgs, conditionMessage(m))
      invokeRestart("muffleMessage")
    }
  )
  expect_equal(status, 3L)
  expect_true(any(grepl("INDETERMINATE", c(out, msgs))))
  expect_true(any(grepl("EXAMINED: 0", out)))
  expect_false(any(grepl("PASS", out)))
})

test_that("indeterminate case: imports= names a DIFFERENT package -> exit 3 (declaration must be for historicaldata)", {
  dir <- withr::local_tempdir()
  built <- .make_pkg_toy_store(dir)
  status <- NA_integer_
  suppressMessages(utils::capture.output(status <- .cps_main(
    store_path = built$store_path, r_dir = .make_vacuous_r_dir(dir),
    targets_script = .make_targets_script(dir, imports = "otherpkg")
  )))
  expect_equal(status, 3L)
})

test_that(".cps_imports_declared() reads the AST: true only for tar_option_set(imports = ...historicaldata...)", {
  dir <- withr::local_tempdir()
  expect_true(.cps_imports_declared(.make_targets_script(dir)))
  expect_false(.cps_imports_declared(.make_targets_script(dir, imports = NULL)))
  expect_false(.cps_imports_declared(.make_targets_script(dir, imports = "otherpkg")))
  # a comment or string mentioning it is not a declaration
  p <- file.path(dir, "commented.R")
  writeLines(c("# tar_option_set(imports = \"historicaldata\")", "x <- 'imports = historicaldata'"), p)
  expect_false(.cps_imports_declared(p))
  # missing / unparsable file is FALSE (indeterminate upstream), never an error
  expect_false(.cps_imports_declared(file.path(dir, "nope.R")))
})

test_that("the REAL docs/_targets.R declares imports = \"historicaldata\" (the mechanism the vacuous-pass label relies on)", {
  expect_true(.cps_imports_declared(here::here("docs", "_targets.R")))
})

test_that("discovery: a comment/roxygen mention of historicaldata:: is not a consumer", {
  r_dir <- .make_vacuous_r_dir(withr::local_tempdir())
  expect_equal(nrow(.cps_discover_consuming_targets(r_dir)), 0L)
})

test_that(".cps_imports_declared signature is stable", {
  expect_snapshot(args(.cps_imports_declared))
})
