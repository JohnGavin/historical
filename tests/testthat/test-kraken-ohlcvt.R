# Tests for the Kraken OHLCVT fetch pipeline (#436 Phase A)
# Covers:
#  - CSV parsing (7-column no-header Kraken format)
#  - Timestamp conversion to POSIXct UTC (issue #453)
#  - dv_kraken_ohlcvt() validation: schema, duplicates, value ranges, gaps
#  - At least one expect_snapshot() per snapshot-test-policy
testthat::local_edition(3)

# ---------------------------------------------------------------------------
# Helpers for synthetic fixtures
# ---------------------------------------------------------------------------

# Build a minimal in-memory Kraken OHLCVT CSV (no header, 7 cols)
make_kraken_csv_lines <- function(pair = "XBTUSD", interval_min = 60L,
                                  n_rows = 5L, start_ts = 1700000000L) {
  timestamps <- start_ts + seq(0L, by = interval_min * 60L, length.out = n_rows)
  opens  <- seq(30000, by = 10, length.out = n_rows)
  highs  <- opens + 50
  lows   <- opens - 30
  closes <- opens + 20
  vols   <- seq(0.5, by = 0.1, length.out = n_rows)
  trades <- seq(100L, by = 10L, length.out = n_rows)
  paste(timestamps, opens, highs, lows, closes, vols, trades, sep = ",")
}

# Write synthetic CSV to a temp file and zip it
make_kraken_zip <- function(pairs_intervals = list(list("XBTUSD", 60L)),
                             n_rows = 5L, layout = "new") {
  zip_path <- tempfile(fileext = ".zip")
  tmp_dir  <- tempdir()
  csv_paths <- character(0L)

  for (pi in pairs_intervals) {
    pair <- pi[[1L]]
    iv   <- pi[[2L]]
    lines <- make_kraken_csv_lines(pair, iv, n_rows)
    csv_name <- paste0(pair, "_", iv, ".csv")
    if (layout == "old") {
      dir.create(file.path(tmp_dir, "Kraken_OHLCVT"), showWarnings = FALSE)
      csv_path <- file.path(tmp_dir, "Kraken_OHLCVT", csv_name)
    } else {
      csv_path <- file.path(tmp_dir, csv_name)
    }
    writeLines(lines, csv_path)
    csv_paths <- c(csv_paths, csv_path)
  }

  # zip with relative names from tmp_dir
  # utils::zip() requires R_ZIPCMD which is unset in the nix shell; use
  # system2 with the known system zip binary instead.
  old_wd <- setwd(tmp_dir)
  on.exit(setwd(old_wd), add = TRUE)
  rel_paths <- if (layout == "old") {
    file.path("Kraken_OHLCVT", sapply(pairs_intervals, function(pi) paste0(pi[[1L]], "_", pi[[2L]], ".csv")))
  } else {
    sapply(pairs_intervals, function(pi) paste0(pi[[1L]], "_", pi[[2L]], ".csv"))
  }
  zip_bin <- Sys.which("zip")
  if (nchar(zip_bin) == 0L) zip_bin <- "/usr/bin/zip"
  system2(zip_bin, args = c(zip_path, rel_paths), stdout = FALSE, stderr = FALSE)
  zip_path
}

# Source the two key functions from the fetch script (without running main())
source_fetch_fns <- function() {
  script_path <- here::here("scripts", "fetch_kraken_ohlcvt.R")
  if (!file.exists(script_path)) skip("fetch script not found")

  lines  <- readLines(script_path)
  # Find the line where main code starts (the cli::cli_h1 call at the top level)
  # Everything after "# Main" comment block and up to the zip_path / use_rest checks
  # is the interactive part; we want only the functions + PAIRS constant.
  # Strategy: source only up to (but not including) "zip_path <-"
  main_start <- grep("^zip_path\\s*<-", lines)[1L]
  if (is.na(main_start)) stop("Could not find main block in fetch script")
  fn_lines <- lines[seq_len(main_start - 1L)]
  eval(parse(text = fn_lines), envir = parent.frame())
}

