testthat::local_edition(3)

# #937 phase 3 item 1: every `sharpe_ratio_rf()` call in R/ and
# packages/historicaldata/R/ must either
#   (a) take an rf argument routed through `hd_rf_for_basis()` (inline, or a
#       variable assigned from it in the same function), or
#   (b) carry a `# basis: total (<label>)` comment on the call's first line,
#       where <label> is registered in `hd_return_basis()` with basis "total"
#       (a total-return series SHOULD have the raw rf deducted), or
#   (c) be listed in KNOWN_UNCLASSIFIED below, with the reason it cannot yet
#       be classified.
# Scope: static, parse-based (not a line match, so multi-line calls count).
# `tests/` is not scanned. This does NOT prove the routed label is the right
# one for the series, only that the basis decision is visible and registered.

pkg_path <- if (dir.exists(here::here("packages/historicaldata"))) {
  here::here("packages/historicaldata")
} else {
  file.path(dirname(here::here()), "packages/historicaldata")
}
suppressMessages(pkgload::load_all(pkg_path, quiet = TRUE))

.is_empty_arg <- function(x) identical(x, quote(expr = ))

.children <- function(e) {
  l <- as.list(e)
  keep <- vapply(seq_along(l), function(i) !.is_empty_arg(l[[i]]), logical(1))
  l[keep]
}

.has_routed <- function(e) {
  if (!is.call(e)) return(FALSE)
  if (is.symbol(e[[1]]) && identical(as.character(e[[1]]), "hd_rf_for_basis")) {
    return(TRUE)
  }
  any(vapply(.children(e), .has_routed, logical(1)))
}

.sym_routed <- function(scope, sym) {
  found <- FALSE
  walk <- function(e) {
    if (found || !is.call(e)) return(invisible())
    h <- e[[1]]
    if (is.symbol(h) && as.character(h) %in% c("<-", "=", "<<-") &&
        length(e) >= 3L && is.symbol(e[[2]]) &&
        identical(as.character(e[[2]]), sym) && .has_routed(e[[3]])) {
      found <<- TRUE
      return(invisible())
    }
    for (x in .children(e)) walk(x)
  }
  walk(scope)
  found
}

# All calls to sharpe_ratio_rf() in `exprs`, in source order, each with its
# rf argument and the nearest enclosing function (or top-level expression).
.collect_calls <- function(exprs) {
  hits <- list()
  walk <- function(e, scope) {
    if (!is.call(e)) return(invisible())
    h <- e[[1]]
    if (is.symbol(h) && identical(as.character(h), "sharpe_ratio_rf")) {
      hits[[length(hits) + 1L]] <<- list(call = e, scope = scope)
    }
    if (is.symbol(h) && identical(as.character(h), "function")) scope <- e
    for (x in .children(e)) walk(x, scope)
  }
  for (e in as.list(exprs)) walk(e, e)
  hits
}

.rf_arg <- function(call) {
  args <- as.list(call)[-1]
  nm <- names(args)
  if (is.null(nm)) nm <- rep("", length(args))
  if ("rf" %in% nm) return(args[["rf"]])
  pos <- args[nm == ""]
  if (length(pos) >= 2L) pos[[2]] else NULL
}

# Scan source text; returns one row per call.
.rf_scan_text <- function(lines, file = "<text>") {
  exprs <- parse(text = lines, keep.source = TRUE)
  pd <- utils::getParseData(exprs)
  call_lines <- sort(pd$line1[pd$token == "SYMBOL_FUNCTION_CALL" &
                                pd$text == "sharpe_ratio_rf"])
  hits <- .collect_calls(exprs)
  if (length(hits) != length(call_lines)) {
    stop("scanner mismatch in ", file, ": ", length(hits), " calls walked vs ",
         length(call_lines), " in parse data")
  }
  rows <- lapply(seq_along(hits), function(i) {
    rf <- .rf_arg(hits[[i]]$call)
    status <- if (is.null(rf)) {
      "unrouted"
    } else if (.has_routed(rf)) {
      "routed"
    } else if (is.symbol(rf) && .sym_routed(hits[[i]]$scope, as.character(rf))) {
      "routed"
    } else {
      "unrouted"
    }
    src <- lines[call_lines[i]]
    m <- regmatches(src, regexec("#\\s*basis:\\s*total\\s*\\((.+)\\)\\s*$", src))[[1]]
    data.frame(
      file = file, line = call_lines[i], status = status,
      rf = if (is.null(rf)) "<none>" else paste(deparse(rf), collapse = ""),
      label = if (length(m) == 2L) m[2] else NA_character_,
      stringsAsFactors = FALSE
    )
  })
  if (length(rows) == 0L) return(NULL)
  do.call(rbind, rows)
}

