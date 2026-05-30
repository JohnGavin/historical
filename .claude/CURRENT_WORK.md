# Current Work (Session 2026-05-30 #12 — #347 backtest-tracking DuckDB umbrella, ENDED)

**Last updated:** session end
**Previous sessions:** #11 (robustness trio, Pillar 8, 21 PRs), #10 (CI gate, deflated Sharpe), #9 (external-source digests), #8 (research-log DB, OLMAR-1)

## This session — 5 PRs merged + 1 issue filed

### #347 backtest-tracking DuckDB — closed via 4 sub-PRs
- **#364 PR 1/4** schema + bootstrap — 12 tables in `bt.*` + `art.*` + `schema_version`. Exports `hd_registry_path/init/open/schema_version`.
- **#366 PR 2/4** `bt.strategy` + `bt.run` writers + CMR pilot sentinel — `hd_strategy_upsert` (idempotent), `hd_run_record` (UUIDv4, git_sha auto-resolve). `cmr_registry_run` target writes strategy + 3 partition runs (1m/3m/6m).
- **#367 PR 3/4** `bt.metric` + `bt.diagnostic` + `hd_leaderboard_from_registry()` — long-form recorders accept wide- or long-form input, idempotent per (run_uuid, metric_name). CMR sentinel now records 21 metric rows (7 × 3 partitions).
- **#368 PR 4/4** `art.*` writers + `check_artefact_registry()` QA gate — the mermaid-test.html / examples.html regression catch.

### #347 follow-up — pipeline wiring
- **#369** seeded `art.vignette` (12 docs/*.qmd registered) via new `plan_artefact_registry.R` (`art_vignette_seed` + `qa_artefact_registry` targets); negative control confirmed gate aborts on missing HTML.

### Issue filed
- **#365** mom_prepeak — Büsing/Mohrschladt/Siedhoff 2022 "Decomposing Momentum: The Forgotten Component". 84% of standard 12-2 momentum alpha is in the pre-peak portion; positively skewed, crash-avoiding, market-state-independent. Three sibling strategies scoped (`mom_prepeak`, `mom_postpeak`, `mom_combined`).

## Metrics

- **92 PASS / 0 FAIL / 0 WARN / 2 SKIP** across registry test suite
- **12 vignettes registered** in `art.vignette`, all status='published'
- **End-to-end registry path** verified: schema → bootstrap → strategy upsert → run record → metric record → leaderboard read → vignette seed → QA gate

## Next session

### Open umbrella to start
- **#365 mom_prepeak** — first non-CMR strategy through the registry. Likely PR 1: signal extraction (`peak_date`, `pre_peak_return`, `post_peak_return`) + tests against synthetic price series. PR 2: targets + sentinel writing to registry.

### Smaller follow-ups (no umbrella)
- Seed `art.diagram` — scan qmd files for mermaid/plotly chunks
- Register the 3 non-qmd HTMLs (`causal-dag`, `causal-dag-all`, `quiz-app`) in `art.vignette`
- Add registry sentinels for the other 10 strategies in `strategy_names` so the legacy `leaderboard` target can be retired in favour of `hd_leaderboard_from_registry()`

## Working branch

`main` — this session committed nothing to `feat/cc-20260528-101554`; all work merged directly via #364, #366, #367, #368, #369. Working tree is clean except for one untracked PDF in `knowledge/raw/` (append-only, owned by separate workflow).
