# Verifying the four OSAP presumptions (#862)

All numbers below come from `run.R`, run against the live Open Source Asset
Pricing (Chen & Zimmermann) download on 2026-09-11. Nothing here is
hand-typed; re-run `nix develop <repo> --command Rscript
explorations/osap_verification/run.R` to reproduce every figure. Raw OSAP
data is **not** committed anywhere in this repo (see P3) -- only the small
derived summary tables in `results/`.

Source files (current release as of 2026-09-11, ~2.36GB zipped /
~8.35GB unzipped for the firm-level file):

- `SignalDoc.csv` -- 332 signals documented
- `portfolios_wide.csv` -- monthly long-short portfolio returns, 212 predictors
- `signed_predictors_dl_wide.csv` -- 5,416,424 rows, 211 columns
  (`permno`, `yyyymm` + 209 firm-level signals)

## P1 -- Is the data actually delisting-inclusive? **PASS**

**Test (identical methodology to the `equity_daily` comparator in
`explorations/momentum_max_lottery/SUMMARY.md` section (d), for direct
comparability):** for each `permno`, does its last observation fall more
than 12 months before the panel end?

| Dataset | Universe size | Exits > 1yr before panel end | % |
|---|---:|---:|---:|
| `equity_daily` (this repo, comparator) | 502 | 0 | 0.0% |
| OSAP firm-level, panel end = raw max observed month (2026-11) | 38,870 | 33,687 | 86.7% |
| OSAP firm-level, panel end = last dense-coverage month (2026-05, excludes the reporting-lag tail -- see caveat below) | 38,870 | 33,361 | 85.8% |

`equity_daily` is a fixed universe of currently-tradeable-or-recently-stopped
tickers: **zero** of 502 stop appearing more than a year before the panel
ends. OSAP's firm-level file is the structural opposite: roughly **6 in 7**
of the 38,870 distinct firms it has ever carried stopped appearing more than
a year before the most recent data -- a large, continuous churn of entries
and exits, which is exactly what a delisting-inclusive CRSP-derived panel
looks like and a survivorship-biased snapshot cannot produce.

**Tail-artifact-immune robustness check.** The raw/dense split above exists
because the last ~18 months of the file thin out sharply -- monthly
distinct-`permno` counts fall from ~10,000-11,000 (2024) to ~5,100-5,400/month
(Jan 2025-Jun 2026) to a few hundred or fewer (Jul 2026 onward), almost
certainly because slower-reporting accounting-based signals have not yet
caught up to the data frontier (see the `openassetpricing.com/faq/` note on
the Fama-French accounting-lag convention), not because those firms
delisted. To remove any doubt this recency artifact was driving the 86.7%
figure, the same "last observation before cutoff" test was re-run against
fixed historical cutoffs decades before any tail effect could reach them
(`results/osap_p1_historical_exit_robustness.csv`):

| Last observation before | Firms | % of all 38,870 |
|---|---:|---:|
| 1999-12 | 14,363 | 37.0% |
| 2009-12 | 21,206 | 54.6% |
| 2019-12 | 25,637 | 66.0% |
| 2023-12 | 27,906 | 71.8% |
| Comparator: `equity_daily`, any cutoff | 0 | 0.0% |

Even restricted to firms whose last appearance was **before the year
2000** -- utterly untouched by any recent reporting lag -- over a third of
the entire firm roster has already permanently exited. This is the decisive
evidence: it cannot be explained by the tail artifact and it is precisely
the churn pattern `equity_daily` structurally cannot exhibit.

**Supporting evidence -- panel shape** (`results/osap_permno_by_year.csv`):
the distinct-`permno` count rises from 501 (1925) to a first major
inflection around 1962-1973 (the CRSP NASDAQ/AMEX expansion), climbs to
~10,490 by 1998, **declines** to a trough of ~7,466 (2012) -- the
dot-com/financial-crisis delisting wave -- then rises again to a new high of
10,907 by 2024. A rise-decline-rise shape is the signature of continuous
entry and exit; a survivorship-biased snapshot is flat or monotonically
non-decreasing, which is exactly what `equity_daily`'s own 0/502 comparator
shows.

**Optional named-bankrupt sub-check: INDETERMINATE.** The brief asked,
where cheap, to confirm specific known bankrupts (Enron, Lehman, WorldCom,
Bear Stearns, WaMu) are present. This could not be done: the firm-level
file carries no ticker, company name, or CUSIP column --
`results/osap_firmlevel_columns.txt` lists all 211 columns and none
identifies a firm by anything other than an opaque CRSP `permno`. No free
permno-to-ticker crosswalk is bundled with the download or reachable
without WRDS (`results/osap_named_bankrupt_subcheck.txt`). Per the
dispatch instructions, no permno was guessed. This is an honest
INDETERMINATE on the sub-check only -- it does not weaken the P1 verdict
above, which does not depend on it.

## P2 -- Are monthly returns in the free download? **FAIL (returns absent)**

`results/osap_p2_column_check.csv`, derived from the live 211-column header:

| Column | Present in firm-level file |
|---|---|
| `MaxRet` | TRUE |
| `Mom12m` | TRUE |
| `CoskewACX` | TRUE |
| `ReturnSkew` | TRUE |
| `Price` | FALSE |
| `Size` | FALSE |
| `STreversal` | FALSE |
| Any return-like column (ret/RET/return) | FALSE |

