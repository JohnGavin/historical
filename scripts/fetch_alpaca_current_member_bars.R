#!/usr/bin/env Rscript
# fetch_alpaca_current_member_bars.R
#
# #1041: ADJUSTED Alpaca daily bars (adjustment = "all", feed = "sip") for
# TODAY's S&P 500 members, over the WHOLE backtest window. They feed the fourth
# variant of the stock MAX comparison, `current_members`: today's index members
# carried back to 2016, which has the survivors' hindsight but the size range of
# the point-in-time (PIT) variants. One file:
#
#   alpaca_current_member_bars_adj.parquet    symbol, date, open..vwap
#
# WHICH TICKERS. The members on the LATEST snapshot date of
# hd_sp500_pit_universe(hd_sp500_membership(hd_sp500_membership_path())). Plus,
# for every current ticker that is the END of a `ticker_change` chain
# (hd_alpaca_exit_prices() run on the cached exit files: run
# scripts/fetch_alpaca_exit_bars.R first), the OLD symbol(s) of that chain, so a
# renamed company's pre-rename history exists (e.g. META: FB). The old symbols
# come from the same chain rule the PIT returns use (.hd_pit_permanent_id()).
#
# WHICH BARS. Every symbol over the same window
#   [panel_start - LOOKBACK_DAYS, yesterday]
# (LOOKBACK_DAYS = 45 gives a signal month before the first held month). A
# symbol later reused by another company is handled downstream by
# hd_trim_symbol_reuse(), not here. Every symbol has the same window, so there
# is no per-symbol window that could be NA (the failure roborev 15479 found in
# fetch_alpaca_member_bars.R); the check below aborts if a symbol is NA anyway.
#
# OLD SYMBOLS ARE FETCHED BUT NOT USED. The targets (R/plan_pit_max.R,
# pit_current_member_bars()) keep only bars whose symbol is a current member and
# do not splice renames: Alpaca returns a renamed company's full history under its
# CURRENT symbol (META, FISV, DOC: 2016 to now, no gaps), and several old symbols
# were later reused by other companies (HCP: Healthpeak to 2019, then HashiCorp
# 2021-12 to 2025-02), so splicing them corrupts the current company's series.
# The fetch is left unchanged so that its manifest params, and the cached file,
# stay valid (changing them would force a re-fetch).
#
# CREDENTIALS. ALPACA_KEY and ALPACA_SECRET in the environment (the paper keys
# work for market data). They are read by the package functions; nothing here
# prints or stores them.
#
# DATA. The file goes to ALPACA_BARS_DIR (default
# ~/.cache/historical/alpaca_exit_bars/) and stays LOCAL. Only the manifest is
# committed:
#   packages/historicaldata/inst/extdata/alpaca/alpaca_current_member_bars_manifest.csv
# (file, rows, sha256, fetched_at, params).
#
# CACHE REUSE. If the file exists, its sha256 equals the manifest row's and the
# manifest's `params` equal this run's, it is not fetched. A sha256 mismatch, a
# missing manifest row, or changed params ABORTS (provenance cannot be vouched
# for); set ALPACA_FORCE_REFETCH=1 to fetch again on purpose (parsed strictly:
# 1/true/TRUE/yes or 0/false/FALSE/no; anything else aborts). The params include
# a digest of the ticker|window request set. NOTE the window ends at yesterday,
# so the request digest changes every day: a later run aborts on changed params
# and needs ALPACA_FORCE_REFETCH=1.
#
# Usage, from the repo root:
#   nix develop <repo> --command Rscript scripts/fetch_alpaca_current_member_bars.R

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
  "alpaca_current_member_bars_manifest.csv"
)

rule <- hd_alpaca_exit_rule()
data_dir <- hd_alpaca_bars_data_dir()
win_start <- rule$panel_start - LOOKBACK_DAYS

# ---- which tickers ---------------------------------------------------------
membership <- hd_sp500_membership(hd_sp500_membership_path())
u <- hd_sp500_pit_universe(membership)
latest <- max(u$date)
current <- sort(unique(u$ticker[u$date == latest]))
if (length(current) == 0L) {
  cli::cli_abort("No member on the latest snapshot {.val {format(latest)}}: nothing to fetch. Check the membership file.")
}

# Old symbols of renames whose chain ends at a current ticker (needs the exit
# files the other script writes).
ex_bars <- tibble::as_tibble(arrow::read_parquet(hd_alpaca_exit_bars_path()))
ex_adj  <- tibble::as_tibble(arrow::read_parquet(hd_alpaca_exit_bars_adj_path()))
ex_ca   <- tibble::as_tibble(arrow::read_parquet(hd_alpaca_exit_corp_actions_path()))
prices <- hd_alpaca_exit_prices(
  ex_bars, ex_adj, ex_ca, hd_sp500_exits(membership),
  known_failed = hd_sp500_known_delisted()$ticker
)
chg <- prices[prices$exit_type == "ticker_change" & !is.na(prices$new_ticker), , drop = FALSE]
chg_end <- .hd_pit_permanent_id(chg$ticker, prices)
old_syms <- sort(unique(setdiff(chg$ticker[chg_end %in% current], current)))

symbols <- sort(unique(c(current, old_syms)))
if (anyNA(symbols) || !all(nzchar(symbols))) {
  cli::cli_abort("A requested symbol is NA or empty: refusing to send a malformed request.")
}
wins <- data.frame(ticker = symbols, win_start = win_start, win_end = FETCH_END,
                   stringsAsFactors = FALSE)
cli::cli_inform(c(
  "i" = "{length(current)} current member{?s} on the latest snapshot {.val {format(latest)}}, plus {length(old_syms)} old symbol{?s} of renames: {nrow(wins)} ticker{?s} to fetch.",
  "i" = "Window for every symbol: {.val {format(win_start)}} to {.val {format(FETCH_END)}}.",
  "i" = "Old symbols: {.val {old_syms}}"
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
      cli::cli_abort(.hd_params_diff_bullets(name, prev$params, params))
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

# Bars per ticker over the common window.
fetch_bars <- function() {
  cli::cli_progress_bar("Fetching Alpaca current-member bars", total = nrow(wins))
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
# ticker SET or changed window (same count) cannot reuse a stale cache.
request_digest <- .hd_alpaca_request_digest(wins$ticker, wins$win_start, wins$win_end)
params <- sprintf("adjustment=all;feed=%s;tickers=%d;request=%s;lookback_days=%d;panel_start=%s;snapshot=%s",
                  FEED, nrow(wins), request_digest, LOOKBACK_DAYS,
                  format(rule$panel_start), format(latest))

manifest <- ensure_file(.hd_alpaca_current_member_bars_adj_file_name(), params, fetch_bars)
dir.create(dirname(MANIFEST_PATH), recursive = TRUE, showWarnings = FALSE)
utils::write.csv(manifest, MANIFEST_PATH, row.names = FALSE)
cli::cli_alert_success("Manifest written: {.path {MANIFEST_PATH}}")
print(manifest[, c("file", "rows", "sha256")], row.names = FALSE)
cli::cli_inform("Raw file kept at {.path {data_dir}} -- NOT committed (see header).")
