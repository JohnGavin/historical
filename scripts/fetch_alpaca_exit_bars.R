#!/usr/bin/env Rscript
# fetch_alpaca_exit_bars.R
#
# #1041: Alpaca data for every ticker that left the point-in-time S&P 500 on or
# after 2016-01-04, the date the sip feed starts. Used to classify and price
# index leavers (hd_alpaca_exit_prices()); the 464 leavers before that date
# have no free source and are not requested. Three files:
#
#   alpaca_exit_bars.parquet          RAW daily bars (adjustment = "raw")
#   alpaca_exit_bars_adj.parquet      ADJUSTED daily bars (adjustment = "all")
#                                     for the same tickers and windows, plus SPY
#                                     over 2015-10-01..today. A spin-off or
#                                     split looks like a crash on raw prices.
#   alpaca_exit_corp_actions.parquet  Alpaca corporate-action records
#                                     (name_change, cash_merger, stock_merger,
#                                     stock_and_cash_merger, spin_off) for the
#                                     tickers, 2016-01-01..today, flattened by
#                                     hd_alpaca_corporate_actions().
#
# WHICH TICKERS. Derived from the package, not re-parsed here:
# hd_sp500_exits(hd_sp500_membership(hd_sp500_membership_path())), kept when
# index_exit_date >= hd_alpaca_exit_rule()$panel_start. Run
# scripts/fetch_sp500_membership.R first.
#
# WHICH BARS. For each ticker the window
#   [max(panel_start, first membership date) - window_days, exit + window_days]
# (window_days from hd_alpaca_exit_rule()). One request series per ticker, so a
# symbol later reused by another company is not pulled in beyond its window.
#
# CREDENTIALS. ALPACA_KEY and ALPACA_SECRET in the environment (the paper
# keys work for market data). They are read by the package functions; nothing
# here prints or stores them.
#
# DATA. Files go to ALPACA_BARS_DIR (default ~/.cache/historical/alpaca_exit_bars/)
# and stay LOCAL (same posture as the S&P 500 membership file and OSAP). Only
# the manifest is committed, one row per file:
#   packages/historicaldata/inst/extdata/alpaca/alpaca_exit_bars_manifest.csv
# (file, rows, sha256, fetched_at, params).
#
# CACHE REUSE, per file. If the file exists, its sha256 equals the manifest
# row's and the manifest's `params` equal this run's, that file is not fetched.
# A sha256 mismatch, a missing manifest row, or changed params ABORTS
# (provenance cannot be vouched for); set ALPACA_FORCE_REFETCH=1 to fetch all
# three again on purpose. A file that does not exist is fetched alone.
#
# Usage, from the repo root:
#   nix develop <repo> --command Rscript scripts/fetch_alpaca_exit_bars.R

suppressPackageStartupMessages({
  library(cli)
})

pkgload::load_all(here::here("packages", "historicaldata"), quiet = TRUE)

FEED          <- "sip"
SPY_START     <- as.Date("2015-10-01")
CA_START      <- as.Date("2016-01-01")
CA_TYPES      <- c("name_change", "cash_merger", "stock_merger",
                   "stock_and_cash_merger", "spin_off")
MANIFEST_PATH <- here::here(
  "packages", "historicaldata", "inst", "extdata", "alpaca",
  "alpaca_exit_bars_manifest.csv"
)

rule <- hd_alpaca_exit_rule()
data_dir <- hd_alpaca_bars_data_dir()

# ---- which tickers, and over what windows ----------------------------------
membership <- hd_sp500_membership(hd_sp500_membership_path())
exits <- hd_sp500_exits(membership)
pre_start <- sum(exits$index_exit_date < rule$panel_start)
exits <- exits[exits$index_exit_date >= rule$panel_start, , drop = FALSE]
if (nrow(exits) == 0L) {
  cli::cli_abort("No index exits on or after {.val {format(rule$panel_start)}}: nothing to fetch. Check the membership file.")
}
exits$win_start <- pmax(exits$first_member_date, rule$panel_start) - rule$window_days
exits$win_end   <- exits$index_exit_date + rule$window_days
cli::cli_inform(c(
  "i" = "{nrow(exits)} index exit{?s} on or after {format(rule$panel_start)} to fetch.",
  "i" = "{pre_start} earlier exit{?s} have no free price source and are not requested."
))

force_refetch <- nzchar(Sys.getenv("ALPACA_FORCE_REFETCH", ""))
existing <- if (file.exists(MANIFEST_PATH)) {
  utils::read.csv(MANIFEST_PATH, stringsAsFactors = FALSE, colClasses = "character")
} else NULL

