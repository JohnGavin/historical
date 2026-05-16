#!/usr/bin/env Rscript
# Snapshot the Alpaca Markets `v2/assets` universe (#171).
#
# One-off discovery snapshot — NOT a daily fetch. Captures all 18 asset
# metadata fields for use as tradability-flag enrichment for
# `equity_daily` (see issue #171 acceptance criteria).
#
# Three calls produce three parquet files in inst/extdata/alpaca/:
#   1. us_equity / active   — currently-tradable US equities
#   2. us_equity / inactive — delisted US equities (independent #150 check)
#   3. crypto    / active   — currently-tradable crypto
#
# Credentials: requires ALPACA_KEY and ALPACA_SECRET in ~/.Renviron.
# See `?hd_alpaca_assets_snapshot` Credentials section. Paper-trading
# keys are sufficient (the assets endpoint returns the same data).
#
# Survivorship caveat (per `look-ahead-bias-prevention` rule + #150):
# A 2026 snapshot is NOT a "universe at time t" for any historical backtest.
# Pair active+inactive snapshots to start building a PIT universe.
#
# Usage: Rscript scripts/fetch_alpaca_assets.R

suppressPackageStartupMessages({
  library(here)
  library(pkgload)
})

pkgload::load_all(
  file.path(here::here(), "packages/historicaldata"),
  quiet = TRUE
)

out_dir <- file.path(here::here(), "packages", "historicaldata", "inst", "extdata", "alpaca")

# US equities — active (current universe)
hd_alpaca_assets_snapshot(
  out_dir     = out_dir,
  asset_class = "us_equity",
  status      = "active",
  min_rows    = 5000L
)

# US equities — inactive (delisted; independent #150 survivorship check)
hd_alpaca_assets_snapshot(
  out_dir     = out_dir,
  asset_class = "us_equity",
  status      = "inactive",
  min_rows    = 100L
)

# Crypto — active
hd_alpaca_assets_snapshot(
  out_dir     = out_dir,
  asset_class = "crypto",
  status      = "active",
  min_rows    = 10L
)
