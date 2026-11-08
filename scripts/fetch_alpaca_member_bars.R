#!/usr/bin/env Rscript
# fetch_alpaca_member_bars.R
#
# #1041: ADJUSTED Alpaca daily bars (adjustment = "all", feed = "sip") for EVERY
# ticker that was a point-in-time S&P 500 member on or after 2016-01-04, the
# date the sip feed starts. All members come from ONE source, so a monthly
# return never splices two data sources (hd_pit_monthly_returns()). One file:
#
#   alpaca_member_bars_adj.parquet    symbol, date, open..vwap
#
# WHICH TICKERS. Derived from the package, not re-parsed here:
# hd_sp500_pit_universe(hd_sp500_membership(hd_sp500_membership_path())). A
# ticker qualifies if it was still a member on 2016-01-04 or joined later: it
# is a current member, or its index_exit_date (the first snapshot without it)
# is on or after hd_alpaca_exit_rule()$panel_start. Plus, for every
# `ticker_change` exit (hd_alpaca_exit_prices() run on the cached exit files:
# run scripts/fetch_alpaca_exit_bars.R first), the NEW symbol, which is usually
# a member already; if it is not, it is fetched over the old ticker's window.
#
# WHICH BARS. Per ticker one request series over
#   [max(panel_start, first member date) - LOOKBACK_DAYS,
#    min(index_exit_date + LOOKBACK_DAYS, yesterday)]
# so a symbol later reused by another company is not pulled in beyond its
# window. A current member runs to yesterday. NOTE the end: a member stays a
# member until the next snapshot that omits it (index_exit_date), which can be
# months after the last snapshot that lists it, so the window ends at
# index_exit_date, not at the last listing date. LOOKBACK_DAYS = 45 gives the
# signal month and the held month after the last member month-end.
#
# CREDENTIALS. ALPACA_KEY and ALPACA_SECRET in the environment (the paper keys
# work for market data). They are read by the package functions; nothing here
# prints or stores them.
#
# DATA. The file goes to ALPACA_BARS_DIR (default
# ~/.cache/historical/alpaca_exit_bars/) and stays LOCAL. Only the manifest is
# committed:
#   packages/historicaldata/inst/extdata/alpaca/alpaca_member_bars_manifest.csv
# (file, rows, sha256, fetched_at, params).
#
# CACHE REUSE. If the file exists, its sha256 equals the manifest row's and the
# manifest's `params` equal this run's, it is not fetched. A sha256 mismatch, a
# missing manifest row, or changed params ABORTS (provenance cannot be vouched
# for); set ALPACA_FORCE_REFETCH=1 to fetch again on purpose (parsed strictly:
# 1/true/TRUE/yes or 0/false/FALSE/no; anything else aborts). The params include
# a digest of the ticker|window request set.
#
# Usage, from the repo root:
#   nix develop <repo> --command Rscript scripts/fetch_alpaca_member_bars.R

suppressPackageStartupMessages({
  library(cli)
})

pkgload::load_all(here::here("packages", "historicaldata"), quiet = TRUE)

FEED          <- "sip"
LOOKBACK_DAYS <- 45L
# Free Alpaca plans refuse SIP data from the last 15 minutes (HTTP 403), so
# requests that run to "now" stop at yesterday instead.
FETCH_END     <- Sys.Date() - 1L
MANIFEST_PATH <- here::here(
  "packages", "historicaldata", "inst", "extdata", "alpaca",
  "alpaca_member_bars_manifest.csv"
)

rule <- hd_alpaca_exit_rule()
data_dir <- hd_alpaca_bars_data_dir()

# ---- which tickers, and over what windows ----------------------------------
membership <- hd_sp500_membership(hd_sp500_membership_path())
u <- hd_sp500_pit_universe(membership)
exits <- hd_sp500_exits(membership)

tk <- sort(unique(u$ticker))
first_member <- as.Date(vapply(tk, function(t) as.numeric(min(u$date[u$ticker == t])), numeric(1)),
                        origin = "1970-01-01")
exit_date <- exits$index_exit_date[match(tk, exits$ticker)]   # NA = still a member
wins <- data.frame(
  ticker    = tk,
  win_start = pmax(first_member, rule$panel_start) - LOOKBACK_DAYS,
  win_end   = pmin(ifelse(is.na(exit_date), as.numeric(FETCH_END),
                          as.numeric(exit_date) + LOOKBACK_DAYS),
                   as.numeric(FETCH_END)),
  stringsAsFactors = FALSE
)
wins$win_end <- as.Date(wins$win_end, origin = "1970-01-01")
keep <- is.na(exit_date) | exit_date >= rule$panel_start
n_pre <- sum(!keep)
wins <- wins[keep, , drop = FALSE]
if (nrow(wins) == 0L) {
  cli::cli_abort("No S&P 500 member on or after {.val {format(rule$panel_start)}}: nothing to fetch. Check the membership file.")
}

