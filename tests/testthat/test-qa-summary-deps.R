testthat::local_edition(3)

# ── qa_summary dependency completeness ───────────────────────────────────────
#
# Tripwire: every tar_target(*_metrics) defined across R/plan_*.R must appear
# in the qa_summary dependency list, and vice versa.
#
# WHY: qa_summary is the QA pipeline-completion gate. If a new *_metrics
# target is added without updating qa_summary, the false-positive QA
# regression from roborev #2788 can silently recur.
#
# HOW: both sets are derived from source text, so the test stays in sync
# automatically as plan files evolve.

# Helper: extract all target names matching *_metrics from a set of R files.
#
# Uses AST-based extraction (parse() + recursive walk) instead of line-by-line
# regex.  This correctly handles multiline tar_target() definitions such as:
#
#   targets::tar_target(
#         te_ir_metrics,         # plan_integration.R:150-151
#   tar_target(
#       persistence_metrics,     # plan_momentum_decomposition.R:61-62
#
# A line-based regex misses both of these because the target name is on the
# line *after* the tar_target( open — fixes roborev #3130.
extract_defined_metrics <- function(plan_dir) {
  plan_files <- list.files(plan_dir, pattern = "^plan_.*\\.R$", full.names = TRUE)
  out <- character(0)

  walk <- function(e) {
    if (is.call(e)) {
      head <- e[[1L]]
      # Accept both  tar_target(...)  and  targets::tar_target(...)
      is_tar <- (is.symbol(head) && identical(as.character(head), "tar_target")) ||
                (is.call(head) && length(head) == 3L &&
                 identical(head[[1L]], as.symbol("::")) &&
                 identical(head[[2L]], as.symbol("targets")) &&
                 identical(head[[3L]], as.symbol("tar_target")))
      if (is_tar && length(e) >= 2L) {
        nm <- e[[2L]]
        if (is.symbol(nm)) {
          s <- as.character(nm)
          if (grepl("_metrics$", s)) out[[length(out) + 1L]] <<- s
        }
      }
      # Recurse into every sub-expression
      for (i in seq_along(e)) walk(e[[i]])
    }
  }

  for (path in plan_files) {
    exprs <- tryCatch(
      parse(file = path, keep.source = FALSE),
      error = function(e) {
        warning("Parse error in ", basename(path), ": ", conditionMessage(e))
        NULL
      }
    )
    if (!is.null(exprs)) for (e in exprs) walk(e)
  }

  sort(unique(out))
}

# Helper: extract targets listed inside qa_summary's invisible(list(...)) block
extract_declared_metrics <- function(qa_vignette_path) {
  lines <- readLines(qa_vignette_path, warn = FALSE)

  # Find the invisible(list( ... )) block inside qa_summary
  start <- grep("invisible\\(list\\(", lines)
  stop  <- grep("^\\s*\\)\\)", lines)

  if (length(start) == 0 || length(stop) == 0) {
    return(character(0))
  }

  # Take lines between the first invisible(list( and the first closing ))
  block_start <- start[[1]]
  block_end   <- stop[stop > block_start][[1]]
  block <- lines[seq(block_start, block_end)]

  # Extract bare symbol names that end in _metrics (strip comments, whitespace)
  block_clean <- sub("#.*$", "", block)  # strip inline comments
  tokens <- unlist(strsplit(block_clean, "[,\\s\\(\\)]+", perl = TRUE))
  tokens <- trimws(tokens)
  tokens <- tokens[nzchar(tokens)]
  metrics <- grep("^[a-z][a-z0-9_]*_metrics$", tokens, value = TRUE)
  sort(unique(metrics))
}

# ── Tests ─────────────────────────────────────────────────────────────────────

# Regression guard for roborev #3130: the AST extractor must find multiline
# tar_target() definitions that the old line-regex missed.  If someone regresses
# extract_defined_metrics() back to a line-based regex these two assertions will
# fail immediately.
test_that("extract_defined_metrics catches multiline tar_target() definitions (roborev #3130)", {
  plan_dir <- here::here("R")
  defined  <- extract_defined_metrics(plan_dir)

  # te_ir_metrics: defined across two lines in plan_integration.R (targets::tar_target)
  # and plan_te_ir.R (tar_target) — both were invisible to the old line regex.
  expect_true(
    "te_ir_metrics" %in% defined,
    label = "te_ir_metrics present (multiline targets:: form — plan_integration.R:150-151)"
  )
  # persistence_metrics: defined across two lines in plan_momentum_decomposition.R
  expect_true(
    "persistence_metrics" %in% defined,
    label = "persistence_metrics present (multiline form — plan_momentum_decomposition.R:61-62)"
  )
})

test_that("qa_summary declares every *_metrics target defined in plan files", {
  plan_dir    <- here::here("R")
  qa_vignette <- here::here("R/plan_qa_vignette.R")

  defined  <- extract_defined_metrics(plan_dir)
  declared <- extract_declared_metrics(qa_vignette)

  missing_from_qa <- setdiff(defined, declared)
  expect_equal(
    missing_from_qa,
    character(0),
    info = paste0(
      "These *_metrics targets exist in plan files but are NOT listed in qa_summary:\n  ",
      paste(missing_from_qa, collapse = "\n  "),
      "\nAdd them to the invisible(list(...)) block in plan_qa_vignette.R."
    )
  )
})

test_that("qa_summary has no *_metrics entries that lack a tar_target definition", {
  plan_dir    <- here::here("R")
  qa_vignette <- here::here("R/plan_qa_vignette.R")

  defined  <- extract_defined_metrics(plan_dir)
  declared <- extract_declared_metrics(qa_vignette)

  stale_in_qa <- setdiff(declared, defined)
  expect_equal(
    stale_in_qa,
    character(0),
    info = paste0(
      "These names are listed in qa_summary but have no tar_target(*_metrics) definition:\n  ",
      paste(stale_in_qa, collapse = "\n  "),
      "\nRemove stale entries from plan_qa_vignette.R."
    )
  )
})
