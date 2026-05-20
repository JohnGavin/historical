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
                                    targets_r_path = NULL,
                                    project_root = here::here()) {
  # targets_r_path defaults to NULL; derived from project_root so that
  # callers overriding only project_root always read the matching _targets.R.
  if (is.null(targets_r_path)) {
    targets_r_path <- file.path(project_root, "docs/_targets.R")
  }
  # plan_dir is kept for backwards-compatibility but the canonical list of
  # files to walk comes from docs/_targets.R, not a directory glob.
  # This ensures that plan files on disk but not sourced (plan_te_ir.R,
  # plan_integration.R) are excluded from the result.
  # project_root is exposed so the helper is testable in a tempdir.
  #
  # Parse source() calls from docs/_targets.R — exclude commented-out lines.
  all_lines <- readLines(targets_r_path, warn = FALSE)
  active_lines <- all_lines[!grepl("^\\s*#", all_lines)]
  sourced_paths <- regmatches(
    active_lines,
    regexpr('R/plan_[^"]+\\.R', active_lines)
  )
  plan_files <- file.path(project_root, sourced_paths)
  plan_files <- plan_files[file.exists(plan_files)]
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

  # Parse failures must NOT be silently swallowed: a syntax error in any
  # sourced plan_*.R would otherwise drop its *_metrics targets from the
  # completeness check, allowing qa_summary regressions to pass silently.
  # roborev #3509/#3501 — surface the parse error loudly.
  for (path in plan_files) {
    exprs <- tryCatch(
      parse(file = path, keep.source = FALSE),
      error = function(e) {
        cli::cli_abort(c(
          "x" = "Parse error in {.file {basename(path)}}",
          "i" = "{conditionMessage(e)}",
          "i" = "A broken plan_*.R file would silently remove *_metrics targets from the qa_summary completeness check; failing loudly instead."
        ))
      }
    )
    for (e in exprs) walk(e)
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

# Regression guard for roborev #3509/#3501: a syntax error in a sourced
# plan_*.R must abort the helper, NOT be silently swallowed.  Previous
# behaviour (tryCatch -> warning -> NULL) caused targets from broken plan
# files to silently disappear from the completeness check.
test_that("extract_defined_metrics aborts on parse error in a sourced plan file (roborev #3509)", {
  withr::with_tempdir({
    dir.create("R")
    dir.create("docs")
    # Deliberately malformed R syntax — unclosed tar_target() call
    writeLines(
      c(
        "plan_broken <- list(",
        "  tar_target(broken_metrics,",
        "  # missing closing parens"
      ),
      "R/plan_broken.R"
    )
    writeLines(
      'source("R/plan_broken.R")',
      "docs/_targets.R"
    )

    expect_error(
      extract_defined_metrics(
        plan_dir = "R",
        targets_r_path = "docs/_targets.R",
        project_root = "."
      ),
      regexp = "Parse error in"
    )
  })
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
