#!/usr/bin/env Rscript
# scripts/check_dashboard_freshness.R — detects the render-time surface named
# in #695 as the one nothing catches (Option A: detection only; the actual
# re-render is deliberately out of scope of this script, see #695's PR).
#
# scripts/verify.sh's tar_validate() proves the pipeline STRUCTURE is sound;
# scripts/check_pipeline_errors.R (via scripts/build.sh) proves no target
# BODY errored. Neither catches: (a) a docs/*.qmd chunk calling tar_read()
# for a target name that no longer exists in the pipeline -- fails only at
# an actual quarto render, or (b) a page whose committed .html predates its
# own .qmd source, or a page's target data being older than what the
# pipeline currently holds -- both invisible because nothing re-renders
# automatically (GitHub Pages serves the committed .html directly; see
# #695's issue body for the confirmed `gh api repos/.../pages` evidence).
# This script closes (a) and (b) without needing a render.
#
# THREE CHECKS, TWO COST TIERS:
#   Check 1 (dead target references) -- for each docs/*.qmd, extract every
#     tar_read()/tar_read_raw()/safe_tar_read() target-name argument (see
#     "Why safe_tar_read()" below) and compare against
#     targets::tar_manifest(script = "docs/_targets.R")$name. A reference to
#     a target absent from the manifest is a real defect: it WILL fail at
#     render time. Needs no store, but tar_manifest() must fully evaluate
#     docs/_targets.R to build the real target list -- measured 2026-08-20 at
#     ~7.5s warm, the same order of cost as scripts/verify.sh's own
#     tar_validate() call (~7s, per that script's header). There is no
#     cheaper way to get the CURRENT target-name set; tar_validate() itself
#     returns NULL invisibly (confirmed by inspection), so its cost cannot be
#     reused. Given that cost, this check is NOT added to verify.sh --quick
#     mode (documented there as "parse + tar_validate only"); it runs in full
#     mode only, embedded in the SAME Rscript process (via source(), not a
#     second `nix develop --command` call) to avoid paying a second ~13s
#     nix-develop entry on top of the ~7.5s tar_manifest() cost.
#   Check 2 (source-vs-render staleness) -- for each docs/*.qmd, compare its
#     last git commit date against its .html sibling's. Needs no store, no
#     manifest, no target extraction -- just `git log -1 --format=%ct`, ~30
#     calls, measured well under a second. Runs in verify.sh full mode
#     alongside Check 1 (kept together as one "dashboard freshness" report
#     rather than splitting across --quick/full). REDIRECT STUBS (#695
#     follow-up) are excluded from this check's staleness verdict: a page
#     whose entire content is "this page has moved" (see
#     .cdf_is_redirect_stub() below) has its .qmd permanently postdate its
#     .html, because nobody re-renders a redirect -- reporting that as STALE
#     forever is not a real signal, it is noise that trains readers to stop
#     reading the report. Exclusion is NEVER silent: every excluded page is
#     still named in the output (per .claude/rules/fail-loud-not-null.md,
#     "report, do not hide" -- filtering a real check's output must stay
#     observable, or the filter itself becomes the next undetected defect).
#   Check 3 (data staleness) -- for each docs/*.qmd, compare its page-render
#     time (parsed from the committed .html's build_info() "Built" footer,
#     falling back to the .html's own git commit date when no footer is
#     present -- see #695 follow-up filed for the 7 dashboards missing one)
#     against the newest targets::tar_meta() build time among the SPECIFIC
#     targets that page reads (not the store's global newest time -- that
#     would mark every page stale the instant anything rebuilds, defeating
#     the point of per-page restriction). Needs target build times from
#     EITHER a REAL targets store OR the committed
#     docs/_targets_meta_snapshot.csv fallback (#695 Check 3 CI gap -- see
#     the "Metadata snapshot" section below for the full design). It is NOT
#     part of verify.sh (both sources are more expensive/stateful than
#     verify.sh's no-store contract); it runs only under --data-staleness,
#     from TWO callers: scripts/build.sh (MAIN CHECKOUT ONLY, after
#     scripts/check_pipeline_errors.R, always uses the live store -- a
#     worktree has no store and must not build one that could race the main
#     checkout's, see .claude/CLAUDE.md) and
#     .github/workflows/dashboard-freshness.yml (CI, no store ever exists on
#     a runner, always uses the committed snapshot). Redirect stubs need NO
#     explicit exclusion here (#695 follow-up): a stub purls to zero R
#     expressions, so .cdf_collect_page_targets() maps it to character(0)
#     referenced targets, and .cdf_check_data_staleness() already `next`s
#     past any page with zero references -- a page that reads nothing cannot
#     have stale data. This is structural (a consequence of stubs
#     referencing no targets), not a name- or redirect-marker-based filter
#     like Check 2's, so it needs no code change and no separate "excluded"
#     report line.
#
# EXTRACTION APPROACH -- knitr::purl(), not regex on the .qmd text. This repo
# spent a whole session (#691->#696) on the cost of fragile ad-hoc
# extraction; the brief for this script explicitly avoided repeating that.
# knitr::purl(documentation = 0, quiet = TRUE) tangles each .qmd's R chunks
# to a temp .R file, which is then parse()'d (no evaluation) into an
# expression list, walked for calls headed by a recognised read-function
# name (bare or `pkg::fn` form), taking the FIRST argument. Verified
# empirically against every docs/*.qmd (2026-08-20, warm nix shell):
#   - All 15 files purl() cleanly (no errors). 8 emit a cosmetic
#     "Duplicated chunk option(s) 'label'" warning (setup/scorecard/heatmap/
#     build-info chunks that set `label` in both the chunk header and a pipe
#     comment) -- suppressWarnings() around the purl() call, confirmed to be
#     the ONLY warning class these files produce.
#   - 4 files (drif.qmd, factor-max.qmd, jst-dashboard.qmd,
#     negative-results.qmd) purl() to ZERO expressions. Verified these are
#     genuinely redirect stub pages (0 ```{r fences in the raw source, `>
#     This page has moved.` prose + a <meta http-equiv="refresh">) -- NOT a
#     broken extractor. .cdf_extract_qmd_targets() distinguishes this
#     legitimate case from a real extraction failure via
#     .cdf_has_r_chunk_fence(): it aborts ONLY when purl() finds zero
#     expressions AND the raw .qmd has at least one ```{r fence (meaning
#     purl() silently dropped real chunks -- e.g. a non-R engine masquerading
#     as r, or a chunk-header form purl() cannot parse). This narrow,
#     single-purpose fence count is NOT how target names are extracted (that
#     stays purl()+parse()-only per the brief) -- it exists solely as a
#     sanity invariant. index.qmd purl()s to 27 expressions but references
#     ZERO targets -- confirmed legitimate (a landing page with no
#     tar_read-family calls at all), and is NOT flagged, because the
#     fence-vs-zero-expression check (not a zero-target-reference check) is
#     what distinguishes "broken" from "genuinely nothing here". This
#     per-file purl()+parse() step now lives in .cdf_purl_and_extract();
#     .cdf_extract_qmd_targets() wraps it with include resolution (see
#     "QUARTO {{< include >}} RESOLUTION" below).
#   - Every tar_read()/tar_read_raw() call's first argument across all 15
#     files is a character literal or a bare symbol (0 calls with the target
#     name in a variable/expression) -- confirmed via
#     `grep -rnE "tar_read(_raw)?\(([^\"'a-zA-Z_.]|[a-zA-Z_.]+\()"` returning
#     no matches. .cdf_extract_read_targets() aborts loudly on anything else
#     (per .claude/rules/fail-loud-not-null.md) rather than silently skipping
#     an unresolvable reference -- untested code path today, but the guard
#     stays because the 0-variable-calls state is a fact about today's
#     source, not a structural guarantee.
#
# WHY safe_tar_read() IS ALSO TREATED AS A READ (scope addition beyond the
# original task brief, discovered during development): docs/vignette_utils.R
# defines `safe_tar_read(name, strict = ...)`, a wrapper around
# targets::tar_read_raw(name) that falls back to a bundled RDS fixture (or
# NULL) on error -- used by 8 of the 15 dashboard pages. The brief specified
# extracting only tar_read()/tar_read_raw(); treating those alone as "the"
# read functions would make Check 1 and Check 3 silently blind on every page
# that uses the wrapper. Verified 2026-08-20: for stock-backtest.qmd and
# falsification.qmd (the two files with the heaviest safe_tar_read() use),
# the SET of distinct target names referenced only via safe_tar_read() is
# non-empty for falsification.qmd specifically ("cg_dag", "cg_caption" --
# see the inline-expression limitation below), so the wrapper cannot be
# ignored without a real coverage gap.
#
# QUARTO {{< include >}} RESOLUTION (closed 2026-08-20, #695 follow-up) --
# knitr::purl() tangles only the fenced chunks physically present in the
# file it is HANDED. It does not resolve Quarto's `{{< include path.qmd >}}`
# shortcode (that expansion happens inside quarto render's own pandoc
# preprocessing, never inside knitr), so a tar_read() living in an included
# file was previously invisible to Check 1 and Check 3 -- SILENTLY: no
# error, no log line, nothing. Verified empirically 2026-08-20 with a
# synthetic parent.qmd containing only `{{< include child.qmd >}}` (child.qmd
# has one fenced `tar_read()` chunk): knitr::purl(parent.qmd) tangles to an
# EMPTY file (zero expressions), and .cdf_has_r_chunk_fence(parent.qmd) is
# FALSE (the fence lives in child.qmd, not parent.qmd) -- so the old
# zero-expressions-but-no-fence branch treated it exactly like index.qmd's
# legitimate "no code here" case and never flagged the hidden tar_read().
# .cdf_extract_qmd_targets() now resolves every `{{< include >}}` directive
# in a page (.cdf_extract_include_paths(), a raw-text regex -- Quarto
# shortcodes are not knitr chunks, so there is no purl()-based way to find
# them; this is NOT the tar_read-extraction regex ruled out above, it only
# locates WHICH FILES to also purl()) and recurses the SAME
# purl()+parse()-based .cdf_purl_and_extract() into each one, transitively,
# unioning target references into the including page's set. A `visited`
# accumulator prevents a circular include graph from recursing forever.
# Per .claude/rules/fail-loud-not-null.md, an include directive whose target
# file does not exist is a hard cli_abort() (.cdf_resolve_include_path()),
# never a silent skip -- a dead include fails at Quarto render time too, so
# treating it as "nothing to see here" would just move the surprise later.
# Confirmed against the real repo 2026-08-20: docs/_includes/ contains
# exactly one file (build-info-footer.qmd), it has zero tar_read calls, and
# exactly one page (docs/macro-defense-rotation.qmd:710) includes it -- so
# this gap is provably empty today; the fix exists so the NEXT include that
# adds a tar_read() does not repeat the silent-miss pattern.
#
# KNOWN LIMITATION -- inline R expressions (single-backtick `` `r { ... } ``
# `` syntax, as opposed to fenced ```{r} chunks) are NOT tangled by
# knitr::purl() (confirmed: purl() only extracts fenced chunks, by design --
# there is no supported knitr API to extract inline expressions without
# evaluating them). Measured 2026-08-20: docs/falsification.qmd has 8 inline
# tar_read-family calls invisible to this script, 2 of which reference
# target names ("cg_dag" at line 806, "cg_caption" at line 986) that are
# NEVER referenced in any fenced chunk in that file -- these two names are
# therefore completely outside this script's coverage: Check 1 cannot catch
# a dead reference to either, and Check 3 will not include either target
# when computing falsification.qmd's own-targets staleness bound.
# docs/stock-backtest.qmd has 19 inline calls, but (verified by diffing the
# full-source unique target-name set against the purl()-extracted set) every
# name referenced inline there is ALSO referenced at least once in a fenced
# chunk in the same file -- so stock-backtest.qmd has no actual coverage gap
# despite the high inline call count. This script deliberately does NOT
# regex the .qmd text to close this gap (the brief was explicit: no regex
# extraction of tar_read, and inline-expression parsing has no clean
# non-regex alternative within knitr's public API) -- it is documented here,
# at the one call site the gap affects, instead.
#
# ESCALATION POLICY (#695 rescope, decided 2026-08-22) -- Check 2 and Check 3
# are DIFFERENT DEFECT CLASSES and get different grace periods, but a SINGLE
# switch (HD_FAIL_ON_STALE_DASHBOARDS) turns escalation on for both, each
# applying its own threshold:
#   - Check 2 (source staleness -- a page's .qmd committed newer than its own
#     .html) gets ZERO grace: a human edited a page and it never reached
#     readers, which is unambiguously wrong the moment it happens, not after
#     N days. Any amount of source staleness escalates once the switch is on.
#   - Check 3 (data staleness -- the pipeline rebuilt after a page rendered)
#     gets a configurable grace period, HD_STALE_DASHBOARD_DATA_THRESHOLD_DAYS
#     (default 14 days, see .cdf_data_staleness_threshold_hours() below).
#     Data staleness is the NORMAL consequence of any rebuild, not a mistake:
#     measured 2026-08-22, two pages (falsification.qmd, european-overlay.qmd)
#     became data-stale within 45.9 hours of a routine tar_make() run that
#     touched none of their own source. A zero-grace threshold here would be
#     permanently red days after every build, and a permanently red check is
#     one nobody reads (exactly the failure mode the redirect-stub exclusion
#     above was already added to prevent, applied to a second cause).
#
# ONE SWITCH, NOT TWO, is the deliberate choice here (over separate
# HD_FAIL_ON_STALE_SOURCE / HD_FAIL_ON_STALE_DATA switches): the two checks
# already answer two different questions with two different, independently
# tunable thresholds (Check 2's is fixed at zero; Check 3's is
# HD_STALE_DASHBOARD_DATA_THRESHOLD_DAYS) -- adding a second on/off switch on
# top would let someone configure "escalate data staleness but not source
# staleness," which is backwards: source staleness is the more clear-cut
# defect of the two and should never be the one left unescalated. Fewer knobs
# also means fewer states to reason about when reading a CI failure. The
# counter-argument -- a project might genuinely want Check 3 enforcement
# (e.g. in the new weekly workflow) without Check 2 enforcement, or vice
# versa, and a single switch cannot express that -- is real, but no caller of
# this script has needed that split yet; add a second switch if one does.
#
# EXIT CODES:
#   0  ran clean: no dead target references (Check 1 -- ALWAYS a hard
#      failure when found, see below), and no staleness escalated to a
#      failure (see the ESCALATION POLICY section above).
#   1  a real problem was found and treated as a failure:
#        - Check 1 always fails the run when it finds a dead reference --
#          confirmed today: zero instances, so this does not turn a green
#          run red. This is a genuine defect class (#695's issue body shows
#          the live leaderboard is missing two merged features precisely
#          because nothing else in the repo detects it), not a style
#          preference, so it is not gated behind an opt-in flag.
#        - Check 2 (source staleness) and Check 3 (data staleness) are both
#          REPORTED but do NOT fail the run by default -- ~8 of 15 dashboards
#          were stale under one measure or the other when this script
#          shipped (#695's own evidence), so defaulting staleness to a hard
#          failure would turn verify.sh/build.sh red on main until the
#          re-render half of #695 landed (it has -- see #702). Set
#          HD_FAIL_ON_STALE_DASHBOARDS=1 (any of "1"/"true"/"yes",
#          case-insensitive -- see .cdf_env_flag_true(), which exists
#          specifically because `isTRUE(as.logical(Sys.getenv(...)))` is a
#          known footgun: as.logical("1") is NA, not TRUE, per
#          .claude/rules/fail-loud-not-null.md) to escalate: Check 2 always
#          (zero grace) and Check 3 once a page's gap exceeds
#          HD_STALE_DASHBOARD_DATA_THRESHOLD_DAYS (default 14). This is the
#          explicit, documented escalation path -- not an unwritten
#          intention.
#   2  could not run the check(s) at all: knitr::purl()/parse() failed or
#      found a broken extraction, targets::tar_manifest()/tar_meta() failed,
#      or (--data-staleness only) neither a live store nor the committed
#      docs/_targets_meta_snapshot.csv fallback was available, OR the
#      snapshot exists but is older than HD_STALE_DASHBOARD_DATA_THRESHOLD_DAYS
#      itself (see "Metadata snapshot" section below -- a snapshot that old
#      cannot support a Check 3 verdict at all, so it is treated the same as
#      "no data source found", never as a pass). NOT a pass.
#
# Usage:
#   nix develop --command Rscript scripts/check_dashboard_freshness.R
#     Runs Check 1 + Check 2 (no store needed). This is also what
#     scripts/verify.sh's full mode calls, but embedded via source() into
#     its existing Rscript process rather than spawned as a second process
#     (see the cost note above) -- run this file directly only for a
#     standalone/manual check.
#   nix develop --command Rscript scripts/check_dashboard_freshness.R --data-staleness
#     Additionally runs Check 3. Two callers, two data sources, both
#     documented on the same command:
#       - scripts/build.sh (MAIN CHECKOUT ONLY, after
#         scripts/check_pipeline_errors.R): a real docs/_targets store always
#         exists at that point, so Check 3 always uses live tar_meta() data
#         here -- unchanged from before the #695 Check 3 CI gap fix.
#       - .github/workflows/dashboard-freshness.yml (CI, weekly + manual
#         dispatch, HD_FAIL_ON_STALE_DASHBOARDS=1): a GitHub Actions runner
#         never has a store, so Check 3 here always falls back to the
#         committed docs/_targets_meta_snapshot.csv (written by
#         scripts/write_targets_meta_snapshot.R, called from scripts/build.sh
#         after a clean build, and committed by a human -- see that script
#         and the "Metadata snapshot" section below). If the snapshot is
#         missing or older than HD_STALE_DASHBOARD_DATA_THRESHOLD_DAYS, this
#         is a hard failure (exit 2) naming `scripts/build.sh` as the fix --
#         see "THE SNAPSHOT'S OWN AGE IS A FIRST-CLASS, CHECKABLE SIGNAL"
#         below for why this is not merely a warning.
#
# This file is also source()'d directly by
# tests/testthat/test-dashboard-freshness.R to unit-test the extractor
# functions against synthetic fixtures -- sourcing it does NOT run the
# checks (see the `sys.nframe() == 0` guard at the bottom: 0 only when this
# file is the Rscript entry point, non-zero when source()'d, confirmed
# empirically 2026-08-20).

