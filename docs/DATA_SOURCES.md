# Data sources

This file records data sources we know about. A source listed under "Known, not ingested" is NOT used by any target; it is a pointer for when a strategy needs it. Figures enter the pipeline only from a primary source through committed, tested parser code.

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
