# Tests for the point-in-time S&P 500 membership loader (#816).
#
# Every fixture is SYNTHETIC (invented tickers A..E, invented dates) written to
# a tempdir. No real downloaded membership data is read or committed here.
# testthat edition 3.

testthat::local_edition(3)

# ── Synthetic fixture helpers ────────────────────────────────────────────────

.sp_toy <- data.frame(
  date = c("2020-01-01", "2020-02-01", "2020-03-01", "2020-04-01"),
  tickers = c("A,B,C", "A,B,D", "A,C,D", "A,C,D"),
  stringsAsFactors = FALSE
)

.sp_write <- function(dir, rows = .sp_toy, name = "m.csv") {
  p <- file.path(dir, name)
  utils::write.csv(rows, p, row.names = FALSE)
  p
}

.sp_mem <- function(rows = .sp_toy) {
  d <- withr::local_tempdir(.local_envir = parent.frame())
  hd_sp500_membership(.sp_write(d, rows), min_members = 2L)
}

# ── cache directory resolution ───────────────────────────────────────────────

test_that("hd_sp500_data_dir: defaults and honours the env var", {
  withr::local_envvar(SP500_MEMBERSHIP_DIR = NA)
  expect_equal(hd_sp500_data_dir(), path.expand("~/.cache/historical/sp500_membership"))
  withr::local_envvar(SP500_MEMBERSHIP_DIR = "/tmp/custom_sp500_dir")
  expect_equal(hd_sp500_data_dir(), "/tmp/custom_sp500_dir")
})

test_that("hd_sp500_membership_path: aborts naming the fetch script when absent", {
  tmp <- withr::local_tempdir()
  expect_snapshot(
    error = TRUE,
    hd_sp500_membership_path(tmp),
    transform = function(x) gsub(tmp, "<TMP>", x, fixed = TRUE)
  )
  .sp_write(tmp, name = "sp500_historical_components.csv")
  expect_equal(hd_sp500_membership_path(tmp),
               file.path(tmp, "sp500_historical_components.csv"))
})

# ── hd_sp500_membership: happy path ──────────────────────────────────────────

test_that("hd_sp500_membership: tidy long table, one row per date x ticker", {
  m <- .sp_mem(.sp_toy[4:1, ])  # unsorted input is sorted by date
  expect_s3_class(m, "tbl_df")
  expect_named(m, c("date", "ticker"))
  expect_s3_class(m$date, "Date")
  expect_type(m$ticker, "character")
  expect_equal(nrow(m), 3L * 4L)
  expect_false(is.unsorted(m$date))
  expect_equal(m$ticker[m$date == as.Date("2020-02-01")], c("A", "B", "D"))
  expect_false(anyDuplicated(m[c("date", "ticker")]) > 0L)
})

test_that("hd_sp500_members_asof: last snapshot on or before the date, inclusive", {
  m <- .sp_mem()
  r <- hd_sp500_members_asof(m, "2020-02-15")
  expect_equal(r$snapshot_date, as.Date("2020-02-01"))
  expect_equal(r$tickers, c("A", "B", "D"))
  expect_equal(hd_sp500_members_asof(m, "2020-03-01")$snapshot_date, as.Date("2020-03-01"))
  expect_snapshot(error = TRUE, hd_sp500_members_asof(m, "2019-01-01"))
  expect_snapshot(error = TRUE, hd_sp500_members_asof(m, NA))
})

# ── hd_sp500_membership: every boundary aborts loudly ────────────────────────

test_that("hd_sp500_membership: aborts on a missing file", {
  tmp <- withr::local_tempdir()
  expect_snapshot(
    error = TRUE,
    hd_sp500_membership(file.path(tmp, "nope.csv")),
    transform = function(x) gsub(tmp, "<TMP>", x, fixed = TRUE)
  )
})

test_that("hd_sp500_membership: aborts on wrong columns", {
  tmp <- withr::local_tempdir()
  p <- .sp_write(tmp, data.frame(day = "2020-01-01", syms = "A,B"))
  expect_snapshot(error = TRUE, hd_sp500_membership(p, min_members = 1L))
})

test_that("hd_sp500_membership: aborts on an empty file", {
  tmp <- withr::local_tempdir()
  p <- .sp_write(tmp, data.frame(date = character(), tickers = character()))
  expect_snapshot(error = TRUE, hd_sp500_membership(p, min_members = 1L))
})

test_that("hd_sp500_membership: aborts on unparseable or missing dates, never NA", {
  tmp <- withr::local_tempdir()
  p <- .sp_write(tmp, data.frame(date = c("2020-01-01", "not-a-date"),
                                 tickers = c("A,B", "A,B")))
  expect_snapshot(error = TRUE, hd_sp500_membership(p, min_members = 1L))
  p2 <- .sp_write(tmp, data.frame(date = c("2020-01-01", ""), tickers = c("A,B", "A,B")),
                  name = "m2.csv")
  expect_error(hd_sp500_membership(p2, min_members = 1L), "unparseable")
})

