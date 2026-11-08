#!/usr/bin/env Rscript
# fetch_alpaca_exit_bars.R
#
# #1041: daily bars from Alpaca (sip feed, raw prices) for every ticker that
# left the point-in-time S&P 500 on or after 2016-01-04, the date the sip feed
# starts. Used to price index leavers (hd_alpaca_exit_prices()); the 464
# leavers before that date have no free source and are not requested.
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
# keys work for market data). They are read by hd_alpaca_bars(); nothing here
# prints or stores them.
#
# DATA. Bars go to ALPACA_BARS_DIR (default ~/.cache/historical/alpaca_exit_bars/)
# as alpaca_exit_bars.parquet and stay LOCAL (same posture as the S&P 500
# membership file and OSAP). Only the manifest is committed:
#   packages/historicaldata/inst/extdata/alpaca/alpaca_exit_bars_manifest.csv
# (symbols requested, symbols returned, rows, sha256, fetched_at, feed).
#
# CACHE REUSE. If the parquet exists and its sha256 equals the manifest's, and
# the number of tickers requested still equals the manifest's, nothing is
# fetched. A sha256 mismatch, a missing manifest, or a changed request list
# ABORTS (provenance cannot be vouched for); set ALPACA_FORCE_REFETCH=1 to
# fetch again on purpose.
#
# Usage, from the repo root:
#   nix develop <repo> --command Rscript scripts/fetch_alpaca_exit_bars.R

suppressPackageStartupMessages({
  library(cli)
})

pkgload::load_all(here::here("packages", "historicaldata"), quiet = TRUE)

FEED       <- "sip"
ADJUSTMENT <- "raw"
MANIFEST_PATH <- here::here(
  "packages", "historicaldata", "inst", "extdata", "alpaca",
  "alpaca_exit_bars_manifest.csv"
)

rule <- hd_alpaca_exit_rule()
data_dir <- hd_alpaca_bars_data_dir()
dest <- file.path(data_dir, .hd_alpaca_exit_bars_file_name())

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

if (file.exists(dest) && !force_refetch) {
  cached_sha <- digest::digest(dest, algo = "sha256", file = TRUE)
  if (is.null(existing) || nrow(existing) != 1L || !identical(existing$sha256, cached_sha)) {
    cli::cli_abort(c(
      "x" = "Cached {.path {dest}} does not match the committed manifest (or there is none).",
      "i" = "Cached sha256: {cached_sha}; manifest sha256: {if (is.null(existing)) 'no manifest' else existing$sha256[1L]}.",
      "i" = "Provenance cannot be vouched for. Re-fetch with {.code ALPACA_FORCE_REFETCH=1}."
    ))
  }
  if (!identical(as.integer(existing$symbols_requested), nrow(exits))) {
    cli::cli_abort(c(
      "x" = "The cache was fetched for {existing$symbols_requested} ticker{?s}; the membership file now has {nrow(exits)} exit{?s} in range.",
      "i" = "Re-fetch with {.code ALPACA_FORCE_REFETCH=1}."
    ))
  }
  cli::cli_inform("Already present, matches manifest: {.path {dest}} ({file.info(dest)$size} bytes). Nothing fetched.")
  quit(save = "no", status = 0L)
}

# ---- fetch -----------------------------------------------------------------
cli::cli_progress_bar("Fetching Alpaca bars", total = nrow(exits))
pieces <- vector("list", nrow(exits))
for (i in seq_len(nrow(exits))) {
  b <- hd_alpaca_bars(
    exits$ticker[i], exits$win_start[i], exits$win_end[i],
    feed = FEED, adjustment = ADJUSTMENT
  )
  # Belt and braces: the request window is already the clip window, but a
  # symbol must never carry bars outside it into the cache.
  pieces[[i]] <- b[b$date >= exits$win_start[i] & b$date <= exits$win_end[i], , drop = FALSE]
  cli::cli_progress_update()
}
cli::cli_progress_done()
bars <- dplyr::bind_rows(pieces)
if (nrow(bars) == 0L) {
  cli::cli_abort(c(
    "x" = "Alpaca returned no bars for any of {nrow(exits)} ticker{?s}.",
    "i" = "Refusing to write an empty cache: that would look like data and mean nothing."
  ))
}
bars <- bars[order(bars$symbol, bars$date), , drop = FALSE]

dir.create(data_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(dirname(MANIFEST_PATH), recursive = TRUE, showWarnings = FALSE)
arrow::write_parquet(bars, dest)

returned <- length(unique(bars$symbol))
manifest <- data.frame(
  file              = basename(dest),
  symbols_requested = nrow(exits),
  symbols_returned  = returned,
  rows              = nrow(bars),
  first_date        = as.character(min(bars$date)),
  last_date         = as.character(max(bars$date)),
  bytes             = file.info(dest)$size,
  sha256            = digest::digest(dest, algo = "sha256", file = TRUE),
  fetched_at        = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  feed              = FEED,
  adjustment        = ADJUSTMENT,
  note              = "Daily bars for S&P 500 index leavers, window = membership span +/- window_days. Raw file kept LOCAL, not committed.",
  stringsAsFactors  = FALSE
)
utils::write.csv(manifest, MANIFEST_PATH, row.names = FALSE)

missing_syms <- setdiff(exits$ticker, bars$symbol)
cli::cli_alert_success("Wrote {nrow(bars)} bar{?s} for {returned} of {nrow(exits)} ticker{?s} to {.path {dest}}")
cli::cli_alert_success("Manifest written: {.path {MANIFEST_PATH}}")
if (length(missing_syms) > 0L) {
  cli::cli_inform(c(
    "i" = "{length(missing_syms)} requested ticker{?s} returned no bars (unknown to Alpaca, or no trades in the window): {.val {missing_syms}}"
  ))
}
print(manifest[, c("symbols_requested", "symbols_returned", "rows", "sha256", "feed")], row.names = FALSE)
cli::cli_inform("Raw file kept at {.path {data_dir}} -- NOT committed (see header).")