suppressPackageStartupMessages({
  library(here)
})

# ---------------------------------------------------------------------------
# Extraction
# ---------------------------------------------------------------------------

# Read-function names this checker recognises -- see "Why safe_tar_read()"
# in the header comment above.
.CDF_READ_FN_NAMES <- c("tar_read", "tar_read_raw", "safe_tar_read")

# Returns the function name for a bare call (`tar_read(...)`) or a
# `pkg::fn(...)` call (`targets::tar_read(...)`); NULL for anything else
# (e.g. a call stored behind an indirection this checker cannot resolve).
.cdf_call_head_name <- function(e) {
  if (!is.call(e)) {
    return(NULL)
  }
  head <- e[[1]]
  if (is.symbol(head)) {
    return(as.character(head))
  }
  if (is.call(head) && length(head) == 3 && identical(head[[1]], as.symbol("::"))) {
    return(as.character(head[[3]]))
  }
  NULL
}

# Walks a parsed (unevaluated) expression list looking for calls to
# .CDF_READ_FN_NAMES, returning the unique set of target names referenced.
# Aborts -- does not skip or return NA -- the moment a matched call's first
# argument is neither a string literal nor a bare symbol, per
# .claude/rules/fail-loud-not-null.md: an unresolvable reference must stop
# the check, never be silently treated as "no reference here".
.cdf_extract_read_targets <- function(exprs, qmd_basename) {
  names_out <- character(0)
  is_call_safe <- function(x) tryCatch(is.call(x), error = function(err) FALSE)
  walk <- function(e) {
    if (!is_call_safe(e)) {
      return(invisible())
    }
    fn_name <- .cdf_call_head_name(e)
    if (!is.null(fn_name) && fn_name %in% .CDF_READ_FN_NAMES) {
      args <- as.list(e)[-1]
      if (length(args) == 0) {
        cli::cli_abort(c(
          "x" = "{.fn {fn_name}} call with no arguments in {.file {qmd_basename}}.",
          "i" = "Expected a target name as the first argument."
        ))
      }
      arg1 <- args[[1]]
      target_name <- if (is.character(arg1) && length(arg1) == 1) {
        arg1
      } else if (is.symbol(arg1)) {
        as.character(arg1)
      } else {
        cli::cli_abort(c(
          "x" = "{.fn {fn_name}} called with a non-literal, non-symbol first argument in {.file {qmd_basename}}.",
          "i" = "Argument was: {.code {deparse(arg1)}}",
          "i" = "This checker can only statically resolve a string literal or a bare symbol target name."
        ))
      }
      names_out <<- c(names_out, target_name)
    }
    for (part in as.list(e)) {
      if (is_call_safe(part)) walk(part)
    }
  }
  for (e in exprs) walk(e)
  unique(names_out)
}

