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
# HOW THE CHECK WORKS (avoiding the same-run-scheduling-order trap): a
# naive "is target X's tar_meta() build time older than pkg_source_digest's
# build time" comparison produces FALSE POSITIVES on a fresh/full rebuild,
# where every target (including pkg_source_digest) builds in the same
# invocation and `targets`' scheduler is free to run them in any relative
# order — a target that legitimately built moments BEFORE pkg_source_digest
# in the very same run would wrongly read as "older". This script instead
# combines tar_meta() (time) with tar_progress() (this run's outcome per
# target — "completed" vs "skipped" vs "errored"): a target is only flagged
# stale when it was SKIPPED in the current run (progress != "completed")
# AND its recorded build time predates pkg_source_digest's — i.e. its
# cached value was computed before the package's last recorded content
# change, and this run gave it no chance to catch up either. A target that
# DID rebuild this run is always current, regardless of exact timestamp
# ordering against pkg_source_digest within the same invocation.
#
# WHICH TARGETS ARE CHECKED (the registry, and its honest limits): this
# script does NOT hand-maintain a list of "package-consuming target names"
# — that list would itself go stale the same way #753's own bug did (see
# .claude/rules/fail-loud-not-null.md: "a guard scoped to the input that
# failed last time"). Instead, .cps_discover_consuming_targets() scans
# every R/*.R file for a `historicaldata::` occurrence and, for any file
# that has one, extracts every tar_target()/tar_target_raw() name defined
# ANYWHERE in that file (a per-FILE, not per-call-site, over-approximation
# — cheaper and, per this project's stated design constraint that a false
# PASS is worse than a false FAIL, the deliberately noisier direction).
# This is a REGISTRY OF NAMESPACED-CALL SITES specifically: bare-name calls
# are already covered automatically by tar_option_set(imports =
# "historicaldata") in docs/_targets.R (#753 mechanism 2a) and are not
# re-scanned here — the residual risk that mechanism ALSO leaves uncovered
# (an indirect call via do.call()/Reduce()/a stored function reference that
# codetools::findGlobals() cannot see) is not caught by this script either;
# nothing in this repo currently exercises that pattern for
# `historicaldata::`, but it is worth naming as a known gap rather than
# implying full coverage this script does not actually have.
#
# Usage (from anywhere inside the repo, after a real docs/ build):
#   nix develop --command Rscript -e \
#     'targets::tar_make(script = "docs/_targets.R", store = "docs/_targets")'
#   nix develop --command Rscript scripts/check_pkg_staleness.R
#
# Exit codes:
#   0  no stale package-consuming target found (or none discovered at all)
#   1  one or more known package-consuming targets were skipped in a run
#      where pkg_source_digest's recorded build time is newer than theirs
#   2  could not run the check at all (no store, pkg_source_digest not yet
#      built in this store, tar_meta()/tar_progress() failed or returned a
#      truncated read — see #730) — this is NOT a pass, never treat it as
#      one

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

# .cps_discover_consuming_targets() — see the header comment above for the
# full design and its honest limits. Returns a tibble(file, target_name),
# one row per (file, target) pair found; a target defined in more than one
# scanned file (should not happen, but not this function's job to enforce)
# would simply appear more than once here.
.cps_discover_consuming_targets <- function(r_dir = here::here("R")) {
  files <- list.files(r_dir, pattern = "\\.R$", full.names = TRUE)
  out_files <- character(0)
  out_names <- character(0)
  for (f in files) {
    lines <- readLines(f, warn = FALSE)
    if (!any(grepl("historicaldata::", lines, fixed = TRUE))) next

    # Name always appears on the SAME line as the opening call in this
    # repo's style (confirmed via grep across every plan_*.R file,
    # 2026-08-25) -- e.g. `targets::tar_target(cmr_signals_1m, {`.
    m1 <- regmatches(lines, regexpr("tar_target\\(\\s*([A-Za-z.][A-Za-z0-9._]*)", lines, perl = TRUE))
    names1 <- sub("^tar_target\\(\\s*", "", m1)

    m2 <- regmatches(lines, regexpr('tar_target_raw\\(\\s*"([^"]+)"', lines, perl = TRUE))
    names2 <- sub('^tar_target_raw\\(\\s*"', "", m2)
    names2 <- sub('"$', "", names2)

    nm <- unique(c(names1, names2))
    nm <- nm[nzchar(nm)]
    if (length(nm) > 0L) {
      out_files <- c(out_files, rep(basename(f), length(nm)))
      out_names <- c(out_names, nm)
    }
  }
  tibble::tibble(file = out_files, target_name = out_names)
}

