# Data sources

This file records data sources we know about. A source listed under "Known, not ingested" is NOT used by any target; it is a pointer for when a strategy needs it. Figures enter the pipeline only from a primary source through committed, tested parser code.

## Ingested: Hyperliquid candles, funding and open interest, primary copy on Hugging Face (#870, #1080, #1088)

| Source | Written by | Published to | Terms on redistribution |
|---|---|---|---|
| Hyperliquid info API (`candleSnapshot`, `fundingHistory`, `metaAndAssetCtxs`, `perpDexs`, `allPerpMetas`) | `scripts/fetch_hyperliquid.R` and `scripts/fetch_hl_market_reference.R`, weekly, by `.github/workflows/hl-weekly.yml` | public dataset `JohnGavin/finance-data`, prefix `hyperliquid/` | Not located by the owner (2026-11-22); data published in the public dataset by owner decision |

- **Tables.** `hyperliquid/<table>.parquet` for `perp_daily`, `perp_hourly`, `perp_15m`, `spot_daily`, `spot_hourly`, `perp_funding`, `perp_funding_daily`, `perp_oi_snapshot` (all required), and `perp_dexs`, `perp_markets`, `spot_15m` (required once the seed marker lists them). The list and the upsert key of each table have one home: `HL_HIST_TABLES` in `scripts/hl_history_guard.R`.
- **Raw replies.** Packed, never file by file (a day holds about 10,000 files and Hugging Face allows under 10,000 per folder): `hyperliquid/raw/weekly/date=YYYY-MM-DD/<run id>.tar` for a weekly run, `.../seed.tar` for the one-off seed. Each tar member is one raw reply, gzipped on its own. This includes the saved copy of the trade.xyz specification page, a third-party document.
- **The weekly run is incremental and cannot lose history.** It downloads every table first and stops (exit 3) unless all came down whole and the seed marker `hyperliquid/_seeded.json` exists: `fetch_hyperliquid.R` writes only the new rows when its target file is absent, so a run that started from a missing table would publish a table that had lost its history. It passes `--start` derived from the tables (the oldest of the latest bars, less 3 days), because every run re-requests each market's whole funding history from `--start`, and from 2023-01-01 that took more than 9 hours on the laptop. After the fetch a guard checks, per table, that rows are not fewer, the earliest date is not later and every old key is still present; any violation publishes nothing. A partial fetch publishes nothing either.
- **The seed.** `scripts/seed_hl_to_hf.R` (dry run by default) merges the laptop's tables with whatever Hugging Face holds, never overwriting, packs the raw day folders, writes the marker and publishes in one commit. The laptop's `ctx_poll/` raw files and `perp_ctx_5m/laptop-1` files are not part of it yet.

## Ingested: Hyperliquid reference tables (#1084)

Two small tables describe the exchanges and markets that every other Hyperliquid table (`perp_daily`, `perp_ctx_5m`, ...) names only by a short code. Both are gitignored files under `data/dist/`, written by committed, tested parsers; neither holds a hand-typed name.