# TRUE if the raw .qmd text contains at least one fenced R chunk
# (```` ```{r ```` at the start of a line). NOT used for target-name
# extraction -- see the header comment's "EXTRACTION APPROACH" section for
# why this is a narrow structural sanity check, not a second extraction
# path.
.cdf_has_r_chunk_fence <- function(qmd_path) {
  lines <- readLines(qmd_path, warn = FALSE)
  any(grepl("^```\\{r", lines))
}

# Matches the `<meta http-equiv="refresh" ...>` tag every redirect stub in
# this repo carries (verified 2026-08-20 against drif.qmd, factor-max.qmd,
# jst-dashboard.qmd, negative-results.qmd -- all four, identically).
.CDF_REDIRECT_META_RE <- '<meta\\s+http-equiv="refresh"'

# TRUE if `qmd_path` is a "redirect stub" page (#695 follow-up): its whole
# purpose is to send a reader elsewhere, so its .qmd will ALWAYS postdate its
# .html (nobody re-renders a page whose entire content is "this page has
# moved") -- Check 2 (source-vs-render staleness) treats this as a real,
# permanent, uninteresting signal and excludes it rather than reporting it as
# STALE forever.
#
# Requires BOTH conditions, deliberately -- NOT ".cdf_has_r_chunk_fence() ==
# FALSE" alone:
#   1. No fenced R chunk (a real dashboard always has at least one).
#   2. The actual redirect mechanism these pages use: a
#      `<meta http-equiv="refresh" ...>` tag.
# "No R chunks" alone is necessary but not sufficient. A hypothetical future
# page with genuinely no R chunks and no redirect (e.g. a pure-prose landing
# section) would be silently dropped from Check 2's staleness reporting by
# the weaker test -- which is exactly the failure mode
# .claude/rules/fail-loud-not-null.md exists to prevent: an exclusion rule
# that is too loose turns a real staleness signal into a hidden one. Testing
# for the meta-refresh tag -- the mechanism itself, not a name-based
# allowlist on the four known stubs -- also means a FUTURE fifth stub of the
# same shape is detected automatically, without editing this script.
.cdf_is_redirect_stub <- function(qmd_path) {
  if (.cdf_has_r_chunk_fence(qmd_path)) {
    return(FALSE)
  }
  text <- paste(readLines(qmd_path, warn = FALSE), collapse = "\n")
  grepl(.CDF_REDIRECT_META_RE, text, perl = TRUE)
}

# ---------------------------------------------------------------------------
# Quarto {{< include >}} resolution (#695 follow-up -- knitr::purl() tangles
# only the fenced chunks physically present in the file it is handed; it
# does NOT resolve Quarto's `{{< include path.qmd >}}` shortcode, so a
# tar_read() living inside an included file was previously invisible to both
# Check 1 (dead references) and Check 3 (data staleness) -- silently, with
# no error and no log line. Verified empirically 2026-08-20:
# knitr::purl() on a synthetic parent.qmd containing only
# `{{< include child.qmd >}}` (child.qmd has one fenced tar_read() chunk)
# purls to a completely empty file -- zero expressions, and
# .cdf_has_r_chunk_fence(parent.qmd) is FALSE (the fence lives in child.qmd,
# not parent.qmd), so the old code took the SAME "legitimate empty page"
# path as index.qmd and never flagged anything. This section closes that gap
# by resolving each include directive to its target file and recursing the
# SAME purl()+parse() extraction into it, per fail-loud-not-null.md: a
# missing include target aborts, it is never silently skipped.
# ---------------------------------------------------------------------------

# Matches a Quarto include shortcode `{{< include PATH >}}`, where PATH is
# either a bare unquoted token (no spaces/`>`) or a double-quoted string
# (may contain spaces). Both forms are part of Quarto's shortcode grammar;
# the one real usage in this repo today
# (docs/macro-defense-rotation.qmd:710) is the unquoted form. This is
# regex-on-raw-text, same category as .cdf_has_r_chunk_fence() above --
# Quarto shortcodes are not knitr chunks and purl() never sees them, so
# there is no purl()-based way to locate them. This is NOT the
# tar_read-extraction regex the header comment's "EXTRACTION APPROACH"
# section rules out -- that restriction is about resolving WHICH targets a
# chunk reads (still purl()+parse()-only, unchanged below); this regex only
# locates WHICH FILES to also purl().
.CDF_INCLUDE_RE <- '\\{\\{<\\s*include\\s+(?:"([^"]+)"|([^\\s>]+))\\s*>\\}\\}'