test_that("hd_sp500_membership: aborts on duplicate snapshot dates", {
  tmp <- withr::local_tempdir()
  p <- .sp_write(tmp, data.frame(date = c("2020-01-01", "2020-01-01"),
                                 tickers = c("A,B", "A,C")))
  expect_snapshot(error = TRUE, hd_sp500_membership(p, min_members = 1L))
})

test_that("hd_sp500_membership: aborts on empty tokens and repeated tickers", {
  tmp <- withr::local_tempdir()
  p <- .sp_write(tmp, data.frame(date = "2020-01-01", tickers = "A,,B"))
  expect_snapshot(error = TRUE, hd_sp500_membership(p, min_members = 1L))
  p2 <- .sp_write(tmp, data.frame(date = "2020-01-01", tickers = "A,B,A"), name = "m2.csv")
  expect_snapshot(error = TRUE, hd_sp500_membership(p2, min_members = 1L))
})

test_that("hd_sp500_membership: aborts on legacy SYM-YYYYMM marker tokens", {
  tmp <- withr::local_tempdir()
  p <- .sp_write(tmp, data.frame(date = "2020-01-01", tickers = "A,B,C-201002"))
  expect_snapshot(error = TRUE, hd_sp500_membership(p, min_members = 1L))
})

test_that("hd_sp500_membership: aborts when a snapshot is thinner than min_members", {
  tmp <- withr::local_tempdir()
  p <- .sp_write(tmp)
  expect_snapshot(error = TRUE, hd_sp500_membership(p, min_members = 4L))
})

# ── hd_sp500_pit_universe ────────────────────────────────────────────────────

test_that("hd_sp500_pit_universe: schema matches the stub, types are exact", {
  u <- hd_sp500_pit_universe(.sp_mem())
  expect_named(u, c("ticker", "date", "in_universe_pit", "index_name",
                    "delisting_date", "delisting_reason", "delisting_price"))
  expect_type(u$ticker, "character")
  expect_s3_class(u$date, "Date")
  expect_type(u$in_universe_pit, "logical")
  expect_true(all(u$in_universe_pit))
  expect_true(all(u$index_name == "SP500"))
  expect_s3_class(u$delisting_date, "Date")
  expect_type(u$delisting_reason, "character")
  expect_type(u$delisting_price, "double")
  expect_true(all(is.na(u$delisting_reason)))   # unavailable from this source
  expect_true(all(is.na(u$delisting_price)))    # unavailable from this source
  expect_equal(nrow(u), 12L)
})

test_that("hd_sp500_pit_universe: delisting_date is the index-exit date of the spell", {
  u <- hd_sp500_pit_universe(.sp_mem())
  ex <- function(t, d) u$delisting_date[u$ticker == t & u$date == as.Date(d)]
  expect_true(is.na(ex("A", "2020-01-01")))            # never leaves
  expect_equal(ex("B", "2020-01-01"), as.Date("2020-03-01"))
  expect_equal(ex("B", "2020-02-01"), as.Date("2020-03-01"))
  expect_equal(ex("C", "2020-01-01"), as.Date("2020-02-01"))   # first spell ends
  expect_true(is.na(ex("C", "2020-03-01")))                    # re-entered, still in
  expect_true(is.na(ex("C", "2020-04-01")))
  expect_true(is.na(ex("D", "2020-02-01")))
})

test_that("hd_sp500_pit_universe: rejects a malformed membership", {
  expect_snapshot(error = TRUE, hd_sp500_pit_universe(data.frame(a = 1)))
  expect_error(
    hd_sp500_pit_universe(tibble::tibble(date = as.Date(character()), ticker = character())),
    "empty"
  )
})

# ── known-delisted presence check ────────────────────────────────────────────

test_that("hd_sp500_known_delisted: ships the five fixture names with Date member_on", {
  k <- hd_sp500_known_delisted()
  expect_named(k, c("ticker", "name", "member_on"))
  expect_s3_class(k$member_on, "Date")
  expect_gte(nrow(k), 5L)
  expect_false(anyNA(k$member_on))
})

.sp_known <- data.frame(ticker = c("B", "C"), name = c("Bee", "Sea"),
                        member_on = as.Date(c("2020-02-10", "2020-01-10")))

test_that("presence check: PASS when a PIT member is absent from the price universe", {
  r <- hd_sp500_presence_check(.sp_mem(), c("A", "D"), known = .sp_known)
  expect_equal(r$status, c("PASS", "PASS"))
  expect_equal(r$is_pit_member, c(TRUE, TRUE))
  expect_equal(r$in_price_universe, c(FALSE, FALSE))
})

test_that("presence check can go RED: name not a PIT member on the fixture date", {
  # Falsification: drop B from every snapshot; the check must fail, not pass.
  rows <- .sp_toy
  rows$tickers <- c("A,C", "A,D", "A,C,D", "A,C,D")
  r <- hd_sp500_presence_check(.sp_mem(rows), c("A", "D"), known = .sp_known)
  expect_equal(r$status, c("FAIL_NOT_MEMBER", "PASS"))
})

test_that("presence check can go RED: name now present in the price universe", {
  r <- hd_sp500_presence_check(.sp_mem(), c("A", "B"), known = .sp_known)
  expect_equal(r$status, c("FAIL_IN_PRICE_UNIVERSE", "PASS"))
})

