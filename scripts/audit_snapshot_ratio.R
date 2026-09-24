#!/usr/bin/env Rscript
# Audit the snapshot-test ratio required by .claude/rules/snapshot-test-policy.md
# (and the global ~/docs_gh/llm/.claude/rules/snapshot-tests-mandatory.md) across
# every tests/testthat/test-*.R file in this repo.
#
# The policy's minimum-ratio rule:
#   1-3 test_that() blocks  -> at least 1 snapshot call
#   4-8 test_that() blocks  -> at least 2 snapshot calls
#   9+  test_that() blocks  -> at least 30% of the block count, as snapshot calls
#
# A "snapshot call" is any of: expect_snapshot, expect_snapshot_value,
# expect_snapshot_file, expect_snapshot_output, expect_snapshot_error,
# expect_snapshot_warning -- bare or namespace-qualified (testthat::expect_snapshot).
#
# Deliberately base R only, no new package dependencies. Files are parsed with
# parse()/the language-object AST (not regex) so that e.g. a snapshot call
# mentioned only in a comment or a string literal is never miscounted.
#
# Usage:
#   Rscript scripts/audit_snapshot_ratio.R [--dirs=d1,d2] [--root=PATH]
#                                           [--out=FILE] [--quiet] [-h|--help]
#
#   --dirs   Comma-separated list of directories (relative to --root, or
#            absolute) to scan for test-*.R files. Default:
#            "tests/testthat,packages/historicaldata/tests/testthat"
#   --root   Repository root used to resolve relative --dirs entries.
#            Default: the parent of this script's own directory.
#   --out    Also write the markdown report to this file.
#   --quiet  Print only the summary line, not the per-file table.
#
# Exit codes (see ~/docs_gh/llm/.claude/rules/exit-code-conventions.md, llm#1140):
#   0  PASS         -- every scanned file meets its minimum-ratio requirement
#   1  FAIL         -- at least one file is below the required ratio
#   2  usage error  -- bad flag, or an explicitly-named directory does not exist
#   3  INDETERMINATE -- zero test files were found, or one or more matched
#                       files could not be parsed (so compliance for those
#                       files is unknown, not "compliant" and not "below")

# ── CLI ──────────────────────────────────────────────────────────────────────

.args_raw <- commandArgs(trailingOnly = TRUE)

.usage <- function() {
  cat(
    "Usage: Rscript scripts/audit_snapshot_ratio.R [--dirs=d1,d2] [--root=PATH] [--out=FILE] [--quiet] [-h|--help]\n",
    file = stderr()
  )
}

if (any(.args_raw %in% c("-h", "--help"))) {
  .usage()
  quit(status = 0L)
}

.get_flag <- function(args, name) {
  hit <- grep(paste0("^--", name, "="), args, value = TRUE)
  if (length(hit) == 0L) return(NULL)
  sub(paste0("^--", name, "="), "", hit[[length(hit)]])
}

.unknown <- Filter(function(a) {
  !grepl("^--(dirs|root|out)=", a) && !(a %in% c("--quiet"))
}, .args_raw)
if (length(.unknown) > 0L) {
  cat("audit_snapshot_ratio.R: unrecognised argument(s): ",
      paste(.unknown, collapse = ", "), "\n", sep = "", file = stderr())
  .usage()
  quit(status = 2L)
}

.quiet <- "--quiet" %in% .args_raw

.script_path <- local({
  a <- commandArgs(trailingOnly = FALSE)
  hit <- grep("^--file=", a, value = TRUE)
  if (length(hit) == 1L) normalizePath(sub("^--file=", "", hit)) else NA_character_
})

.default_root <- if (!is.na(.script_path)) {
  dirname(dirname(.script_path)) # <repo>/scripts/audit_snapshot_ratio.R -> <repo>
} else {
  getwd()
}

.root_arg <- .get_flag(.args_raw, "root")
.root <- if (!is.null(.root_arg)) .root_arg else .default_root