| Table | Written by | Key | Source |
|---|---|---|---|
| `perp_dexs.parquet` | `scripts/fetch_hyperliquid.R` (weekly) | `dex` | The info API, `{"type": "perpDexs"}`: `name` and `fullName` only. The deployer, wallet and fee-recipient fields are never read. The core exchange (`dex = ""`) is the reply's `null` entry, which has no name, so its `full_name` is NA. |
| `perp_markets.parquet` | `scripts/fetch_hl_market_reference.R` (weekly, after the fetch) | `(dex, coin)` | The API (`allPerpMetas`): `is_delisted`, `max_leverage`. For `dex = "xyz"` (trade.xyz) also its [specification index](https://docs.trade.xyz/perpetuals/specifications-and-schedules/specification-index), read as Markdown (`.md`): `long_name`, `category`, `definition`, `source_url`. |

- **What the page gives and what is derived.** The page's Description column is stored whole as `definition` (HTML entities decoded). `long_name` is read from it only where it names a listed security, as "(EXCHANGE: SYMBOL)" (a stock, ADS or ETF); indices, commodities and FX pairs have no such name, so NA. `category` (stock, etf, fx, commodity, index) is derived from the description wording by the rules in `HL_SPEC_CATEGORY_RULES`; the page has no category column. NA means no rule fits.
- **Every other exchange** (`flx`, `io`, `para`, `km`, ...) has no parser yet, so its source columns are NA. A parser is added per exchange only when it publishes a machine-readable page.
- **A market that leaves the page** (delisting) keeps its last known source columns; `source_fetched_at` then shows how old they are. A market the page never described stays NA.
- **Reproducing a parse.** The raw Markdown is kept append-only at `data/raw/hyperliquid/<UTC date>/spec_trade_xyz_specification-index.md` (a copy of a third-party page; it is packed with that day's raw replies into the public dataset, see the next section). `Rscript scripts/fetch_hl_market_reference.R --spec-file=<that file>` re-parses it.
- **Why not `metadata.parquet`.** That file is keyed by ticker, rewritten whole by `scripts/fetch_metadata.py` and holds no Hyperliquid rows; a second writer would race it and would store a long name in two places.
- These are PERPETUAL FUTURES markets that reference securities; the long name says what the market references, not that the market is the security.

## Ingested: Hyperliquid 5-minute context snapshots (#1080, #1082)

`scripts/poll_hyperliquid_ctx.R` (launchd, every 5 minutes) records, for every market of every exchange, the mid, oracle, mark and impact prices, premium, funding, open interest and 24-hour notional volume. The info API (`metaAndAssetCtxs`) has no history, so a snapshot not recorded now is lost.

- **Layout.** `data/dist/perp_ctx_5m/date=YYYY-MM-DD/<collector>.parquet`, one file per UTC day (the date of `fetched_at`) and collector, key `(dex, coin, fetched_at)`. A run that crosses 00:00 UTC writes two files. A poll rewrites only today's file; earlier days are never touched. Read the whole table with `hl_ctx_read()` / `hl_ctx_open()` (arrow). The reader must unite the files' schemas (`unify_schemas = TRUE`, measured with arrow 23): otherwise the first file's columns win and `is_delisted`, absent from the oldest files, is silently dropped.
- **Collector.** A configured label (env var `HL_POLL_COLLECTOR`, default `laptop-1`), never the host name.
- **The old single file** `data/dist/perp_ctx_5m.parquet` is no longer written and the reader ignores it. `Rscript scripts/migrate_hl_ctx_to_daily.R` (dry run by default, `--apply` to write) splits it into the daily layout, replaces its host-name collector values by the label, verifies the key sets and values, and leaves the file in place; delete it yourself once checked. Rows are matched on the key, so running it twice, or after the poller has started writing daily files, never doubles a row.
- **Raw replies and replay.** `data/raw/hyperliquid/ctx_poll/<UTC date>/<collector>_<HHMMSS>.json.gz`: one gzipped file per run holding every reply (exact text) with its `fetched_at`. `hl_ctx_replay_day(date, raw_dir, out_dir)` rebuilds that day's daily file(s) from them and the result equals what the poller wrote. The folder `data/raw/hyperliquid/<UTC date>/` holds the weekly fetch's and the volume estimate's own `metaAndAssetCtxs` replies, which the replay never reads. Raw files are gitignored. The `<UTC date>/` folders are published packed (next section); the laptop's `ctx_poll/` files are not uploaded yet (a later step converts them to the Worker's daily `jsonl.gz` layout).
- **Primary collector: a Cloudflare Worker, published to Hugging Face (#1088).** `cloudflare/hl-ctx-collector/worker.js` (free plan, cron every 5 minutes) fetches `perpDexs` and then `metaAndAssetCtxs` for the core exchange and every listed exchange (at most 48), and stores the unparsed reply bytes in one Workers KV value per slot (key `ctx/<date>/<HHMM>`, kept 10 days). `scripts/drain_hl_ctx_kv.R`, run daily by `.github/workflows/hl-ctx-drain.yml`, reads those values, parses them with the same `hl_parse_ctx` code and publishes, in one commit by `scripts/hf_upload_commit.sh`, to the public dataset `finance-data`: `hyperliquid/perp_ctx_5m/date=YYYY-MM-DD/cf-1.parquet` (collector label `cf-1`, same columns and key as above) and `hyperliquid/raw/ctx_poll/date=YYYY-MM-DD/cf-1.jsonl.gz` (one raw document per slot per line; `hl_ctx_replay_day_jsonl()` rebuilds the parquet from it, and a test asserts that it does). Unlike the laptop's raw files, these raw replies are published (owner decision 2026-11-22; terms on redistribution: not located by the owner, 2026-11-22; data published in the public dataset by owner decision). `scripts/hl_ctx_gap_report.R` reports, per UTC day, the slots due, on HF and in KV. While the laptop poller also runs, `hl_ctx_read()` keeps one collector per `(dex, coin, slot)`, preferring `cf-1`, then `laptop-1`. A slot in which the Worker's `perpDexs` request fails is stored as a header-only marker, so a failed fetch is told apart from a run that never happened.

## Known, not ingested

### Econvitals (econvitals.org)

Read on 2026-11-12, for ideas only. Counts below are a dated snapshot and may change.

**What it is.** A U.S. macro-monitoring site run by Jason Furman: charts on growth, jobs, inflation, financial conditions and the federal budget. Briefings are written by Claude without human review, except "Jason's Occasional Posts".

**Access.** There is no documented API (`/api`, `/docs`, `/llms.txt` and `/openapi.json` return 404). The site's own pages fetch about 40 undocumented JSON/CSV files (for example `/data/dashboard.json`, `/data/calendar.json`, `/data/briefings.json`, `/tools/*/data.json`) and an RSS feed at `/feeds/all.xml`. These are unsupported and may change without notice: **do not depend on them in any target or scheduled job.**

**Licence.** Content is CC0 (public domain) per its Terms page.

**The stable route.** The replication repository, https://github.com/econvitals/replication (public, CC0, Python). It has one folder per measure the site builds itself. Each folder holds `replicate.py` (rebuilds the measure from FRED, BEA, EIA and Census data) and `check.json` (which published series it must match, over how many dates, within what tolerance); the site checks them nightly. Its `history/` folder is the track record of every GDP, PCE and CPI tracking estimate beside the official figure.

**What its figures are.**

| Kind | Examples | Where to get it |
|---|---|---|
| Agency numbers, unchanged | most of the dashboard | BLS, BEA or FRED directly |
| Third-party numbers, credited to their publisher | Atlanta Fed GDPNow, New York Fed Staff Nowcast, CME fed funds futures, Kalshi prediction-market prices, Cleveland/Dallas Fed median and trimmed-mean inflation | Those publishers |
| "Close to the source" constructions (24 of 38 methods): published recipes rerun, or deflations | core PCE excluding housing and used vehicles, real wage growth, term premium by the ACM (Adrian-Crump-Moench) method, Taylor rule | Rebuild from the primary data if needed |
| "Econvitals original" (14 of 38) | Ecumenical underlying inflation, inflation dispersion and skewness indices, PCE tracking estimate, current-quarter GDP estimate, composite GDP tracker, Fedspeak score, composite activity and inflation indicators | Not available elsewhere |

**How we use it (decided policy).**

1. Agency and third-party numbers come from the original publisher, never via Econvitals.
2. For a construction we want, re-implement it in R from primary data, using the replication folder as the specification (sources, formula, tolerance). Copy no code.
3. Their published value may be used as a TEST of our re-implementation, within their stated tolerance. Such a check must report INDETERMINATE (could not decide), not pass or fail, when their file is unavailable.
4. No scheduled fetch until a strategy has a portfolio-fit case for a specific series.

**Candidates of possible interest to strategies (not adopted).** The composite GDP tracker / nowcast and its track record (growth regime); inflation dispersion; the Fedspeak score (a text signal of policy stance); term-premium and real-rate splits. See issues #1055 (full data review), #994 (macro gaps) and #1056 (dashboard design ideas).
