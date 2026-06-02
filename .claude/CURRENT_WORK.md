# Current Work (Session 2026-06-02 #15 — #400 SSR rollout closed + 2 issues filed + housekeeping, ENDED)

**Last updated:** session end
**Previous sessions:** #14 (12 PRs + SSR rollout kicked off), #13 (#365 mom_prepeak umbrella, 14 PRs), #12 (#347 DuckDB registry, 5 PRs)

## This session — 5 PRs merged + 2 issues filed + ~1 GB reclaimed

### #400 SSR rollout closed (4 PRs — full 6-PR umbrella now in main)

- **#410 PR 3/6** `hd_record_stability_metrics()` — registry orchestrator writing 8 stability scalars per run into `bt.metric` (no DDL change). 8 new tests; 137 PASS / 0 FAIL registry suite.
- **#409 PR 4/6** leaderboard SSR + top5pct columns — broadcast as full-sample stats via left-join; surfaced in Full Period tab. 9 strategies covered; 6 NA pending direct return-vector dependencies. 6 new tests.
- **#413 PR 5/6** auto-record from `*_register_runs` — threads strategy returns through `.mom_prepeak_register_runs()` (3 siblings) and `.cmr_register_runs()` (3 lookback partitions). Supersedes closed #412. 5 new tests.
- **#408 PR 6/6** mom_prepeak gauntlet SSR axis — new `mom_prepeak_ssr`, `mom_prepeak_top5pct` targets; dashboard section with DT table + calibration anchors (S&P 500 SSR ~5.3, macro FX ~4.4). 13 new tests.

### Vignette deploy

- **#411** re-render 2 of 3 deferred vignettes — `macro-defense-rotation.qmd` against warm-started `_targets/`; `jst-dashboard.qmd` migrated to `safe_tar_read()` + 4 RDS fallbacks in `inst/extdata/vignettes/`. Third (`leaderboard.qmd`) addressed by #409's schema change.

### 2 research issues filed

- **#414** — Active Dual Momentum GTAA (Quantpedia 6080 / Beluska 2026). 9-ETF dual-window RoC with absolute-momentum filter. Reported Sharpe 0.91 / Calmar 0.89. 7 subtasks (data sourcing, gauntlet, net-of-cost sensitivity, pervasiveness probe).
- **#415** — `alphaarchitect.com/factor-strategies/` gap audit vs our 14-strategy inventory. Cloudflare-blocked from WebFetch; Subtask 1 covers manual page capture. 7-subtask audit including child-issue generation for each GAP row.

### Housekeeping

- Duplicate clone `~/docs_gh/historical` removed (all 7 local branches verified `0 0` against origin; clean working trees).
- `.claire/` typo dir removed — orphan with stale older copy of `strategy_mom_prepeak.R` (deprecated `purrr::map_dfr`); 12 KB.
- **Worktree bulk cleanup**: 11 worktrees + 11 branches removed after 3-step `branch-salvage-workflow` on all 11 (5 orchestrator + 6 background-agent). Reclaimed ~1 GB.
  - 6 stale-locked agent worktrees unlocked (lock-PIDs 67230/1318/98890 all dead)
  - 7 agent worktrees removed (`abd130`, `ae3190`, `a1af5b`, `a8564e`, `a9196a`, `aeb77`, `aa99f6`)
  - 4 sibling `historical-feat-cc-*` worktrees removed (382 MB)
  - 4 named-feature branches deleted (all verified squash-merged): `docs/316-adjusted-close-schema`, `fix/313-trp-heap-walk`, `feat/269-pillar8-risk-metrics`, `fix/4371-drif-selection-helper`
  - **Session #14 aa99f6 hold resolved** — `cc31850` IS PR #384 (squash-merged 9 min after authoring; identical changes)
  - 13 anonymous unlocked agent worktrees left untouched (1–4 d old; Phase 7f auto-GC will sweep naturally)

## Headline numbers

| Metric | Value |
|---|---|
| PRs merged | 5 (#408, #409, #410, #411, #413) + 1 superseded (#412) |
| Issues filed | 2 (#414, #415) |
| New tests added | ~32 (8 + 6 + 5 + 13) |
| `bt.metric` extension | 8 new stability scalars per run, auto-recorded by both register_runs paths |
| #400 umbrella | All 6 PRs merged; issue still OPEN (close pending pipeline run + leaderboard re-render) |
| Worktrees | 25 → 14 (-11) |
| Disk reclaimed | ~1 GB (.claude/worktrees 2.1 → 1.5 GB; siblings 382 MB gone) |
| Branches deleted | 11 |
| Background agents | 2 (`ab6c9dd9` cherry-checks, `a528165b` cleanup) — both completed cleanly |

## Carry to next session

### Recommended priority

1. **Close #400 umbrella** — run full pipeline `tar_make()`, re-render `docs/leaderboard.qmd`, verify SSR values populated for the 9 covered strategies, then close #400
2. **Surface SSR for the 6 NA leaderboard rows** — wire direct return-vector dependencies for TOM, CMR, Avoid Worst, Risk State, OLMAR, PSO Optimal
3. **#414 Active Dual Momentum GTAA** — Subtask 1 (data sourcing): register 9-ETF daily series with common 2007+ start; decide on extending `strategy_names` to 15 rows
4. **#415 AA factor-strategies gap audit** — Subtask 1 (manual page capture, Cloudflare-blocked); then taxonomy extraction + COVERED/PARTIAL/GAP classification

### Or pick from

- **#362** Lazy Man's Momentum (queued since session #14)
- **roborev backlog** — 98 failed / 50 addressed / 48 unaddressed (pre-existing; unchanged this session)

## Known limitations / carry-forward

- **#400 itself still OPEN** despite all 6 PRs merged — close pending end-to-end pipeline run + leaderboard re-render
- **6 leaderboard strategies NA on SSR/top5pct** — TOM, CMR, Avoid Worst, Risk State, OLMAR, PSO Optimal — need direct return-vector dependencies
- **`leaderboard.qmd` HTML not yet re-rendered** — #409 ships the schema change only; `tar_make(leaderboard)` + render deferred
- **13 anonymous worktrees** — left untouched this session; Phase 7f auto-GC handles them as PIDs die and they age past 14 d
- **roborev backlog** — 48 unaddressed (pre-existing; not scoped to this session)
