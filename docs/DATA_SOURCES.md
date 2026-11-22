# Data sources

This file records data sources we know about. A source listed under "Known, not ingested" is NOT used by any target; it is a pointer for when a strategy needs it. Figures enter the pipeline only from a primary source through committed, tested parser code.

## Ingested: Hyperliquid reference tables (#1084)

Two small tables describe the exchanges and markets that every other Hyperliquid table (`perp_daily`, `perp_ctx_5m`, ...) names only by a short code. Both are gitignored files under `data/dist/`, written by committed, tested parsers; neither holds a hand-typed name.

| Table | Written by | Key | Source |
|---|---|---|---|
| `perp_dexs.parquet` | `scripts/fetch_hyperliquid.R` (weekly) | `dex` | The info API, `{"type": "perpDexs"}`: `name` and `fullName` only. The deployer, wallet and fee-recipient fields are never read. The core exchange (`dex = ""`) is the reply's `null` entry, which has no name, so its `full_name` is NA. |
| `perp_markets.parquet` | `scripts/fetch_hl_market_reference.R` (weekly, after the fetch) | `(dex, coin)` | The API (`allPerpMetas`): `is_delisted`, `max_leverage`. For `dex = "xyz"` (trade.xyz) also its [specification index](https://docs.trade.xyz/perpetuals/specifications-and-schedules/specification-index), read as Markdown (`.md`): `long_name`, `category`, `definition`, `source_url`. |

- **What the page gives and what is derived.** The page's Description column is stored whole as `definition` (HTML entities decoded). `long_name` is read from it only where it names a listed security, as "(EXCHANGE: SYMBOL)" (a stock, ADS or ETF); indices, commodities and FX pairs have no such name, so NA. `category` (stock, etf, fx, commodity, index) is derived from the description wording by the rules in `HL_SPEC_CATEGORY_RULES`; the page has no category column. NA means no rule fits.
- **Every other exchange** (`flx`, `io`, `para`, `km`, ...) has no parser yet, so its source columns are NA. A parser is added per exchange only when it publishes a machine-readable page.
- **A market that leaves the page** (delisting) keeps its last known source columns; `source_fetched_at` then shows how old they are. A market the page never described stays NA.
- **Reproducing a parse.** The raw Markdown is kept append-only at `data/raw/hyperliquid/<UTC date>/spec_trade_xyz_specification-index.md` (never uploaded). `Rscript scripts/fetch_hl_market_reference.R --spec-file=<that file>` re-parses it.
- **Why not `metadata.parquet`.** That file is keyed by ticker, rewritten whole by `scripts/fetch_metadata.py` and holds no Hyperliquid rows; a second writer would race it and would store a long name in two places.
- These are PERPETUAL FUTURES markets that reference securities; the long name says what the market references, not that the market is the security.

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
