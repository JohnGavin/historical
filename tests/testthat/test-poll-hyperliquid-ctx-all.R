testthat::local_edition(3)
source(here::here("scripts", "poll_hyperliquid_ctx.R"))

# scripts/poll_hyperliquid_ctx.R: every exchange in one run, the delisted flag
# (#1084). NO network: the post function is injected. The fixtures are real
# replies: perpDexs (null = core, then 10 add-on exchanges), the core
# metaAndAssetCtxs, and a 3-market xyz metaAndAssetCtxs. Every add-on exchange
# answers with the xyz fixture (the parser does not look at the coin prefix).

.fxdir <- here::here("tests", "testthat", "fixtures", "hyperliquid")
.read <- function(f) jsonlite::read_json(file.path(.fxdir, f), simplifyVector = FALSE)
.mac <- .read("metaandassetctxs_xyz.json")
.dexs <- .read("perpdexs.json")
.core <- .read("meta_core.json")
.t0 <- as.POSIXct("2026-11-22 12:07:31.5", tz = "UTC")
.now <- function() .t0
.nosleep <- function(s) invisible(NULL)
.all_names <- hl_parse_dexs(.dexs)          # "" first, then the ten add-on exchanges
.poll <- function(post, out, dexes = "all", ...) {
  suppressMessages(hl_ctx_poll(post, out_dir = out, dexes = dexes, now = .now,
                               sleep_fn = .nosleep, ...))
}

# `log` (an environment) collects every request body; `fail` maps "d_<dex>" to a
# function that answers that exchange's request instead.
.all_post <- function(log = NULL, fail = list()) {
  function(body) {
    if (!is.null(log)) log$bodies[[length(log$bodies) + 1L]] <- body
    if (identical(body$type, "perpDexs")) return(.dexs)
    stopifnot(identical(body$type, "metaAndAssetCtxs"))
    key <- if (is.null(body$dex)) "" else body$dex
    f <- fail[[paste0("d_", key)]]
    if (!is.null(f)) return(f(body))
    if (is.null(body$dex)) .core else .mac
  }
}

test_that("the default polls EVERY exchange, the core one included, in 1 + 11 requests", {
  out <- withr::local_tempdir()
  log <- new.env(); log$bodies <- list()
  r <- .poll(.all_post(log), out)
  expect_equal(r$status, 0L)
  types <- vapply(log$bodies, function(b) b$type, character(1))
  expect_equal(types, c("perpDexs", rep("metaAndAssetCtxs", 11L)))
  dex_asked <- vapply(log$bodies[-1], function(b) if (is.null(b$dex)) "" else b$dex,
                      character(1))
  expect_equal(dex_asked, .all_names)
  # the core exchange is asked WITHOUT a dex field (as fetch_hyperliquid.R does)
  expect_null(log$bodies[[2]]$dex)
  x <- arrow::read_parquet(file.path(out, "perp_ctx_5m.parquet"))
  expect_equal(sort(unique(x$dex)), sort(.all_names))
  expect_equal(sum(x$dex == ""), length(.core[[1]]$universe))   # every core market kept
  expect_equal(sum(x$dex == "xyz"), 3L)
  expect_equal(r$n_rows, nrow(x))
  expect_equal(nrow(r$by_dex), 11L)
  expect_equal(r$attempts, 12L)
})

test_that("--dexes limits the run; \"main\" is the core exchange; bad values are usage errors", {
  expect_equal(.ctx_parse_dexes("all"), "all")
  expect_equal(.ctx_parse_dexes("main,xyz"), c("", "xyz"))
  expect_equal(.ctx_parse_dexes("xyz"), "xyz")
  expect_null(.ctx_parse_dexes("xyz,,flx"))      # red: an empty name is not accepted
  expect_null(.ctx_parse_dexes("a b"))
  out <- withr::local_tempdir()
  log <- new.env(); log$bodies <- list()
  args <- c(paste0("--out-dir=", out), paste0("--raw-dir=", file.path(out, "raw")),
            "--dexes=main,xyz")
  expect_equal(suppressMessages(.poll_hyperliquid_ctx_main(args, post_fn = .all_post(log))), 0L)
  expect_equal(vapply(log$bodies, function(b) if (is.null(b$dex)) "" else b$dex, character(1)),
               c("", "xyz"))
  expect_equal(suppressMessages(.poll_hyperliquid_ctx_main("--dexes=a b")), 2L)
  expect_equal(suppressMessages(.poll_hyperliquid_ctx_main("--dex=xyz")), 2L)   # old flag gone
})

