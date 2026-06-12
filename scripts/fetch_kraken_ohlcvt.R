#!/usr/bin/env Rscript
# fetch_kraken_ohlcvt.R
#
# Phase A (#436): Fetch hourly + daily OHLCVT for the 6 largest USD pairs on
# Kraken by 24 h USD volume: BTC, ETH, SOL, XRP, ADA, LINK.
#
# DOWNLOAD MECHANICS (investigated 2026-06-12):
#   Kraken hosts one full archive and quarterly update ZIPs on Google Drive:
#     Full archive (7.3 GB):
#       https://drive.google.com/file/d/1ptNqWYidLkhb2VAKuLCxmp2OXEfGO-AP/view
#     Quarterly updates folder:
#       https://drive.google.com/drive/folders/15RSlNuW_h0kVM8or8McOGOMfHeBFvFGI
#
#   Automated download is NOT possible without the manual "Download anyway"
#   click-through: Google Drive serves a virus-scan warning HTML page for files
#   > 25 MB and the confirm token is session-scoped. The script therefore
#   reads the ZIP from a path the user supplies (or the env var
#   KRAKEN_ZIP_PATH) after they have manually downloaded it.
#
#   Fallback: for the recent ~30-day window the script can also pull from the
#   Kraken public REST API (max 720 candles per call; no API key required).
#   Set KRAKEN_REST_FALLBACK=1 to enable this for development / smoke-testing.
#
# CSV LAYOUT INSIDE THE ZIP (confirmed from community source):
#   No header row. Seven columns:
#     timestamp (Unix epoch seconds, integer)
#     open, high, low, close (numeric, as string)
#     volume (numeric, as string)
#     trades (integer)
#   File names: {PAIR}_{interval_minutes}.csv
#   e.g. XBTUSD_60.csv, ETHUSD_1440.csv
#   ZIP internal path: either "Kraken_OHLCVT/{file}" (old layout)
#     or "{file}" (new layout from ~2023 quarterly updates).
#   Source: https://github.com/gwangjinkim/krakenohlcvt
#
# OUTPUT SCHEMA (data/raw/kraken_ohlcvt.parquet):
#   ticker      chr   Short symbol — "BTC", "ETH", "SOL", "XRP", "ADA", "LINK"
#   pair        chr   Kraken pair name — "XBTUSD", "ETHUSD", etc.
#   interval_min int  60 or 1440
#   time        POSIXct (UTC) — heed issue #453: stored as proper timestamp
#   open        dbl
#   high        dbl
#   low         dbl
#   close       dbl
#   volume      dbl
#   trades      int
#
# USAGE:
#   # With a manually downloaded ZIP:
#   KRAKEN_ZIP_PATH=~/Downloads/Kraken_OHLCVT.zip Rscript scripts/fetch_kraken_ohlcvt.R
#
#   # REST fallback (recent ~30 days only, for smoke-testing):
#   KRAKEN_REST_FALLBACK=1 Rscript scripts/fetch_kraken_ohlcvt.R

suppressPackageStartupMessages({
  library(httr2)
  library(tibble)
  library(dplyr)
  library(arrow)
  library(cli)
})

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

# The 6 largest USD pairs on Kraken by 24 h USD volume (verified 2026-06-12).
# Ranking source: Kraken public REST API /Ticker endpoint.
# Kraken internal name → (ticker, CSV pair prefix, wsname)
PAIRS <- list(
  list(kraken_pair = "XXBTZUSD", ticker = "BTC",  csv_prefix = "XBTUSD",  wsname = "XBT/USD"),
  list(kraken_pair = "XETHZUSD", ticker = "ETH",  csv_prefix = "ETHUSD",  wsname = "ETH/USD"),
  list(kraken_pair = "SOLUSD",   ticker = "SOL",  csv_prefix = "SOLUSD",  wsname = "SOL/USD"),
  list(kraken_pair = "XXRPZUSD", ticker = "XRP",  csv_prefix = "XRPUSD",  wsname = "XRP/USD"),
  list(kraken_pair = "ADAUSD",   ticker = "ADA",  csv_prefix = "ADAUSD",  wsname = "ADA/USD"),
  list(kraken_pair = "LINKUSD",  ticker = "LINK", csv_prefix = "LINKUSD", wsname = "LINK/USD")
)