if (!dir.exists(.root)) {
  cat("audit_snapshot_ratio.R: --root does not exist: ", .root, "\n", sep = "", file = stderr())
  quit(status = 2L)
}

.dirs_arg <- .get_flag(.args_raw, "dirs")
.dirs_rel <- if (!is.null(.dirs_arg)) {
  strsplit(.dirs_arg, ",", fixed = TRUE)[[1]]
} else {
  c("tests/testthat", "packages/historicaldata/tests/testthat")
}

.resolve_dir <- function(d) if (isTRUE(grepl("^(/|~)", d))) path.expand(d) else file.path(.root, d)
.dirs <- vapply(.dirs_rel, .resolve_dir, character(1))

.missing_dirs <- .dirs[!dir.exists(.dirs)]
if (length(.missing_dirs) > 0L) {
  cat("audit_snapshot_ratio.R: directory does not exist: ",
      paste(.missing_dirs, collapse = ", "), "\n", sep = "", file = stderr())
  quit(status = 2L)
}

.out_file <- .get_flag(.args_raw, "out")

# ── AST-based counters ───────────────────────────────────────────────────────

SNAPSHOT_FNS <- c(
  "expect_snapshot", "expect_snapshot_value", "expect_snapshot_file",
  "expect_snapshot_output", "expect_snapshot_error", "expect_snapshot_warning"
)

# Name of the function being called in a language `call` object, resolving
# both bare calls (`fn(...)`) and namespace-qualified ones
# (`pkg::fn(...)` / `pkg:::fn(...)`) to the bare function name. Returns
# NA_character_ for anything else (a call through a variable, `(expr)(...)`,
# etc.) -- those simply never match a target name below.
call_name <- function(e) {
  if (!is.call(e)) return(NA_character_)
  head <- e[[1]]
  if (is.symbol(head)) return(as.character(head))
  if (is.call(head) && length(head) == 3L) {
    op <- tryCatch(as.character(head[[1]]), error = function(e) NA_character_)
    if (identical(op, "::") || identical(op, ":::")) {
      return(as.character(head[[3]]))
    }
  }
  NA_character_
}

# Recursively counts test_that()/snapshot/expect_* calls anywhere in a parsed
# expression tree -- including inside for/if/function bodies, so a snapshot
# assertion nested in a loop or a helper closure is still counted.
scan_exprs <- function(exprs) {
  n_test_that <- 0L
  n_snapshot  <- 0L
  n_expect    <- 0L

  # A pairlist entry for a formal argument with no default (e.g. the `y` in
  # `function(x, y) ...`) is R's internal "missing argument" sentinel, not an
  # ordinary empty symbol. Merely *referencing* it once it has been assigned
  # to an ordinary variable (as the `for (item in ...)` loop below does)
  # raises "argument ... is missing, with no default" -- not a real parse
  # problem, just an unfillable leaf with nothing further to descend into.
  # Caught narrowly by message text so any other, genuine error still
  # propagates rather than being silently swallowed.
  recurse <- function(e) {
    tryCatch({
      if (is.call(e)) {
        nm <- call_name(e)
        if (!is.na(nm)) {
          if (identical(nm, "test_that")) n_test_that <<- n_test_that + 1L
          if (nm %in% SNAPSHOT_FNS)       n_snapshot  <<- n_snapshot + 1L
          if (grepl("^expect_", nm))      n_expect    <<- n_expect + 1L
        }
        for (i in seq_along(e)) recurse(e[[i]])
      } else if (is.pairlist(e)) {
        for (item in as.list(e)) recurse(item)
      }
    }, error = function(err) {
      if (!grepl("missing, with no default", conditionMessage(err), fixed = TRUE)) {
        stop(err)
      }
      invisible(NULL)
    })
  }

  for (top in as.list(exprs)) recurse(top)
  list(test_that = n_test_that, snapshot = n_snapshot, expect = n_expect)
}

