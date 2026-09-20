# Current Work — session 31 (2026-09-20)

Branch `feat/cc-20260920-192457` (2 commits ahead of `main`, not merged, no PR).

## What happened

Assessed Aligrithm 3.41 / Tepelyan (arXiv 2509.16137) against the primary PDF and filed [#873](https://github.com/JohnGavin/historical/issues/873). Verdict: intra-bar high/low timestamps are a 1-minute variance-forecast feature (5.5% of the log-likelihood gain, 0.006 pp of direction), not worth ingesting for their own sake; range-based volatility estimators on OHLC we already hold are the cheap related test.

Built and committed:
- `scripts/kraken_zip_inventory.sh` (+ selftest, exit 0/1/3) → `inst/extdata/kraken_ohlcvt_inventory.csv`
- `docs/DATA_SOURCES.md` — the single source of truth for raw data sources (linked from `.claude/CLAUDE.md`)
- Calibration-check proposal posted on [#539](https://github.com/JohnGavin/historical/issues/539)

Key facts: `~/Downloads/Kraken_OHLCVT.zip` (laptop-local, 7.9 GB, vintage 2026-01-24) holds intervals 1/5/15/30/60/240/720/1440 min for every ingested pair; only 60 and 1440 were ingested. The 30-min files look truncated (unexplained).

## Next step

Post the staged range-volatility plan to #873 (user has not yet approved posting), then Stage 0: implement Parkinson / Garman-Klass / Rogers-Satchell / Yang-Zhang in `packages/historicaldata/` with known-answer simulation tests. Baselines must include daily close-to-close realised vol, not only the current 12-monthly-obs sd. Pre-register the prediction (range advantage shrinks as lookback grows) and seal it in the research log before looking.

## Open

- Push branch + open PR for the inventory work (asked, not answered).
- Investigate the 30-min Kraken anomaly.
- Nothing was run through `scripts/verify.sh` or `scripts/build.sh` (no package or pipeline code changed).
