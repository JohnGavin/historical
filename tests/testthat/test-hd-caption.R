testthat::local_edition(3)
source(here::here("docs/vignette_utils.R"))

# ---------------------------------------------------------------------------
# hd_caption() / hd_link() — dashboard caption length + well-formedness
# (historical dispatch 0b412a9c: leaderboard's Rankings caption measured at
# 618 words / 4589 characters, and markdown-style `[text](url)` links baked
# into DT captions never render as clickable HTML since DT hands captions
# straight to the browser with no pandoc/markdown pass.)
#
# hd_caption() splits long captions into a short, unconditional summary plus
# a collapsed <details> block; hd_link() builds a real <a href> tag instead
# of markdown link syntax. Both are exercised here in isolation from the
# `leaderboard` target/RDS fixture, which as of this dispatch is stale (see
# the "known issue" test below) and cannot drive a full qmd render locally.
# ---------------------------------------------------------------------------

# xml2 is used only to assert real HTML well-formedness (not declared in any
# DESCRIPTION Suggests at the root -- tests/testthat/ here is not part of the
# packages/historicaldata check surface). Skip gracefully if unavailable.
skip_if_no_xml2 <- function() testthat::skip_if_not_installed("xml2")

n_caption_nodes <- function(html_fragment) {
  skip_if_no_xml2()
  doc <- xml2::read_html(paste0("<table>", html_fragment, "</table>"))
  length(xml2::xml_find_all(doc, "//caption"))
}

test_that("hd_caption: short plain text renders as a single well-formed <caption>, unchanged", {
  cap <- hd_caption("A short caption.")
  html <- as.character(cap)
  expect_match(html, "^<caption", fixed = FALSE)
  expect_match(html, "A short caption.", fixed = TRUE)
  expect_false(grepl("<details>", html, fixed = TRUE))
  expect_equal(n_caption_nodes(html), 1L)
})

test_that("hd_caption: long plain text (no `short`) auto-splits into span + <details>", {
  long_text <- paste(rep("Sentence about strategy comparability and cost conventions.", 10),
                      collapse = " ")
  cap <- hd_caption(long_text)
  html <- as.character(cap)
  expect_true(grepl("<details>", html, fixed = TRUE))
  expect_true(grepl("<summary>", html, fixed = TRUE))
  # The full text is still present (nothing was deleted, only re-parented).
  expect_true(grepl(long_text, html, fixed = TRUE))
  expect_equal(n_caption_nodes(html), 1L)
})

test_that("hd_caption: exactly-threshold-length text is NOT wrapped (boundary)", {
  exact <- strrep("x", 300)
  cap <- hd_caption(exact, threshold = 300)
  html <- as.character(cap)
  expect_false(grepl("<details>", html, fixed = TRUE))
})

test_that("hd_caption: one-char-over-threshold text IS wrapped (boundary)", {
  over <- strrep("x", 301)
  cap <- hd_caption(over, threshold = 300)
  html <- as.character(cap)
  expect_true(grepl("<details>", html, fixed = TRUE))
})

test_that("hd_caption: tagList content requires an explicit `short`", {
  notes <- htmltools::tagList("some notes with a ", hd_link("link", "https://example.com"))
  expect_error(hd_caption(notes), regexp = "`short` is required")
})

test_that("hd_caption: tagList + real <a> link renders as ONE well-formed caption with a real anchor", {
  lnk <- hd_link(htmltools::tags$code("hd_exposure_metrics()"), "https://example.com/foo")
  notes <- htmltools::tagList(
    "Some notes with a link: ", lnk, ". And a literal <20% comparison that must stay escaped."
  )
  cap <- hd_caption(notes, short = "Short summary here.")
  html <- as.character(cap)

  expect_equal(n_caption_nodes(html), 1L)
  # The link is real HTML, not markdown-style `[text](url)` dead text.
  expect_true(grepl('<a href="https://example.com/foo"', html, fixed = TRUE))
  expect_false(grepl("[`hd_exposure_metrics()`](", html, fixed = TRUE))
  # Literal `<` in prose is still auto-escaped (htmltools default for plain-
  # string children) -- this is what keeps a caption well-formed even when a
  # note happens to contain a bare comparison operator.
  expect_true(grepl("&lt;20%", html, fixed = TRUE))

  skip_if_no_xml2()
  doc <- xml2::read_html(paste0("<table>", html, "</table>"))
  expect_length(xml2::xml_find_all(doc, "//caption//a[@href]"), 1L)
})

