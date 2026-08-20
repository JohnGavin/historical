#!/usr/bin/env bash
# scripts/verify.sh — single entry point to verify a change to this repo.
#
# This project uses flake.nix (NOT default.nix) and has no R on the bare
# PATH. This script wraps everything in `nix develop --command` so it works
# the same for a human or an agent, and runs (full mode) with NOT_CRAN=true
# set — WITHOUT it, testthat silently skips every skip_on_cran()-gated test,
# which includes this repo's mandated snapshot tests:
#   1. parse("_targets.R")                                    (always)
#   2. parse("docs/_targets.R")                                (always, #680)
#   3. tar_validate(script="docs/_targets.R")                  (always, #680)
#   4. dashboard freshness Check 1 + Check 2 (#695)            (full mode only)
#   5. root testthat suite  (tests/testthat/)                  (full mode only)
#   6. package testthat suite (packages/historicaldata/)        (full mode only)
#
# TWO PIPELINES — always pass script= explicitly (#680). `_targets.R` at repo
# root is a small "rn node" sandbox pipeline (~4 plan_ references). The real
# one is `docs/_targets.R` (~148 plan_ references) — it produces `leaderboard`
# and everything this repo publishes. Which one `targets` uses by default is
# decided by `_targets.yaml`, and that file is GITIGNORED — it exists only in
# the main checkout, never in a worktree. Any check that omits an explicit
# `script =` therefore silently validates the wrong pipeline in a worktree.
# Checks 1-3 above avoid that trap by naming the file directly.
#
# WHAT THIS SCRIPT DOES NOT PROVE — read before trusting a PASS (#680).
# tar_validate() needs no store and runs no target body: it only confirms the
# pipeline is STRUCTURALLY sound (parses, no duplicate target names, no
# circular deps, no unresolved symbols). It would NOT have caught either
# failure that broke `main` this week:
#   - PR #678 — a runtime cli_abort() inside ltr_portfolio (rf coverage).
#   - PR #683 — the same class, from stk_rf being scoped to one consumer's
#     window.
#   Both are structurally valid pipelines that abort on real data. Catching
#   that class needs an actual build (`tar_make()`) plus
#   `tar_meta(fields = error)` against a real store — see
#   scripts/check_pipeline_errors.R, a separate, post-build, main-checkout-
#   only script (a worktree has no store, and must not build one that could
#   race the main checkout's store).
# `error = "continue"` is set project-wide in docs/_targets.R, which means
# tar_make() itself EXITS 0 even when targets errored — a green tar_make()
# run is not proof either. That is exactly why check_pipeline_errors.R reads
# tar_meta() directly instead of trusting the exit code.
# A THIRD surface — docs/*.qmd chunks calling tar_read()/tar_read_raw()/
# safe_tar_read() for a specific target name — used to be entirely
# uncovered: a chunk referencing a target that no longer exists (typo,
# rename, removal) fails only at RENDER time, not at parse, not at
# tar_validate(), not at tar_make(). scripts/check_dashboard_freshness.R
# (#695) now closes the DEAD-REFERENCE half of that gap (its Check 1, run
# below in full mode only — see the fragment's own comment for why it is
# not in --quick) plus a related but distinct gap, source-vs-render
# staleness (its Check 2: a committed .html older than its own .qmd source —
# GitHub Pages serves the committed .html directly, so nothing else notices
# this). What remains uncovered by THIS script: DATA staleness — a
# correctly-rendered page still showing month-old target values because
# nothing re-renders it after the pipeline rebuilds. That needs a real
# targets store, so it is Check 3 of the same script, wired into
# scripts/build.sh instead (main-checkout only) — see that script and
# check_dashboard_freshness.R own header comment.
#
# Both testthat suites carry a small number of known pre-existing failures
# (see the BASELINE_* arrays below, issue #569) that predate this script and
# are NOT regressions. verify.sh exits 0 only if a suite's failing-test
# signatures are EXACTLY its baseline set — any addition, removal, or
# substitution is treated as a change worth a human's attention. A NEW
# failure that testthat reports as snapshot-related is called out as
# [NEW-SNAPSHOT] rather than [NEW] — it means a snapshot is missing or stale,
# not that behaviour regressed. SKIP counts are always printed alongside
# PASS/FAIL; for the package suite, a rise above BASELINE_PKG_SKIP_COUNT now
# FAILS the run (#654) rather than merely printing a warning. The root suite
# has no maintained skip baseline (normally 0) and is printed only.
#
# Usage:
#   scripts/verify.sh            # full verification (can take a few minutes)
#   scripts/verify.sh --quick    # parse + structural DAG validate (fast; the
#                                 # tar_validate() call measured ~7s warm —
#                                 # see #680 PR body — so it stays in --quick)
#
# Exit codes:
#   0  verified: both pipelines parse, docs/_targets.R validates structurally
#      OK, dashboard freshness Check 1 found no dead target references (full
#      mode only — see #695), and both testthat suites' failures == their
#      baseline exactly
#   1  verification RAN and found a problem (new/missing test failure, a
#      parse error in docs/_targets.R, a tar_validate() structural error, a
#      dead target reference in a docs/*.qmd chunk (#695 Check 1 — always a
#      hard failure), or — only when HD_FAIL_ON_STALE_DASHBOARDS is set — a
#      stale dashboard (#695 Check 2, informational-only by default; see
#      scripts/check_dashboard_freshness.R header comment for why)
#   2  verification did NOT run at all (nix develop / Rscript unavailable or
#      crashed, or the ROOT _targets.R failed to parse) — this is NOT a pass,
#      never treat it as one

