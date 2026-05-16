# Snapshot the Yahoo Finance screener for UK-listed ETFs.
#
# One-off discovery snapshot — NOT a daily fetch. Re-run to update the
# universe roster. Output is a parquet under
# `packages/historicaldata/inst/extdata/yahoo/`.
#
# This is the Phase 1.5 deliverable from issue #168 — it answers
# "which LSE ETFs exist" without requiring the IBKR Client Portal gateway,
# unblocking ETF selection ahead of IBKR conid resolution.
#
# Survivorship caveat: yfscreen returns CURRENTLY-ACTIVE symbols only.
# Do NOT use a 2026 snapshot as a "universe at time t" for any backtest.
# See `look-ahead-bias-prevention` rule and issue #150.
#
# Usage:
#   Rscript scripts/fetch_yahoo_uk_etfs.R

library(historicaldata)

out_dir <- file.path("packages", "historicaldata", "inst", "extdata", "yahoo")

hd_yahoo_screen_snapshot(
  region   = "gb",
  sec_type = "etf",
  out_dir  = out_dir,
  min_rows = 50L  # UK ETF universe is hundreds of symbols; <50 = schema break
)
