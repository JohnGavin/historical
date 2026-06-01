# Current Work (Session 2026-06-01 #14 — 12 PRs merged + SSR rollout kicked off, ENDED)

**Last updated:** session end
**Previous sessions:** #13 (#365 mom_prepeak umbrella, 14 PRs), #12 (#347 DuckDB registry, 5 PRs), #11 (robustness trio + Pillar 8, 21 PRs)

## This session — 12 PRs merged + 2 issues filed + #400 rollout kicked off

### Session #13 follow-ups closed
- **#394** lychee long-tail cleanup (closes #392) — `.lycheeignore`, nix-shelled workflow, `vdev` URL semver guard
- **#395** idempotent `hd_run_upsert()` (closes #375)
- **#396** mom_prepeak short-leg +100% cap (closes #374)
- **#402** test-suite hygiene (closes #397) — `adjusted_close` rename cascade cleared

### Leaderboard fully populated
- **#398** wired 8 missing strategies + `qa_leaderboard_coverage` (closes #345)
- **#401** tar_make re-materialisation — all 14 strategies confirmed in deployed HTML; QA gate passes; warm-start rsync from main's `_targets/` cache worked (4m 22s second-pass)

### Testing & docs
- **#399** snapshot-test policy (closes #340) — decision-matrix doc + DRIF backfill
- **#404** inter-vignette cross-references (closes #339) — `## Related Vignettes` on 12 vignettes + QA gate
- **#406** re-render 9 of 12 vignettes + 3 cwd-trap fixes

### SSR rollout (issue #400)
- **#400 filed** — gap analysis vs existing `hd_hac_sharpe()`, `hd_deflated_sharpe()`, etc.; 6-PR rollout proposed
- **#403 PR 1/6** — `hd_rolling_sharpe()` + `hd_sharpe_stability_ratio()` (Newey-West HAC SE; 31 tests)
- **#405 PR 2/6** — `hd_top5pct_share()` seasonality companion (16 tests)
- **PRs 3-6 briefed in #400 comment 4597073377** — fixer for PR 3/6 hit Anthropic session limit; full self-contained briefs filed for post-reset pickup

### Lychee follow-up
- **#407** removed broken `.claude/memory/*` markdown link in CHANGELOG.md
- Manual `gh workflow run link-audit.yml` confirmed **conclusion: success** post-merge

### Worktree maintenance
- Pruned 13 unlocked agent worktrees (51 → 38). Held `agent-aa99f6` (unique commit `cc31850` overlapping with #384 — verify or remove next session)

## Headline numbers

| Metric | Value |
|---|---|
| PRs merged | 12 |
| Issues filed | 2 (#397, #400) |
| New tests added | ~47 (12 from #395, 7 from #398, 5 from #399, 7 from #404, 31 from #403, 16 from #405) |
| Test suite delta | FAIL 3 → FAIL 0 |
| Leaderboard strategies | 5 visible → 14 visible |
| Lychee CI | failing → green |

## Carry to next session

### Recommended priority
1. **#400 PRs 3-6 re-dispatch** (after Anthropic session reset at 14:50 Dublin) — full briefs in #400 comment 4597073377. Sequence: 3 (registry helper) → 4 (leaderboard wiring) → 5 (register_runs integration) → 6 (mom_prepeak gauntlet)
2. **3 deferred vignette re-renders** — `leaderboard.qmd` (cvar_95 schema mismatch — likely auto-fixed by PR 4/6), `jst-dashboard.qmd` (no RDS fallback), `macro-defense-rotation.qmd` (needs live `bt_*` targets). Small targets-runner dispatch after PR 4/6 lands.
3. **roborev backlog** — 48 unaddressed findings (pre-existing)

### Or pick from
- **#362** Lazy Man's Momentum (queued from session #13)
- **agent-aa99f6 worktree** — verify overlap with PR #384, then remove
- **Global rule proposal** — llm-side: ban `[X](.claude/memory/...)` link syntax in CHANGELOG.md (the #407 lesson)

## Known limitations / follow-up issues

- **#400 idempotency caveat** — `hd_metric_record()` upsert semantics need verifying as part of PR 3/6
- **Pre-existing roborev backlog** — 103 failed / 48 unaddressed (not scoped to this session)
- **Mid-session shell hiccup** — a few Bash calls returned exit 1 with no output during the lychee fix dispatch; self-recovered. Worth flagging if it recurs.