# Fetch one file, or keep the cached one if it matches the manifest. Returns
# its one-row manifest data frame.
ensure_file <- function(name, params, build) {
  dest <- file.path(data_dir, name)
  prev <- if (is.null(existing)) NULL else existing[existing$file == name, , drop = FALSE]
  if (file.exists(dest) && !force_refetch) {
    sha <- digest::digest(dest, algo = "sha256", file = TRUE)
    if (is.null(prev) || nrow(prev) != 1L || !identical(prev$sha256, sha)) {
      cli::cli_abort(c(
        "x" = "Cached {.path {dest}} does not match the committed manifest (or has no row there).",
        "i" = "Cached sha256: {sha}; manifest sha256: {if (is.null(prev) || nrow(prev) != 1L) 'no manifest row' else prev$sha256}.",
        "i" = "Provenance cannot be vouched for. Re-fetch with {.code ALPACA_FORCE_REFETCH=1}."
      ))
    }
    if (!identical(prev$params, params)) {
      cli::cli_abort(c(
        "x" = "{.file {name}} was fetched with different parameters.",
        "i" = "Manifest: {prev$params}",
        "i" = "Now: {params}",
        "i" = "Re-fetch with {.code ALPACA_FORCE_REFETCH=1}."
      ))
    }
    cli::cli_inform("Already present, matches manifest: {.path {dest}} ({file.info(dest)$size} bytes). Not fetched.")
    return(data.frame(file = name, rows = prev$rows, sha256 = prev$sha256,
                      fetched_at = prev$fetched_at, params = prev$params,
                      stringsAsFactors = FALSE))
  }
  df <- build()
  if (nrow(df) == 0L) {
    cli::cli_abort(c(
      "x" = "Alpaca returned nothing for {.file {name}}.",
      "i" = "Refusing to write an empty cache: that would look like data and mean nothing."
    ))
  }
  dir.create(data_dir, recursive = TRUE, showWarnings = FALSE)
  arrow::write_parquet(df, dest)
  cli::cli_alert_success("Wrote {nrow(df)} row{?s} to {.path {dest}}")
  data.frame(
    file       = name,
    rows       = as.character(nrow(df)),
    sha256     = digest::digest(dest, algo = "sha256", file = TRUE),
    fetched_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    params     = params,
    stringsAsFactors = FALSE
  )
}

# Bars per ticker over its own window; "SPY" is added by the caller.
fetch_bars <- function(adjustment) {
  cli::cli_progress_bar(paste("Fetching Alpaca bars,", adjustment), total = nrow(exits))
  pieces <- vector("list", nrow(exits))
  for (i in seq_len(nrow(exits))) {
    b <- hd_alpaca_bars(
      exits$ticker[i], exits$win_start[i], exits$win_end[i],
      feed = FEED, adjustment = adjustment
    )
    # Belt and braces: the request window is already the clip window, but a
    # symbol must never carry bars outside it into the cache.
    pieces[[i]] <- b[b$date >= exits$win_start[i] & b$date <= exits$win_end[i], , drop = FALSE]
    cli::cli_progress_update()
  }
  cli::cli_progress_done()
  bars <- dplyr::bind_rows(pieces)
  missing_syms <- setdiff(exits$ticker, bars$symbol)
  if (length(missing_syms) > 0L) {
    cli::cli_inform(c(
      "i" = "{length(missing_syms)} requested ticker{?s} returned no {adjustment} bars (unknown to Alpaca, or no trades in the window): {.val {missing_syms}}"
    ))
  }
  bars
}

base_params <- sprintf("feed=%s;tickers=%d;window_days=%d;panel_start=%s",
                       FEED, nrow(exits), rule$window_days, format(rule$panel_start))

# ---- the three files --------------------------------------------------------
m_raw <- ensure_file(
  .hd_alpaca_exit_bars_file_name(),
  paste0("adjustment=raw;", base_params),
  function() {
    b <- fetch_bars("raw")
    b[order(b$symbol, b$date), , drop = FALSE]
  }
)

m_adj <- ensure_file(
  .hd_alpaca_exit_bars_adj_file_name(),
  paste0("adjustment=all;spy_start=", format(SPY_START), ";", base_params),
  function() {
    b <- fetch_bars("all")
    spy <- hd_alpaca_bars("SPY", SPY_START, Sys.Date(), feed = FEED, adjustment = "all")
    b <- dplyr::bind_rows(b, spy)
    b[order(b$symbol, b$date), , drop = FALSE]
  }
)

m_ca <- ensure_file(
  .hd_alpaca_exit_corp_actions_file_name(),
  sprintf("start=%s;types=%s;tickers=%d", format(CA_START),
          paste(CA_TYPES, collapse = ","), nrow(exits)),
  function() {
    hd_alpaca_corporate_actions(exits$ticker, CA_START, Sys.Date(), types = CA_TYPES)
  }
)

manifest <- rbind(m_raw, m_adj, m_ca)
dir.create(dirname(MANIFEST_PATH), recursive = TRUE, showWarnings = FALSE)
utils::write.csv(manifest, MANIFEST_PATH, row.names = FALSE)
cli::cli_alert_success("Manifest written: {.path {MANIFEST_PATH}}")
print(manifest[, c("file", "rows", "sha256")], row.names = FALSE)
cli::cli_inform("Raw files kept at {.path {data_dir}} -- NOT committed (see header).")
