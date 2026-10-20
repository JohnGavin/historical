testthat::local_edition(3)
# Rankings caption as bullets (presentation only). Guards:
#   (a) the always-visible part is <= 3 bullets and < 300 characters
#   (b) the details are ONE <ul>, one <li> per column/concept
#   (c) every issue number the old prose carried is still reachable
#   (d) the dynamic counts are computed from the data (distinctive fixture
#       values 7 and 13, never hand-typed in the builder)

source(here::here("R/glossary.R"))
source(here::here("R/column_popover.R"))
source(here::here("R/leaderboard_caption.R"))

# 13 strategies; 7 at 2.0x gross; 3 non-credible; 5 ssr covered; etc.
.lc_fixture <- function() {
  n <- 13L
  data.frame(
    strategy = paste0("S", seq_len(n)),
    credible = c(rep(TRUE, 10), rep(FALSE, 3)),
    ssr = c(rep(1.5, 5), rep(NA_real_, 8)),
    net_cagr = c(rep(0.05, 11), NA, NA),
    survivorship_biased = c(TRUE, rep(FALSE, 12)),
    gross_convention = c(rep(2, 7), rep(1, 5), NA),
    is_cap = c(TRUE, TRUE, rep(FALSE, 11)),
    G_capped = c(rep(1.5, 9), rep(NA_real_, 4)),
    backstop_binds = c(TRUE, TRUE, TRUE, rep(FALSE, 10)),
    detection_underpowered = c(TRUE, rep(FALSE, 12)),
    sigma_target_used = c(rep(0.1234, 9), rep(NA_real_, 4)),
    backstop_used = c(rep(3, 9), rep(NA_real_, 4)),
    cost_per_trade_bps = c(0, 5, 10, rep(20, 9), NA),
    redundant = c(rep(FALSE, 6), TRUE, TRUE, rep(NA, 5)),
    stringsAsFactors = FALSE
  )
}

.lc_build <- function(full = .lc_fixture(), ...) {
  hd_leaderboard_caption(
    full, gh_base = "https://github.com/JohnGavin/historical", git_sha = "abc123",
    kraw = 17L, keff = 9.4, has_sharpe_ci = TRUE, n_ci_crosses_zero = 4L, ...
  )
}

# Whole caption as text: the markup plus every decoded popover attribute, so a
# fact moved into a hover body is still found.
.lc_all_text <- function(cap) {
  html <- as.character(htmltools::tagList(cap$short, cap$details))
  doc <- xml2::read_html(paste0("<html><body>", html, "</body></html>"))
  nodes <- xml2::xml_find_all(doc, "//*[@data-bs-content]")
  popover <- vapply(nodes, function(nd) {
    paste(xml2::xml_attr(nd, "data-bs-title"), xml2::xml_attr(nd, "data-bs-content"))
  }, character(1))
  paste(c(html, popover), collapse = "\n")
}

test_that("(a) visible part is <= 3 bullets and under 300 characters", {
  cap <- .lc_build()
  doc <- xml2::read_html(paste0("<html><body>", as.character(cap$short), "</body></html>"))
  expect_lte(length(xml2::xml_find_all(doc, "//li")), 3L)
  expect_lt(nchar(xml2::xml_text(doc)), 300L)
})

test_that("(b) details are one <ul> with one <li> per concept", {
  cap <- .lc_build()
  expect_identical(cap$details$name, "ul")
  doc <- xml2::read_html(paste0("<html><body>", as.character(cap$details), "</body></html>"))
  expect_length(xml2::xml_find_all(doc, "//ul"), 1L)
  terms <- xml2::xml_text(xml2::xml_find_all(doc, "//li/strong"))
  expect_identical(
    terms,
    c("CAGR / Net CAGR", "SSR", "Top5% Share", "Credible", "CVaR 95%", "Flags",
      "Gross (now)", "Gross (target)", "Cost (bps)", "Redundant",
      "Incremental Sharpe", "Detection", "Rigour", "Sharpe CI")
  )
  expect_length(xml2::xml_find_all(doc, "//li"), 14L)
})

