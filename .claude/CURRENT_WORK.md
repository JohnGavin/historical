# Current Work (Session 2026-06-04 → 2026-06-11 #16 — #425 critical cost-bug fix + #442 Tier 1 registry + 7 PRs, ENDED)

**Last updated:** session end 2026-06-11
**Previous sessions:** #15 (#400 SSR closed, 5 PRs), #14 (12 PRs), #13 (#365 mom_prepeak umbrella, 14 PRs)

## This session — 7 PRs merged + 16 issues filed + critical cost-deduction bug discovered and fixed

### Headline

Multi-day session that discovered and fixed a **critical zero-cost-deduction bug** (#425) in `drif_portfolio` / `fm_portfolio` / `rsc_portfolio` — the deployed leaderboard's factor-level "net" Sharpe numbers were actually **gross**. PR cascade #437→#439→#440→#441 corrected the source, rebuilt the dashboards, and made the install-check chunk produce real output. Closed the registry/scorecard disconnect with **#442 Tier 1** (PR #444 — drif/fac_max/ltr/avoid_worst/rsc registered; `bt.strategy` now 8/14).

### PRs merged (7)

| PR | Subject |
|---|---|
| #433 | Umbrella session 1 (Cakici A/B + #278 + #125 + #415 + #425 + render) |
| #434 | docs/ HTML re-render against rebuilt #425 targets |
| #437 | Data-poll workflow + index.qmd headline source fixes (yr_history + 30→120 functions + collapsible datasets + install-check) |
| #439 | `<span>` not `<div>` in stats-row — fixes pandoc strip regression |
| #440 | Wider stat-card spacing + R install-check actually runs example commands |
| #441 | `space-evenly` stats-row + Nix `flake metadata` chunk + T pipeline-overview chunk |
| #444 | #442 Tier 1: register_runs for drif, fac_max, ltr, avoid_worst, rsc |

### Issues filed (16)

- **Tracking / bugs**: #424 (DRIF signal quality — resolved), **#425 (P0 cost deduction — fixed)**, #442 (registry gap — Tier 1 done)
- **Research (AA gap analysis)**: #426 Fundamental Value (HIGH), #427 Managed Futures (HIGH), #428 FIP momentum (MED), #429 Intl Momentum (MED), #430 ADD crowding (MED), #431 Long-history trend (LOW-MED), #432 Asset-class vs factor (LOW)
- **Strategy research**: #443 BDBB queueing on SOL (Varma 2026, depends on #436)
- **Infrastructure / UX**: #435 Collapsible articles table, #436 Kraken data integration, #438 Project Stop-hook for pkgctx
- **Cross-project**: **JohnGavin/JohnGavin.github.io#10** (user-site font +2), **JohnGavin/llm#532** (global pkgctx rollout)

### Issues closed (4)

- #312 Cakici A/B — deferred until universe widens (paired with #278); empirically no-op on top-100
- #424 DRIF signal quality — resolved on current universe (net SR -1.13 Full, -0.01 Validation; signal dies under realistic costs)
- #425 Zero-cost-deduction bug — fixed in #437
- #415 AlphaArchitect audit — 7 gap stubs filed (#426–#432) and labeled

### Key numerical impacts (now live on https://johngavin.github.io/historical/)

| Surface | Before | After |
|---|---|---|
| `drif_metrics` Full Sharpe | 0.259 | **0.076** |
| `fm_metrics` Full Sharpe | 0.015 | **-0.098** |
| `rsc_metrics` SPY_overlay Testing Sharpe | 0.853 | 0.582 |
| Stock MAX terminal $1 → | (gross) | **$0.21** |
| Stock DRIF terminal $1 → | (gross) | **$0.10** |
| Headline "history" | 5,553,492yr (bogus) | **100yr** |
| Headline "functions" | 30 (hardcoded) | **120** (from NAMESPACE / api-historicaldata.md) |
| `bt.strategy` rows | 3 | **8** |

### pkgctx integration (new this session)

- `docs/api-historicaldata.md` — 1,155 lines, 120 functions with signatures + human-friendly descriptions (replaces NAMESPACE link from landing page)
- `scripts/regen_api_context.sh` — manual entrypoint (`nix run github:b-rodrigues/pkgctx -- r packages/historicaldata --compact`)
- `.claude/CLAUDE.md` — regen reminder added
- **#438** (project-local Stop-hook + CI safety net) and **llm#532** (global rollout) filed as follow-ups

### Cakici A/B prototype (#312 explorations)

- `explorations/cakici_design_ab/` — three-variant comparison (Baseline / A filter-then-rank / B rank-then-renormalise) using cached `stk_drif_signal` × `stk_monthly_adv` with $5M ADV gate
- **Result**: A and B bit-for-bit identical on top-100 universe (Spearman 1.000); Baseline 0.998 vs both. Design choice is empirically a no-op until universe widens
- Deferred until #278 lands

## Failed Approaches (documented for future-session avoidance)

- **Pandoc strips `<div>` inside `<a>`** once `<details>` blocks appear later in the doc. Investigation chain: knit-level produces correct values (rules it OUT of R) → markdown intermediate fine → HTML missing div content → pandoc layer responsible. Workaround: Option A (spans + `display: block`); rejected Options B (`::: fenced div`) and C (include partial) without testing because A worked.
- **First render-fix subagent died with socket error** after 10 min (5 tool calls). Took over inline rather than re-dispatching.
- **Tier 1 register_runs agent's tar_make verification** failed on 3/5 strategies in fresh worktree (missing upstream targets cache). Fixed by orchestrator copying main's `docs/_targets/` (553 MB) into worktree → all 5 succeeded in 3.9s. Lesson: agents on fresh worktrees need a primed cache for any target with deep upstream deps.
- **`if/else` on separate lines without `{}` braces** parses fine interactively but FATAL in non-interactive Rscript — caught the `nix-verify` + `pipeline-overview` chunks in #441's first render attempt.

## Roborev status (advisory — NOT addressed this session)

- Last 7d: **23 reviews, 5 PASS, 18 FAIL, 0 ADDRESSED** (22% pass rate)
- 2 review-job crashes (claude-code agent)
- Median review duration: 47s, p99: 2.2m
- **For next session**: triage the 18 unaddressed failures. Many likely from this session's high-velocity PR cadence; may auto-resolve via cleanup-on-merge.

## Next session

- Continue on branch: `main` (session branch fully merged via squash; nothing pending)
- **Open priorities** (in suggested order):
  1. **#442 Tier 2** — wire register_runs for stk_max, stk_drif, xgb_drif (stock-level workhorses; follow same pattern as Tier 1 PR #444)
  2. **Triage roborev backlog** — 18 unaddressed failures from this session's velocity
  3. **#438** — project-local Stop-hook for `docs/api-historicaldata.md` auto-regen (small infra task)
  4. **#436** — Kraken data integration (gates #443 BDBB-SOL)
  5. **#442 Tier 3** — tom, cmr, pso_optimal (closes #442 entirely at 14/14)
- **Awaiting user decision**:
  - #278 OLMAR Phase 4 data source pick (Norgate ~$30/mo vs EODHD ~$20/mo vs CRSP academic vs defer)
- **Cross-project (someone else's session)**:
  - JohnGavin.github.io#10 (font size on user site — llm session has authority)
  - llm#532 (global pkgctx rollout — llm session)

## Session-end state

- Working tree: clean (6 untracked render byproducts retained as before — deliberately not committed)
- Branch: `feat/cc-20260604-102429` at 62b4139 (Tier 1 cherry-pick; superseded by main `e8cb7a9` via PR #444 squash)
- Remote: main contains all session work (ahead of session branch by 1 commit content-identical via squash)
