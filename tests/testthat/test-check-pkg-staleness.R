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
# tracking one real file (`pkg_file`), a digest target depending on it
# (`pkg_source_digest` -- named to match what .cps_main() looks for), and a
# `consumer` target that does NOT reference the digest -- i.e. the exact
# "unwired, namespaced-call-style" shape #753 is about. Returns the store
# path; `pkg_file_path` is the file callers mutate to trigger a rebuild.
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
    sprintf('  targets::tar_target(pkg_file, "%s", format = "file"),', pkg_file_path),
    "  targets::tar_target(pkg_source_digest, tools::md5sum(pkg_file)[[1]]),",
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

  # Mutate the tracked package file and rebuild -- `pkg_file`/`pkg_source_digest`
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

# ── Function signature stability (catches API drift, snapshot-test-policy.md) ──

test_that("key .cps_* function signatures are stable", {
  expect_snapshot(args(.cps_discover_consuming_targets))
  expect_snapshot(args(.cps_main))
  expect_snapshot(args(.cps_contains_pkg_call))
  expect_snapshot(args(.cps_target_touches_pkg))
  expect_snapshot(args(.cps_helper_touches_pkg))
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