# .cps_main() -- orchestrates the check, printing a human-readable report and
# RETURNING (not quit()-ing) an exit-status integer -- same testable-without-
# terminating-the-session pattern as .cpe_main()/.cdf_main().
.cps_main <- function(store_path = here::here("docs", "_targets"),
                       r_dir = here::here("R")) {
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

  progress <- tryCatch(.cps_read_progress(store_path), error = function(e) {
    message("!!! tar_progress() failed: ", conditionMessage(e), " !!!")
    NULL
  })
  if (is.null(progress)) {
    message("!!! VERIFICATION DID NOT RUN. This is NOT a pass. !!!")
    return(2L)
  }

  digest_row <- match("pkg_source_digest", meta$name)
  if (is.na(digest_row)) {
    message("!!! pkg_source_digest not found in tar_meta() -- the #753 tracking ")
    message("!!! mechanism has never been built in this store. Run ")
    message("!!! scripts/build.sh (which calls tar_make()) first. !!!")
    message("!!! VERIFICATION DID NOT RUN. This is NOT a pass. !!!")
    return(2L)
  }
  pkg_digest_time <- meta$time[digest_row]

  cat(sprintf("Store: %s\n", store_path))
  cat(sprintf("pkg_source_digest last recorded change: %s\n", format(pkg_digest_time, tz = "UTC")))

  registry <- .cps_discover_consuming_targets(r_dir)
  registry_names <- unique(registry$target_name)
  cat(sprintf(
    "Discovered %d package-consuming target name(s) across %d file(s) (historicaldata:: namespaced-call sites only -- see header comment)\n",
    length(registry_names), length(unique(registry$file))
  ))

  present <- registry_names %in% meta$name
  unknown <- registry_names[!present]
  if (length(unknown) > 0L) {
    cat(sprintf(
      "  [NOTE] %d discovered target name(s) have no tar_meta() build record (never built, or a name the regex misread): %s\n",
      length(unknown), paste(unknown, collapse = ", ")
    ))
  }

  known <- registry_names[present]
  stale <- character(0)
  stale_detail <- character(0)
  for (nm in known) {
    t <- meta$time[match(nm, meta$name)]
    prog_row <- match(nm, progress$name)
    prog_val <- if (is.na(prog_row)) NA_character_ else progress$progress[prog_row]
    completed_this_run <- identical(prog_val, "completed")
    if (!is.na(t) && t < pkg_digest_time && !completed_this_run) {
      stale <- c(stale, nm)
      stale_detail <- c(stale_detail, sprintf(
        "  [STALE-PKG] %s -- last built %s (progress this run: %s), predates pkg_source_digest (%s)",
        nm, format(t, tz = "UTC"), if (is.na(prog_val)) "<unknown>" else prog_val,
        format(pkg_digest_time, tz = "UTC")
      ))
    }
  }

  if (length(stale) == 0L) {
    cat(sprintf("PASS: no known package-consuming target is stale relative to pkg_source_digest (%d checked)\n", length(known)))
    return(0L)
  }

  cat(sprintf("FAIL: %d target(s) were skipped in a run where the package source changed:\n", length(stale)))
  cat(paste(stale_detail, collapse = "\n"), "\n", sep = "")
  cat(paste0(
    "!!! packages/historicaldata/R changed (pkg_source_digest is newer than the target(s)\n",
    "!!! above) but these targets were SKIPPED, not rebuilt -- they are serving values\n",
    "!!! computed by an OLDER version of the package (#753). Force an invalidation and\n",
    "!!! rebuild, e.g.:\n",
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