set -euo pipefail

# ---------------------------------------------------------------------------
# Known pre-existing failures in the ROOT testthat suite (tests/testthat/),
# confirmed 2026-07-19 (issue #569). These predate this script and are
# tracked here deliberately so an agent doesn't misread them as its own
# regression. Format: one line per failure, "<file>::<test description>".
# Do NOT add an entry here to silence a new failure; fix it, or get explicit
# sign-off and update this list on purpose.
# ---------------------------------------------------------------------------
BASELINE_ROOT_FAILURES=(
  "test-crypto-momentum.R::C1: as.Date coercion makes POSIXct dates filterable against Date bounds"
  "test-qa-summary-deps.R::qa_summary declares every *_metrics target defined in plan files"
  "test-stock-backtest.R::raw POSIXct vs Date comparison emits Ops.POSIXt warning (baseline)"
)

# ---------------------------------------------------------------------------
# Known pre-existing failures in the packages/historicaldata testthat suite,
# confirmed 2026-07-19 (issue #569). Same rules as BASELINE_ROOT_FAILURES.
# ---------------------------------------------------------------------------
BASELINE_PKG_FAILURES=(
  "test-mom-prepeak-portfolio.R::.mom_prepeak_compute_returns caps short returns at +100%"
)

# ---------------------------------------------------------------------------
# Normal SKIP count for the package suite, confirmed 2026-07-22 (issue #580
# Phase 2). Composition (verify with the [SKIP] detail lines this script
# prints once the count exceeds this baseline):
#   - 4: {alphavantager} not installed (test-alphavantage.R x3,
#        test-column-naming.R x1) — pre-existing, unrelated to #580.
#   - 11: test-remote-live.R — the opt-in live-endpoint coverage file added
#        by #580 Phase 2. These intentionally skip by default (gated on
#        `HD_TEST_LIVE` being set) because Phase 2 made the 13 tests that
#        used to call `skip_if_no_remote_data()` in test-query.R,
#        test-ranked.R, and test-registry.R hermetic against bundled sample
#        fixtures (inst/extdata/sample/*.parquet) instead — they now run
#        unconditionally and contribute 0 to this count. test-remote-live.R
#        preserves the original live-endpoint assertions for opt-in use
#        (`HD_TEST_LIVE=1`) so "does the real remote schema still match?"
#        stays checkable on demand.
# Do NOT bump this number to silence a rising skip count from any OTHER
# source — a jump above it means something besides the known 4+11 above is
# skipping; investigate, don't hide it.
# ---------------------------------------------------------------------------
BASELINE_PKG_SKIP_COUNT=15

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# CRITICAL: cd into the repo this script belongs to.
# `nix develop "$REPO_ROOT"` only selects which flake provides the shell — the
# Rscript process it launches INHERITS THE CALLER'S CWD. Without this cd, running
# e.g. /path/to/worktree-A/scripts/verify.sh from inside worktree-B silently
# verifies worktree-B while reporting worktree-A's path in its header. That is a
# false PASS: it tests a tree the caller never asked about.
# Symptom to watch for: the suite's total test count differs between runs that
# should be identical. See #575.
cd "$REPO_ROOT"