test_that("a partial run writes the exchanges that worked and is 3, never 0", {
  out <- withr::local_tempdir()
  down <- function(body) hl_unavailable("connection refused")
  r <- .poll(.all_post(fail = list(d_flx = down)), out)
  expect_equal(r$status, 3L)
  expect_match(r$reason, "dex 'flx'", fixed = TRUE)
  x <- arrow::read_parquet(file.path(out, "perp_ctx_5m.parquet"))
  expect_false("flx" %in% x$dex)
  expect_equal(length(unique(x$dex)), 10L)         # the other ten are in
  # Red -> green: the same run without the fault is 0 and has all eleven
  out2 <- withr::local_tempdir()
  expect_equal(.poll(.all_post(), out2)$status, 0L)
  expect_equal(length(unique(arrow::read_parquet(file.path(out2, "perp_ctx_5m.parquet"))$dex)), 11L)
})

test_that("a rate limit is not retried and stops the run; what came before is kept", {
  out <- withr::local_tempdir()
  calls <- 0L
  limited <- function(body) {
    calls <<- calls + 1L
    cli::cli_abort("HTTP 429", class = c("hl_rate_limited", "hl_source_unavailable"))
  }
  r <- .poll(.all_post(fail = list(d_xyz = limited)), out)
  expect_equal(c(r$status, calls), c(3L, 1L))
  expect_equal(r$not_attempted, .all_names[-(1:2)])   # everything after xyz
  x <- arrow::read_parquet(file.path(out, "perp_ctx_5m.parquet"))
  expect_equal(unique(x$dex), "")                    # the core exchange was written
})

test_that("perpDexs failing: poll the last known exchanges (else the core one), and be 3", {
  out <- withr::local_tempdir()
  nolist <- function(body) {
    if (identical(body$type, "perpDexs")) hl_unavailable("HTTP 502")
    .all_post()(body)
  }
  r <- .poll(nolist, out)
  expect_equal(r$status, 3L)
  expect_match(r$reason, "perpDexs", fixed = TRUE)
  expect_equal(unique(arrow::read_parquet(file.path(out, "perp_ctx_5m.parquet"))$dex), "")
  # with a previous exchange table, those exchanges are polled
  out2 <- withr::local_tempdir()
  arrow::write_parquet(data.frame(dex = c("", "xyz"), full_name = c(NA, "XYZ")),
                       file.path(out2, "perp_dexs.parquet"))
  r2 <- .poll(nolist, out2)
  expect_equal(r2$status, 3L)
  expect_equal(sort(unique(arrow::read_parquet(file.path(out2, "perp_ctx_5m.parquet"))$dex)),
               c("", "xyz"))
})

test_that("no request starts without budget left; the run is 3 and says what it skipped", {
  out <- withr::local_tempdir()
  calls <- 0L
  post <- function(body) { calls <<- calls + 1L; .all_post()(body) }
  r <- .poll(post, out, deadline = Sys.time() - 1)
  expect_equal(c(r$status, calls), c(3L, 0L))
  expect_false(file.exists(file.path(out, "perp_ctx_5m.parquet")))
  # Red -> green: a deadline well ahead is a normal run
  expect_equal(.poll(.all_post(), withr::local_tempdir(), deadline = Sys.time() + 3600)$status, 0L)
  # a retry that the budget cannot afford is not started
  waits <- numeric()
  n <- 0L
  flaky <- function(body) { n <<- n + 1L; hl_unavailable("blip") }
  tight <- Sys.time() + HL_CTX_MIN_REMAINING_S + 1       # room for ONE attempt, not a retry
  r2 <- suppressMessages(hl_ctx_poll(flaky, out_dir = withr::local_tempdir(), dexes = "xyz",
                                     now = .now, sleep_fn = function(s) waits <<- c(waits, s),
                                     deadline = tight))
  expect_equal(c(r2$status, n, length(waits)), c(3L, 1L, 0L))
})

test_that("is_delisted comes from the universe; absent means FALSE", {
  m <- .mac
  m[[1]]$universe[[3]]$isDelisted <- TRUE
  d <- hl_parse_ctx(m, "xyz", .t0)
  expect_equal(d$is_delisted, c(FALSE, FALSE, TRUE))
  expect_type(d$is_delisted, "logical")
  expect_false(anyNA(d$is_delisted))
})

test_that("rows written before #1084 stay readable; the new column is NA for them", {
  out <- withr::local_tempdir()
  .poll(.all_post(), out, dexes = "xyz")
  f <- file.path(out, "perp_ctx_5m.parquet")
  old <- arrow::read_parquet(f)
  old$is_delisted <- NULL                                   # the pre-#1084 schema
  old$fetched_at <- old$fetched_at - 3600
  arrow::write_parquet(old, f)
  .poll(.all_post(), out, dexes = "xyz")
  x <- arrow::read_parquet(f)
  expect_equal(nrow(x), 6L)
  expect_true("is_delisted" %in% names(x))
  expect_equal(sum(is.na(x$is_delisted)), 3L)               # the old rows
  expect_equal(sum(x$is_delisted, na.rm = TRUE), 0L)
  expect_false(anyNA(x$is_delisted[x$fetched_at == .t0]))   # the new rows
})
