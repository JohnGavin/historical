testthat::local_edition(3)
# #657 lint-style guard: every `inner_join(` call in R/ and
# packages/historicaldata/R/ must be listed in
# tests/testthat/inner_join_allowlist.tsv with a classification and a reason.
#
# Why: an inner_join across period-keyed series silently deletes a period for
# every constituent (#641: 18% of a published series' months). Each site was
# measured once (docs/inner-join-audit-657.md); this test makes the next
# site a visible, reviewed decision instead of a fresh unmeasured prior. It
# does NOT decide whether a new join is safe -- the reason column is where
# the author states the measured dropped count.
#
# Matching is by (file, ordinal, code): the n-th non-comment `inner_join(` in
# a file plus its trimmed source line. Inserting a join before another one in
# the same file shifts the ordinals and the code text, so the entries have to
# be re-checked, not silently re-numbered.

ALLOW_CLASSES   <- c("CONFIRMED", "LATENT", "BENIGN", "INDETERMINATE", "AUDITED")
ALLOW_CONSUMERS <- c("published-metric", "published-diagnostic", "unpublished", "dead")
SCAN_DIRS       <- c("R", "packages/historicaldata/R")

scan_inner_joins <- function(root, dirs = SCAN_DIRS) {
  rows <- list()
  for (d in dirs) {
    files <- sort(list.files(file.path(root, d), pattern = "\\.R$", full.names = FALSE))
    for (f in files) {
      lines <- readLines(file.path(root, d, f), warn = FALSE)
      code  <- trimws(gsub("\t", " ", lines, fixed = TRUE))
      hit   <- which(!grepl("^#", code) & grepl("inner_join[[:space:]]*\\(", code))
      for (k in seq_along(hit)) {
        rows[[length(rows) + 1L]] <- data.frame(
          file = paste0(d, "/", f), ordinal = k, code = code[hit[k]],
          stringsAsFactors = FALSE
        )
      }
    }
  }
  if (length(rows) == 0L) {
    return(data.frame(file = character(), ordinal = integer(), code = character(),
                      stringsAsFactors = FALSE))
  }
  do.call(rbind, rows)
}

read_allowlist <- function(path) {
  lines <- readLines(path, warn = FALSE)
  lines <- lines[nzchar(trimws(lines)) & !grepl("^#", lines)]
  parts <- strsplit(lines, "\t", fixed = TRUE)
  n <- vapply(parts, length, integer(1))
  if (any(n != 7L)) {
    stop("inner_join_allowlist.tsv: every line needs 7 tab-separated columns; bad line(s): ",
         paste(which(n != 7L), collapse = ", "))
  }
  m <- do.call(rbind, parts)
  data.frame(file = m[, 1], ordinal = as.integer(m[, 2]), code = m[, 3],
             class = m[, 4], target = m[, 5], consumer = m[, 6], reason = m[, 7],
             stringsAsFactors = FALSE)
}

# Returns the keys that fail each condition. Pure, so it can be falsified.
check_allowlist <- function(sites, allow) {
  key <- function(d) paste(d$file, d$ordinal, d$code, sep = "\t")
  list(
    unlisted  = key(sites)[!key(sites) %in% key(allow)],
    stale     = key(allow)[!key(allow) %in% key(sites)],
    duplicate = key(allow)[duplicated(key(allow))],
    bad_class = allow$file[!allow$class %in% ALLOW_CLASSES],
    bad_consumer = allow$file[!allow$consumer %in% ALLOW_CONSUMERS],
    thin_reason = allow$file[nchar(trimws(allow$reason)) < 25L | nchar(trimws(allow$target)) < 1L]
  )
}

root  <- here::here()
sites <- scan_inner_joins(root)
allow <- read_allowlist(file.path(root, "tests", "testthat", "inner_join_allowlist.tsv"))
chk   <- check_allowlist(sites, allow)

test_that("the scan and the allow-list are not thin (a vacuous pass is not a pass)", {
  expect_gte(nrow(sites), 20L)
  expect_gte(nrow(allow), 20L)
})

test_that("every inner_join( in R/ and packages/historicaldata/R/ is in the allow-list", {
  expect_equal(
    chk$unlisted, character(),
    info = paste0(
      "Unlisted inner_join site(s) (file, ordinal, code):\n  ",
      paste(gsub("\t", " | ", chk$unlisted), collapse = "\n  "),
      "\nMeasure the dropped count on the join key (docs/inner-join-audit-657.md), ",
      "then add a line to tests/testthat/inner_join_allowlist.tsv with a class and reason."
    )
  )
})

test_that("the allow-list has no stale or duplicate entries", {
  expect_equal(chk$stale, character(), info = paste(gsub("\t", " | ", chk$stale), collapse = "\n"))
  expect_equal(chk$duplicate, character())
})

test_that("every entry has a valid class, consumer and a real reason", {
  expect_equal(chk$bad_class, character())
  expect_equal(chk$bad_consumer, character())
  expect_equal(chk$thin_reason, character())
})

test_that("every CONFIRMED or LATENT entry says what was measured or what is missing", {
  flagged <- allow[allow$class %in% c("CONFIRMED", "LATENT"), ]
  expect_gt(nrow(flagged), 0L)
  expect_true(all(grepl("[0-9]", flagged$reason)))
})

# -- Positive controls: the guard must be able to go red ---------------------

test_that("control: a new unlisted inner_join( site is detected", {
  tmp <- withr::local_tempdir()
  dir.create(file.path(tmp, "R"))
  writeLines(c(
    "f <- function(a, b) {",
    "  a |> dplyr::inner_join(b, by = \"ym\")",
    "}"
  ), file.path(tmp, "R", "fake.R"))
  fake <- scan_inner_joins(tmp, dirs = "R")
  expect_equal(nrow(fake), 1L)
  res <- check_allowlist(fake, allow)
  expect_length(res$unlisted, 1L)
})

test_that("control: comments, roxygen and prose mentions are not sites", {
  tmp <- withr::local_tempdir()
  dir.create(file.path(tmp, "R"))
  writeLines(c(
    "# inner_join(a, b) was replaced by a spine",
    "#' used to chain four `inner_join()`s",
    "msg <- \"dropped by inner_join.\"",
    "x <- 1"
  ), file.path(tmp, "R", "fake.R"))
  expect_equal(nrow(scan_inner_joins(tmp, dirs = "R")), 0L)
})

test_that("control: editing a listed join's code makes its entry stale and the site unlisted", {
  # Built from the allow-list itself, so this control does not depend on the
  # real tree being clean.
  moved <- allow[, c("file", "ordinal", "code")]
  moved$code[1] <- paste0(moved$code[1], " # edited")
  res <- check_allowlist(moved, allow)
  expect_length(res$unlisted, 1L)
  expect_length(res$stale, 1L)
})

test_that("control: an empty reason or an unknown class is rejected", {
  bad <- allow
  bad$reason[1] <- ""
  bad$class[2]  <- "SAFE"
  res <- check_allowlist(allow[, c("file", "ordinal", "code")], bad)
  expect_equal(res$thin_reason[1], bad$file[1])
  expect_equal(res$bad_class[1], bad$file[2])
})