# Intervals to extract (minutes)
INTERVALS <- c(60L, 1440L)

# ---------------------------------------------------------------------------
# Helper: parse one pair+interval from an open zip connection
# ---------------------------------------------------------------------------

#' Parse Kraken OHLCVT CSV from a ZIP file
#'
#' @param zip_path Path to the downloaded ZIP archive.
#' @param csv_prefix Pair prefix as used in the CSV file name (e.g. "XBTUSD").
#' @param interval_min Interval in minutes (60 or 1440).
#' @param ticker Short ticker label for the output (e.g. "BTC").
#' @param kraken_pair Full Kraken pair identifier (e.g. "XXBTZUSD").
#' @return Tibble with normalised schema, or NULL on failure.
parse_ohlcvt_from_zip <- function(zip_path, csv_prefix, interval_min,
                                   ticker, kraken_pair) {
  # The CSV's parent directory inside the ZIP varies by archive vintage:
  # root ("{file}"), "Kraken_OHLCVT/{file}", "master_q4/{file}" (2026 full
  # archive), etc. Match by basename anywhere in the tree instead of
  # hardcoding layouts; ignore macOS resource-fork junk under __MACOSX/.
  csv_name <- paste0(csv_prefix, "_", interval_min, ".csv")

  zip_contents <- tryCatch(unzip(zip_path, list = TRUE)$Name, error = function(e) character(0))
  hits <- zip_contents[
    basename(zip_contents) == csv_name &
      !grepl("(^|/)__MACOSX/", paste0("/", zip_contents))
  ]

  if (length(hits) == 0L) {
    cli::cli_warn("  {ticker} {interval_min}min: {csv_name} not found in ZIP")
    return(NULL)
  }
  if (length(hits) > 1L) {
    cli::cli_warn("  {ticker} {interval_min}min: {length(hits)} copies of {csv_name} in ZIP; using {hits[1L]}")
  }

  matched_name <- hits[1L]
  tmp_dir <- tempdir()

  tryCatch({
    unzip(zip_path, files = matched_name, exdir = tmp_dir, overwrite = TRUE)
    csv_path <- file.path(tmp_dir, matched_name)

    # No header; 7 columns: timestamp, open, high, low, close, volume, trades
    raw <- utils::read.csv(
      csv_path,
      header = FALSE,
      col.names = c("timestamp_s", "open", "high", "low", "close", "volume", "trades"),
      colClasses = c("integer", "double", "double", "double", "double", "double", "integer"),
      stringsAsFactors = FALSE
    )

    tibble::as_tibble(raw) |>
      dplyr::mutate(
        ticker       = ticker,
        pair         = csv_prefix,
        interval_min = interval_min,
        # Issue #453: write proper POSIXct, NOT character
        time         = as.POSIXct(timestamp_s, origin = "1970-01-01", tz = "UTC")
      ) |>
      dplyr::select(ticker, pair, interval_min, time, open, high, low, close, volume, trades)
  }, error = function(e) {
    cli::cli_warn("  {ticker} {interval_min}min: parse failed — {conditionMessage(e)}")
    NULL
  })
}

# ---------------------------------------------------------------------------
# Helper: fetch recent candles from Kraken REST API (fallback only)
# ---------------------------------------------------------------------------

