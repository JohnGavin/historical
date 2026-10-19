testthat::local_edition(3)
# Hover popovers for column headers (#788; DSR conventions #959):
#   1. definitions containing quotes / angle brackets / ampersands survive the
#      attribute encoding, and the links inside the body stay real <a> elements
#   2. a convention with no glossary entry (or none at all, or several) fails
#      LOUDLY with a classed cli_abort, never a bare header
#   3. the shipped data/column_glossary.yaml covers every convention and links
#      to the details the owner asked for

source(here::here("R/glossary.R"))
source(here::here("R/column_popover.R"))

# A glossary whose text deliberately contains every character that breaks a
# naive data-bs-content="..." attribute.
.nasty_text <- "E[max Z] < 1 & \"quoted\" and <b>not bold</b> it's 5 > 3"
.nasty_url <- "https://example.org/a?x=1&y=\"2\""

.fixture_glossary <- function() {
  list(dsr_pvalue = list(
    title = "DSR p-value",
    short = .nasty_text,
    difference = "differ only in <units>",
    ratio = "ratio = sqrt(252 / T) & so on",
    conventions = list(
      alpha = list(label = "alpha", role = "internal", definition = .nasty_text,
                   formula = "h = E[max Z] * sqrt(V) / sqrt(T)"),
      beta = list(label = "beta", role = "external", definition = "plain",
                  formula = "h = E[max Z] * sqrt(V)")
    ),
    links = list(list(label = "A \"link\" <here>", url = .nasty_url))
  ))
}

.span_node <- function(html) {
  doc <- xml2::read_html(paste0("<html><body>", html, "</body></html>"))
  xml2::xml_find_first(doc, "//span")
}

.body_doc <- function(content_html) {
  xml2::read_html(paste0("<html><body>", content_html, "</body></html>"))
}

test_that("quotes, angle brackets and ampersands survive the popover attribute encoding", {
  html <- hd_dsr_header_popover("alpha", .fixture_glossary())
  node <- .span_node(html)

  # The span parsed as ONE element with the expected Bootstrap attributes.
  expect_identical(xml2::xml_attr(node, "data-bs-toggle"), "popover")
  expect_identical(xml2::xml_attr(node, "data-bs-html"), "true")
  expect_identical(xml2::xml_attr(node, "data-bs-trigger"), "hover focus")
  expect_identical(xml2::xml_attr(node, "tabindex"), "0")
  expect_identical(xml2::xml_text(node), "DSR p-value (alpha)")

  # No inline style: size and colour come from the theme (#788).
  expect_false(grepl("style=", html, fixed = TRUE))
  expect_false(grepl("font-size", html, fixed = TRUE))

  # Decoding the attribute and parsing it again gives back the ORIGINAL text,
  # as text: "<b>not bold</b>" is characters, not a bold element.
  body <- .body_doc(xml2::xml_attr(node, "data-bs-content"))
  body_text <- xml2::xml_text(body)
  expect_true(grepl(.nasty_text, body_text, fixed = TRUE))
  expect_length(xml2::xml_find_all(body, "//b"), 0L)

  # The link is a real anchor; its href and label round-trip exactly.
  a <- xml2::xml_find_first(body, "//a")
  expect_identical(xml2::xml_attr(a, "href"), .nasty_url)
  expect_identical(xml2::xml_text(a), "A \"link\" <here>")
  expect_identical(xml2::xml_attr(a, "rel"), "noopener noreferrer")
})

test_that("the popover names both conventions and the difference", {
  node <- .span_node(hd_dsr_header_popover("beta", .fixture_glossary()))
  body_text <- xml2::xml_text(.body_doc(xml2::xml_attr(node, "data-bs-content")))
  expect_match(body_text, "This number: beta", fixed = TRUE)
  expect_match(body_text, "Other convention: alpha", fixed = TRUE)
  expect_match(body_text, "Difference: differ only in <units>", fixed = TRUE)
})

