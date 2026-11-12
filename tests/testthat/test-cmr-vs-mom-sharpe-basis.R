testthat::local_edition(3)
# #1058: the CMR captions quoted the naive HAC-test Sharpe (0.405 at 6m) next
# to a head-to-head table whose best MR row read 0.250 (geometric
# sharpe_ratio_rf()), and the verdict compared that naive figure with an
# arithmetic momentum Sharpe: three bases in one sentence.
#
# Pinned here: (a) every Sharpe quoted in the head-to-head caption, and the
# verdict, come from the table's own column; (b) the scorecard caption quotes
# only its table's Naive Sharpe column (labelled) plus the head-to-head
# figures under their own label; (c) momentum in cmr_vs_mom_compare uses CMR's
# estimator (geometric sharpe_ratio_rf() at 252, rf 0 on the excess basis).

pkg_path <- if (dir.exists(here::here("packages/historicaldata"))) {
  here::here("packages/historicaldata")
} else {
  file.path(dirname(here::here()), "packages/historicaldata")
}
suppressMessages(pkgload::load_all(pkg_path, quiet = TRUE))
suppressMessages(library(dplyr))
source(here::here("R/utils_metrics.R"))
source(here::here("R/plan_commodities_mean_reversion.R"))
source(here::here("R/plan_falsification_vignette.R"))

.target_cmd <- function(tl, name) {
  hit <- vapply(tl, function(t) identical(t$settings$name, name), logical(1))
  if (sum(hit) != 1L) stop("target '", name, "' not found (or not unique)")
  tl[[which(hit)]]$command$expr[[1]]
}
.eval_cmd <- function(expr, ...) {
  env <- list2env(list(...), envir = new.env(parent = globalenv()))
  eval(expr, envir = env)
}

# Fixture mirroring the defect: naive HAC Sharpe (0.405) differs from the
# table's geometric Sharpe (0.250) at the best lookback.
.fals_cmr_summary <- tibble::tibble(
  lookback = c("1m", "3m", "6m"),
  hac_sharpe = c(-0.144, 0.180, 0.405),
  hac_tstat = c(-0.5, 0.6, 1.4),
  rej_rate_wn = 0.05, rej_rate_rv = 0.05, rej_rate_ma1 = 0.05,
  rej_rate_fn = 0.05, rej_rate_garch = 0.05, rej_rate_gjr = 0.05,
  dsr = 0.5, dsr_pvalue = 0.4
)
.compare <- function(mom = -0.120) {
  tibble::tibble(
    lookback = c("1m (MR)", "3m (MR)", "6m (MR)", "12-bar (momentum)"),
    type     = c(rep("mean_reversion", 3), "momentum"),
    sharpe   = c(-0.297, 0.013, 0.250, mom),
    max_dd   = c(-0.5, -0.4, -0.3, -0.6)
  )
}

test_that("head-to-head caption quotes the table's own Sharpe, not the naive HAC figure", {
  tl  <- plan_falsification_vignette()
  cap <- .eval_cmd(.target_cmd(tl, "fals_vig_cmr_head_to_head_caption"),
                   cmr_vs_mom_compare = .compare(),
                   fals_cmr_summary = .fals_cmr_summary)
  tbl <- .eval_cmd(.target_cmd(tl, "fals_vig_cmr_head_to_head"),
                   cmr_vs_mom_compare = .compare())
  mr_best_table <- max(tbl$Sharpe[tbl$Type == "mean_reversion"])
  expect_match(cap, paste0("Best MR Sharpe (6m): ", mr_best_table), fixed = TRUE)
  expect_false(grepl("0.405", cap, fixed = TRUE))
  expect_match(cap, "geometric", fixed = TRUE)   # names the estimator
})