test_that("hd_link: builds a real, safe anchor tag (target/rel set, label escaped)", {
  lnk <- hd_link("a <b> label", "https://example.com/?a=1&b=2")
  html <- as.character(lnk)
  expect_match(html, '^<a href="https://example.com/\\?a=1&amp;b=2"')
  expect_match(html, 'target="_blank"', fixed = TRUE)
  expect_match(html, 'rel="noopener noreferrer"', fixed = TRUE)
  expect_true(grepl("&lt;b&gt;", html, fixed = TRUE))
})

test_that("hd_dt: caption is built via hd_caption() (regression guard against re-wrapping)", {
  # hd_dt()'s widget is built by DT::datatable(); assert only the caption
  # construction path, not the full DT widget (heavy dependency, and not
  # what this dispatch touched).
  df <- data.frame(x = 1:3)
  long_caption <- paste(rep("Detail sentence about this table.", 15), collapse = " ")
  widget <- hd_dt(df, long_caption)
  cap_html <- as.character(widget$x$caption)
  expect_equal(n_caption_nodes(cap_html), 1L)
  expect_true(grepl("<details>", cap_html, fixed = TRUE))
})

# ---------------------------------------------------------------------------
# Known issue (out of scope for this dispatch, documented not silently
# skipped): inst/extdata/vignettes/leaderboard.rds is stale relative to the
# current leaderboard.qmd -- it carries only strategy/period/months/cagr/vol/
# sharpe/max_dd/hit_rate/bench_*/level/signal/definition/avg_long/avg_short
# (16 columns), missing every column the caption-building code and the
# detection-rigour-summary chunk depend on (detection_underpowered,
# detection_underpowered_mt, k_eff_leaderboard, k_raw_leaderboard, credible,
# survivorship_biased, gross_convention, is_cap, cost_per_trade_bps,
# redundant, incremental_sharpe, net_cagr, deflated_sharpe, dsr_pvalue).
# `!full_dp$detection_underpowered` on a NULL column throws "invalid
# argument type" and halts `quarto render` before it reaches any caption
# code -- confirmed via `git stash` A/B (pre-existing on unmodified main,
# not introduced by this dispatch). This test pins the fixture's current
# (broken) shape so a future fixture regen is visible as a passing-test
# diff rather than a silent fix.
# ---------------------------------------------------------------------------

test_that("KNOWN ISSUE: leaderboard.rds fixture is stale -- missing columns the qmd requires", {
  rds_path <- here::here("inst/extdata/vignettes/leaderboard.rds")
  skip_if_not(file.exists(rds_path), "leaderboard.rds fixture not present in this checkout")
  lb <- readRDS(rds_path)
  required_cols <- c(
    "detection_underpowered", "detection_underpowered_mt",
    "k_eff_leaderboard", "k_raw_leaderboard", "credible",
    "survivorship_biased", "gross_convention", "is_cap",
    "cost_per_trade_bps", "redundant", "incremental_sharpe",
    "net_cagr", "deflated_sharpe", "dsr_pvalue"
  )
  missing <- setdiff(required_cols, names(lb))
  # This assertion is EXPECTED to hold today (documenting the known issue).
  # If it starts failing, the fixture has been regenerated -- update/remove
  # this test and re-verify the leaderboard.qmd render locally.
  expect_true(
    length(missing) > 0,
    label = "leaderboard.rds fixture columns (expected still-missing set)"
  )
})

# ---------------------------------------------------------------------------
# Function signature stability (catches API drift) — Tier A snapshots
# ---------------------------------------------------------------------------

test_that("function signatures are stable (catches API drift)", {
  expect_snapshot(args(hd_caption))
  expect_snapshot(args(hd_link))
})