.rf_scan_files <- function(paths) {
  out <- lapply(paths, function(p) {
    .rf_scan_text(readLines(p, warn = FALSE), file = basename(p))
  })
  do.call(rbind, out)
}

# Sites that cannot yet be classified. Key: "<file>::<rf argument text>".
# Every entry states why; a stale entry (site now routed/annotated, or gone)
# fails the test below so this list cannot rot.
KNOWN_UNCLASSIFIED <- c(
  "plan_backtest.R::df$rf_ret" = paste(
    "INDETERMINATE (#937 phase 3 item 4): .bt_sharpe_rf() deducts raw rf from",
    "bt_expanding$actual_return / benchmark_return; the basis of that series",
    "is not established, so it is neither routed nor annotated total."
  )
)

repo_root <- here::here()
scan_paths <- c(
  list.files(file.path(repo_root, "R"), pattern = "\\.R$", full.names = TRUE),
  list.files(file.path(repo_root, "packages/historicaldata/R"),
             pattern = "\\.R$", full.names = TRUE)
)
scan_paths <- scan_paths[!grepl("(^|/)tests/", scan_paths)]
sites <- .rf_scan_files(scan_paths)
sites$key <- paste0(sites$file, "::", sites$rf)

test_that("scanner: positive control classifies routed, annotated and unrouted calls", {
  src <- c(
    "f <- function(r, rf) {",
    "  a <- sharpe_ratio_rf(r, hd_rf_for_basis(rf, 'LTR'), periods_per_year = 12L)",
    "  rf2 <- hd_rf_for_basis(rf, 'LTR')",
    "  b <- sharpe_ratio_rf(r, rf2, periods_per_year = 12L)",
    "  c <- sharpe_ratio_rf(r, rf, periods_per_year = 12L)  # basis: total (TOM)",
    "  d <- sharpe_ratio_rf(r, rf, periods_per_year = 12L)",
    "}"
  )
  got <- .rf_scan_text(src)
  expect_identical(got$status, c("routed", "routed", "unrouted", "unrouted"))
  expect_identical(got$label, c(NA, NA, "TOM", NA))
})

test_that("scanner: an rf variable assigned in a DIFFERENT function is not routed", {
  src <- c(
    "g <- function(rf) { rf2 <- hd_rf_for_basis(rf, 'LTR'); rf2 }",
    "h <- function(r, rf2) sharpe_ratio_rf(r, rf2, periods_per_year = 12L)"
  )
  expect_identical(.rf_scan_text(src)$status, "unrouted")
})

test_that("scanner reads real files: it finds the sites it is meant to guard (not vacuous)", {
  expect_gt(nrow(sites), 20L)
  expect_true(all(c("routed", "unrouted") %in% sites$status))
  expect_true("plan_turn_of_month.R" %in% sites$file)
})

test_that("every sharpe_ratio_rf() call is routed, annotated total, or a stated exception", {
  bad <- sites[sites$status == "unrouted" & is.na(sites$label) &
                 !(sites$key %in% names(KNOWN_UNCLASSIFIED)), ]
  expect_identical(
    nrow(bad), 0L,
    info = paste0("Unrouted, unannotated sharpe_ratio_rf() call(s): ",
                  paste0(bad$file, ":", bad$line, " rf=", bad$rf, collapse = "; "),
                  ". Route rf through hd_rf_for_basis(), or add ",
                  "'# basis: total (<registered label>)' if the series is total.")
  )
})

test_that("every '# basis: total (<label>)' names a label registered with basis total", {
  ann <- sites[!is.na(sites$label), ]
  expect_gt(nrow(ann), 0L)
  reg <- hd_return_basis()
  total_labels <- reg$strategy[reg$basis == "total"]
  bad <- ann[!(ann$label %in% total_labels), ]
  expect_identical(
    nrow(bad), 0L,
    info = paste0("Annotation label not registered as total: ",
                  paste0(bad$file, ":", bad$line, " '", bad$label, "'", collapse = "; "))
  )
})

test_that("an annotation never sits on a call whose rf is already routed", {
  both <- sites[sites$status == "routed" & !is.na(sites$label), ]
  expect_identical(nrow(both), 0L)
})

test_that("KNOWN_UNCLASSIFIED has no stale entries and every entry has a reason", {
  expect_true(all(nzchar(KNOWN_UNCLASSIFIED)))
  live <- sites$key[sites$status == "unrouted" & is.na(sites$label)]
  stale <- setdiff(names(KNOWN_UNCLASSIFIED), live)
  expect_identical(stale, character(0))
})
