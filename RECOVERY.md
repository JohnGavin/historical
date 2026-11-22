---
gitignore: false
note: This file is committed. It holds restore instructions, not secrets. Credentials stay in .Renviron. The repository is public, so nothing here names a person, host, drive or volume.
---

# RECOVERY: historical

Restore instructions for the state in this project that `git` plus a deterministic
pipeline cannot rebuild. Update this file whenever a fetcher, a data file or the
backup set changes. Test the restore at least once a quarter and record it under
[Last drill](#last-drill).

**Short version.** Everything under `data/dist/` and `data/raw/` is gitignored and
exists only on this Mac, except eight datasets that are also on the public Hugging
Face dataset `finance-data`. Most files can be fetched again from their source. The
Hyperliquid 5-minute snapshots, the open-interest snapshots, the market-reference
history and the part of the hourly and 15-minute bars older than the API window
cannot, and their only backup is Time Machine. That is one failure domain with no
off-site copy; see [Residual risks](#residual-risks).

`scripts/check_backup.sh` says whether the newest Time Machine snapshot is newer than
the newest data file. The weekly Hyperliquid job runs it and logs the result.

## What Needs Backing Up

Classification of every file under `data/dist/` and `data/raw/`, by what produces it
and whether it can be fetched again.

Why a table here and not a generated list: `data/` is gitignored, so a generator has
no data to read in CI or in a fresh checkout, and the facts that matter (API retention,
who else holds a copy) are not in the files. The table is grouped by producing script,
which changes rarely. To catch drift, list what exists and compare with the table:

```sh
ls data/dist data/raw data/raw/hyperliquid
```

A file that is not in the table is **unclassified: treat it as unrecoverable** until
someone classifies it here.

Legend. **Refetch** = the source still serves it; the script named is the one to run
(each reads its source and rewrites the file). **Backup only** = no source serves it
again, so a lost copy is lost. **HF** = also on the public Hugging Face dataset
(restorable from there; the dataset id is the default of `hd_base_url()` in
`packages/historicaldata/R/registry.R`).

### Hyperliquid, `data/dist/`

Hyperliquid data are perpetual futures on an on-chain exchange, not shares. The API
keeps only the most recent 5000 bars per interval (`HL_CANDLE_PAGE_MAX` in
`scripts/fetch_hyperliquid.R`), which is a bar count, not a time window.

| File | What | Refetch? | For how long |
|---|---|---|---|
| `perp_daily.parquet`, `spot_daily.parquet` | daily bars | Refetch: `scripts/fetch_hyperliquid.R --intervals=1d` | 5000 daily bars, about 13 years: all of it today. A market the API stops listing would lose its bars from the source |
| `perp_hourly.parquet`, `spot_hourly.parquet` | hourly bars | Refetch the last window only | about 208 days. **Older rows are backup only** |
| `perp_15m.parquet`, `spot_15m.parquet` | 15-minute bars | Refetch the last window only | about 52 days. **Older rows are backup only** |
| `perp_funding.parquet`, `perp_funding_daily.parquet` | funding rows and their daily sums | Refetch: `fetch_hyperliquid.R --funding=true` | the API serves the full funding history |
| `perp_oi_snapshot.parquet` | open interest, one snapshot per run | **Backup only** | the API has no open-interest history: only the current value exists |
| `perp_ctx_5m/date=YYYY-MM-DD/<collector>.parquet` (before PR #1086: one file `perp_ctx_5m.parquet`) | 5-minute mid, oracle and mark prices, funding, open interest, volume per market | **Backup only** | `metaAndAssetCtxs` has no history. Can be rebuilt from its raw files (below), not from the API |
| `perp_dexs.parquet` | exchange reference table | Refetch: `fetch_hyperliquid.R` | current list only |
| `perp_markets.parquet` | market long names, categories, definitions | Refetch the current page: `scripts/fetch_hl_market_reference.R` | a market that drops off the exchange's page keeps its last text only here. **Names of delisted markets are backup only** |
| `hl_progress.txt` | resume marker of a running fetch | not data | delete freely when no fetch is running |

### Hyperliquid, `data/raw/hyperliquid/`

| Folder | What | Refetch? |
|---|---|---|
| `<UTC date>/*.json` and `*.md` | the weekly fetch's raw replies (candles, funding, `allPerpMetas`, current contexts, the saved specification page) | The candle and funding replies can be fetched again within the windows above. The saved page and the contexts of that day are **backup only**. The parquet files above are derived from these and survive without them; losing them loses the audit trail |
| `ctx_poll/<UTC date>/<collector>_<HHMMSS>.json.gz` | one gzipped file per 5-minute run, every reply and its `fetched_at` | **Backup only.** It is the source for rebuilding a day of `perp_ctx_5m` (see Restore Steps). Never uploaded: raw Hyperliquid replies are not redistributed |

### Other files in `data/dist/`

| File | What | Refetch? | HF |
|---|---|---|---|
| `crypto_daily.parquet` | crypto daily bars via Yahoo Finance | Refetch (`fetch_crypto.R`) | yes |
| `equity_daily.parquet` | equity daily bars via yfinance | Refetch (`fetch_equity.py`); Yahoo may revise adjusted prices and drop delisted tickers | yes |
| `factors.parquet` | Fama-French factors | Refetch (`fetch_factors.R`) | yes |
| `macro_daily.parquet` | daily macro and volatility panel | Rebuild (`build_macro_daily.R`) from the `data/raw` files below | yes |
| `macro_vintages.parquet` | FRED/ALFRED vintages: each value as first published | Refetch (`fetch_macro_vintages.R`, FRED key needed) | yes |
| `metadata.parquet` | ticker metadata | Refetch and enrich (`fetch_metadata.py`, `enrich_metadata.py`) | yes |
| `metadata_amendments.parquet` | log of corrections made to metadata, with old values and time | **Backup only**: it records edits made here, not a source's data | yes: **the HF copy is the second backup** |

### Other files in `data/raw/`

| File | Source | Refetch? |
|---|---|---|
| `fred_macro.parquet` | FRED | Refetch (`fetch_macro.R`); revised values replace old ones, so a refetch is not identical |
| `cboe_vol.parquet`, `intl_vol.parquet` | CBOE CDN, STOXX files, Yahoo | Refetch (`fetch_cboe_vol.R`, `fetch_intl_vol.R`) |
| `ecb_series.parquet` | ECB | Refetch (`fetch_ecb.R`) |
| `french_factors.parquet` | Ken French data library | Refetch (`fetch_factors.R`) |
| `macro_daily_combined.parquet` | derived from the three rows above | Rebuild |
| `crypto_all.parquet` | Yahoo Finance | Refetch (`fetch_crypto.R`) |
| `yfinance_equity.parquet`, `yfinance_aapl.parquet` | Yahoo Finance | Refetch (`fetch_equity.py`) |
| `commodities.parquet` | FRED and Yahoo | Refetch (`fetch_commodities.R`) |
| `commodities_long_run.parquet` | AQR workbook | Refetch (`fetch_commodities_long_run.R`) while AQR keeps the file at that address |
| `guardian_monthly.parquet` | Guardian API | Refetch (`fetch_guardian.R`) |
| `kalshi_fomc.parquet` | Kalshi public API | Refetch (`fetch_kalshi.R`). How long Kalshi serves settled markets is **not verified**: treat as at risk |
| `nyt_keywords.parquet` | pre-processed files of a third-party GitHub project | Refetch (`parse_nyt_tedalcorn.R`) while that project stays online |
| `ltr_features.parquet`, `ltr_portfolio.parquet`, `ltr_model_importance.parquet` | computed here | Rebuild (`compute_ltr_features.R`, `compute_ltr_model.R`); a model refit need not match bit for bit |
| `metadata.parquet`, `metadata_amendments.parquet` | as in `data/dist` | as in `data/dist`; also on HF |
| `kaggle_aapl.csv` | manual download from Kaggle | Download again by hand (account needed) |
| `btc_backfill.parquet`, `btc_backfill.csv`, `geckor_btc.parquet` | a copy made from another local project, and an early CoinGecko pull (`PLAN.md`) | Provenance not recorded here: **treat as backup only** until the source is written down |
| `kraken_ohlcvt.parquet` (when present) | built by `fetch_kraken_ohlcvt.R` from a Kraken archive zip that is itself held only on this Mac | **Backup only**; on HF (restore from there) |

## Where Backups Live

| Asset | Backup | Failure domain | Retention |
|---|---|---|---|
| Everything in `data/dist/` and `data/raw/` | Time Machine to external drives (three destinations are configured) | Different physical drive, **same location and same machine owner**; no off-site copy | Time Machine's own thinning; snapshots seen go back to 2023 |
| The eight datasets in the HF row above | Public Hugging Face dataset `finance-data` | Different provider | Hugging Face's, with git history of the dataset |
| Fetcher and pipeline code | `git` remote | Different provider | full history |

Not backed up anywhere else: the 5-minute snapshots, the open-interest snapshots, the
Hyperliquid raw replies and the older hourly and 15-minute bars. They cannot go on
Hugging Face as things stand (`fetch_hyperliquid.R`: raw "NEVER uploaded or
redistributed"; publication of the derived files is an open follow-up).

**Failure-domain check (done):** an external Time Machine drive is a different volume
from the Mac's disk, so it passes the "not the same volume" test. It does not survive
loss of the whole location (fire, theft), and it only holds data that existed at the
last time a drive was connected. See Residual risks.

## RPO (Recovery Point Objective)

Maximum data loss on a full disaster of this Mac:

| Asset | RPO | Basis |
|---|---|---|
| Refetchable files | none for the source's retained window | fetch again |
| Unrecoverable files (5-minute, open interest, market names, old bars) | the age of the newest snapshot at the time of the loss | Time Machine runs hourly **while a backup drive is connected**. A drive is not always connected, so in practice the RPO is the time since the last connection: days, sometimes more. `scripts/check_backup.sh` measures exactly this gap |
| The eight HF datasets | the last upload to Hugging Face | uploads are manual (`scripts/upload_hf.sh`) |

The 5-minute poller adds a row set every 5 minutes, so every hour without a snapshot
puts about 12 polls at risk, and the data from a poll missed while the Mac sleeps never
existed (gaps are expected and are not backed up because they are not data).

## RTO (Recovery Time Objective)

Not yet measured (no drill). Expected, to be confirmed by the first drill:

| Step | Estimate | Bottleneck |
|---|---|---|
| Copy `data/` back from Time Machine | minutes to an hour | drive read speed |
| Restore the HF datasets | minutes | download |
| Refetch Hyperliquid candles and funding | hours | rate limit (the weekly fetch paces itself under 1200 weight a minute) |
| Rebuild a day of `perp_ctx_5m` from raw | seconds a day | none |

## Restore Steps

Run from the repository root. Check out the repository with `git` first, then:

1. **Connect a backup drive and open Time Machine** (menu bar, "Browse Time Machine
   Backups"), or list snapshots with `tmutil listbackups`. Choose the newest snapshot.
   Inspecting is read-only; do not start a backup or change a destination while
   recovering.
2. **Restore `data/`** from that snapshot into the checkout, in Time Machine's
   window ("Restore"), or from a terminal after setting the two variables to the
   snapshot's copy of `data` and this checkout's `data` folder:

   ```sh
   SRC="<the data folder inside the snapshot, from tmutil listbackups>"
   DEST="$PWD/data"
   tmutil restore -v "$SRC" "$DEST"
   ```

   If Time Machine reports a name collision, restore into an empty folder
   (`DEST=$(mktemp -d)`) and copy across.
3. **Restore the HF datasets that are missing or older** (the dataset id is the
   default in `hd_base_url()`; set it first):

   ```sh
   HF_REPO="<dataset id from hd_base_url()>"
   hf download "$HF_REPO" crypto_daily.parquet equity_daily.parquet factors.parquet macro_daily.parquet macro_vintages.parquet metadata.parquet metadata_amendments.parquet --repo-type dataset --local-dir data/dist
   hf download "$HF_REPO" kraken_ohlcvt.parquet --repo-type dataset --local-dir data/raw
   ```

4. **Refetch what the source still serves**, after steps 1 to 3 so the fetch only has
   to fill the gap (it upserts and resumes):

   ```sh
   nix develop . --command Rscript scripts/fetch_hyperliquid.R --intervals=1d,1h,15m --resume
   nix develop . --command Rscript scripts/fetch_hl_market_reference.R
   ```

   The other fetchers are named in the tables above; run those whose file is missing.
5. **Rebuild any day of the 5-minute table that is missing** but whose raw files are
   present (the replay reads only `data/raw/hyperliquid/ctx_poll/`; it never calls
   the API and its result equals what the poller wrote). Example for one day, change
   the date:

   ```sh
   DAY=2026-11-20 nix develop . --command Rscript -e 'source("scripts/poll_hyperliquid_ctx.R"); r <- hl_ctx_replay_day(as.Date(Sys.getenv("DAY")), "data/raw/hyperliquid", "data/dist/perp_ctx_5m"); str(r)'
   ```

6. **Verify** (next section). Do not resume the launchd jobs' normal reporting until
   the checks pass.

## Verification

Print row counts and date ranges, then compare with the figures recorded at the last
drill:

```sh
nix develop . --command Rscript -e 'for (f in list.files("data/dist", "[.]parquet$", full.names = TRUE)) { d <- arrow::read_parquet(f); cat(basename(f), nrow(d), "rows\n") }; source("scripts/poll_hyperliquid_ctx.R"); d <- hl_ctx_read("data/dist/perp_ctx_5m"); cat("perp_ctx_5m", nrow(d), "rows,", format(min(d$fetched_at)), "to", format(max(d$fetched_at)), "\n")'
```

For the 5-minute data, also prove the restored files against their raw source: replay
one restored day into an **empty** folder and compare its row count with that day's
file.

```sh
DAY=2026-11-20 nix develop . --command Rscript -e 'source("scripts/poll_hyperliquid_ctx.R"); day <- as.Date(Sys.getenv("DAY")); out <- tempfile(); r <- hl_ctx_replay_day(day, "data/raw/hyperliquid", out); live <- hl_ctx_read("data/dist/perp_ctx_5m"); n_live <- sum(as.Date(live$fetched_at, tz = "UTC") == day); cat("replay", r$n_rows, "rows; live file", n_live, "rows\n")'
```

The two numbers must be equal. Then run `scripts/check_backup.sh`: after a restore it
should print PASS once a new snapshot exists.

| Asset | Check | Expected minimum | Last verified |
|---|---|---|---|
| each `data/dist/*.parquet` | row count printed above | the count recorded at the last drill (none yet: record at the first drill) | never |
| `perp_ctx_5m` | replay of one day equals its live file | equal | never |

## Owner

| Role | Name / contact |
|---|---|
| Primary owner | the repository owner (contact through the repository's issue tracker) |
| Backup owner | none |

## Last Drill

| Date | Who | Outcome | Notes |
|---|---|---|---|
| not yet drilled | none | none | Written 2026-11-22. First drill due before the next quarter ends |

**Drill procedure:** restore into an empty scratch folder, never over the live `data/`
(Restore Steps 1 to 3 with `DEST` pointing at the scratch folder). Run the Verification
commands against that folder (`data/dist` becomes the scratch path). Record row counts,
the replay comparison, the time it took (for RTO) and whether any step failed. Commit
this file.

Cadence: quarterly (next due: 2027-02-22).

## Residual risks

Stated so they are decided, not discovered:

- **No off-site copy of the unrecoverable data.** Time Machine drives sit in one
  place. Whether to add an encrypted off-site copy is the owner's decision; Hugging
  Face is excluded for the raw replies by the project's own rule.
- **Time Machine is only as current as the last connection.** `scripts/check_backup.sh`
  makes that visible weekly; it does not make a backup happen.
- **The check reads recorded dates, not a restore.** A PASS means a snapshot newer than
  the data is recorded; only a drill proves it can be read back.
- **The 15-minute and hourly windows keep shrinking history.** Each week the API drops
  its oldest bars; the weekly fetch is what stops the loss, so a missed fetch is
  permanent loss after about 52 days (15-minute) or 208 days (hourly).