# Returns the raw (unresolved) include path string(s) found in `qmd_path`'s
# text, in the order they appear, NOT deduplicated and NOT yet resolved to
# absolute paths (path resolution happens in .cdf_resolve_include_path()).
# character(0) if the file contains no include shortcode.
.cdf_extract_include_paths <- function(qmd_path) {
  text <- paste(readLines(qmd_path, warn = FALSE), collapse = "\n")
  whole_matches <- regmatches(text, gregexpr(.CDF_INCLUDE_RE, text, perl = TRUE))[[1]]
  if (length(whole_matches) == 0) {
    return(character(0))
  }
  groups <- regmatches(whole_matches, regexec(.CDF_INCLUDE_RE, whole_matches, perl = TRUE))
  vapply(groups, function(g) if (nzchar(g[2])) g[2] else g[3], character(1))
}

# Resolves `raw_path` (as it appeared in an include shortcode inside
# `including_path`) to an absolute path, the way Quarto itself resolves
# includes: relative to the directory of the file that CONTAINS the
# directive (not relative to the top-level page being rendered, and not
# relative to the repo root). Aborts if the resolved file does not exist --
# per .claude/rules/fail-loud-not-null.md, a dead include target must stop
# the check; it must never be silently treated as "nothing to extract here".
.cdf_resolve_include_path <- function(raw_path, including_path) {
  resolved <- file.path(dirname(including_path), raw_path)
  resolved <- normalizePath(resolved, mustWork = FALSE)
  if (!file.exists(resolved)) {
    # NOTE: the message deliberately shows only `raw_path` (as written in the
    # include directive) and basename(including_path) -- NEVER the resolved
    # absolute path, which lives under a volatile tempdir in tests and would
    # break snapshot portability across machines/CI runs (portable-build-artifacts).
    cli::cli_abort(c(
      "x" = "{.file {basename(including_path)}} includes {.file {raw_path}}, but that file does not exist.",
      "i" = "Looked for it relative to {.file {basename(including_path)}}'s own directory (Quarto's include-resolution rule).",
      "i" = "A dead include target fails at Quarto render time; fix the path or restore the file."
    ))
  }
  resolved
}

# Purls a single file's R chunks to a temp file, parses it (no evaluation),
# and returns the unique set of target names referenced via
# .CDF_READ_FN_NAMES in THIS FILE ONLY (no include recursion -- that is
# layered on by .cdf_extract_qmd_targets() below). Aborts if purl()/parse()
# itself fails, or if purl() extracts zero expressions from a file that
# plainly has R chunks (see header comment).
.cdf_purl_and_extract <- function(qmd_path) {
  qmd_basename <- basename(qmd_path)
  tmp_dir <- tempfile("dashboard_freshness_")
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE), add = TRUE)
  tmp_r <- file.path(tmp_dir, "purled.R")

  # suppressWarnings(): verified 2026-08-20 the only warnings knitr::purl()
  # emits across every docs/*.qmd are cosmetic "Duplicated chunk option(s)
  # 'label'" notices (chunks that set `label` in both the header and a pipe
  # comment) -- see header comment.
  tryCatch(
    suppressWarnings(knitr::purl(qmd_path, output = tmp_r, documentation = 0, quiet = TRUE)),
    error = function(e) {
      cli::cli_abort(c(
        "x" = "knitr::purl() failed on {.file {qmd_basename}}.",
        "i" = conditionMessage(e)
      ))
    }
  )

  exprs <- tryCatch(
    parse(tmp_r, keep.source = FALSE),
    error = function(e) {
      cli::cli_abort(c(
        "x" = "Failed to parse() knitr::purl() output for {.file {qmd_basename}}.",
        "i" = conditionMessage(e)
      ))
    }
  )

  if (length(exprs) == 0 && .cdf_has_r_chunk_fence(qmd_path)) {
    cli::cli_abort(c(
      "x" = "knitr::purl() extracted zero R expressions from {.file {qmd_basename}}, but the file contains R chunk fence(s).",
      "i" = "This is more likely a broken extractor (e.g. a non-r engine, an unusual chunk header) than a page with no code.",
      "i" = "Investigate before trusting this check; do not add an exception without confirming the file genuinely has no executable R."
    ))
  }

  .cdf_extract_read_targets(exprs, qmd_basename)
}

# Purls `qmd_path`'s own R chunks AND recurses into every file it reaches
# via `{{< include >}}` (directly or transitively), returning the union of
# target names referenced anywhere in that include tree. `visited` (a
# character vector of already-processed absolute paths, internal use only)
# guards against a circular include graph re-processing a file forever --
# not expected in this repo today, but cheap to guard against structurally
# rather than assume away.
.cdf_extract_qmd_targets <- function(qmd_path, visited = character(0)) {
  qmd_path <- normalizePath(qmd_path, mustWork = FALSE)
  if (qmd_path %in% visited) {
    return(character(0))
  }
  visited <- c(visited, qmd_path)

  own_targets <- .cdf_purl_and_extract(qmd_path)

  include_paths <- .cdf_extract_include_paths(qmd_path)
  included_targets <- unlist(
    lapply(include_paths, function(raw_path) {
      resolved <- .cdf_resolve_include_path(raw_path, qmd_path)
      .cdf_extract_qmd_targets(resolved, visited)
    }),
    use.names = FALSE
  )

  unique(c(own_targets, included_targets))
}

# Sorted docs/*.qmd paths under `docs_dir`.
.cdf_qmd_files <- function(docs_dir) {
  sort(list.files(docs_dir, pattern = "\\.qmd$", full.names = TRUE))
}

# Named list: basename(qmd) -> unique character vector of referenced target
# names (possibly empty, e.g. index.qmd or a redirect stub).
.cdf_collect_page_targets <- function(qmd_files) {
  stats::setNames(
    lapply(qmd_files, .cdf_extract_qmd_targets),
    basename(qmd_files)
  )
}

# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

# Parses an env var as a boolean flag against a fixed, explicit vocabulary --
# NEVER `isTRUE(as.logical(Sys.getenv(...)))`: as.logical("1") is NA, not
# TRUE, which would silently default the flag OFF. See
# .claude/rules/fail-loud-not-null.md and
# .claude/memory/feedback_as-logical-numeric-strings.md.
.cdf_env_flag_true <- function(var_name) {
  val <- Sys.getenv(var_name, unset = "")
  tolower(val) %in% c("1", "true", "yes")
}

# Default grace period (days) for Check 3 (data staleness) before it
# escalates to a hard failure under HD_FAIL_ON_STALE_DASHBOARDS=1 -- see the
# "ESCALATION POLICY" section in this file's header comment for the full
# rationale (a rebuild is the normal consequence of the pipeline moving on;
# Check 2/source staleness gets NO such grace period).
.CDF_DEFAULT_DATA_STALENESS_THRESHOLD_DAYS <- 14

# Reads HD_STALE_DASHBOARD_DATA_THRESHOLD_DAYS, defaulting to
# .CDF_DEFAULT_DATA_STALENESS_THRESHOLD_DAYS days, and returns it in HOURS
# (the unit .cdf_check_data_staleness() already reports gaps in, via
# gap_hrs). Aborts loudly -- never silently falls back to the default -- on a
# set-but-unparseable or negative value, per
# .claude/rules/fail-loud-not-null.md: a misconfigured threshold must stop
# the run, not silently mask the misconfiguration with a value nobody chose.
.cdf_data_staleness_threshold_hours <- function() {
  var_name <- "HD_STALE_DASHBOARD_DATA_THRESHOLD_DAYS"
  raw <- Sys.getenv(var_name, unset = "")
  if (!nzchar(raw)) {
    return(.CDF_DEFAULT_DATA_STALENESS_THRESHOLD_DAYS * 24)
  }
  days <- suppressWarnings(as.numeric(raw))
  if (is.na(days) || days < 0) {
    default_days <- .CDF_DEFAULT_DATA_STALENESS_THRESHOLD_DAYS
    cli::cli_abort(c(
      "x" = "{.envvar {var_name}} is set to {.val {raw}}, which is not a non-negative number of days.",
      "i" = "Unset it to use the default ({.val {default_days}} days), or set it to a non-negative number."
    ))
  }
  days * 24
}