All four signals #857/#552 need (`MaxRet`, `Mom12m`, `CoskewACX`,
`ReturnSkew`) are present. But the file has no return column of any
kind -- not `STreversal` (last month's return), not a raw monthly return,
nothing. This confirms the suspicion in #862: the free firm-level download
is signals only.

**Consequence for #857:** a custom `Mom12m` x `MaxRet` double sort that
needs each firm's own realised forward return cannot be run on this free
file. What remains available: each predictor's pre-built long-short
portfolio return in `portfolios_wide.csv` / the per-portfolio CSVs (212
series, confirmed downloadable, see P4). That supports asking whether MAX
and momentum interact at the portfolio level (e.g., correlating the
`MaxRet` portfolio series against the `Mom12m` portfolio series), but not
the 3x3 corner-table replication against Zadeh's firm-level numbers that
#857 originally wanted.

## P3 -- What licence governs the data? **No data licence found -- verified absence, not inferred**

Checked, exhaustively:

| Source | Result |
|---|---|
| `openassetpricing.com` homepage | Only a copyright-year footer notice; no terms-of-use, licence, or redistribution language anywhere on the page |
| `openassetpricing.com/data/` | Same -- full page content reviewed, no licence text |
| `openassetpricing.com/faq/` | 9 FAQ entries, none address licensing, redistribution, or terms of use |
| GitHub `OpenSourceAP/CrossSection` LICENSE file | GNU GPL v2 -- this is the code licence only |
| GitHub `OpenSourceAP/CrossSection` README.md (full text, 6,209 bytes, grepped for licence/terms-of-use/redistribution/creative-commons/CC-BY/copyright) | Zero matches. No data-specific licence or terms-of-use language anywhere in the README |
| Google Drive data bundle root folder (Firm Level Characteristics, Portfolios, DailyPortfolios, Results, release notes, SignalDoc.csv/.html, storage_checks files) | No README or LICENSE file present in the bundle at all |
| `SignalDoc.csv` header/content | No licence text (it is a pure data dictionary) |
| Chen and Zimmermann (2022) SSRN paper | WebFetch returned HTTP 403 (blocked). Per this session's policy on blocked fetches, the paper's content was not reconstructed from search snippets and is not used as evidence either way. This is a gap in the search, not evidence of an answer, and does not change the verdict below since every other primary source was checked exhaustively |

**Verdict: no explicit data licence is stated anywhere the authors publish
the data.** This is a verified absence (multiple independent sources
checked and none contain the text), not an inference from silence on one
page. Compare with JKP Global Factor Data, which is explicitly CC BY-NC
4.0 -- OSAP states nothing comparable.

**Why this matters (context, not a decision made here):** this repo
publishes parquet to HuggingFace and renders a public dashboard. Ingesting
OSAP's raw files and republishing them would very likely constitute
redistribution of a dataset with no stated redistribution terms -- the safe
default is to treat it as not clear to redistribute. Open question for
the owner, explicitly not resolved here: if this repo only ever publishes
derived outputs (signals recomputed from our own equity data, portfolios
aggregated from OSAP inputs, summary statistics), that may be a materially
different position from redistributing the OSAP file itself -- but "derived
work" vs "redistribution" is a licensing judgement this dispatch does not
attempt to make. Until decided: local-only -- no HuggingFace push, no
committed parquet, no publishing of raw or lightly-transformed OSAP columns.

## P4 -- Does the free download need WRDS? **PASS (no WRDS required)**

`results/osap_p4_wrds_check.csv` -- this session never had `WRDS_USER`,
`WRDS_PASSWORD`, `WRDS_USERNAME`, `WRDS_HOST`, `PGHOST`, `PGUSER`, or
`PGPASSWORD` set (`any_wrds_env_var_set = FALSE`), and all three files
(`SignalDoc.csv`, `portfolios_wide.csv`, the 8.35GB firm-level CSV)
downloaded successfully with plain unauthenticated curl requests against
Google Drive.

The only friction encountered was Google Drive's virus-scan size
warning for the 2.2GB zip ("Google Drive can't scan this file for
viruses... Would you still like to download this file?") -- a one-time
confirm-token exchange, not a login or credential prompt of any
kind. Nothing in the download path referenced WRDS, CRSP direct access, or
any credential store. This confirms #862's belief and closes P4 cleanly.

## What this means for #862, #857, #552, #816

**#862** should proceed with ingestion, but the registry entry must
carry an honest, corrected description: delisting-inclusive (verified,
P1 PASS -- cite the 86.7%/37% figures above), returns absent from the free
firm-level file (P2), data licence unstated and therefore local-only until
the owner decides on the derived-vs-redistribution question (P3), and no
WRDS dependency (P4, confirmed). `hd_register_add_dataset()`'s stub
`sample_start = "1990-01"` is also wrong on the evidence here -- the
firm-level file's real range is 1925-01 through the current data frontier,
per-signal ranges as documented in `SignalDoc.csv`.

**#857** (`MaxRet` x `Mom12m` double sort) is narrowed, not blocked: the
firm-level signals (`MaxRet`, `Mom12m`) are present and can be used to
construct sort buckets, but the custom double-sort return construction
originally envisioned needs firm-level returns that are not in this file.
#857 can still test whether the two predictors' pre-built portfolio
return series interact (correlation/spread analysis on the 212-portfolio
file), which is a real but smaller result than the originally planned 3x3
corner-table replication.

**#552** (`CoskewACX`) is unaffected by the P2 finding -- it only needed the
signal itself (present, confirmed) to build its own quintile assignments
from our own return data, not a return column from OSAP.

**#816** (a free delisting-inclusive universe) is the biggest winner here:
P1 is a clean PASS with an unusually strong margin (86.7% raw exit rate,
37% even on a tail-artifact-immune historical cutoff, against
`equity_daily`'s structural 0%). #816's survivorship blocker is lifted for
firm-level signal work, though it remains gated on P3: nothing derived
from OSAP that constitutes redistribution should ship to a public surface
until the licence question is resolved by the owner.
