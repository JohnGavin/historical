testthat::local_edition(3)
# Tests for S45 (every vocabulary label resolves through the glossary), Refs #668.
#
# Gate numbering: S45 is new. S16 is check_borrow_status_registry() and is
# untouched. Fixtures below use the period spellings actually present on the
# leaderboard and the S11 registry targets in the built store (read-only probe,
# 2026-11-02): "Full Period"/"Holdout"/"OOS"/"Testing"/"Training" on the
# leaderboard and "Full"/"OOS"/"Training"/"Testing"/"Full Period" on registry
# targets.

source(here::here("R/glossary.R"))
source(here::here("R/plan_qa_gates.R"))

glossary   <- load_glossary()
resolution <- load_entity_resolution()

.surf <- function(period) tibble::tibble(strategy = "S", period = period, cagr = 0.1)

real_like <- list(
  leaderboard = .surf(c("Full Period", "Holdout", "OOS", "Testing", "Training")),
  mf_metrics  = .surf(c("Full", "OOS", "Training")),     # alias spelling "Full"
  rsc_metrics = .surf(c("Full Period", "Testing", "Training"))
)

run <- function(surfaces, g = glossary, r = resolution) {
  check_vocab_resolution(build_vocab_resolution_table(surfaces, g, r))
}

test_that("PASS on real-registry-like surfaces, including the registered 'Full' alias", {
  out <- run(real_like)
  s <- attr(out, "summary")
  expect_identical(s[["fail"]], 0L)
  expect_identical(s[["indeterminate"]], 0L)
  expect_gt(s[["examined"]], 0L)
  expect_identical(s[["surfaces"]], 3L)
})

test_that("FAIL on an injected unresolved label (falsification: input 'Fullz' on mf_metrics)", {
  bad <- real_like
  bad$mf_metrics <- .surf(c("Fullz", "OOS", "Training"))
  expect_error(run(bad), class = "qa_s45_fail")
  tbl <- build_vocab_resolution_table(bad, glossary, resolution)
  expect_identical(tbl$verdict[tbl$value %in% "Fullz"], "FAIL")
})

test_that("FAIL when the alias is removed from the resolution map (falsification: empty map)", {
  expect_error(run(real_like, r = list()), class = "qa_s45_fail")
})

test_that("FAIL on an NA label (unresolved, not skipped)", {
  bad <- real_like
  bad$rsc_metrics <- .surf(c("Full Period", NA))
  expect_error(run(bad), class = "qa_s45_fail")
})

test_that("FAIL on an unknown metric_unit when a surface carries that column", {
  s <- real_like
  s$reg <- tibble::tibble(metric_unit = c("fraction", "percnt"))
  expect_error(run(s), class = "qa_s45_fail")
  s$reg <- tibble::tibble(metric_unit = c("fraction", "percent"))
  expect_identical(attr(run(s), "summary")[["fail"]], 0L)
})

test_that("INDETERMINATE on empty or missing input, never PASS", {
  expect_error(run(list()), class = "qa_s45_indeterminate")
  expect_error(run(NULL), class = "qa_s45_indeterminate")
  expect_error(run(list(leaderboard = NULL)), class = "qa_s45_indeterminate")
  expect_error(run(list(leaderboard = .surf(character(0)))), class = "qa_s45_indeterminate")
  expect_error(run(list(leaderboard = tibble::tibble(x = 1))), class = "qa_s45_indeterminate")
  expect_error(run(unname(real_like)), class = "qa_s45_indeterminate")
})

test_that("INDETERMINATE when one surface is unreadable even if the others pass", {
  s <- real_like
  s["eur_results"] <- list(NULL)
  expect_error(run(s), class = "qa_s45_indeterminate")
})

test_that("INDETERMINATE when the glossary lacks the entity's allowed values", {
  g <- glossary
  g$period_label$values <- NULL
  expect_error(run(real_like, g = g), class = "qa_s45_indeterminate")
})

test_that("FAIL outranks INDETERMINATE when both are present", {
  s <- real_like
  s$mf_metrics <- .surf("Fullz")
  s["eur_results"] <- list(NULL)
  expect_error(run(s), class = "qa_s45_fail")
})

test_that("the gate is registered in plan_qa_gates() and covers leaderboard + every S11 registry target", {
  plan <- plan_qa_gates()
  nms <- vapply(plan, function(t) t$settings$name, character(1))
  expect_true("qa_vocab_resolution" %in% nms)
  tgt <- plan[[which(nms == "qa_vocab_resolution")]]
  # symbols the command mentions are what targets' static analysis turns into
  # dependency edges (the literal-list pattern S11 uses)
  deps <- all.vars(tgt$command$expr)
  expect_true(all(c("leaderboard", names(S11_METRICS_REGISTRY)) %in% deps))
})