# New symbols of ticker changes (needs the exit files the other script writes).
ex_bars <- tibble::as_tibble(arrow::read_parquet(hd_alpaca_exit_bars_path()))
ex_adj  <- tibble::as_tibble(arrow::read_parquet(hd_alpaca_exit_bars_adj_path()))
ex_ca   <- tibble::as_tibble(arrow::read_parquet(hd_alpaca_exit_corp_actions_path()))
prices <- hd_alpaca_exit_prices(
  ex_bars, ex_adj, ex_ca, exits,
  known_failed = hd_sp500_known_delisted()$ticker
)
chg <- prices[prices$exit_type == "ticker_change" & !is.na(prices$new_ticker), , drop = FALSE]
extra <- chg[!(chg$new_ticker %in% wins$ticker), , drop = FALSE]
if (nrow(extra) > 0L) {
  old_w <- wins[match(extra$ticker, wins$ticker), , drop = FALSE]
  extra_w <- data.frame(
    ticker = extra$new_ticker, win_start = old_w$win_start,
    win_end = old_w$win_end, stringsAsFactors = FALSE
  )
  # One request series per symbol: widen if the symbol is renamed to twice.
  extra_w <- do.call(rbind, lapply(split(extra_w, extra_w$ticker), function(d) {
    data.frame(ticker = d$ticker[1L], win_start = min(d$win_start),
               win_end = max(d$win_end), stringsAsFactors = FALSE)
  }))
  wins <- rbind(wins, extra_w)
}
wins <- wins[order(wins$ticker), , drop = FALSE]
cli::cli_inform(c(
  "i" = "{nrow(wins)} ticker{?s} to fetch ({nrow(extra)} new symbol{?s} of ticker changes that {?is/are} not members).",
  "i" = "{n_pre} earlier leaver{?s} (index exit before {format(rule$panel_start)}) have no free price source and are not requested."
))

force_refetch <- .hd_env_flag("ALPACA_FORCE_REFETCH")
existing <- if (file.exists(MANIFEST_PATH)) {
  utils::read.csv(MANIFEST_PATH, stringsAsFactors = FALSE, colClasses = "character")
} else NULL

# Fetch the file, or keep the cached one if it matches the manifest. Returns its
# one-row manifest data frame.
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
      # Show only the key=value pieces that differ: a whole params string is
      # one long unbreakable token that cli wraps onto a continuation line.
      old_p <- strsplit(prev$params, ";", fixed = TRUE)[[1L]]
      new_p <- strsplit(params, ";", fixed = TRUE)[[1L]]
      only_manifest <- setdiff(old_p, new_p)
      only_now <- setdiff(new_p, old_p)
      cli::cli_abort(c(
        "x" = "{.file {name}} was fetched with different parameters.",
        "i" = "In the manifest only: {.val {only_manifest}}",
        "i" = "In this run only: {.val {only_now}}",
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

# Bars per ticker over its own window.
fetch_bars <- function() {
  cli::cli_progress_bar("Fetching Alpaca member bars", total = nrow(wins))
  pieces <- vector("list", nrow(wins))
  for (i in seq_len(nrow(wins))) {
    b <- hd_alpaca_bars(
      wins$ticker[i], wins$win_start[i], wins$win_end[i],
      feed = FEED, adjustment = "all"
    )
    # Belt and braces: a symbol must never carry bars outside its window.
    pieces[[i]] <- b[b$date >= wins$win_start[i] & b$date <= wins$win_end[i], , drop = FALSE]
    cli::cli_progress_update()
  }
  cli::cli_progress_done()
  bars <- dplyr::bind_rows(pieces)
  missing_syms <- setdiff(wins$ticker, bars$symbol)
  if (length(missing_syms) > 0L) {
    cli::cli_inform(c(
      "i" = "{length(missing_syms)} requested ticker{?s} returned no bars (unknown to Alpaca, or no trades in the window): {.val {missing_syms}}"
    ))
  }
  bars[order(bars$symbol, bars$date), , drop = FALSE]
}

# request= is a digest of the sorted ticker|win_start|win_end lines, so a changed
# ticker SET or changed windows (same count) cannot reuse a stale cache.
request_digest <- .hd_alpaca_request_digest(wins$ticker, wins$win_start, wins$win_end)
params <- sprintf("adjustment=all;feed=%s;tickers=%d;request=%s;lookback_days=%d;panel_start=%s",
                  FEED, nrow(wins), request_digest, LOOKBACK_DAYS,
                  format(rule$panel_start))

manifest <- ensure_file(.hd_alpaca_member_bars_adj_file_name(), params, fetch_bars)
dir.create(dirname(MANIFEST_PATH), recursive = TRUE, showWarnings = FALSE)
utils::write.csv(manifest, MANIFEST_PATH, row.names = FALSE)
cli::cli_alert_success("Manifest written: {.path {MANIFEST_PATH}}")
print(manifest[, c("file", "rows", "sha256")], row.names = FALSE)
cli::cli_inform("Raw file kept at {.path {data_dir}} -- NOT committed (see header).")