#' Fetch OHLC candles from the Kraken public REST API
#'
#' Maximum 720 candles per call (no authentication required).
#' Use ONLY for smoke-testing. The full archive ZIP is required for
#' production-quality history.
#'
#' @param kraken_pair Kraken pair string, e.g. "XXBTZUSD".
#' @param interval_min Interval in minutes (must be one of Kraken's supported values).
#' @param ticker Short ticker label.
#' @param csv_prefix CSV pair prefix for the pair column.
#' @return Tibble with normalised schema, or NULL on failure.
fetch_ohlc_rest <- function(kraken_pair, interval_min, ticker, csv_prefix) {
  url <- paste0(
    "https://api.kraken.com/0/public/OHLC?pair=", kraken_pair,
    "&interval=", interval_min
  )
  cli::cli_progress_step("  REST {ticker} {interval_min}min (last ~720 candles)")

  tryCatch({
    resp <- httr2::request(url) |>
      httr2::req_timeout(30L) |>
      httr2::req_perform()
    body <- httr2::resp_body_json(resp, simplifyVector = FALSE)

    if (length(body$error) > 0L) {
      cli::cli_warn("  REST error for {ticker}: {paste(body$error, collapse=', ')}")
      return(NULL)
    }

    # result has one key = the pair name, plus "last"
    pair_data <- body$result[[kraken_pair]]
    if (is.null(pair_data) || length(pair_data) == 0L) return(NULL)

    # Each candle: [time, open, high, low, close, vwap, volume, count]
    # Note: REST includes vwap (position 6); ZIP does not. We drop vwap.
    rows <- lapply(pair_data, function(c) {
      tibble::tibble(
        ticker       = ticker,
        pair         = csv_prefix,
        interval_min = interval_min,
        time         = as.POSIXct(as.integer(c[[1L]]), origin = "1970-01-01", tz = "UTC"),
        open         = as.double(c[[2L]]),
        high         = as.double(c[[3L]]),
        low          = as.double(c[[4L]]),
        close        = as.double(c[[5L]]),
        # c[[6]] is vwap — skip
        volume       = as.double(c[[7L]]),
        trades       = as.integer(c[[8L]])
      )
    })
    dplyr::bind_rows(rows)
  }, error = function(e) {
    cli::cli_warn("  REST fetch failed for {ticker}: {conditionMessage(e)}")
    NULL
  })
}

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