# ---------------------------------------------------------------------------
# Tests: parse_ohlcvt_from_zip
# ---------------------------------------------------------------------------

test_that("parse_ohlcvt_from_zip returns correct schema from new-layout ZIP", {
  suppressPackageStartupMessages({
    library(tibble)
    library(dplyr)
  })
  source_fetch_fns()

  zip_path <- make_kraken_zip(list(list("XBTUSD", 60L)), n_rows = 5L, layout = "new")
  on.exit(unlink(zip_path), add = TRUE)

  result <- parse_ohlcvt_from_zip(zip_path, "XBTUSD", 60L, "BTC", "XXBTZUSD")

  expect_s3_class(result, "tbl_df")
  expect_named(result, c("ticker", "pair", "interval_min", "time", "open", "high", "low", "close", "volume", "trades"))
  expect_equal(nrow(result), 5L)
  expect_equal(unique(result$ticker), "BTC")
  expect_equal(unique(result$pair), "XBTUSD")
  expect_equal(unique(result$interval_min), 60L)
  # Issue #453: time must be POSIXct, NOT character
  expect_s3_class(result$time, "POSIXct")
  expect_equal(attr(result$time, "tzone"), "UTC")
})

test_that("parse_ohlcvt_from_zip returns correct schema from old-layout ZIP (Kraken_OHLCVT/ prefix)", {
  suppressPackageStartupMessages(library(tibble))
  source_fetch_fns()

  zip_path <- make_kraken_zip(list(list("ETHUSD", 1440L)), n_rows = 3L, layout = "old")
  on.exit(unlink(zip_path), add = TRUE)

  result <- parse_ohlcvt_from_zip(zip_path, "ETHUSD", 1440L, "ETH", "XETHZUSD")
  expect_equal(nrow(result), 3L)
  expect_equal(unique(result$ticker), "ETH")
})

test_that("parse_ohlcvt_from_zip returns NULL and warns when CSV not in ZIP", {
  source_fetch_fns()
  zip_path <- make_kraken_zip(list(list("XBTUSD", 60L)), layout = "new")
  on.exit(unlink(zip_path), add = TRUE)

  # Request a different pair that does not exist in the ZIP
  # Use withCallingHandlers to capture the warning without affecting the return value
  warned <- FALSE
  result <- withCallingHandlers(
    parse_ohlcvt_from_zip(zip_path, "SOLUSD", 60L, "SOL", "SOLUSD"),
    warning = function(w) { warned <<- TRUE; invokeRestart("muffleWarning") }
  )
  expect_null(result)
  expect_true(warned)
})

test_that("parsed timestamps match expected Unix epoch conversion", {
  source_fetch_fns()

  # ts 1700000000 = 2023-11-14 22:13:20 UTC
  zip_path <- make_kraken_zip(list(list("XBTUSD", 60L)), n_rows = 1L, layout = "new")
  on.exit(unlink(zip_path), add = TRUE)

  result <- parse_ohlcvt_from_zip(zip_path, "XBTUSD", 60L, "BTC", "XXBTZUSD")
  expected_time <- as.POSIXct(1700000000L, origin = "1970-01-01", tz = "UTC")
  expect_equal(result$time[1L], expected_time)
})

test_that("parse_ohlcvt_from_zip snapshot — column names and type summary", {
  source_fetch_fns()
  zip_path <- make_kraken_zip(list(list("XBTUSD", 60L)), n_rows = 2L, layout = "new")
  on.exit(unlink(zip_path), add = TRUE)

  result <- parse_ohlcvt_from_zip(zip_path, "XBTUSD", 60L, "BTC", "XXBTZUSD")
  summary_str <- paste(
    names(result),
    sapply(result, function(col) class(col)[[1L]]),
    sep = ":", collapse = ", "
  )
  # Snapshot: catches column name or type drift
  expect_snapshot(cat(summary_str))
})