# Fail loudly if this is not actually a checkout of this repo.
if [[ ! -f "$REPO_ROOT/_targets.R" ]]; then
  echo "!!! $REPO_ROOT does not contain _targets.R — not a valid checkout !!!"
  echo "!!! VERIFICATION DID NOT RUN. This is NOT a pass.                 !!!"
  exit 2
fi

# testthat edition 3 for the ROOT suite (#578/#579).
#
# The repo root is not a package, so testthat's find_edition() finds no
# DESCRIPTION and falls back to edition 2:
#     from_environment <- Sys.getenv("TESTTHAT_EDITION")
#     if (nzchar(from_environment)) return(as.integer(from_environment))
#     desc <- find_description(path, package)
#     if (is.null(desc)) return(2L)
#
# TESTTHAT_EDITION is the only lever that works without a DESCRIPTION, and it
# must be set BEFORE test_dir() — edition_get() caches into `the$edition`, so
# a tests/setup.R cannot do it (setup runs too late). Measured, all variants:
#     setup.R local_edition(3, .env = teardown_env())  -> edition 2  (no-op)
#     setup.R local_edition(3, .env = globalenv())     -> edition 2  (no-op)
#     setup.R options(testthat.edition = 3)            -> edition 2  (no-op)
#     setup.R Sys.setenv(TESTTHAT_EDITION = 3)         -> edition 2  (too late)
#     TESTTHAT_EDITION=3 exported before test_dir()    -> edition 3  (works)
#
# Note the global snapshot-tests-mandatory rule prescribes the first form,
# which does nothing — see JohnGavin/llm#799.
#
# This does NOT make the per-file `testthat::local_edition(3)` declarations
# redundant: they are the only thing that holds when someone runs test_dir()
# directly without this script. Keep declaring it in new root test files.
export TESTTHAT_EDITION=3

QUICK=0
if [[ "${1:-}" == "--quick" ]]; then
  QUICK=1
fi

echo "=== scripts/verify.sh ==="
echo "Repo root: $REPO_ROOT"
if [[ "$QUICK" -eq 1 ]]; then
  echo "Mode: --quick (parse + docs/_targets.R structural validate)"
else
  echo "Mode: full (parse + docs/_targets.R structural validate + root suite + package suite)"
fi
echo ""

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
R_OUT="$WORK_DIR/r_out.txt"

# R fragment shared by both modes (#680): validate the REAL pipeline
# (docs/_targets.R), always naming script= explicitly — see the header
# comment for why relying on the ambient (gitignored) _targets.yaml is the
# bug this issue is about. Does NOT quit() on failure -- unlike the root
# _targets.R gate above, a failure here is reported via OVERALL_STATUS
# (exit 1), never treated as "verification did not run" (exit 2).
DOCS_VALIDATE_FRAGMENT='
    docs_parse_ok <- tryCatch({
      parse(file.path("docs", "_targets.R"))
      TRUE
    }, error = function(e) {
      message("DOCS_PARSE_ERROR: ", conditionMessage(e))
      FALSE
    })
    cat("::VERIFY:DOCS_PARSE_OK::", docs_parse_ok, "\n")

    # tar_validate() needs no store and runs no target body -- see the
    # header comment for exactly what this does and does not prove.
    validate_start <- Sys.time()
    validate_ok <- if (isTRUE(docs_parse_ok)) {
      tryCatch({
        targets::tar_validate(script = file.path("docs", "_targets.R"), store = tempfile())
        TRUE
      }, error = function(e) {
        message("TAR_VALIDATE_ERROR: ", conditionMessage(e))
        FALSE
      })
    } else {
      message("TAR_VALIDATE_ERROR: skipped -- docs/_targets.R failed to parse")
      FALSE
    }
    validate_elapsed <- as.numeric(Sys.time() - validate_start, units = "secs")
    cat("::VERIFY:TAR_VALIDATE_OK::", validate_ok, "\n")
    cat(sprintf("::VERIFY:TAR_VALIDATE_ELAPSED:: %.2f\n", validate_elapsed))
'

