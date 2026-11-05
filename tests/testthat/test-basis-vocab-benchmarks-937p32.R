testthat::local_edition(3)

# #937 phase 3 item 2: benchmarks and non-strategy series (SPY, market, asset
# panels) get their basis from ONE home, the hd_return_basis() registry, rather
# than from an `NA_character_` "no label" bypass plus a free-text annotation.
#
#   (1) every `# basis: total (<label>)` comment ANYWHERE in R/ names a label
#       registered with basis total (item 1's test only covers comments on
#       sharpe_ratio_rf() call lines);
#   (2) no code passes `NA_character_` as a basis label (the old benchmark
#       bypass in .aw_excess_series() and rsc_metrics' calc_metrics());
#   (3) .aw_excess_series() classifies a benchmark through a registered label
#       and refuses NA.
# Classification only: the benchmark's rf-deducted value is unchanged.

pkg_path <- if (dir.exists(here::here("packages/historicaldata"))) {
  here::here("packages/historicaldata")
} else {
  file.path(dirname(here::here()), "packages/historicaldata")
}
suppressMessages(pkgload::load_all(pkg_path, quiet = TRUE))
source(here::here("R/plan_avoid_worst.R"))

.src_files <- c(
  list.files(here::here("R"), pattern = "\\.R$", full.names = TRUE),
  list.files(here::here("packages/historicaldata/R"), pattern = "\\.R$",
             full.names = TRUE)
)

# Annotation labels and NA-label uses in `lines` (pure; used with a positive
# control below).
.scan_vocab <- function(lines, file = "<text>") {
  ann_re <- "#\\s*basis:\\s*total\\s*\\(([^)]*(\\([^)]*\\))?[^)]*)\\)"
  m <- regmatches(lines, regexec(ann_re, lines))
  ann <- vapply(m, function(x) if (length(x) >= 2L) x[2] else NA_character_,
                character(1))
  list(
    annotations = data.frame(file = rep(file, sum(!is.na(ann))),
                             line = which(!is.na(ann)),
                             label = ann[!is.na(ann)], stringsAsFactors = FALSE),
    na_label = which(grepl("(registry_label|strategy)\\s*=\\s*NA_character_|,\\s*NA_character_\\)\\$ret|^\\s*NA_character_\\)\\$ret", lines))
  )
}

test_that("scanner: positive control finds an unregistered annotation and an NA label", {
  got <- .scan_vocab(c(
    "x <- 1  # basis: total (Nope)",
    "y <- 2  # basis: total (Value (HML))",
    "f(registry_label = NA_character_, rf_vec = z)"
  ))
  expect_identical(got$annotations$label, c("Nope", "Value (HML)"))
  expect_identical(got$na_label, 3L)
})

test_that("every '# basis: total (<label>)' in R/ names a label registered as total", {
  total_labels <- hd_return_basis()$strategy[hd_return_basis()$basis == "total"]
  ann <- do.call(rbind, lapply(.src_files, function(p) {
    .scan_vocab(readLines(p, warn = FALSE), basename(p))$annotations
  }))
  expect_gt(nrow(ann), 10L)
  bad <- ann[!(ann$label %in% total_labels), ]
  expect_identical(
    nrow(bad), 0L,
    info = paste0("Unregistered basis label(s): ",
                  paste0(bad$file, ":", bad$line, " '", bad$label, "'", collapse = "; "))
  )
})

test_that("no code passes NA_character_ as a basis label (benchmarks use the registry)", {
  hits <- unlist(lapply(.src_files, function(p) {
    l <- .scan_vocab(readLines(p, warn = FALSE))$na_label
    if (length(l)) paste0(basename(p), ":", l)
  }))
  expect_identical(hits, NULL)
})

test_that(".aw_excess_series: a benchmark is classified by its registered label; NA aborts", {
  d <- as.Date("2020-01-01") + 0:9
  rf <- tibble::tibble(date = d, rf_ret = 0.0002)
  r <- seq(0.001, 0.01, length.out = 10L)
  expect_equal(.aw_excess_series(d, r, rf, "Research: ETF buy and hold")$ret,
               r - 0.0002)
  expect_error(.aw_excess_series(d, r, rf, NA_character_))
})

# #937 phase 3 item 2, excess side: the Fama-French Mkt-RF benchmark (DRIF,
# Factor MAX) is registered as excess rather than hard-coded "no rf" with a
# free-text "tracked in #937" note. Every `# basis: excess (<label>)` comment
# must name a label registered as excess.
.scan_excess <- function(lines, file = "<text>") {
  ann_re <- "#\\s*basis:\\s*excess\\s*\\(([^()]*(\\([^)]*\\))?[^()]*)\\)"
  m <- regmatches(lines, regexec(ann_re, lines))
  ann <- vapply(m, function(x) if (length(x) >= 2L) x[2] else NA_character_,
                character(1))
  data.frame(file = rep(file, sum(!is.na(ann))), line = which(!is.na(ann)),
             label = ann[!is.na(ann)], stringsAsFactors = FALSE)
}

test_that("excess scanner: positive control reads nested-parenthesis labels", {
  got <- .scan_excess(c(
    "# basis: excess (Benchmark: Fama-French Mkt-RF (market excess))",
    "# basis: excess (Nope)",
    "# basis: total (Value (HML))"
  ))
  expect_identical(got$label,
                   c("Benchmark: Fama-French Mkt-RF (market excess)", "Nope"))
})

test_that("every '# basis: excess (<label>)' in R/ names a label registered as excess", {
  reg <- hd_return_basis()
  excess_labels <- reg$strategy[reg$basis == "excess"]
  ann <- do.call(rbind, lapply(.src_files, function(p) {
    .scan_excess(readLines(p, warn = FALSE), basename(p))
  }))
  expect_gte(nrow(ann), 2L)  # the DRIF and Factor MAX benchmark sites
  bad <- ann[!(ann$label %in% excess_labels), ]
  expect_identical(
    nrow(bad), 0L,
    info = paste0("Unregistered excess label(s): ",
                  paste0(bad$file, ":", bad$line, " '", bad$label, "'", collapse = "; "))
  )
})

test_that("Mkt-RF benchmark is excess in the registry: zero rf, Sharpe unchanged", {
  lab <- "Benchmark: Fama-French Mkt-RF (market excess)"
  expect_identical(hd_return_basis_of(lab), "excess")
  rf <- rep(0.003, 24L)
  expect_identical(hd_rf_for_basis(rf, lab), rep(0, 24L))
})

test_that("no 'registry vocabulary ... tracked in #937' placeholder remains", {
  hits <- unlist(lapply(.src_files, function(p) {
    l <- grep("registry vocabulary for benchmarks tracked in #937",
              readLines(p, warn = FALSE), fixed = TRUE)
    if (length(l)) paste0(basename(p), ":", l)
  }))
  expect_identical(hits, NULL)
})