test_that("verdict uses the table column: a naive figure above momentum cannot flip it", {
  # Table: best MR 0.250 < momentum 0.300 => does not outperform. The naive
  # 0.405 is above 0.300 and would have said "outperforms" before the fix.
  tl  <- plan_falsification_vignette()
  cap <- .eval_cmd(.target_cmd(tl, "fals_vig_cmr_head_to_head_caption"),
                   cmr_vs_mom_compare = .compare(mom = 0.300),
                   fals_cmr_summary = .fals_cmr_summary)
  expect_match(cap, "does not outperform", fixed = TRUE)
  cap2 <- .eval_cmd(.target_cmd(tl, "fals_vig_cmr_head_to_head_caption"),
                    cmr_vs_mom_compare = .compare(mom = -0.120),
                    fals_cmr_summary = .fals_cmr_summary)
  expect_match(cap2, "Mean reversion outperforms momentum", fixed = TRUE)
})

test_that("scorecard caption quotes its table's Naive Sharpe column, labelled, plus table-matching head-to-head figures", {
  tl  <- plan_falsification_vignette()
  cap <- .eval_cmd(.target_cmd(tl, "fals_vig_cmr_caption"),
                   fals_cmr_summary = .fals_cmr_summary,
                   cmr_vs_mom_compare = .compare())
  tbl <- .eval_cmd(.target_cmd(tl, "fals_vig_cmr_table"),
                   fals_cmr_summary = .fals_cmr_summary)
  naive_best <- max(tbl$`Naive Sharpe`)
  expect_match(cap, paste0("Naive Sharpe column: 6m (", naive_best, ")"), fixed = TRUE)
  expect_match(cap, "naive (HAC-test input)", fixed = TRUE)
  # Head-to-head figures are the compare table's, labelled geometric.
  expect_match(cap, "geometric Sharpe", fixed = TRUE)
  expect_match(cap, "6m (0.25)", fixed = TRUE)
  expect_match(cap, "-0.12", fixed = TRUE)
})

test_that(".fals_vig_cmr_compare_stats aborts rather than guessing on a thin table", {
  expect_error(.fals_vig_cmr_compare_stats(.compare()[.compare()$type == "momentum", ]),
               "mean-reversion row")
  expect_error(.fals_vig_cmr_compare_stats(tibble::tibble(x = 1)), "columns")
})

# ── cmr_vs_mom_compare: momentum on CMR's estimator ─────────────────────────

test_that("momentum figure in cmr_vs_mom_compare is the geometric Sharpe, not the arithmetic one", {
  # Skewed series so geometric and arithmetic Sharpe differ visibly.
  r <- rep(c(0.05, -0.03, 0.002, -0.001), length.out = 400L)
  bt <- tibble::tibble(
    date = seq(as.Date("2020-01-01"), by = "day", length.out = 400L),
    strategy = "baseline", portfolio_ret = r, turnover = 0, cost = 0,
    net_ret = r, n_positions = 20L
  )
  perf <- tibble::tibble(
    strategy = "baseline",
    sharpe = mean(r) / stats::sd(r) * sqrt(252),   # arithmetic, as perf_summary
    max_dd = -0.2
  )
  cmr_summary <- tibble::tibble(lookback = c("1m", "3m", "6m"),
                                sharpe = c(0.1, 0.2, 0.3),
                                max_dd = c(-0.1, -0.1, -0.1))
  out <- .eval_cmd(.target_cmd(plan_commodities_mean_reversion(), "cmr_vs_mom_compare"),
                   commodities_perf_summary = perf,
                   commodities_backtest = bt,
                   cmr_summary = cmr_summary)
  mom <- out$sharpe[out$type == "momentum"]
  geo <- round(sharpe_ratio_rf(r, rep(0, length(r)), periods_per_year = 252L)$sharpe, 3)
  expect_equal(mom, geo)
  expect_false(isTRUE(all.equal(mom, round(perf$sharpe, 3))))
})

test_that(".cmr_momentum_geometric_sharpe refuses a non-excess basis label", {
  expect_error(.cmr_momentum_geometric_sharpe(c(0.01, -0.01, 0.02), basis_strategy = "Research: ETF buy and hold"))
  expect_error(.cmr_momentum_geometric_sharpe("a"), "numeric")
})