# scripts/check_dashboard_freshness.R Check 1 (dead target references) and
# Check 2 (source-vs-render staleness) -- #695, the third render-time
# surface named by #680 that nothing else in this script catches: a
# docs/*.qmd chunk calling tar_read() for a target name that no longer
# exists fails only at an actual quarto render (Check 1); a committed .html
# older than its own .qmd source silently keeps serving stale content, since
# GitHub Pages serves the committed .html directly with nothing re-rendering
# it (Check 2). FULL MODE ONLY, not --quick: Check 1 needs
# targets::tar_manifest(docs/_targets.R), which must fully evaluate the real
# pipeline script -- the same order of cost (~7-8s warm, measured
# 2026-08-20) as this script own tar_validate() call above, and --quick is
# documented as parse plus structural validate only. Embedded via source()
# into THIS Rscript process rather than a second nix develop --command call,
# to avoid paying a second ~13s nix-develop entry on top of that ~7-8s
# manifest cost. Does NOT quit() on failure, matching
# DOCS_VALIDATE_FRAGMENT above and check_dashboard_freshness.R own internal
# contract (see that script header comment) -- a problem is reported via
# OVERALL_STATUS below via the printed ::VERIFY:DASHBOARD_FRESHNESS_STATUS::
# marker, never treated as verification did not run.
DASHBOARD_FRESHNESS_FRAGMENT='
    source(file.path("scripts", "check_dashboard_freshness.R"))
    invisible(.cdf_main(data_staleness = FALSE))
'

if [[ "$QUICK" -eq 1 ]]; then
  R_SCRIPT='
    cat("::VERIFY:CWD::", getwd(), "\n")
    parse_ok <- tryCatch({
      parse(file.path("_targets.R"))
      TRUE
    }, error = function(e) {
      message("PARSE_ERROR: ", conditionMessage(e))
      FALSE
    })
    if (!isTRUE(parse_ok)) quit(status = 1, save = "no")
    cat("::VERIFY:PARSE_OK::\n")
'"$DOCS_VALIDATE_FRAGMENT"'
  '
else
  R_SCRIPT='
    cat("::VERIFY:CWD::", getwd(), "\n")
    cat("::VERIFY:EDITION::", testthat::edition_get(), "\n")
    pkg_path <- file.path("packages", "historicaldata")

    parse_ok <- tryCatch({
      parse(file.path("_targets.R"))
      TRUE
    }, error = function(e) {
      message("PARSE_ERROR: ", conditionMessage(e))
      FALSE
    })
    if (!isTRUE(parse_ok)) quit(status = 1, save = "no")
    cat("::VERIFY:PARSE_OK::\n")