# ---------------------------------------------------------------------------
# Tests: dv_kraken_ohlcvt
# ---------------------------------------------------------------------------

make_valid_df <- function(n = 5L) {
  tibble::tibble(
    ticker       = rep("BTC", n),
    pair         = rep("XBTUSD", n),
    interval_min = rep(60L, n),
    time         = as.POSIXct(
      seq(1700000000L, by = 3600L, length.out = n),
      origin = "1970-01-01", tz = "UTC"
    ),
    open         = seq(30000.0, by = 10.0, length.out = n),
    high         = seq(30050.0, by = 10.0, length.out = n),
    low          = seq(29970.0, by = 10.0, length.out = n),
    close        = seq(30020.0, by = 10.0, length.out = n),
    volume       = seq(0.5, by = 0.1, length.out = n),
    trades       = seq(100L, by = 10L, length.out = n)
  )
}

test_that("dv_kraken_ohlcvt passes on valid data", {
  source_fetch_fns()
  df <- make_valid_df()
  expect_no_error(dv_kraken_ohlcvt(df))
})

test_that("dv_kraken_ohlcvt aborts on missing columns", {
  source_fetch_fns()
  df <- make_valid_df()
  df_bad <- df[, setdiff(names(df), "volume")]
  expect_error(dv_kraken_ohlcvt(df_bad), regexp = "volume")
})

test_that("dv_kraken_ohlcvt aborts on non-POSIXct time column", {
  source_fetch_fns()
  df <- make_valid_df()
  df$time <- as.character(df$time)
  expect_error(dv_kraken_ohlcvt(df), regexp = "POSIXct")
})

test_that("dv_kraken_ohlcvt aborts on duplicate (pair, interval_min, time)", {
  source_fetch_fns()
  df <- make_valid_df()
  df_dup <- dplyr::bind_rows(df, df[1L, ])
  expect_error(dv_kraken_ohlcvt(df_dup), regexp = "duplicate")
})

test_that("dv_kraken_ohlcvt aborts when close <= 0", {
  source_fetch_fns()
  df <- make_valid_df()
  df$close[2L] <- -5.0
  expect_error(dv_kraken_ohlcvt(df), regexp = "close <= 0")
})

test_that("dv_kraken_ohlcvt aborts when high < low", {
  source_fetch_fns()
  df <- make_valid_df()
  df$high[3L] <- df$low[3L] - 1.0
  expect_error(dv_kraken_ohlcvt(df), regexp = "high < low")
})

test_that("dv_kraken_ohlcvt warns on hourly gaps but does not abort", {
  source_fetch_fns()
  df <- make_valid_df(n = 5L)
  # Introduce a 5-hour gap between rows 3 and 4
  df$time[4L] <- df$time[3L] + 5L * 3600L
  df$time[5L] <- df$time[4L] + 3600L
  expect_warning(dv_kraken_ohlcvt(df), regexp = NULL)
})

test_that("dv_kraken_ohlcvt error message snapshot — missing column", {
  source_fetch_fns()
  df <- make_valid_df()
  df_bad <- df[, setdiff(names(df), c("volume", "trades"))]
  expect_snapshot(
    error = TRUE,
    dv_kraken_ohlcvt(df_bad)
  )
})

# ---------------------------------------------------------------------------
# Tests: PAIRS constant (pair list shape)
# ---------------------------------------------------------------------------

test_that("PAIRS constant has exactly 6 entries with required keys", {
  source_fetch_fns()
  expect_length(PAIRS, 6L)
  for (p in PAIRS) {
    expect_true(all(c("kraken_pair", "ticker", "csv_prefix", "wsname") %in% names(p)))
    expect_type(p$ticker, "character")
    expect_type(p$csv_prefix, "character")
  }
})

test_that("PAIRS snapshot — ticker list is stable", {
  source_fetch_fns()
  tickers <- sapply(PAIRS, `[[`, "ticker")
  # Snapshot: catches unintended pair substitutions (#436)
  expect_snapshot(cat(paste(tickers, collapse = ", ")))
})
