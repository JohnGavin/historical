testthat::local_edition(3)
# #937 item 4 row 2: shadow_summary's per-offset ratio is mean/sd of PER-TRADE
# returns -- not annualised and with no rf deducted (not excess). It is NOT a
# Sharpe, so it must not carry the name or caption of one: an annual Sharpe
# sits beside it on the same page and the two are not comparable.

source(here::here("R/plan_shadow_trades.R"))

.target_command <- function(target_list, name) {
  hit <- vapply(target_list, function(t) identical(t$settings$name, name), logical(1))
  if (sum(hit) != 1L) stop("target '", name, "' not found (or not unique)")
  target_list[[which(hit)]]$command$expr[[1]]
}
.run <- function(cmd, ...) {
  env <- list2env(list(...), envir = new.env(parent = globalenv()))
  eval(cmd, envir = env)
}

# Two offsets, four trades each, hand-checkable mean/sd.
.fake_shadow <- function() {
  tibble::tibble(
    entry_offset = rep(c(0L, 1L), each = 4L),
    exit_offset  = 0L,
    return_pct   = c(0.02, 0.04, -0.01, 0.03,   0.01, 0.01, 0.03, -0.01),
    is_win       = return_pct > 0
  )
}

tg <- plan_shadow_trades()

test_that("shadow_summary names the ratio per_trade_ratio and has no `sharpe` column", {
  out <- .run(.target_command(tg, "shadow_summary"), shadow_avoid_worst = .fake_shadow())
  expect_true("per_trade_ratio" %in% names(out))
  expect_false("sharpe" %in% names(out))
  r0 <- c(0.02, 0.04, -0.01, 0.03)
  expect_equal(out$per_trade_ratio[out$entry_offset == 0L],
               round(mean(r0) / stats::sd(r0), 2))
})

test_that("shadow_optimal and shadow_caption say per-trade, not annualised, not excess", {
  summ <- .run(.target_command(tg, "shadow_summary"), shadow_avoid_worst = .fake_shadow())
  opt  <- .run(.target_command(tg, "shadow_optimal"), shadow_summary = summ)
  expect_false(any(grepl("sharpe", names(opt), ignore.case = TRUE)))
  expect_true(all(c("actual_ratio", "best_ratio") %in% names(opt)))

  cap <- .run(.target_command(tg, "shadow_caption"), shadow_optimal = opt)
  expect_match(cap, "per-trade ratio, not annualised, not excess", fixed = TRUE)
  expect_false(grepl("Sharpe", cap, fixed = TRUE))
})

test_that("the insufficient-trades caption does not call the analysis a Sharpe either", {
  cap <- .run(.target_command(tg, "shadow_caption"), shadow_optimal = NULL)
  expect_false(grepl("Sharpe", cap, fixed = TRUE))
})
