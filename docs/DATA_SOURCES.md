# Data sources — single source of truth

**Read this before assuming what data we have, where it came from, or what we left behind.** Add to it whenever you learn something about a source (see "How to extend" at the bottom).

## Precedence — which file answers which question

| Question | Authoritative place |
|---|---|
| What datasets does the package serve, their schema, frequency, caveats? | `hd_datasets()` in [`packages/historicaldata/R/registry.R`](../packages/historicaldata/R/registry.R) (machine-readable; do not duplicate its columns here) |
| Canonical column names / source-system synonyms | [`inst/COLUMN_NAMING.md`](../inst/COLUMN_NAMING.md) |
| **Raw upstream sources**: what archive exists, where it lives locally, what vintage, what we ingested vs left behind | **this file** |
| Why a dataset is archived / frozen, and what was tried | [`DATA_SOURCING_LESSONS.md`](DATA_SOURCING_LESSONS.md) |

Served datasets live on Hugging Face at `hf://datasets/JohnGavin/finance-data/<name>.parquet` (override with `HD_HF_REPO`; see `hd_base_url()`).

## Served datasets (from `hd_datasets()`)

Names and frequencies are read from the registry as of this writing; the registry wins if they ever disagree.

| Dataset | Frequency | Producer named in the registry |
|---|---|---|
| `equity_daily` | daily | `scripts/fetch_equity.py` (frozen seed, see lessons doc) |
| `crypto_daily` | daily | — |
| `macro_daily` | mixed | — (frozen seed, see lessons doc) |
| `factors` | daily+monthly | — |
| `metadata` | static | — |
| `macro_vintages` | vintage | — |
| `metadata_amendments` | append-only | — |
| `jst_macrohistory` | annual | — |
| `alphavantage_daily` | daily | — |
| `fundamentals` | filing | `scripts/fetch_fundamentals_edgar.R` |
| `kraken_ohlcvt` | 60min+1440min | `scripts/fetch_kraken_ohlcvt.R` (#436) |

"—" means the registry does not name a producer; it does **not** mean there is none. Fill these in as they are verified.

---

## Kraken OHLCVT

### The raw source

| Fact | Value | How established |
|---|---|---|
| Local path | `/Users/johngavin/Downloads/Kraken_OHLCVT.zip` (**laptop-local; not in git, not on HF**) | user, 2026-09-20 |
| Size | 7,885,068,519 bytes | `scripts/kraken_zip_inventory.sh` |
| Members | 12,026 `{PAIR}_{interval}.csv` files, all under `master_q4/` | same |
| Vintage | member date 2026-01-24 ("master_q4"); data runs to **2025-12-31** | inventory + #867 |
| Upstream | Kraken support pages (OHLCVT + Time-and-Sales), Google Drive archive; needs a manual "Download anyway" click, so it cannot be automated (see header of `scripts/fetch_kraken_ohlcvt.R`) | #436 |
| CSV layout | no header; `timestamp(unix s), open, high, low, close, volume, trades` | `scripts/fetch_kraken_ohlcvt.R` header |
| **Intervals in the archive** | **1, 5, 15, 30, 60, 240, 720, 1440 minutes** | inventory, 2026-09-20 |

Not in the OHLCVT files: **VWAP / quote volume** (only base `volume` and a `trades` count). True VWAP needs the separate Time-and-Sales (per-trade) archive, ~150 GB, never ingested.

### What we ingested vs left behind

| | Ingested | Not ingested |
|---|---|---|
| Pairs | 19 (6 crypto majors vs USD, 12 fiat-fiat FX, PAXG) — list is the `csv_prefix` entries in `scripts/fetch_kraken_ohlcvt.R` | ~1,500 other pairs incl. delisted/dead ones (survivorship: the 19 are today's largest by volume) |
| Intervals | **60 and 1440 only** | 1, 5, 15, 30, 240, 720 |
| Where it went | `data/raw/kraken_ohlcvt.parquet` → `hf://datasets/JohnGavin/finance-data/kraken_ohlcvt.parquet` via `scripts/upload_kraken_hf.sh`; query with `hd_kraken_ohlcvt()` | — |

Uncompressed CSV size of the 19 ingested pairs, per interval (from `inst/extdata/kraken_ohlcvt_inventory.csv`):

| interval_min | bytes (CSV) |
|---:|---:|
| 1 | 1,583,174,260 |
| 5 | 475,811,312 |
| 15 | 187,607,683 |
| 30 | 27,864,565 |
| 60 | 54,637,680 (ingested) |
| 240 | 4,784,152 |
| 720 | 5,479,396 |
| 1440 | 2,813,472 (ingested) |

The per-pair, per-interval detail is committed at [`inst/extdata/kraken_ohlcvt_inventory.csv`](../inst/extdata/kraken_ohlcvt_inventory.csv). Regenerate (about a second, reads the zip's directory only, extracts nothing):

```bash
scripts/kraken_zip_inventory.sh            # exit 0 ok, 1 pair missing, 3 could not answer
scripts/kraken_zip_inventory.sh --selftest
```

### Derived-data note: when the high and low of a bar occurred

The finer files let us locate the extremes of a coarser bar to the resolution of the finer bar: take the earliest sub-bar whose `high` equals the parent bar's `high` (likewise `low`). This is deterministic, not probabilistic, up to two limits: (a) position *inside* the winning sub-bar is unknown (uncertainty = one sub-bar width), (b) ties must be broken explicitly (earliest). 1-minute files give a daily bar's high/low time to 1/1440 of the bar, hourly files only to 1/24. Tracked in [#873](https://github.com/JohnGavin/historical/issues/873). Any such derivation must be committed, tested parser code (Reproducible Ingestion), not ad-hoc.

### Caveats that travel with the data

- Bars exist only for periods with trades; hourly gaps are normal in thin pairs.
- FX volume is retail crypto-exchange flow, not interbank — fine for hourly/daily returns, not for cost/spread/microstructure work.
- The 19 pairs were chosen as the largest by 2026 volume (forward-looking selection).
- **Unexplained anomaly — do not use the 30-minute files until checked (2026-09-20).** They are *smaller* than the 60-minute files (BTC: 1,836,905 B at 30 min vs 5,640,237 B at 60 min; the same holds for ETH), and only 1,403 pairs have a 30-min file against ~1,521 for every other interval. A finer interval over the same history cannot be smaller, so the 30-min series is probably truncated or covers a shorter window. Not yet investigated; found from `inst/extdata/kraken_ohlcvt_inventory.csv` alone, so it needs a look at the file contents (first/last timestamp) before anyone relies on it.

---

## How to extend

When you learn a fact about any source (an archive's location or vintage, an interval or column that exists, a licence, an ingest decision), add it **here** in the same commit, with *how you established it* (script, issue, or date). If a fact belongs in the machine-readable registry instead, put it there and link to it — do not copy registry columns into this file.
