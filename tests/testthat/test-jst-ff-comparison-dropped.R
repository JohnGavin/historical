testthat::local_edition(3)
# Owner decision 2026-11-04: the `jst_ff_comparison` target always returned
# NULL (hd_factors("FF3", "annual") has 0 rows; docs/inner-join-audit-657.md
# row A16), so it was dropped. Guard against it (or the empty
# `correlation_with_ff` value it fed into docs/evidence.qmd) coming back.

testthat::test_that("jst_ff_comparison target is not defined in R/plan_jst.R", {
  src <- readLines(here::here("R", "plan_jst.R"), warn = FALSE)
  testthat::expect_false(any(grepl("jst_ff_comparison", src, fixed = TRUE)))
})

testthat::test_that("correlation_with_ff appears nowhere in docs/*.qmd or R/plan_jst.R", {
  qmd <- list.files(here::here("docs"), pattern = "\\.qmd$", full.names = TRUE)
  testthat::expect_gt(length(qmd), 0L)
  hits <- vapply(
    c(qmd, here::here("R", "plan_jst.R")),
    function(f) any(grepl("correlation_with_ff", readLines(f, warn = FALSE), fixed = TRUE)),
    logical(1)
  )
  testthat::expect_false(any(hits))
})