test_that("(b) each bullet's blurb is short (<= 15 words)", {
  cap <- .lc_build()
  doc <- xml2::read_html(paste0("<html><body>", as.character(cap$details), "</body></html>"))
  for (li in xml2::xml_find_all(doc, "//li")) {
    term <- xml2::xml_text(xml2::xml_find_first(li, "./strong"))
    link_txt <- xml2::xml_text(xml2::xml_find_all(li, "./a"))
    blurb <- xml2::xml_text(li)
    for (l in c(term, link_txt, ":", "\u00b7")) blurb <- sub(l, "", blurb, fixed = TRUE)
    words <- strsplit(trimws(gsub("\\s+", " ", blurb)), " ")[[1]]
    expect_lte(length(words), 15L, label = term)
  }
})

test_that("(c) every issue number from the old prose is still present", {
  txt <- .lc_all_text(.lc_build())
  # #637 was never cited in the old caption text (only in a code comment).
  for (n in c(626, 624, 496, 726, 728, 150)) {
    expect_match(txt, paste0("#", n), fixed = TRUE, info = as.character(n))
  }
  # issue links are real anchors to the repo
  expect_match(txt, "https://github.com/JohnGavin/historical/issues/626", fixed = TRUE)
  # code links keep their #L anchors
  expect_match(txt, "packages/historicaldata/R/exposure.R#L67", fixed = TRUE)
  expect_match(txt, "R/plan_exposure.R#L27", fixed = TRUE)
  expect_match(txt, "R/plan_cost_convention.R#L44", fixed = TRUE)
  expect_match(txt, "R/plan_strategy_correlation.R#L31", fixed = TRUE)
})

test_that("(d) dynamic numbers are computed from the data", {
  txt <- .lc_all_text(.lc_build())
  expect_match(txt, "7 strategies are built dollar-neutral", fixed = TRUE)  # n_2x
  expect_match(txt, "(5 of 13)", fixed = TRUE)                              # ssr covered
  expect_match(txt, "remaining 8 show", fixed = TRUE)                       # ssr NA
  expect_match(txt, "(11 of 13 strategies covered)", fixed = TRUE)          # net_cagr
  expect_match(txt, "binds for 3 strategies (9 strategies have", fixed = TRUE)
  expect_match(txt, "0.1234", fixed = TRUE)
  expect_match(txt, "backstop of 3.0x", fixed = TRUE)
  expect_match(txt, "0–20 bps", fixed = TRUE)
  expect_match(txt, "testing 17 strategies (K_eff = 9.4)", fixed = TRUE)
  expect_match(txt, "4 of 13", fixed = TRUE)                                # CI spans zero
  expect_match(txt, "(2 of 13 strategies currently flagged)", fixed = TRUE) # redundant
  expect_match(txt, "outside the 8-strategy", fixed = TRUE)
})

test_that("popover attributes carry the long prose and nothing is double-escaped", {
  cap <- .lc_build()
  txt <- .lc_all_text(cap)
  # Decode each popover attribute ONCE: the result is HTML. A second decode
  # must be unnecessary, i.e. no entity-of-an-entity (&amp;lt; ...) remains.
  doc <- xml2::read_html(paste0("<html><body>", as.character(cap$details), "</body></html>"))
  bodies <- xml2::xml_attr(xml2::xml_find_all(doc, "//*[@data-bs-content]"), "data-bs-content")
  expect_gt(length(bodies), 10L)
  expect_no_match(bodies, "&amp;(lt|gt|amp|#)")
  # and the raw "<" / "&" of the prose did get escaped once (Credible bullet)
  expect_match(paste(bodies, collapse = ""), "&lt;20%", fixed = TRUE)
  expect_match(txt, "sum(abs(w))", fixed = TRUE)
  expect_match(txt, "Multiple-testing|corrected for testing", perl = TRUE)
})

test_that("bullet text is plain-sized and uses no hard-coded colours", {
  html <- as.character(htmltools::tagList(.lc_build()$short, .lc_build()$details))
  expect_no_match(html, "font-size|color:|#[0-9a-fA-F]{6}\\b")
})