test_that("presence check: a date before coverage aborts rather than passing", {
  k <- .sp_known
  k$member_on[1] <- as.Date("1990-01-01")
  expect_error(hd_sp500_presence_check(.sp_mem(), "A", known = k), "No membership snapshot")
})

test_that("presence check: an empty price universe is rejected, not vacuously passed", {
  expect_snapshot(error = TRUE,
                  hd_sp500_presence_check(.sp_mem(), character(), known = .sp_known))
  expect_error(hd_sp500_presence_check(.sp_mem(), NA_character_, known = .sp_known),
               "non-empty")
})

test_that("presence check: rejects a malformed known table", {
  expect_snapshot(error = TRUE,
                  hd_sp500_presence_check(.sp_mem(), "A", known = data.frame(ticker = "B")))
})

# ── coverage statistic ───────────────────────────────────────────────────────

test_that("coverage: share of members with price data on or near each snapshot", {
  spans <- data.frame(
    ticker = c("A", "B", "D"),
    first_date = as.Date(c("2019-01-01", "2019-01-01", "2020-01-20")),
    last_date  = as.Date(c("2021-01-01", "2020-02-20", "2021-01-01"))
  )
  cv <- hd_sp500_coverage(.sp_mem(), spans, tol_days = 0L)
  expect_named(cv, c("date", "n_members", "n_covered", "share_covered"))
  expect_equal(cv$date, as.Date(c("2020-01-01", "2020-02-01", "2020-03-01", "2020-04-01")))
  # 01-01: A,B,C  -> A,B covered (C has no price row)            = 2/3
  # 02-01: A,B,D  -> A,B covered; D starts 01-20 so covered       = 3/3
  # 03-01: A,C,D  -> A covered, D covered; C none                 = 2/3
  # 04-01: A,C,D  -> A, D covered                                 = 2/3
  expect_equal(cv$n_members, c(3L, 3L, 3L, 3L))
  expect_equal(cv$n_covered, c(2L, 3L, 2L, 2L))
  expect_equal(cv$share_covered, c(2, 3, 2, 2) / 3)
})

test_that("coverage: tolerance widens each span; ticker_map reconciles symbols", {
  m <- tibble::tibble(date = as.Date("2020-01-10"), ticker = c("BRK.B", "ZZZ"))
  spans <- data.frame(ticker = c("BRK-B", "ZZZ"),
                      first_date = as.Date(c("2020-01-05", "2020-01-15")),
                      last_date = as.Date("2020-12-31"))
  expect_equal(hd_sp500_coverage(m, spans, tol_days = 0L)$n_covered, 1L)  # ZZZ starts later
  expect_equal(hd_sp500_coverage(m, spans, tol_days = 7L)$n_covered, 2L)
  no_map <- hd_sp500_coverage(m, spans, tol_days = 0L, ticker_map = identity)
  expect_equal(no_map$n_covered, 0L)   # BRK.B != BRK-B without the map
})

test_that("coverage: snapshots outside the price window are not scored", {
  spans <- data.frame(ticker = "A", first_date = as.Date("2020-01-15"),
                      last_date = as.Date("2020-02-10"))
  cv <- hd_sp500_coverage(.sp_mem(), spans, tol_days = 0L)
  expect_equal(cv$date, as.Date("2020-02-01"))   # 01-01, 03-01, 04-01 are outside
})

test_that("coverage: rejects bad inputs", {
  spans <- data.frame(ticker = "A", first_date = as.Date("2020-01-01"),
                      last_date = as.Date("2020-12-31"))
  expect_snapshot(error = TRUE, hd_sp500_coverage(.sp_mem(), spans[0, ]))
  expect_snapshot(error = TRUE,
                  hd_sp500_coverage(.sp_mem(), rbind(spans, spans)))
  bad <- spans; bad$first_date <- as.Date("2021-01-01")
  expect_snapshot(error = TRUE, hd_sp500_coverage(.sp_mem(), bad))
  expect_snapshot(error = TRUE, hd_sp500_coverage(.sp_mem(), spans, tol_days = -1))
  late <- spans; late$first_date <- as.Date("2030-01-01"); late$last_date <- as.Date("2030-02-01")
  expect_snapshot(error = TRUE, hd_sp500_coverage(.sp_mem(), late, tol_days = 0L))
})

# ── equity spans (hermetic: bundled sample fixture, no network) ──────────────

test_that("hd_sp500_equity_spans: one row per ticker with Date columns", {
  local_sample_data()
  # hd_lazy() warns once per session that equity_daily is survivorship-biased;
  # mark it as already shown so this test stays warning-free.
  withr::local_options(hd_survivorship_warned_equity_daily = TRUE)
  s <- hd_sp500_equity_spans()
  expect_named(s, c("ticker", "first_date", "last_date"))
  expect_s3_class(s$first_date, "Date")
  expect_s3_class(s$last_date, "Date")
  expect_gt(nrow(s), 0L)
  expect_false(anyDuplicated(s$ticker) > 0L)
  expect_true(all(s$first_date <= s$last_date))
})
