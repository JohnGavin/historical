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

# Helper: extract all target names matching *_metrics from a set of R files
extract_defined_metrics <- function(plan_dir) {
  plan_files <- list.files(plan_dir, pattern = "^plan_.*\\.R$", full.names = TRUE)
  lines <- unlist(lapply(plan_files, readLines, warn = FALSE))
  # Match: tar_target(  <name>_metrics  ,  (whitespace-tolerant, no tar_target_raw)
  hits <- regmatches(
    lines,
    regexpr("tar_target\\s*\\(\\s*[a-z][a-z0-9_]*_metrics", lines, perl = TRUE)
  )
  hits <- hits[nzchar(hits)]
  # Extract just the target name (everything after the opening paren and whitespace)
  nms <- sub("tar_target\\s*\\(\\s*", "", hits, perl = TRUE)
  sort(unique(nms))
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
  tokens <- unlist(strsplit(block_clean, "[,\\s\\(\\)]+"))
  tokens <- trimws(tokens)
  tokens <- tokens[nzchar(tokens)]
  metrics <- grep("^[a-z][a-z0-9_]*_metrics$", tokens, value = TRUE)
  sort(unique(metrics))
}

# ── Tests ─────────────────────────────────────────────────────────────────────

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