required_snapshots <- function(n_blocks) {
  if (n_blocks <= 0L) return(0L)
  if (n_blocks <= 3L) return(1L)
  if (n_blocks <= 8L) return(2L)
  as.integer(ceiling(0.30 * n_blocks))
}

audit_file <- function(path, root) {
  rel <- sub(paste0("^", gsub("([][^$.|?*+(){}\\\\])", "\\\\\\1", root), "/?"), "", path)
  parsed <- tryCatch(parse(path, keep.source = FALSE), error = function(e) e)
  if (inherits(parsed, "error")) {
    return(list(file = rel, status = "parse-error", message = conditionMessage(parsed)))
  }
  counts <- scan_exprs(parsed)
  req <- required_snapshots(counts$test_that)
  status <- if (counts$snapshot >= req) "compliant" else "below"
  list(
    file = rel, status = status,
    test_that = counts$test_that, snapshot = counts$snapshot,
    expect = counts$expect, required = req,
    shortfall = max(0L, req - counts$snapshot)
  )
}

# ── Run ──────────────────────────────────────────────────────────────────────

files <- unlist(lapply(.dirs, function(d) {
  list.files(d, pattern = "^test[-_].*\\.R$", full.names = TRUE)
}))
files <- sort(unique(files))

if (length(files) == 0L) {
  cat("audit_snapshot_ratio.R: INDETERMINATE -- no test-*.R files found under: ",
      paste(.dirs_rel, collapse = ", "), "\n", sep = "", file = stderr())
  quit(status = 3L)
}

results <- lapply(files, audit_file, root = .root)

parse_errors <- Filter(function(r) identical(r$status, "parse-error"), results)
compliant    <- Filter(function(r) identical(r$status, "compliant"), results)
below        <- Filter(function(r) identical(r$status, "below"), results)

snapshots_short <- sum(vapply(below, function(r) r$shortfall, integer(1)))

lines <- c(
  "| File | test_that blocks | snapshot calls | total expect_* calls | required | status |",
  "|------|------------------|-----------------|-----------------------|----------|--------|"
)
for (r in results) {
  if (identical(r$status, "parse-error")) {
    lines <- c(lines, sprintf("| %s | -- | -- | -- | -- | PARSE ERROR: %s |", r$file, r$message))
  } else {
    lines <- c(lines, sprintf(
      "| %s | %d | %d | %d | %d | %s |",
      r$file, r$test_that, r$snapshot, r$expect, r$required, r$status
    ))
  }
}

summary_line <- sprintf(
  "files=%d compliant=%d below=%d snapshots_short=%d",
  length(files), length(compliant), length(below), snapshots_short
)

output <- character(0)
if (!.quiet) {
  output <- c(
    "# Snapshot Ratio Audit",
    "",
    sprintf("Generated by `scripts/audit_snapshot_ratio.R` on %s.", Sys.Date()),
    "",
    lines,
    ""
  )
}
if (length(parse_errors) > 0L) {
  output <- c(output, sprintf(
    "INDETERMINATE: %d file(s) could not be parsed: %s",
    length(parse_errors),
    paste(vapply(parse_errors, `[[`, character(1), "file"), collapse = ", ")
  ), "")
}
output <- c(output, summary_line)

cat(paste(output, collapse = "\n"), "\n", sep = "")

if (!is.null(.out_file)) {
  writeLines(c(
    "# Snapshot Ratio Audit",
    "",
    sprintf("Generated by `scripts/audit_snapshot_ratio.R` on %s.", Sys.Date()),
    "",
    lines,
    "",
    if (length(parse_errors) > 0L) c(sprintf(
      "INDETERMINATE: %d file(s) could not be parsed: %s",
      length(parse_errors),
      paste(vapply(parse_errors, `[[`, character(1), "file"), collapse = ", ")
    ), "") else character(0),
    summary_line
  ), .out_file)
}

if (length(parse_errors) > 0L) {
  quit(status = 3L)
} else if (length(below) > 0L) {
  quit(status = 1L)
} else {
  quit(status = 0L)
}
