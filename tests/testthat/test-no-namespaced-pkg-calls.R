testthat::local_edition(3)
# Regression guard for #911 Flaw 1 / #753: a `historicaldata::fn()` (or
# `historicaldata:::fn()`) call anywhere in R/ is INVISIBLE to
# `targets`' own dependency tracking -- `tar_option_set(imports =
# "historicaldata")` in docs/_targets.R only tracks BARE-name calls, because
# `targets`' own documentation for `imports` states namespaced calls "are
# ignored because of limitations in codetools::findGlobals()". #911 converted
# every namespaced call in R/ to bare form (proof: docs/_targets.R's own
# tar_network() edges gained a dependency on the package function for every
# converted target -- see the #911 PR body for the before/after evidence).
# This test is the backstop that keeps that population at zero: R/ is where
# every historicaldata::-calling file in this repo lives (plan_*.R files plus
# a handful of helpers like utils_metrics.R, cov_config.R, glossary.R), and
# a new namespaced call anywhere under R/ would silently re-open the exact
# defect #753/#911 fixed, invisible to tar_make() and to scripts/build.sh
# (see .claude/CLAUDE.md's "Package source not tracked" note).
#
# WHY AST INSPECTION, NOT LINE REGEX: a plain `grepl("historicaldata::", ...)`
# would also match the string inside a `#'` roxygen comment describing the
# package (dozens of these exist deliberately, e.g. "See
# historicaldata::hd_market_impact." in R/plan_stock_backtest.R) or inside a
# string literal. Only a real `historicaldata::fn` / `historicaldata:::fn`
# parse-tree token (SYMBOL_PACKAGE "historicaldata" immediately followed by
# NS_GET/NS_GET_INT) is a genuine call this defect applies to. This mirrors
# the AST-not-regex discipline scripts/check_pkg_staleness.R already uses for
# the same reason (see that script's header comment on the xgb_vs_enet
# false-positive it replaced a regex-based version to fix).
#
# ALLOW-LIST: a call site may be deliberately exempted (e.g. a documented,
# rare case where staying namespaced is intentional) by adding the literal
# marker `# HD-NS-ALLOW: <reason>` on the SAME line as the call (deliberately
# NOT "the line above" -- with two namespaced calls on consecutive lines, a
# marker meant for one line would ambiguously exempt its neighbour too; a
# same-line-only rule has no such ambiguity). As of #911, this list is EMPTY
# -- every call in R/ was converted to bare form, and no call currently needs
# the exemption. Do not add an exemption to make this test pass without also
# documenting, in the PR that adds it, why the call cannot be a bare call
# (e.g. a genuine multi-package ambiguity that `library()`/`imports` cannot
# resolve).

.hdns_allow_marker <- "HD-NS-ALLOW:"

# .hdns_find_violations(path) -- returns a character vector of
# "path:line: historicaldata::name" strings for every namespaced call to
# `historicaldata` in `path` that is not covered by the allow-list marker.
# Returns character(0) for a clean file. A file that fails to parse is a
# hard test failure (via the caller), not a silent skip -- consistent with
# checks-must-distinguish-unknown: a check that cannot run must never be
# folded into "found nothing".
.hdns_find_violations <- function(path) {
  parsed <- parse(path, keep.source = TRUE)
  pd <- getParseData(parsed)
  if (is.null(pd) || nrow(pd) == 0L) {
    return(character(0))
  }
  pkg_rows <- which(pd$token == "SYMBOL_PACKAGE" & pd$text == "historicaldata")
  if (length(pkg_rows) == 0L) {
    return(character(0))
  }

  lines <- readLines(path, warn = FALSE)
  out <- character(0)
  for (i in pkg_rows) {
    nxt <- pd[i + 1L, ]
    is_ns_call <- isTRUE(nxt$token %in% c("NS_GET", "NS_GET_INT"))
    ln <- pd$line1[i]
    # Name of the symbol/function immediately after the :: / ::: , if
    # resolvable; fall back to "<unknown>" rather than failing the check --
    # the flag itself does not depend on knowing the callee's name.
    callee <- if (i + 2L <= nrow(pd)) pd$text[i + 2L] else "<unknown>"

    this_line_allowed <- grepl(.hdns_allow_marker, lines[ln], fixed = TRUE)
    if (this_line_allowed) next

    if (is_ns_call) {
      out <- c(out, sprintf("%s:%d: historicaldata::%s", basename(path), ln, callee))
    } else {
      out <- c(out, sprintf(
        "%s:%d: SYMBOL_PACKAGE 'historicaldata' not followed by NS_GET/NS_GET_INT (unexpected parse shape)",
        basename(path), ln
      ))
    }
  }
  out
}

test_that("no R/*.R file contains a namespaced historicaldata:: call (#911, #753)", {
  r_files <- list.files(here::here("R"), pattern = "\\.R$", full.names = TRUE)
  expect_gt(length(r_files), 0L) # sanity: the discovery mechanism itself must find files

  all_violations <- unlist(lapply(r_files, .hdns_find_violations))

  if (length(all_violations) > 0L) {
    fail(paste0(
      length(all_violations),
      " namespaced historicaldata:: call(s) found in R/ -- these are ",
      "INVISIBLE to tar_option_set(imports = \"historicaldata\") in ",
      "docs/_targets.R (targets' own documented codetools::findGlobals() ",
      "limitation), so a change to the called function silently fails to ",
      "invalidate the consuming target (#753/#911). Convert to a bare call, ",
      "or add an explicit `# HD-NS-ALLOW: <reason>` marker on the SAME line ",
      "if the namespaced form is genuinely required:\n",
      paste(all_violations, collapse = "\n")
    ))
  }
  expect_equal(all_violations, character(0))
})

test_that(".hdns_find_violations detects a real namespaced call and ignores a comment/allowed one", {
  dir <- withr::local_tempdir()
  f <- file.path(dir, "plan_fixture.R")
  writeLines(c(
    "# See historicaldata::hd_market_impact. for background (comment -- not flagged)",
    "plan_fixture <- function() {",
    "  x <- historicaldata::hd_fake_fn(1)  # HD-NS-ALLOW: deliberately kept namespaced for this test",
    "  y <- historicaldata::hd_fake_fn2(2)",
    "  list(x, y)",
    "}"
  ), f)

  violations <- .hdns_find_violations(f)
  expect_length(violations, 1L)
  expect_match(violations, "hd_fake_fn2", fixed = TRUE)
})

test_that(".hdns_find_violations returns character(0) for a file with no historicaldata:: reference at all", {
  dir <- withr::local_tempdir()
  f <- file.path(dir, "plan_clean.R")
  writeLines("plan_clean <- function() list(targets::tar_target(x, 1))", f)
  expect_equal(.hdns_find_violations(f), character(0))
})