'"$DOCS_VALIDATE_FRAGMENT"'
'"$DASHBOARD_FRESHNESS_FRAGMENT"'

    # NOT_CRAN=true — WITHOUT this, testthat silently SKIPS every
    # skip_on_cran()-gated test, and that gate is what this project uses to
    # guard its mandated snapshot tests (error messages, captions, function
    # signatures, target schemas — see the snapshot-test-policy rule). A
    # plain `Rscript -e test_dir(...)` run leaves NOT_CRAN unset, so those
    # snapshot tests never execute at all — they get written, committed, and
    # then never checked again. Confirmed empirically 2026-07-19 (#569
    # follow-up) on this exact root suite: NOT_CRAN unset -> 41 skipped;
    # NOT_CRAN=true -> 0 skipped, same 3 baseline failures either way.
    Sys.setenv(NOT_CRAN = "true")

    suppressPackageStartupMessages(library(testthat))

    # Pull the failure message out of a test_dir() result row so we can tell
    # a snapshot mismatch/missing-snapshot failure (testthat mentions
    # "snapshot" in the condition message) apart from an ordinary assertion
    # failure. Heuristic, based on testthat'"'"'s documented expect_snapshot()
    # message format — a missing/stale snapshot means the test never ran
    # under the old NOT_CRAN-unset regime, not that behaviour regressed.
    extract_fail_msg <- function(result_list) {
      msgs <- vapply(result_list, function(cond) {
        if (inherits(cond, "expectation") && !inherits(cond, "expectation_success")) {
          tryCatch(conditionMessage(cond), error = function(e) "<no message>")
        } else {
          NA_character_
        }
      }, character(1))
      paste(msgs[!is.na(msgs)], collapse = " ||| ")
    }

    # Pull the skip() reason out of a test result row (#580). A skipped test
    # (df$skipped > 0) carries an "expectation_skip" condition among its
    # recorded results (confirmed empirically against this testthat version —
    # NOT "skip", which is a different, unrelated condition class); surfacing
    # its message is what makes a rising SKIP count diagnosable instead of
    # just visible as a bare number.
    extract_skip_msg <- function(result_list) {
      msgs <- vapply(result_list, function(cond) {
        if (inherits(cond, "expectation_skip")) {
          tryCatch(conditionMessage(cond), error = function(e) "<no message>")
        } else {
          NA_character_
        }
      }, character(1))
      msgs <- msgs[!is.na(msgs)]
      if (length(msgs) == 0) "<no skip reason recorded>" else paste(msgs, collapse = " ||| ")
    }

    report_suite <- function(res) {
      df <- as.data.frame(res)
      fail_idx <- which((df$failed > 0) | (df$error > 0))
      sig <- sort(paste0(df$file[fail_idx], "::", df$test[fail_idx]))
      snap_sig <- character(0)
      for (i in fail_idx) {
        msg <- extract_fail_msg(df$result[[i]])
        if (grepl("snapshot", msg, ignore.case = TRUE)) {
          snap_sig <- c(snap_sig, paste0(df$file[i], "::", df$test[i]))
        }
      }
      skip_idx <- which(df$skipped > 0)
      skip_detail <- vapply(skip_idx, function(i) {
        sprintf("%s::%s -- %s", df$file[i], df$test[i], extract_skip_msg(df$result[[i]]))
      }, character(1))
      list(total = nrow(df), failed = length(sig), skipped = sum(df$skipped),
           sig = sig, snap_sig = sort(snap_sig), skip_detail = sort(skip_detail))
    }

    # Root suite: tests/testthat/ exercises repo-root R/ scripts that are
    # NOT part of packages/historicaldata (see tests/testthat.R). Note this
    # is test_dir(), not test_local() — test_local() fails at repo root
    # because there is no DESCRIPTION file here.
    root_res <- test_dir("tests/testthat", stop_on_failure = FALSE, reporter = "silent")
    root <- report_suite(root_res)
    cat("::VERIFY:ROOT_SIGNATURES_START::\n")
    if (length(root$sig) > 0) cat(paste(root$sig, collapse = "\n"), "\n", sep = "")
    cat("::VERIFY:ROOT_SIGNATURES_END::\n")
    cat("::VERIFY:ROOT_SNAPSHOT_FAILS_START::\n")
    if (length(root$snap_sig) > 0) cat(paste(root$snap_sig, collapse = "\n"), "\n", sep = "")
    cat("::VERIFY:ROOT_SNAPSHOT_FAILS_END::\n")
    cat("::VERIFY:ROOT_SKIP_DETAILS_START::\n")
    if (length(root$skip_detail) > 0) cat(paste(root$skip_detail, collapse = "\n"), "\n", sep = "")
    cat("::VERIFY:ROOT_SKIP_DETAILS_END::\n")
    cat(sprintf("::VERIFY:ROOT_SUMMARY:: total=%d failed=%d skipped=%d\n", root$total, root$failed, root$skipped))

    # Package suite: packages/historicaldata — load_all() first so the
    # package tests see the current source, not an installed copy.
    suppressPackageStartupMessages(library(pkgload))
    load_all(pkg_path, quiet = TRUE)
    pkg_res <- test_dir(file.path(pkg_path, "tests", "testthat"),
                         package = "historicaldata", stop_on_failure = FALSE, reporter = "silent")
    pkg <- report_suite(pkg_res)
    cat("::VERIFY:PKG_SIGNATURES_START::\n")
    if (length(pkg$sig) > 0) cat(paste(pkg$sig, collapse = "\n"), "\n", sep = "")
    cat("::VERIFY:PKG_SIGNATURES_END::\n")
    cat("::VERIFY:PKG_SNAPSHOT_FAILS_START::\n")
    if (length(pkg$snap_sig) > 0) cat(paste(pkg$snap_sig, collapse = "\n"), "\n", sep = "")
    cat("::VERIFY:PKG_SNAPSHOT_FAILS_END::\n")
    cat("::VERIFY:PKG_SKIP_DETAILS_START::\n")
    if (length(pkg$skip_detail) > 0) cat(paste(pkg$skip_detail, collapse = "\n"), "\n", sep = "")
    cat("::VERIFY:PKG_SKIP_DETAILS_END::\n")
    cat(sprintf("::VERIFY:PKG_SUMMARY:: total=%d failed=%d skipped=%d\n", pkg$total, pkg$failed, pkg$skipped))

    cat("::VERIFY:DONE::\n")
  '
fi

echo "--- entering nix develop (warm: ~13s, cold build: 10+ min compiling R packages) ---"
set +e
nix develop "$REPO_ROOT" --command Rscript -e "$R_SCRIPT" 2>&1 | tee "$R_OUT"
NIX_STATUS=${PIPESTATUS[0]}
set -e
echo "--- nix develop exited $NIX_STATUS ---"
echo ""

