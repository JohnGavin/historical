#!/usr/bin/env bash
# scripts/verify.sh — single entry point to verify a change to this repo.
#
# This project uses flake.nix (NOT default.nix) and has no R on the bare
# PATH. This script wraps everything in `nix develop --command` so it works
# the same for a human or an agent, and runs (full mode) with NOT_CRAN=true
# set — WITHOUT it, testthat silently skips every skip_on_cran()-gated test,
# which includes this repo's mandated snapshot tests:
#   1. parse("_targets.R")                                  (always)
#   2. root testthat suite  (tests/testthat/)                (full mode only)
#   3. package testthat suite (packages/historicaldata/)      (full mode only)
#
# Both suites carry a small number of known pre-existing failures (see the
# BASELINE_* arrays below, issue #569) that predate this script and are NOT
# regressions. verify.sh exits 0 only if a suite's failing-test signatures
# are EXACTLY its baseline set — any addition, removal, or substitution is
# treated as a change worth a human's attention. A NEW failure that testthat
# reports as snapshot-related is called out as [NEW-SNAPSHOT] rather than
# [NEW] — it means a snapshot is missing or stale, not that behaviour
# regressed. SKIP counts are always printed alongside PASS/FAIL; a jump in
# SKIP without a code change is itself a signal worth investigating.
#
# Usage:
#   scripts/verify.sh            # full verification (can take a few minutes)
#   scripts/verify.sh --quick    # parse-only, fast pre-commit check
#
# Exit codes:
#   0  verified: parse OK, both suites' failures == their baseline exactly
#   1  verification RAN and found a problem (new/missing failure, parse error)
#   2  verification did NOT run at all (nix develop / Rscript unavailable or
#      crashed) — this is NOT a pass, never treat it as one

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
  echo "Mode: --quick (parse only)"
else
  echo "Mode: full (parse + root suite + package suite)"
fi
echo ""

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
R_OUT="$WORK_DIR/r_out.txt"

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
      list(total = nrow(df), failed = length(sig), skipped = sum(df$skipped),
           sig = sig, snap_sig = sort(snap_sig))
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
  echo "=== scripts/verify.sh: PASS (--quick, parse only) ==="
  exit 0
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

echo ""
if [[ "$OVERALL_STATUS" -eq 0 ]]; then
  echo "=== scripts/verify.sh: PASS ==="
else
  echo "=== scripts/verify.sh: FAIL ==="
fi
exit "$OVERALL_STATUS"
