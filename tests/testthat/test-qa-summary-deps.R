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
#   tar_target(
#       persistence_metrics,     # plan_momentum_decomposition.R:61-62
#
# A line-based regex misses this because the target name is on the line *after*
# the tar_target( open — fixes roborev #3130.
#
# FILTER: only plan files that are source()d in docs/_targets.R are walked.
# Plan files that exist on disk but are NOT wired in (e.g. plan_te_ir.R,
# plan_integration.R) are excluded — their targets never enter the live
# pipeline and must NOT appear in qa_summary.
extract_defined_metrics <- function(plan_dir = here::here("R"),
                                    targets_r_path = here::here("docs/_targets.R")) {
  # plan_dir is kept for backwards-compatibility but the canonical list of
  # files to walk comes from docs/_targets.R, not a directory glob.
  # This ensures that plan files on disk but not sourced (plan_te_ir.R,
  # plan_integration.R) are excluded from the result.
  #
  # AST-walk docs/_targets.R to find source() calls — handles multi-line
  # source() definitions and correctly excludes commented-out source() calls
  # (which regex on active_lines cannot do reliably when comments are inline
  # rather than line-leading).
  targets_exprs <- tryCatch(
    parse(file = targets_r_path, keep.source = FALSE),
    error = function(e) {
      testthat::fail(paste0(
        "Fatal: could not parse ", targets_r_path, "\n",
        conditionMessage(e)
      ))
    }
  )

  sourced_paths <- character(0)
  find_sources <- function(e) {
    if (!is.call(e)) return()
    head <- e[[1L]]
    is_source <- is.symbol(head) && identical(as.character(head), "source")
    if (is_source && length(e) >= 2L) {
      arg <- e[[2L]]
      # Handle: source("R/plan_foo.R")  or  source(here::here("R/plan_foo.R"))
      path_str <- NULL
      if (is.character(arg)) {
        path_str <- arg
      } else if (is.call(arg)) {
        # Detect here::here("R/plan_foo.R") — the last string argument is the path
        str_args <- Filter(is.character, as.list(arg))
        if (length(str_args) > 0L) path_str <- str_args[[length(str_args)]]
      }
      if (!is.null(path_str) && grepl("^R/plan_.*\\.R$", path_str)) {
        sourced_paths[[length(sourced_paths) + 1L]] <<- path_str
      }
    }
    # Recurse into every sub-expression
    for (i in seq_along(e)) find_sources(e[[i]])
  }
  for (e in targets_exprs) find_sources(e)

  plan_files <- file.path(here::here(), sourced_paths)
  plan_files <- plan_files[file.exists(plan_files)]
  out <- character(0)
  parse_errors <- character(0)

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
        parse_errors[[length(parse_errors) + 1L]] <<- paste0(
          basename(path), ": ", conditionMessage(e)
        )
        NULL
      }
    )
    if (!is.null(exprs)) for (e in exprs) walk(e)
  }

  # Fail loudly — a parse error means the test cannot guarantee completeness.
  # Silently skipping would defeat the purpose of this tripwire.
  if (length(parse_errors) > 0L) {
    testthat::fail(paste0(
      "Fatal parse error(s) in plan file(s) — qa_summary completeness cannot be verified:\n  ",
      paste(parse_errors, collapse = "\n  ")
    ))
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
# extract_defined_metrics() back to a line-based regex this assertion will
# fail immediately.
#
# Note: te_ir_metrics was previously used as the regression marker here, but
# plan_te_ir.R and plan_integration.R are NOT sourced by docs/_targets.R so
# te_ir_metrics never enters the live pipeline.  extract_defined_metrics() now
# filters to sourced plan files only, so te_ir_metrics is correctly absent.
# persistence_metrics (plan_momentum_decomposition.R, a sourced file) remains
# the multiline-form regression sentinel.
test_that("extract_defined_metrics catches multiline tar_target() definitions (roborev #3130)", {
  plan_dir <- here::here("R")
  defined  <- extract_defined_metrics(plan_dir)

  # persistence_metrics: defined across two lines in plan_momentum_decomposition.R
  # (a sourced plan file) — invisible to the old line-based regex.
  expect_true(
    "persistence_metrics" %in% defined,
    label = "persistence_metrics present (multiline form — plan_momentum_decomposition.R:61-62)"
  )

  # te_ir_metrics must NOT appear — plan_te_ir.R and plan_integration.R are
  # not sourced by docs/_targets.R, so their targets are not in the live pipeline.
  expect_false(
    "te_ir_metrics" %in% defined,
    label = "te_ir_metrics absent (plan_te_ir.R / plan_integration.R not sourced)"
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