if [[ "$NIX_STATUS" -ne 0 ]] || ! grep -q "::VERIFY:PARSE_OK::" "$R_OUT"; then
  echo "!!! VERIFICATION DID NOT RUN — nix develop / Rscript failed or exited early !!!"
  echo "!!! This is NOT a pass. Do not report this as verified-clean.             !!!"
  exit 2
fi

# Guard against the #575 class of bug: confirm R actually ran in REPO_ROOT and
# not in some inherited cwd. If these ever diverge the results describe a
# different tree than the one this script claims to be verifying.
R_CWD="$(grep '::VERIFY:CWD::' "$R_OUT" | head -1 | sed 's/.*::VERIFY:CWD:: *//' | sed 's/[[:space:]]*$//' | tr -d '\r')"
if [[ "$(cd "$R_CWD" 2>/dev/null && pwd -P)" != "$(cd "$REPO_ROOT" && pwd -P)" ]]; then
  echo "!!! CWD MISMATCH — R ran in '$R_CWD' but this script targets '$REPO_ROOT' !!!"
  echo "!!! Results would describe the WRONG TREE. This is NOT a pass.           !!!"
  exit 2
fi
echo "PASS: _targets.R parses (verified tree: $R_CWD)"

# The REAL pipeline (#680) — root _targets.R above is a small sandbox
# pipeline; docs/_targets.R is the one that builds `leaderboard`. A failure
# here is a genuine problem, reported below (exit 1), never the "did not run"
# gate above (exit 2) — see the header comment for exactly what tar_validate()
# does and does not prove.
DOCS_STATUS=0
if grep -q '::VERIFY:DOCS_PARSE_OK:: TRUE' "$R_OUT"; then
  echo "PASS: docs/_targets.R parses"
else
  echo "FAIL: docs/_targets.R failed to parse — see DOCS_PARSE_ERROR above"
  DOCS_STATUS=1
fi

VALIDATE_STATUS=0
VALIDATE_ELAPSED="$(grep '::VERIFY:TAR_VALIDATE_ELAPSED::' "$R_OUT" | head -1 | sed 's/.*:: *//' | tr -d '[:space:]')"
if grep -q '::VERIFY:TAR_VALIDATE_OK:: TRUE' "$R_OUT"; then
  echo "PASS: docs/_targets.R is structurally valid (tar_validate, ${VALIDATE_ELAPSED}s — structural only, see header comment for what this does not prove)"
else
  echo "FAIL: docs/_targets.R failed tar_validate() (${VALIDATE_ELAPSED}s) — see TAR_VALIDATE_ERROR above"
  VALIDATE_STATUS=1
fi

# Edition guard. If this ever reads 2, every skip_on_cran()-gated snapshot test
# silently changes behaviour while the suite still reports green — the #574
# failure mode. Loud is the only acceptable outcome.
if [[ "$QUICK" -eq 0 ]]; then
  R_EDITION="$(grep '::VERIFY:EDITION::' "$R_OUT" | head -1 | sed 's/.*::VERIFY:EDITION:: *//' | sed 's/[[:space:]]*$//')"
  if [[ "$R_EDITION" != "3" ]]; then
    echo "!!! testthat edition is '$R_EDITION', expected 3 !!!"
    echo "!!! Snapshot tests do not behave as intended. This is NOT a pass. !!!"
    exit 2
  fi
  echo "PASS: testthat edition 3 active"
fi

if [[ "$QUICK" -eq 1 ]]; then
  echo ""
  if [[ "$DOCS_STATUS" -eq 0 ]] && [[ "$VALIDATE_STATUS" -eq 0 ]]; then
    echo "=== scripts/verify.sh: PASS (--quick, parse + docs/_targets.R structural validate) ==="
    exit 0
  fi
  echo "=== scripts/verify.sh: FAIL (--quick) ==="
  exit 1
fi

if ! grep -q "::VERIFY:DONE::" "$R_OUT"; then
  echo "!!! VERIFICATION DID NOT COMPLETE — R script did not reach the end !!!"
  echo "!!! This is NOT a pass. Do not report this as verified-clean.     !!!"
  exit 2
fi