test_that("a convention with no glossary entry aborts loudly with a classed error", {
  gl <- .fixture_glossary()
  expect_error(hd_dsr_header_popover("gamma", gl),
               class = "hd_error_dsr_convention_unknown")
  expect_snapshot(error = TRUE, hd_dsr_header_popover("gamma", gl))
})

test_that("a column with no convention, or several, or no glossary entry aborts", {
  gl <- .fixture_glossary()
  expect_error(hd_dsr_header_popover(NA_character_, gl),
               class = "hd_error_dsr_convention_unknown")
  expect_snapshot(error = TRUE, hd_dsr_header_popover(NA_character_, gl))
  expect_snapshot(error = TRUE, hd_dsr_header_popover(c("alpha", "beta"), gl))
  expect_snapshot(error = TRUE, hd_dsr_header_popover("alpha", list()))
})

test_that("popover and container builders reject bad input with classed errors", {
  expect_snapshot(error = TRUE, hd_popover_span("", "t", "<p>x</p>"))
  expect_snapshot(error = TRUE,
                  hd_dt_header_container(c("a", "b"), list(zzz = "<span>x</span>")))
  expect_snapshot(error = TRUE,
                  load_column_glossary(path = "no/such/dir/column_glossary.yaml"))
  tmp <- withr::local_tempfile(fileext = ".yaml")
  writeLines("other: 1", tmp)
  expect_error(load_column_glossary(tmp), class = "hd_error_column_glossary_malformed")
})

test_that("the header container keeps one <th> per column and the popover HTML intact", {
  hdr <- hd_dsr_header_popover("alpha", .fixture_glossary())
  ct <- hd_dt_header_container(c("Strategy", "DSR p-value", "K"), list(`DSR p-value` = hdr))
  doc <- xml2::read_html(paste0("<html><body>", as.character(ct), "</body></html>"))
  ths <- xml2::xml_find_all(doc, "//th")
  expect_length(ths, 3L)
  expect_identical(xml2::xml_text(ths[[1]]), "Strategy")
  span <- xml2::xml_find_first(ths[[2]], ".//span")
  expect_identical(xml2::xml_attr(span, "data-bs-toggle"), "popover")
})

test_that("the shipped glossary covers every DSR convention and links to the details", {
  gl <- load_column_glossary()
  entry <- gl$dsr_pvalue
  expect_setequal(names(entry$conventions), c("multiplier", "statistic-units"))

  urls <- vapply(entry$links, function(l) l$url, character(1))
  expect_true("https://github.com/JohnGavin/historical/tree/main/explorations/dsr_conventions" %in% urls)
  expect_true("https://github.com/JohnGavin/historical/pull/982" %in% urls)
  expect_true("https://github.com/JohnGavin/historical/issues/959" %in% urls)
  expect_true(any(grepl("api-historicaldata.md", urls, fixed = TRUE)))

  for (conv in names(entry$conventions)) {
    node <- .span_node(hd_dsr_header_popover(conv, gl))
    expect_identical(xml2::xml_text(node),
                     paste0("DSR p-value (", entry$conventions[[conv]]$label, ")"))
    body <- .body_doc(xml2::xml_attr(node, "data-bs-content"))
    # every glossary link is rendered as an anchor in the popover body
    expect_length(xml2::xml_find_all(body, "//a"), length(entry$links))
  }
})

test_that("the hurdle_convention values the package emits are the ones the glossary keys on", {
  skip_if_not(file.exists(here::here("packages/historicaldata/R/falsification.R")))
  src <- paste(readLines(here::here("packages/historicaldata/R/falsification.R")), collapse = "\n")
  gl <- load_column_glossary()
  for (conv in names(gl$dsr_pvalue$conventions)) {
    expect_true(grepl(paste0('"', conv, '"'), src, fixed = TRUE),
                info = paste("package never emits hurdle_convention", conv))
  }
})
