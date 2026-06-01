# Tests for check_vignette_cross_refs() — Related Vignettes section gate (S8)
# All tests are offline — uses synthetic temp-directory .qmd files.
# testthat edition 3.

# check_vignette_cross_refs() lives in R/plan_qa_gates.R (plan-level, not
# exported from historicaldata).  When running devtools::test() from the package,
# source the plan file from the repo root so the helper is available.
.repo_root <- function() {
  p <- normalizePath(".", mustWork = FALSE)
  for (i in seq_len(8L)) {
    if (file.exists(file.path(p, "docs", "_targets.R"))) return(p)
    p <- dirname(p)
  }
  stop("Cannot locate repo root from: ", normalizePath(".", mustWork = FALSE))
}

if (!exists("check_vignette_cross_refs", mode = "function")) {
  root <- .repo_root()
  source(file.path(root, "R", "plan_qa_gates.R"))
}


# ── Helpers ───────────────────────────────────────────────────────────────────

.write_qmd <- function(dir, name, content) {
  path <- file.path(dir, name)
  writeLines(content, path)
  invisible(path)
}

.qmd_with_section <- function(section_header = "## Related vignettes") {
  c(
    "---",
    "title: Test",
    "---",
    "",
    "## Methodology",
    "",
    "Some content.",
    "",
    section_header,
    "",
    "- **[Foo](foo.html)** — related page",
    ""
  )
}

.qmd_without_section <- function() {
  c(
    "---",
    "title: Test",
    "---",
    "",
    "## Methodology",
    "",
    "Some content.",
    ""
  )
}


# ── Tests: missing section → error ───────────────────────────────────────────

test_that("check_vignette_cross_refs: throws when a vignette lacks the section", {
  tmp <- withr::local_tempdir()
  .write_qmd(tmp, "strat-a.qmd", .qmd_with_section())
  .write_qmd(tmp, "strat-b.qmd", .qmd_without_section())

  expect_error(
    check_vignette_cross_refs(tmp),
    regexp = "Related Vignettes"
  )
})

test_that("check_vignette_cross_refs: error message names the missing file", {
  tmp <- withr::local_tempdir()
  .write_qmd(tmp, "strat-a.qmd", .qmd_with_section())
  .write_qmd(tmp, "strat-b.qmd", .qmd_without_section())

  expect_error(
    check_vignette_cross_refs(tmp),
    regexp = "strat-b.qmd"
  )
})

test_that("check_vignette_cross_refs: accepts #### Related Vignettes tab form", {
  tmp <- withr::local_tempdir()
  .write_qmd(tmp, "strat-a.qmd", .qmd_with_section("#### Related Vignettes"))

  result <- check_vignette_cross_refs(tmp)
  expect_true(result)
})

test_that("check_vignette_cross_refs: index.qmd is silently skipped", {
  tmp <- withr::local_tempdir()
  # Only index.qmd, which should be skipped → no files to check → TRUE
  .write_qmd(tmp, "index.qmd", .qmd_without_section())

  result <- check_vignette_cross_refs(tmp)
  expect_true(result)
})


# ── Tests: all sections present → TRUE ───────────────────────────────────────

test_that("check_vignette_cross_refs: returns TRUE when all vignettes have section", {
  tmp <- withr::local_tempdir()
  .write_qmd(tmp, "strat-a.qmd", .qmd_with_section())
  .write_qmd(tmp, "strat-b.qmd", .qmd_with_section())

  result <- check_vignette_cross_refs(tmp)
  expect_true(result)
})

test_that("check_vignette_cross_refs: returns TRUE for empty directory (no qmd files)", {
  tmp <- withr::local_tempdir()

  result <- check_vignette_cross_refs(tmp)
  expect_true(result)
})

test_that("check_vignette_cross_refs: case-insensitive match for vignettes keyword", {
  tmp <- withr::local_tempdir()
  # Use lowercase 'v' in 'vignettes' — function uses regex so both cases pass
  .write_qmd(tmp, "strat-a.qmd", .qmd_with_section("## Related vignettes"))

  result <- check_vignette_cross_refs(tmp)
  expect_true(result)
})