# compare_failure_set LABEL BASELINE_NL CURRENT_NL SNAPSHOT_CURRENT_NL SUMMARY_LINE
# Prints a PASS/FAIL block (with SKIP count) for one suite and returns 0
# (match) or 1 (differs). NEW failures that testthat flagged as
# snapshot-related (SNAPSHOT_CURRENT_NL) are called out distinctly — a
# missing/stale snapshot means the test never ran before, not a regression.
compare_failure_set() {
  local label="$1"
  local baseline="$2"
  local current="$3"
  local snapshot_current="$4"
  local summary_line="$5"
  local baseline_sorted current_sorted snapshot_sorted new_failures resolved_failures skipped_n line

  baseline_sorted="$(printf '%s\n' "$baseline" | sed '/^[[:space:]]*$/d' | sort)"
  current_sorted="$(printf '%s\n' "$current" | sed '/^[[:space:]]*$/d' | sort)"
  snapshot_sorted="$(printf '%s\n' "$snapshot_current" | sed '/^[[:space:]]*$/d' | sort)"
  skipped_n="$(printf '%s\n' "$summary_line" | grep -oE 'skipped=[0-9]+' | grep -oE '[0-9]+' || echo '?')"

  echo ""
  echo "=== $label ==="
  echo "SKIP count this run: $skipped_n"
  if [[ "$current_sorted" == "$baseline_sorted" ]]; then
    if [[ -z "$baseline_sorted" ]]; then
      echo "PASS: no failures (fully green)"
    else
      echo "PASS: failures match the known baseline exactly:"
      echo "$baseline_sorted" | sed 's/^/  [baseline, expected] /'
    fi
    return 0
  fi

  echo "FAIL: failures differ from the known baseline."
  new_failures="$(comm -13 <(echo "$baseline_sorted") <(echo "$current_sorted") | sed '/^[[:space:]]*$/d' || true)"
  resolved_failures="$(comm -23 <(echo "$baseline_sorted") <(echo "$current_sorted") | sed '/^[[:space:]]*$/d' || true)"
  if [[ -n "$new_failures" ]]; then
    echo "  NEW failures (not in baseline — investigate, these may be your regression):"
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      if printf '%s\n' "$snapshot_sorted" | grep -qxF "$line"; then
        echo "    [NEW-SNAPSHOT] $line"
        echo "        -> missing/stale snapshot, NOT necessarily a behaviour regression."
        echo "           Review with testthat::snapshot_review()/snapshot_accept(), then commit the _snaps/ file."
      else
        echo "    [NEW] $line"
      fi
    done <<< "$new_failures"
  fi
  if [[ -n "$resolved_failures" ]]; then
    echo "  Baseline failures NOT seen this run (may be fixed — update the baseline deliberately if confirmed):"
    echo "$resolved_failures" | sed 's/^/    [RESOLVED?] /'
  fi
  return 1
}

OVERALL_STATUS=0
if [[ "$DOCS_STATUS" -ne 0 ]] || [[ "$VALIDATE_STATUS" -ne 0 ]]; then
  OVERALL_STATUS=1
fi

# scripts/check_dashboard_freshness.R Check 1 + Check 2 (#695). The full
# human-readable report already streamed to the terminal above (tee), since
# this check runs embedded inside the same nix develop -- command Rscript
# call as everything else in this section -- only the final status marker is
# parsed here. A status of 2 (the check itself could not run, e.g.
# tar_manifest() failed to evaluate docs/_targets.R) is folded into
# OVERALL_STATUS=1 rather than exiting this script with 2: by this point the
# root and package test suites have ALREADY run and their results are known
# (this R process never quit() early -- see check_dashboard_freshness.R
# header comment on why), so discarding that information to report "did not
# run at all" would be wrong. A tar_manifest() failure of the real pipeline
# is also very likely to have already surfaced above as a tar_validate()
# FAILURE (VALIDATE_STATUS), since both evaluate the same docs/_targets.R.
DASHBOARD_FRESHNESS_STATUS_RAW="$(grep '::VERIFY:DASHBOARD_FRESHNESS_STATUS::' "$R_OUT" | tail -1 | sed 's/.*:: *//' | tr -d '[:space:]')"
case "$DASHBOARD_FRESHNESS_STATUS_RAW" in
  0)
    echo "PASS: dashboard freshness (scripts/check_dashboard_freshness.R Check 1 + Check 2 — see full report above)"
    ;;
  1)
    echo "FAIL: dashboard freshness found a problem — see [DEAD-REF]/[STALE] lines in the report above"
    OVERALL_STATUS=1
    ;;
  2)
    echo "!!! dashboard freshness check could not run (status 2) — see the report above for the underlying error !!!"
    OVERALL_STATUS=1
    ;;
  *)
    echo "!!! dashboard freshness check produced no ::VERIFY:DASHBOARD_FRESHNESS_STATUS:: marker at all — see report above !!!"
    OVERALL_STATUS=1
    ;;