#' Validate a Kraken OHLCVT tibble
#'
#' Checks schema (column names and types), duplicate (pair, interval_min, time),
#' value ranges (positive prices, high >= low), and hourly gap detection.
#' Aborts with cli_abort on hard failures; warns on soft issues.
#'
#' @param df Tibble produced by the fetch pipeline.
#' @param abort_on_failure If TRUE, call cli_abort on validation failures
#'   (default). Set FALSE in tests to capture the errors.
#' @return df invisibly, after validation.
dv_kraken_ohlcvt <- function(df, abort_on_failure = TRUE) {
  # ── 1. Schema ──────────────────────────────────────────────────────────────
  required_cols <- c("ticker", "pair", "interval_min", "time",
                     "open", "high", "low", "close", "volume", "trades")
  missing_cols <- setdiff(required_cols, names(df))
  if (length(missing_cols) > 0L) {
    msg <- c(
      "x" = "kraken_ohlcvt: missing columns: {paste(missing_cols, collapse=', ')}",
      "i" = "Expected: {paste(required_cols, collapse=', ')}"
    )
    if (abort_on_failure) cli::cli_abort(msg) else { cli::cli_warn(msg); return(invisible(df)) }
  }

  wrong_type <- c(
    if (!inherits(df$time, "POSIXct")) "`time` must be POSIXct (UTC)" else NULL,
    if (!is.character(df$ticker))      "`ticker` must be character" else NULL,
    if (!is.character(df$pair))        "`pair` must be character" else NULL,
    if (!is.integer(df$interval_min))  "`interval_min` must be integer" else NULL,
    if (!is.double(df$close))          "`close` must be double" else NULL
  )
  if (length(wrong_type) > 0L) {
    msg <- c("x" = "kraken_ohlcvt: type mismatch", "i" = wrong_type)
    if (abort_on_failure) cli::cli_abort(msg) else cli::cli_warn(msg)
  }

  # ── 2. Duplicates ──────────────────────────────────────────────────────────
  n_dup <- sum(duplicated(df[c("pair", "interval_min", "time")]))
  if (n_dup > 0L) {
    msg <- c("x" = "kraken_ohlcvt: {n_dup} duplicate (pair, interval_min, time) rows")
    if (abort_on_failure) cli::cli_abort(msg) else cli::cli_warn(msg)
  }

  # ── 3. Value ranges ────────────────────────────────────────────────────────
  n_neg_close <- sum(df$close <= 0L, na.rm = TRUE)
  if (n_neg_close > 0L) {
    msg <- c("x" = "kraken_ohlcvt: {n_neg_close} rows with close <= 0")
    if (abort_on_failure) cli::cli_abort(msg) else cli::cli_warn(msg)
  }

  n_high_lt_low <- sum(df$high < df$low, na.rm = TRUE)
  if (n_high_lt_low > 0L) {
    msg <- c("x" = "kraken_ohlcvt: {n_high_lt_low} rows where high < low")
    if (abort_on_failure) cli::cli_abort(msg) else cli::cli_warn(msg)
  }

  # ── 4. Gap detection (hourly grain only, soft warning) ────────────────────
  hourly <- df[df$interval_min == 60L, ]
  if (nrow(hourly) > 0L) {
    gap_report <- hourly |>
      dplyr::arrange(pair, time) |>
      dplyr::group_by(pair) |>
      dplyr::mutate(
        delta_h = as.double(difftime(time, dplyr::lag(time), units = "hours"))
      ) |>
      dplyr::filter(!is.na(delta_h) & delta_h > 2L) |>
      dplyr::summarise(
        n_gaps    = dplyr::n(),
        max_gap_h = if (dplyr::n() > 0L) max(delta_h, na.rm = TRUE) else NA_real_,
        .groups   = "drop"
      ) |>
      dplyr::filter(n_gaps > 0L)

    if (nrow(gap_report) > 0L) {
      cli::cli_warn(c(
        "!" = "kraken_ohlcvt: gaps >2h detected in hourly data",
        "i" = "This is expected — Kraken only records candles when trades occur",
        "i" = "{paste(gap_report$pair, 'max_gap=', round(gap_report$max_gap_h, 1), 'h', collapse='; ')}"
      ))
    }
  }

  cli::cli_alert_success(
    "kraken_ohlcvt validation passed: {nrow(df)} rows, {dplyr::n_distinct(df$ticker)} pairs, intervals {paste(sort(unique(df$interval_min)), collapse='/')} min"
  )
  invisible(df)
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

cli::cli_h1("Kraken OHLCVT Fetch — 6 majors, 60 + 1440 min (#436 Phase A)")

zip_path <- Sys.getenv("KRAKEN_ZIP_PATH", unset = "")
use_rest  <- nchar(Sys.getenv("KRAKEN_REST_FALLBACK", unset = "")) > 0L

if (nchar(zip_path) == 0L && !use_rest) {
  cli::cli_abort(c(
    "x" = "No data source specified.",
    "i" = "Option 1 (full history): set KRAKEN_ZIP_PATH to the manually downloaded ZIP path:",
    "i" = "  Download from: https://drive.google.com/file/d/1ptNqWYidLkhb2VAKuLCxmp2OXEfGO-AP/view",
    "i" = "  Then: KRAKEN_ZIP_PATH=~/Downloads/Kraken_OHLCVT.zip Rscript scripts/fetch_kraken_ohlcvt.R",
    "i" = "Option 2 (recent ~30 days, smoke-test only): set KRAKEN_REST_FALLBACK=1",
    "i" = "  KRAKEN_REST_FALLBACK=1 Rscript scripts/fetch_kraken_ohlcvt.R"
  ))
}

if (nchar(zip_path) > 0L) {
  zip_path <- path.expand(zip_path)
  if (!file.exists(zip_path)) {
    cli::cli_abort(c(
      "x" = "ZIP not found at {.path {zip_path}}",
      "i" = "Download manually from: https://drive.google.com/file/d/1ptNqWYidLkhb2VAKuLCxmp2OXEfGO-AP/view"
    ))
  }
  cli::cli_alert_info("Source: ZIP archive at {.path {zip_path}}")
} else {
  cli::cli_alert_info("Source: Kraken REST API (recent ~720 candles only)")
}

all_results <- list()

for (p in PAIRS) {
  for (iv in INTERVALS) {
    label <- paste0(p$ticker, "_", iv, "min")
    cli::cli_progress_step("Fetching {label}")

    if (nchar(zip_path) > 0L) {
      df <- parse_ohlcvt_from_zip(
        zip_path    = zip_path,
        csv_prefix  = p$csv_prefix,
        interval_min = iv,
        ticker       = p$ticker,
        kraken_pair  = p$kraken_pair
      )
    } else {
      df <- fetch_ohlc_rest(
        kraken_pair  = p$kraken_pair,
        interval_min = iv,
        ticker       = p$ticker,
        csv_prefix   = p$csv_prefix
      )
      Sys.sleep(1L)  # REST rate limit courtesy
    }

    if (!is.null(df) && nrow(df) > 0L) {
      cli::cli_alert_success(
        "  {label}: {nrow(df)} rows ({format(min(df$time), '%Y-%m-%d')} to {format(max(df$time), '%Y-%m-%d')})"
      )
      all_results[[label]] <- df
    } else {
      cli::cli_warn("  {label}: no data")
    }
  }
}

if (length(all_results) == 0L) {
  cli::cli_abort(c("x" = "No data fetched — cannot write parquet."))
}

combined <- dplyr::bind_rows(all_results) |>
  # Enforce correct types for parquet serialisation (issue #453)
  dplyr::mutate(
    ticker       = as.character(ticker),
    pair         = as.character(pair),
    interval_min = as.integer(interval_min),
    time         = as.POSIXct(time, tz = "UTC"),
    open         = as.double(open),
    high         = as.double(high),
    low          = as.double(low),
    close        = as.double(close),
    volume       = as.double(volume),
    trades       = as.integer(trades)
  ) |>
  dplyr::distinct(pair, interval_min, time, .keep_all = TRUE) |>
  dplyr::arrange(pair, interval_min, time)

# Validate before writing
dv_kraken_ohlcvt(combined)

# ---------------------------------------------------------------------------
# Write to parquet
# ---------------------------------------------------------------------------

out_path <- here::here("data", "raw", "kraken_ohlcvt.parquet")
dir.create(dirname(out_path), showWarnings = FALSE, recursive = TRUE)

# Idempotent merge with existing data if it exists
if (file.exists(out_path)) {
  existing <- arrow::read_parquet(out_path)
  # Coerce existing time to POSIXct in case it was stored differently
  existing <- existing |>
    dplyr::mutate(time = as.POSIXct(time, tz = "UTC"))
  combined <- dplyr::bind_rows(existing, combined) |>
    dplyr::distinct(pair, interval_min, time, .keep_all = TRUE) |>
    dplyr::arrange(pair, interval_min, time)
  cli::cli_alert_info("Merged with existing file; {nrow(combined)} total rows")
}

arrow::write_parquet(combined, out_path, compression = "zstd")

size_kb <- round(file.info(out_path)$size / 1024L)
cli::cli_alert_success(
  "Written {nrow(combined)} rows to {.path {out_path}} ({size_kb} KB)"
)

cli::cli_h2("Summary")
summary_tbl <- combined |>
  dplyr::group_by(ticker, interval_min) |>
  dplyr::summarise(
    n        = dplyr::n(),
    from     = format(min(time), "%Y-%m-%d"),
    to       = format(max(time), "%Y-%m-%d"),
    .groups  = "drop"
  )
print(summary_tbl, n = Inf)