# Returns the subset of `data_stale`'s page names whose gap_hrs exceeds
# `threshold_hrs`. Pure logic, no I/O -- factored out from the driver so it
# can be unit-tested directly against a synthetic `data_stale` list (#695
# rescope: "data staleness under the threshold does not fail; data staleness
# over the threshold does"), rather than only indirectly through a full
# .cdf_main() run (which needs a real manifest/store and is not unit-tested
# elsewhere in this file either). `data_stale` is shaped like
# .cdf_check_data_staleness()'s return value: page basename -> list(gap_hrs=, source=).
.cdf_data_staleness_over_threshold <- function(data_stale, threshold_hrs) {
  names(data_stale)[vapply(data_stale, function(d) d$gap_hrs > threshold_hrs, logical(1))]
}

# Last commit time (POSIXct, seconds resolution) of `abs_path` under
# `repo_root`, via `git log -1 --format=%ct` (committer date, unix epoch --
# avoids ISO-8601 timezone-offset parsing entirely). Returns NA (POSIXct) if
# the path has no commit history (untracked, or newly added and unstaged).
.cdf_git_last_commit_time <- function(abs_path, repo_root) {
  rel_path <- sub(paste0("^", repo_root, "/"), "", abs_path, fixed = TRUE)
  out <- suppressWarnings(system2(
    "git", c("-C", repo_root, "log", "-1", "--format=%ct", "--", rel_path),
    stdout = TRUE, stderr = FALSE
  ))
  status <- attr(out, "status")
  if (!is.null(status) && status != 0) {
    return(as.POSIXct(NA))
  }
  if (length(out) == 0 || !nzchar(out[1])) {
    return(as.POSIXct(NA))
  }
  as.POSIXct(as.numeric(out[1]), origin = "1970-01-01", tz = Sys.timezone())
}

# Parses the "Built" timestamp out of a committed .html's build_info()
# footer (docs/vignette_utils.R:205, format "Built</strong> YYYY-MM-DD
# HH:MM:SS", confirmed against docs/leaderboard.html 2026-08-20). Falls back
# to the .html's own git commit time when no footer is found -- this is a
# DOCUMENTED, CLEARLY-LABELLED fallback (the `source` field in the returned
# list), not a silent substitution: 7 of 15 dashboards currently have no
# build_info() footer at all (see the follow-up issue filed alongside this
# script) and would otherwise report no render time whatsoever.
.cdf_page_render_time <- function(html_path, repo_root) {
  if (file.exists(html_path)) {
    html_text <- tryCatch(
      paste(readLines(html_path, warn = FALSE), collapse = "\n"),
      error = function(e) NA_character_
    )
    if (!is.na(html_text)) {
      m <- regmatches(
        html_text,
        regexpr("Built</strong>\\s*[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}", html_text)
      )
      if (length(m) == 1 && nzchar(m)) {
        ts_str <- sub("^Built</strong>\\s*", "", m)
        ts <- as.POSIXct(ts_str, format = "%Y-%m-%d %H:%M:%S", tz = Sys.timezone())
        if (!is.na(ts)) {
          return(list(time = ts, source = "build_info() footer"))
        }
      }
    }
  }
  git_time <- .cdf_git_last_commit_time(html_path, repo_root)
  if (!is.na(git_time)) {
    return(list(time = git_time, source = "git commit date (fallback -- no build_info() footer found)"))
  }
  list(time = as.POSIXct(NA), source = "unavailable (no footer, no git history)")
}

# ---------------------------------------------------------------------------
# Check 1 -- dead target references
# ---------------------------------------------------------------------------

# Returns a named list: page basename -> character vector of target names it
# references that are absent from `manifest_names`. Empty list means clean.
.cdf_check_dead_references <- function(page_targets, manifest_names) {
  problems <- list()
  for (page in names(page_targets)) {
    missing <- setdiff(page_targets[[page]], manifest_names)
    if (length(missing) > 0) {
      problems[[page]] <- missing
    }
  }
  problems
}

# ---------------------------------------------------------------------------
# Check 2 -- source-vs-render staleness
# ---------------------------------------------------------------------------

# Returns a named list: page basename -> gap in days (.qmd commit time minus
# .html commit time) for every page whose .qmd is newer than its .html.
# Pages with no git history for the .qmd, or no .html counterpart at all,
# are reported separately by the caller (not silently dropped). Pages that
# `is_stub_fn` identifies as redirect stubs (#695 follow-up) are excluded
# from `stale`/`no_html`/`untracked` entirely and returned instead in
# `excluded_stub` -- see .cdf_is_redirect_stub() for why. `excluded_stub` is
# always returned, never silently dropped, so the caller can name every
# excluded page: filtering a check's output must stay observable
# (.claude/rules/fail-loud-not-null.md, "report, do not hide").
.cdf_check_source_staleness <- function(qmd_files, repo_root, is_stub_fn = .cdf_is_redirect_stub) {
  stale <- list()
  no_html <- character(0)
  untracked <- character(0)
  excluded_stub <- character(0)
  for (f in qmd_files) {
    base <- basename(f)
    if (is_stub_fn(f)) {
      excluded_stub <- c(excluded_stub, base)
      next
    }
    html_path <- sub("\\.qmd$", ".html", f)
    qmd_time <- .cdf_git_last_commit_time(f, repo_root)
    if (is.na(qmd_time)) {
      untracked <- c(untracked, base)
      next
    }
    if (!file.exists(html_path)) {
      no_html <- c(no_html, base)
      next
    }
    html_time <- .cdf_git_last_commit_time(html_path, repo_root)
    if (is.na(html_time)) {
      no_html <- c(no_html, base)
      next
    }
    if (qmd_time > html_time) {
      stale[[base]] <- as.numeric(difftime(qmd_time, html_time, units = "days"))
    }
  }
  list(stale = stale, no_html = no_html, untracked = untracked, excluded_stub = excluded_stub)
}

# ---------------------------------------------------------------------------
# Metadata snapshot -- committed docs/_targets_meta_snapshot.csv (#695 Check 3
# CI gap). A GitHub Actions runner never has a real targets store (see the
# "MAIN CHECKOUT ONLY" note on Check 3 below), so Check 3 could not run in CI
# at all until now. The fix: scripts/write_targets_meta_snapshot.R (invoked
# by scripts/build.sh, main checkout only, after a clean tar_make() +
# check_pipeline_errors.R) writes a small, deterministic, COMMITTED snapshot
# of every target's name + tar_meta() build time. .cdf_main()'s Check 3
# section below reads this file as a fallback when no live store exists --
# see "WHICH SOURCE DID CHECK 3 USE" further down.
#
# FORMAT -- one flat CSV, `name,time`, written by .cdf_write_meta_snapshot()
# and read back by .cdf_read_meta_snapshot():
#   - Real target rows are sorted by name (method = "radix", so the row
#     order never depends on the writing machine's locale -- a meaningful,
#     non-churny git diff on every re-generation, per the Part 1 requirement
#     that the diff be deterministic).
#   - `time` is ISO-8601 UTC (.cdf_format_snapshot_time() /
#     .cdf_parse_snapshot_time()), so a round-trip through the file never
#     depends on the writer's or reader's local timezone
#     (.claude/rules/portable-build-artifacts.md).
#   - ONE extra row, name = .CDF_META_SNAPSHOT_SENTINEL_NAME
#     ("__generated_at__"), records when the snapshot itself was written.
#     See .cdf_write_meta_snapshot()'s own comment for why this is a sentinel
#     ROW in the same table rather than a `#`-prefixed header comment line or
#     a second file.
#
# THE SNAPSHOT'S OWN AGE IS A FIRST-CLASS, CHECKABLE SIGNAL (Part 2 of the
# #695 Check 3 CI gap follow-up) -- this is the part of the design that
# matters most. If nobody re-runs scripts/build.sh, this file freezes; a
# Check 3 that silently compared render times against an arbitrarily old
# snapshot would report "fresh" forever, which is exactly the defect class
# this repo has spent the week on (#680, #691, #695: a check that reports
# success because its own reference data stopped moving). So
# .cdf_main() treats a snapshot whose age (.cdf_meta_snapshot_age_hours())
# exceeds .cdf_data_staleness_threshold_hours() -- the SAME
# HD_STALE_DASHBOARD_DATA_THRESHOLD_DAYS threshold Check 3 itself uses to
# decide whether data staleness is tolerable, deliberately reused rather than
# adding a second, independently-tunable knob (mirrors the "ONE SWITCH, NOT
# TWO" reasoning in the ESCALATION POLICY section above) -- as UNTRUSTWORTHY:
# a snapshot that old cannot support a freshness verdict within the very
# grace period it is being asked to police. This is a HARD FAILURE (exit
# code 2, "could not run the check(s) at all"), not a warning and NOT gated
# behind HD_FAIL_ON_STALE_DASHBOARDS -- the same treatment already given to
# "no store found at all" (see the pre-existing `!dir.exists(store_path)`
# branch this replaces): an untrustworthy data source means Check 3 cannot
# run, full stop, exactly like a missing store always has. Making it merely
# a WARNING would recreate the precise failure mode being fixed here: a
# green Check 3 that is actually reporting on month-old data. The message
# always names the fix (`scripts/build.sh`), because the failure is never
# "something is broken", only "nobody ran the one command that updates this".
# ---------------------------------------------------------------------------

