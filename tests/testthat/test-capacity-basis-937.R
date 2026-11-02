testthat::local_edition(3)
# #937 item 4 row 3: hd_capacity_curve() computes mean/sd of whatever monthly
# series it is handed, with NO risk-free rate. That is a correct EXCESS-basis
# Sharpe only if the series is excess; the function cannot tell. The owner
# decision is to add NO rf argument and instead make every wiring declare the
# basis of the series it passes:
#   hd_capacity_curve(...)  # basis: <label registered in hd_return_basis()>
# on the call's first line, where the label names the strategy whose EXCESS
# series (hd_excess_returns(), or an excess-basis row as is) is passed.
# An unlabelled or unregistered call fails this test. Today there are no
# callers outside examples/tests (the scan below is honest about that count).
# Scope: static; `tests/` is not scanned. It checks that a basis is declared
# and registered, NOT that the declared one is the right one for the series.

pkg_path <- if (dir.exists(here::here("packages/historicaldata"))) {
  here::here("packages/historicaldata")
} else {
  file.path(dirname(here::here()), "packages/historicaldata")
}
suppressMessages(pkgload::load_all(pkg_path, quiet = TRUE))

.BASIS_RE <- "#\\s*basis:\\s*(.+?)\\s*$"

# One row per call to hd_capacity_curve() in `lines`. R files are parsed (so a
# call in a comment or string is not counted and a multi-line call is found);
# other files (qmd) are matched line by line.
.cap_scan_text <- function(lines, file = "<text>", parse_r = TRUE) {
  if (parse_r) {
    exprs <- parse(text = lines, keep.source = TRUE)
    pd <- utils::getParseData(exprs)
    at <- sort(pd$line1[pd$token == "SYMBOL_FUNCTION_CALL" & pd$text == "hd_capacity_curve"])
  } else {
    at <- grep("hd_capacity_curve\\s*\\(", lines)
  }
  if (length(at) == 0L) return(NULL)
  do.call(rbind, lapply(at, function(i) {
    m <- regmatches(lines[i], regexec(.BASIS_RE, lines[i]))[[1]]
    data.frame(file = file, line = i,
               label = if (length(m) == 2L) m[2] else NA_character_,
               stringsAsFactors = FALSE)
  }))
}

.cap_bad <- function(sites) {
  if (is.null(sites)) return(sites)
  reg <- hd_return_basis()$strategy
  sites[is.na(sites$label) | !(sites$label %in% reg), , drop = FALSE]
}

repo_root <- here::here()
r_paths <- c(
  list.files(file.path(repo_root, "R"), pattern = "\\.R$", full.names = TRUE),
  list.files(file.path(repo_root, "packages/historicaldata/R"), pattern = "\\.R$", full.names = TRUE),
  list.files(file.path(repo_root, "scripts"), pattern = "\\.R$", full.names = TRUE, recursive = TRUE),
  list.files(file.path(repo_root, "docs"), pattern = "\\.R$", full.names = TRUE)
)
q_paths <- list.files(file.path(repo_root, "docs"), pattern = "\\.qmd$", full.names = TRUE, recursive = TRUE)

real_sites <- do.call(rbind, c(
  lapply(r_paths, function(p) .cap_scan_text(readLines(p, warn = FALSE), basename(p))),
  lapply(q_paths, function(p) .cap_scan_text(readLines(p, warn = FALSE), basename(p), parse_r = FALSE))
))

test_that("scanner positive control: labelled, unlabelled and unregistered calls are told apart", {
  src <- c(
    "a <- hd_capacity_curve(r, g, 1e7, 1)  # basis: Mom 12-2",
    "b <- hd_capacity_curve(r, g, 1e7, 1)",
    "c <- hd_capacity_curve(r, g, 1e7, 1)  # basis: Not A Strategy",
    "d <- hd_capacity_curve(",
    "  r, g, 1e7, 1",
    ")",
    "# hd_capacity_curve(r) in a comment is not a call",
    "e <- 'hd_capacity_curve(r)'"
  )
  got <- .cap_scan_text(src)
  expect_identical(got$line, c(1L, 2L, 3L, 4L))
  expect_identical(got$label, c("Mom 12-2", NA, "Not A Strategy", NA))
  bad <- .cap_bad(got)
  expect_identical(bad$line, c(2L, 3L, 4L))   # only line 1 passes
})

test_that("scanner reads real files: it parses the repo's R sources (not vacuous)", {
  expect_gt(length(r_paths), 50L)
  # The scanner must also see the DEFINITION file without miscounting it as a call.
  def <- .cap_scan_text(readLines(file.path(repo_root, "packages/historicaldata/R/capacity.R"), warn = FALSE))
  expect_null(def)
})

test_that("every hd_capacity_curve() call declares a registered basis on its first line", {
  bad <- .cap_bad(real_sites)
  expect_identical(
    NROW(bad), 0L,
    info = paste0("Call(s) with no registered '# basis: <label>': ",
                  paste0(bad$file, ":", bad$line, collapse = "; "),
                  ". hd_capacity_curve() has no rf argument; declare the basis of the series you pass.")
  )
})

test_that("hd_capacity_curve() has no rf argument and its docs state the input basis", {
  expect_false(any(grepl("rf|risk", names(formals(hd_capacity_curve)), ignore.case = TRUE)))
  txt <- paste(readLines(file.path(pkg_path, "man/hd_capacity_curve.Rd"), warn = FALSE),
               collapse = " ")
  expect_match(txt, "return basis", fixed = TRUE)
  expect_match(txt, "hd_return_basis", fixed = TRUE)
  expect_match(txt, "NO risk-free", fixed = TRUE)
})