esac

CURRENT_ROOT_SIGNATURES="$(awk '/::VERIFY:ROOT_SIGNATURES_START::/{flag=1; next} /::VERIFY:ROOT_SIGNATURES_END::/{flag=0} flag' "$R_OUT")"
CURRENT_ROOT_SNAPSHOT="$(awk '/::VERIFY:ROOT_SNAPSHOT_FAILS_START::/{flag=1; next} /::VERIFY:ROOT_SNAPSHOT_FAILS_END::/{flag=0} flag' "$R_OUT")"
ROOT_SUMMARY_LINE="$(grep '::VERIFY:ROOT_SUMMARY::' "$R_OUT" || true)"
BASELINE_ROOT_STR="$(printf '%s\n' "${BASELINE_ROOT_FAILURES[@]+"${BASELINE_ROOT_FAILURES[@]}"}")"
if ! compare_failure_set "root suite (tests/testthat/, ${#BASELINE_ROOT_FAILURES[@]} known baseline failure(s), issue #569)" \
     "$BASELINE_ROOT_STR" "$CURRENT_ROOT_SIGNATURES" "$CURRENT_ROOT_SNAPSHOT" "$ROOT_SUMMARY_LINE"; then
  OVERALL_STATUS=1
fi

CURRENT_PKG_SIGNATURES="$(awk '/::VERIFY:PKG_SIGNATURES_START::/{flag=1; next} /::VERIFY:PKG_SIGNATURES_END::/{flag=0} flag' "$R_OUT")"
CURRENT_PKG_SNAPSHOT="$(awk '/::VERIFY:PKG_SNAPSHOT_FAILS_START::/{flag=1; next} /::VERIFY:PKG_SNAPSHOT_FAILS_END::/{flag=0} flag' "$R_OUT")"
PKG_SUMMARY_LINE="$(grep '::VERIFY:PKG_SUMMARY::' "$R_OUT" || true)"
BASELINE_PKG_STR="$(printf '%s\n' "${BASELINE_PKG_FAILURES[@]+"${BASELINE_PKG_FAILURES[@]}"}")"
if ! compare_failure_set "package suite (packages/historicaldata/, ${#BASELINE_PKG_FAILURES[@]} known baseline failure(s), issue #569)" \
     "$BASELINE_PKG_STR" "$CURRENT_PKG_SIGNATURES" "$CURRENT_PKG_SNAPSHOT" "$PKG_SUMMARY_LINE"; then
  OVERALL_STATUS=1
fi

# Skip-reason surfacing (#580) + skip-count assertion (#654): a package-suite
# SKIP count above its normal baseline (15 -- see BASELINE_PKG_SKIP_COUNT
# above) must be impossible to miss silently AND must fail the script, not
# merely print a warning that scrolls past. #654 found this block only ever
# echoed a warning -- it never set OVERALL_STATUS, so the count could have
# kept rising forever while verify.sh reported PASS. Any rise above the
# baseline now fails the run (exit 1), matching how the failure-signature
# comparisons above already behave.
PKG_SKIPPED_N="$(printf '%s\n' "$PKG_SUMMARY_LINE" | grep -oE 'skipped=[0-9]+' | grep -oE '[0-9]+' || echo '')"
if [[ -n "$PKG_SKIPPED_N" ]] && [[ "$PKG_SKIPPED_N" -gt "$BASELINE_PKG_SKIP_COUNT" ]]; then
  echo ""
  echo "!!! package suite SKIP count ($PKG_SKIPPED_N) exceeds normal baseline ($BASELINE_PKG_SKIP_COUNT) !!!"
  echo "!!! This is lost coverage, not a pass. Skipped tests and their reasons:                        !!!"
  PKG_SKIP_DETAILS="$(awk '/::VERIFY:PKG_SKIP_DETAILS_START::/{flag=1; next} /::VERIFY:PKG_SKIP_DETAILS_END::/{flag=0} flag' "$R_OUT")"
  echo "$PKG_SKIP_DETAILS" | sed '/^[[:space:]]*$/d' | sed 's/^/    [SKIP] /'
  OVERALL_STATUS=1
fi

echo ""
if [[ "$OVERALL_STATUS" -eq 0 ]]; then
  echo "=== scripts/verify.sh: PASS ==="
else
  echo "=== scripts/verify.sh: FAIL ==="
fi
exit "$OVERALL_STATUS"