.CDF_META_SNAPSHOT_RELPATH <- file.path("docs", "_targets_meta_snapshot.csv")

.CDF_META_SNAPSHOT_SENTINEL_NAME <- "__generated_at__"

# Absolute path to the committed snapshot under `repo_root`.
.cdf_meta_snapshot_path <- function(repo_root) {
  file.path(repo_root, .CDF_META_SNAPSHOT_RELPATH)
}

# ISO-8601 UTC formatting/parsing shared by write + read -- see "FORMAT"
# above for why UTC specifically.
.cdf_format_snapshot_time <- function(t) {
  format(t, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
}
.cdf_parse_snapshot_time <- function(s) {
  as.POSIXct(s, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
}

# Writes `meta_time` (a named POSIXct vector, name -> build time, typically
# straight from targets::tar_meta(fields = time, targets_only = TRUE)) to
# `snapshot_path` as a small, deterministic CSV -- see the "Metadata
# snapshot" section header above for the full file-format rationale.
# `generated_at` defaults to Sys.time(); the real caller,
# scripts/write_targets_meta_snapshot.R, always passes the actual write time
# explicitly so a test can pin it.
#
# WHY A SENTINEL ROW, NOT A SEPARATE FILE OR A `#`-PREFIXED HEADER COMMENT:
# keeps the ENTIRE file one flat table read by ONE read.csv() call (no second
# parser path grepping a comment line out of the file), while still letting
# .cdf_read_meta_snapshot() recover the generation timestamp from the same
# read. "__generated_at__" cannot collide with a real target name in
# practice (targets requires syntactically valid R symbol names;
# double-leading/trailing-underscore names are not used anywhere in this
# repo's pipeline) -- this function still aborts loudly rather than silently
# overwriting/hiding a same-named real target, per
# .claude/rules/fail-loud-not-null.md.
.cdf_write_meta_snapshot <- function(meta_time, snapshot_path, generated_at = Sys.time()) {
  target_names <- names(meta_time)
  # sentinel_name (NOT the leading-dot constant directly) is interpolated
  # below -- cli's glue parser treats a `{...}` expression starting with a
  # dot as an attempted (invalid) nested style span, not a variable
  # reference, so `{.val {.CDF_META_SNAPSHOT_SENTINEL_NAME}}` errors with
  # "Invalid cli literal ... starts with a dot" instead of the intended
  # abort message (caught by this file's own test suite -- see
  # .cdf_write_meta_snapshot's sentinel-collision test).
  sentinel_name <- .CDF_META_SNAPSHOT_SENTINEL_NAME
  if (sentinel_name %in% target_names) {
    cli::cli_abort(c(
      "x" = "A real target is named {.val {sentinel_name}}, which collides with the metadata snapshot's reserved sentinel row name.",
      "i" = "Rename the target, or change .CDF_META_SNAPSHOT_SENTINEL_NAME in scripts/check_dashboard_freshness.R."
    ))
  }
  ordered_names <- sort(target_names, method = "radix")
  rows <- data.frame(
    name = c(.CDF_META_SNAPSHOT_SENTINEL_NAME, ordered_names),
    time = c(
      .cdf_format_snapshot_time(generated_at),
      .cdf_format_snapshot_time(meta_time[ordered_names])
    ),
    stringsAsFactors = FALSE
  )
  dir.create(dirname(snapshot_path), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(rows, snapshot_path, row.names = FALSE)
  invisible(snapshot_path)
}

# Reads `snapshot_path` back into list(meta_time = <named POSIXct vector,
# sentinel row excluded>, generated_at = <POSIXct>). Aborts loudly -- never
# returns a partial/NA result -- on a missing file, a missing/duplicated
# sentinel row, or an unparseable generated_at value, per
# .claude/rules/fail-loud-not-null.md: a snapshot this function cannot fully
# trust must stop the check, never be silently treated as "no data" or
# "assume it's fine".
.cdf_read_meta_snapshot <- function(snapshot_path) {
  # basename only, NEVER the resolved absolute path, in every cli_abort()
  # below -- same discipline as .cdf_resolve_include_path()'s own comment:
  # the absolute path lives under a volatile tempdir in tests and would
  # break snapshot portability across machines/CI runs
  # (portable-build-artifacts).
  snapshot_basename <- basename(snapshot_path)
  if (!file.exists(snapshot_path)) {
    cli::cli_abort(c(
      "x" = "Metadata snapshot not found at {.file {snapshot_basename}}.",
      "i" = "Run {.code scripts/build.sh} in the main checkout to generate one."
    ))
  }
  rows <- tryCatch(
    utils::read.csv(snapshot_path, colClasses = "character", stringsAsFactors = FALSE),
    error = function(e) {
      cli::cli_abort(c(
        "x" = "Failed to read metadata snapshot at {.file {snapshot_basename}}.",
        "i" = conditionMessage(e)
      ))
    }
  )
  if (!identical(names(rows), c("name", "time"))) {
    cli::cli_abort(c(
      "x" = "Metadata snapshot at {.file {snapshot_basename}} does not have the expected {.code name,time} columns.",
      "i" = "Found columns: {paste(names(rows), collapse = ', ')}",
      "i" = "Regenerate it with {.code scripts/build.sh} rather than hand-editing."
    ))
  }
  # sentinel_name, not the leading-dot constant directly, is interpolated
  # below -- see .cdf_write_meta_snapshot()'s equivalent comment for why.
  sentinel_name <- .CDF_META_SNAPSHOT_SENTINEL_NAME
  sentinel_rows <- rows[rows$name == sentinel_name, , drop = FALSE]
  if (nrow(sentinel_rows) != 1) {
    cli::cli_abort(c(
      "x" = "Metadata snapshot at {.file {snapshot_basename}} has {nrow(sentinel_rows)} {.val {sentinel_name}} row(s); expected exactly 1.",
      "i" = "The file is malformed -- regenerate it with {.code scripts/build.sh} rather than hand-editing."
    ))
  }
  generated_at <- .cdf_parse_snapshot_time(sentinel_rows$time[1])
  if (is.na(generated_at)) {
    cli::cli_abort(c(
      "x" = "Metadata snapshot at {.file {snapshot_basename}} has an unparseable generated_at value: {.val {sentinel_rows$time[1]}}",
      "i" = "The file is malformed -- regenerate it with {.code scripts/build.sh} rather than hand-editing."
    ))
  }
  target_rows <- rows[rows$name != .CDF_META_SNAPSHOT_SENTINEL_NAME, , drop = FALSE]
  meta_time <- .cdf_parse_snapshot_time(target_rows$time)
  names(meta_time) <- target_rows$name
  list(meta_time = meta_time, generated_at = generated_at)
}

# Hours elapsed between `generated_at` (the snapshot's own sentinel
# timestamp) and `now` (defaults to Sys.time()) -- factored out as pure
# arithmetic, no file I/O, so it is unit-testable directly (see "THE
# SNAPSHOT'S OWN AGE IS A FIRST-CLASS, CHECKABLE SIGNAL" above).
.cdf_meta_snapshot_age_hours <- function(generated_at, now = Sys.time()) {
  as.numeric(difftime(now, generated_at, units = "hours"))
}

# Decides which data source Check 3 should use, and whether that source is
# trustworthy -- factored out of .cdf_main() specifically so this decision is
# unit-testable without a real store or a real docs/_targets.R manifest (see
# this file's header comment on why .cdf_main() as a whole is not
# unit-tested elsewhere). Deliberately does NOT call targets::tar_meta()
# itself (that needs a real store -- the caller does that read when
# `$decision == "live"`); it DOES read `snapshot_path` off disk via
# .cdf_read_meta_snapshot() when a live store is unavailable, because the
# snapshot's own age (the thing this function exists to police) can only be
# known by actually reading its generated_at row.
#
# `store_exists` is a plain boolean (typically `dir.exists(store_path)`) --
# passed in rather than computed here so tests can exercise "store present"
# without needing a real docs/_targets directory. Returns one of:
#   list(decision = "live")
#     A live store exists and takes priority -- caller reads it directly.
#   list(decision = "snapshot", meta_time =, age_hrs =, generated_at =)
#     No live store, but the committed snapshot exists and is within
#     `threshold_hrs` of its own generated_at -- caller uses `meta_time`
#     as-is.
#   list(decision = "snapshot_too_old", age_hrs =, generated_at =)
#     No live store, and the committed snapshot exists but is OLDER than
#     `threshold_hrs` -- per "THE SNAPSHOT'S OWN AGE IS A FIRST-CLASS,
#     CHECKABLE SIGNAL" above, this is a hard failure, never treated as
#     "snapshot" data.
#   list(decision = "no_source")
#     No live store and no committed snapshot file at all.
# Propagates (does not catch) any error .cdf_read_meta_snapshot() raises
# (missing/duplicated sentinel row, unparseable timestamp, etc.) -- per
# .claude/rules/fail-loud-not-null.md, a malformed snapshot must stop the
# check, never be silently treated as "no snapshot" or "trust it anyway".
.cdf_check3_source_decision <- function(store_exists, snapshot_path, threshold_hrs, now = Sys.time()) {
  if (isTRUE(store_exists)) {
    return(list(decision = "live"))
  }
  if (!file.exists(snapshot_path)) {
    return(list(decision = "no_source"))
  }
  snap <- .cdf_read_meta_snapshot(snapshot_path)
  age_hrs <- .cdf_meta_snapshot_age_hours(snap$generated_at, now = now)
  if (age_hrs > threshold_hrs) {
    return(list(decision = "snapshot_too_old", age_hrs = age_hrs, generated_at = snap$generated_at))
  }
  list(decision = "snapshot", meta_time = snap$meta_time, age_hrs = age_hrs, generated_at = snap$generated_at)
}

# ---------------------------------------------------------------------------
# Check 3 -- data staleness (needs a real store, OR the committed snapshot)
# ---------------------------------------------------------------------------

# Returns a named list: page basename -> list(gap_hrs=, source=) for every
# page whose own referenced targets' newest tar_meta() build time is after
# the page's render time. `meta_time` is a named numeric-time vector
# (name -> POSIXct), typically from targets::tar_meta(fields = time).
.cdf_check_data_staleness <- function(qmd_files, page_targets, meta_time, repo_root, note_fn = NULL) {
  stale <- list()
  for (f in qmd_files) {
    base <- basename(f)
    refs <- page_targets[[base]]
    if (length(refs) == 0) next
    known_refs <- intersect(refs, names(meta_time))
    unknown_refs <- setdiff(refs, names(meta_time))
    if (length(unknown_refs) > 0 && !is.null(note_fn)) {
      note_fn(base, unknown_refs)
    }
    if (length(known_refs) == 0) next
    max_target_time <- max(meta_time[known_refs], na.rm = TRUE)

    html_path <- sub("\\.qmd$", ".html", f)
    render <- .cdf_page_render_time(html_path, repo_root)
    if (is.na(render$time)) next

    if (max_target_time > render$time) {
      stale[[base]] <- list(
        gap_hrs = as.numeric(difftime(max_target_time, render$time, units = "hours")),
        source = render$source
      )
    }
  }
  stale
}

# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------

# Runs Check 1 + Check 2 (and Check 3 when `data_staleness = TRUE`, which
# requires an existing store at `store_path`). Prints a human-readable
# report and a machine-parseable `::VERIFY:DASHBOARD_FRESHNESS_STATUS:: <n>`
# marker line, and RETURNS (does not quit()) an overall status: 0 (clean),
# 1 (a real problem was found -- see EXIT CODES in the header comment for
# what counts), or 2 (could not run at all -- extraction/manifest/store
# failure).
#
# Deliberately does NOT call quit() itself, even on a status-2 condition:
# this function is source()'d and invoked from INSIDE scripts/verify.sh's
# existing Rscript process (see header comment on why -- avoiding a second
# nix-develop entry), which also still has test suites left to run after
# this check. A quit() here would silently truncate that process before the
# test suites ran, and verify.sh's OWN established convention (see its
# header comment: "does NOT quit() on failure ... a failure here is
# reported via OVERALL_STATUS") is that only the initial hard parse gate
# quits early -- everything else continues to completion and reports via
# markers. The standalone entry point at the bottom of this file (used by
# `Rscript scripts/check_dashboard_freshness.R` directly, and by
# scripts/build.sh's separate `--data-staleness` invocation) DOES quit()
# with whatever status this function returns, since those are each their
# own standalone process with nothing left to run afterward.
.cdf_main <- function(data_staleness = FALSE, repo_root = here::here()) {
  docs_dir <- file.path(repo_root, "docs")

  cat("=== scripts/check_dashboard_freshness.R ===\n")
  cat(sprintf("Repo root: %s\n", repo_root))
  cat(sprintf(
    "Mode: %s\n",
    if (data_staleness) "Check 1 + Check 2 + Check 3 (data staleness needs a real store)" else "Check 1 + Check 2 (no store needed)"
  ))
  cat("\n")

  overall_status <- 0
  qmd_files <- .cdf_qmd_files(docs_dir)

  t_extract_start <- Sys.time()
  page_targets <- tryCatch(
    .cdf_collect_page_targets(qmd_files),
    error = function(e) {
      cat("!!! EXTRACTION FAILED -- see error below. This is NOT a pass. !!!\n")
      cat(rlang::cnd_message(e), "\n")
      NULL
    }
  )
  if (is.null(page_targets)) {
    cat("::VERIFY:DASHBOARD_FRESHNESS_STATUS:: 2\n")
    return(invisible(2L))
  }
  t_extract_elapsed <- as.numeric(Sys.time() - t_extract_start, units = "secs")
  cat(sprintf(
    "--- extracted target references from %d docs/*.qmd file(s) (%.2fs) ---\n",
    length(qmd_files), t_extract_elapsed
  ))

  t_manifest_start <- Sys.time()
  manifest <- tryCatch(
    targets::tar_manifest(script = file.path(docs_dir, "_targets.R"), fields = "name"),
    error = function(e) {
      cat("!!! targets::tar_manifest() failed -- cannot run Check 1. This is NOT a pass. !!!\n")
      cat(rlang::cnd_message(e), "\n")
      NULL
    }
  )
  if (is.null(manifest)) {
    cat("::VERIFY:DASHBOARD_FRESHNESS_STATUS:: 2\n")
    return(invisible(2L))
  }
  t_manifest_elapsed <- as.numeric(Sys.time() - t_manifest_start, units = "secs")
  manifest_names <- manifest$name
  cat(sprintf(
    "--- targets::tar_manifest(docs/_targets.R): %d targets (%.2fs) ---\n",
    length(manifest_names), t_manifest_elapsed
  ))

  cat("\n=== Check 1: dead target references ===\n")
  dead <- .cdf_check_dead_references(page_targets, manifest_names)
  n_refs_total <- length(unique(unlist(page_targets, use.names = FALSE)))
  if (length(dead) == 0) {
    cat(sprintf(
      "PASS: no dead target references across %d page(s), %d distinct target reference(s)\n",
      length(page_targets), n_refs_total
    ))
  } else {
    overall_status <- 1
    cat("FAIL: dead target references found (these WILL fail at render/tar_read time):\n")
    for (page in names(dead)) {
      cat(sprintf(
        "  [DEAD-REF] %s -- references non-existent target(s): %s\n",
        page, paste(dead[[page]], collapse = ", ")
      ))
    }
  }

  cat("\n=== Check 2: source-vs-render staleness (git commit date, .qmd vs .html) ===\n")
  src_stale <- .cdf_check_source_staleness(qmd_files, repo_root)
  if (length(src_stale$excluded_stub) > 0) {
    cat(sprintf(
      "  [STUB] excluded %d redirect stub page(s) -- no R chunks + <meta refresh> marker; their .qmd will always postdate their .html, so reporting them STALE forever is not a real signal: %s\n",
      length(src_stale$excluded_stub), paste(src_stale$excluded_stub, collapse = ", ")
    ))
  }
  for (base in src_stale$untracked) {
    cat(sprintf("  [SKIP] %s -- not tracked by git; cannot assess staleness\n", base))
  }
  for (base in src_stale$no_html) {
    cat(sprintf("  [NO-HTML] %s -- no committed .html counterpart found\n", base))
  }
  n_checked <- length(qmd_files) - length(src_stale$excluded_stub)
  if (length(src_stale$stale) == 0) {
    cat("PASS: no page's .qmd source is newer than its committed .html\n")
  } else {
    ordered <- names(src_stale$stale)[order(-unlist(src_stale$stale))]
    cat(sprintf(
      "STALE: %d of %d page(s) have .qmd source newer than their committed .html:\n",
      length(src_stale$stale), n_checked
    ))
    for (page in ordered) {
      cat(sprintf(
        "  [STALE] %s -- source is %.1f day(s) newer than its rendered .html\n",
        page, src_stale$stale[[page]]
      ))
    }
    if (.cdf_env_flag_true("HD_FAIL_ON_STALE_DASHBOARDS")) {
      cat("HD_FAIL_ON_STALE_DASHBOARDS is set -- treating source staleness as a hard failure (zero grace period; see script header \"ESCALATION POLICY\").\n")
      overall_status <- 1
    } else {
      cat("NOTE: staleness is reported but does NOT fail this run by default (see script header for rationale).\n")
      cat("      Set HD_FAIL_ON_STALE_DASHBOARDS=1 to escalate this to a hard failure (zero grace -- any source staleness escalates).\n")
    }
  }

  if (data_staleness) {
    store_path <- file.path(docs_dir, "_targets")
    snapshot_path <- .cdf_meta_snapshot_path(repo_root)
    cat("\n=== Check 3: data staleness (page render time vs newest tar_meta() time of its own targets) ===\n")

    # WHICH SOURCE DID CHECK 3 USE -- always stated explicitly, and never
    # ambiguous between the two: a live store (the main checkout, right
    # after scripts/build.sh's own tar_make()) is authoritative and always
    # preferred when present; the committed snapshot
    # (docs/_targets_meta_snapshot.csv) is the ONLY option in CI, which never
    # has a store, and is used as a fallback in the main checkout too if a
    # store somehow does not exist. See the "Metadata snapshot" section
    # above this function for the full design (file format + the
    # snapshot-age hard-failure policy), and .cdf_check3_source_decision()
    # for why this decision is factored out into its own testable function.
    threshold_hrs <- .cdf_data_staleness_threshold_hours()
    decision <- tryCatch(
      .cdf_check3_source_decision(dir.exists(store_path), snapshot_path, threshold_hrs),
      error = function(e) {
        cat("!!! Failed to read the committed metadata snapshot -- cannot run Check 3. This is NOT a pass. !!!\n")
        cat(rlang::cnd_message(e), "\n")
        NULL
      }
    )
    if (is.null(decision)) {
      cat("::VERIFY:DASHBOARD_FRESHNESS_STATUS:: 2\n")
      return(invisible(2L))
    }

    if (decision$decision == "live") {
      cat(sprintf("Check 3 data source: LIVE STORE (%s)\n", store_path))
      meta <- tryCatch(
        targets::tar_meta(store = store_path, fields = time, targets_only = TRUE),
        error = function(e) {
          cat("!!! targets::tar_meta() failed -- cannot run Check 3. This is NOT a pass. !!!\n")
          cat(rlang::cnd_message(e), "\n")
          NULL
        }
      )
      if (is.null(meta)) {
        cat("::VERIFY:DASHBOARD_FRESHNESS_STATUS:: 2\n")
        return(invisible(2L))
      }
      meta_time <- stats::setNames(meta$time, meta$name)
    } else if (decision$decision == "snapshot") {
      cat(sprintf(
        "Check 3 data source: COMMITTED SNAPSHOT (%s)\n  generated_at=%s UTC, age=%.1fh (max allowed %.1fh / %.0f day(s), HD_STALE_DASHBOARD_DATA_THRESHOLD_DAYS)\n",
        snapshot_path, format(decision$generated_at, "%Y-%m-%d %H:%M:%S", tz = "UTC"),
        decision$age_hrs, threshold_hrs, threshold_hrs / 24
      ))
      meta_time <- decision$meta_time
    } else if (decision$decision == "snapshot_too_old") {
      cat(sprintf(
        "Check 3 data source: COMMITTED SNAPSHOT (%s) -- TOO OLD TO TRUST\n  generated_at=%s UTC, age=%.1fh (max allowed %.1fh / %.0f day(s), HD_STALE_DASHBOARD_DATA_THRESHOLD_DAYS)\n",
        snapshot_path, format(decision$generated_at, "%Y-%m-%d %H:%M:%S", tz = "UTC"),
        decision$age_hrs, threshold_hrs, threshold_hrs / 24
      ))
      cat("!!! A snapshot this old cannot support a Check 3 verdict at all -- it is not a warning, it is a hard failure. !!!\n")
      cat("!!! Run `scripts/build.sh` in the main checkout to regenerate docs/_targets_meta_snapshot.csv, then commit it. !!!\n")
      cat("!!! CHECK 3 DID NOT RUN (snapshot too old to trust). This is NOT a pass. !!!\n")
      cat("::VERIFY:DASHBOARD_FRESHNESS_STATUS:: 2\n")
      return(invisible(2L))
    } else { # "no_source"
      cat(sprintf("!!! No live store found at '%s' and no committed metadata snapshot at '%s' !!!\n", store_path, snapshot_path))
      cat("!!! Run `scripts/build.sh` in the main checkout to build the store and write the snapshot. !!!\n")
      cat("!!! CHECK 3 DID NOT RUN. This is NOT a pass. !!!\n")
      cat("::VERIFY:DASHBOARD_FRESHNESS_STATUS:: 2\n")
      return(invisible(2L))
    }

    data_stale <- .cdf_check_data_staleness(
      qmd_files, page_targets, meta_time, repo_root,
      note_fn = function(base, unknown_refs) {
        cat(sprintf(
          "  [NOTE] %s -- %d referenced target(s) have no tar_meta() build record (never built, or a dead reference already reported by Check 1): %s\n",
          base, length(unknown_refs), paste(unknown_refs, collapse = ", ")
        ))
      }
    )
    if (length(data_stale) == 0) {
      cat("PASS: no page's own referenced targets are newer than the page's render time\n")
    } else {
      cat(sprintf("STALE: %d page(s) have target data newer than their rendered output:\n", length(data_stale)))
      for (page in names(data_stale)) {
        d <- data_stale[[page]]
        cat(sprintf(
          "  [DATA-STALE] %s -- referenced target(s) rebuilt %.1f hour(s) after render (render time source: %s)\n",
          page, d$gap_hrs, d$source
        ))
      }
      threshold_hrs <- .cdf_data_staleness_threshold_hours()
      threshold_days <- threshold_hrs / 24
      over_threshold <- .cdf_data_staleness_over_threshold(data_stale, threshold_hrs)
      if (.cdf_env_flag_true("HD_FAIL_ON_STALE_DASHBOARDS")) {
        if (length(over_threshold) > 0) {
          cat(sprintf(
            "HD_FAIL_ON_STALE_DASHBOARDS is set -- %d of %d stale page(s) exceed the %.0f-day data-staleness grace period (HD_STALE_DASHBOARD_DATA_THRESHOLD_DAYS), treating as a hard failure: %s\n",
            length(over_threshold), length(data_stale), threshold_days, paste(over_threshold, collapse = ", ")
          ))
          overall_status <- 1
        } else {
          cat(sprintf(
            "HD_FAIL_ON_STALE_DASHBOARDS is set, but all %d stale page(s) are within the %.0f-day data-staleness grace period -- not escalating.\n",
            length(data_stale), threshold_days
          ))
        }
      } else {
        cat("NOTE: data staleness is reported but does NOT fail this run by default (see script header for rationale).\n")
        cat(sprintf(
          "      Set HD_FAIL_ON_STALE_DASHBOARDS=1 to escalate page(s) past the %.0f-day grace period (HD_STALE_DASHBOARD_DATA_THRESHOLD_DAYS) to a hard failure.\n",
          threshold_days
        ))
      }
    }
  }

  cat("\n")
  if (overall_status == 0) {
    cat("=== scripts/check_dashboard_freshness.R: PASS ===\n")
  } else {
    cat("=== scripts/check_dashboard_freshness.R: FAIL ===\n")
  }
  cat(sprintf("::VERIFY:DASHBOARD_FRESHNESS_STATUS:: %d\n", overall_status))
  invisible(overall_status)
}

# Only run when this file is the Rscript entry point (sys.nframe() == 0),
# never when source()'d for its functions -- confirmed empirically
# 2026-08-20: `Rscript file.R` gives sys.nframe() == 0 at top level;
# `source("file.R")` gives sys.nframe() > 0 (source() itself adds a frame).
# tests/testthat/test-dashboard-freshness.R and scripts/verify.sh both
# source() this file and must NOT trigger a live run.
if (sys.nframe() == 0) {
  args <- commandArgs(trailingOnly = TRUE)
  status <- .cdf_main(data_staleness = "--data-staleness" %in% args)
  quit(status = status, save = "no")
}
