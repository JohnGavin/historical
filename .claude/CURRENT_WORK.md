# Current Work (Session 2026-05-20 #2 — round-4/5 roborev sweep + qa_summary verified, ENDED + triage addendum)

**Last updated:** post-session triage addendum (open-review backlog measured at 23, not 3)
**Previous sessions:** 2026-05-20 #1 (issue triage, tier-2 fixes, branch hygiene, ENDED), 2026-05-19 #2 (roborev backlog sweep), 2026-05-19 #1 (Nix segfault + #208)

## Final state

`main` at `3c2400b` (post-session triage addendum). Last pushed code commit was `d2ab8d1` (Merge round-5 roborev fixes); subsequent doc-only commits `acd58ba` (session 4 changelog) and `3c2400b` (triage addendum) extend the head. Working tree clean. 8 worktrees remain (1 main + 7 stale per #238).

## Session totals

- **13 roborev findings closed** (3 won't-fix + 5 cluster fixes round 4 + 5 round-5 follow-ups + 2 moot/mitigated)
- **qa_summary verified PASS** end-to-end (first time since te_ir_metrics regression of session 3)
- **5 fixer worktree agents (round 4)** ran in parallel; only 2 of 5 stayed in their feature branches — the other 3 auto-pushed to origin/main. Round-5 prompt added explicit "don't push" discipline.
- **stock-backtest.html re-rendered as dashboard** (was broken on origin/main since cd13635 — plain Bootstrap article instead of declared `format: dashboard`)
- **2 housekeeping issues processed:** #237 closed (4 worktrees + 9 branches deleted); #238 triage comment posted (all 4 mapped issues CLOSED → abandonment recommendation pending user sign-off)
- **1 new issue filed:** #239 (Python pytest CI integration; deferred from roborev 3561)

## Key technical events

### Three of five round-4 fixer agents auto-pushed to main
Despite prompts saying "do not merge to main — orchestrator will handle," 3 of 5 `fixer` (sonnet) agents committed and pushed directly to `origin/main` (commits `bdbcd94 eea9185 cd13635 0e2c302`). Likely cause: inside their isolation:"worktree", the local HEAD was named `main` and a default `git push` targeted `origin/main`. Round-5 prompt explicitly warned the agent: "verify branch is NOT main; do NOT push." Round-5 agent complied; the round-5 work merged via proper `--no-ff` from `worktree-agent-a213234c80687324f`.

### stock-backtest dashboard regression
Cluster C agent (round 4) re-rendered `docs/stock-backtest.html` as a plain Bootstrap article instead of a Quarto dashboard. The qmd declares `format: dashboard` with dark/light themes + `vignette-shared.css/js`. Detected by roborev 4023a. Round-5 agent re-rendered correctly via `nix develop --command quarto render` — output now contains 27 dashboard markers (quarto-dashboard.js, vignette-shared.css, etc.). Published docs were briefly broken on origin/main.

### stale_marker reverted to NULL contract
Cluster B agent audited 50+ `is.null()` callers across 9 vignette qmds before deciding which approach. Session-3's `stale_marker` sentinel would have silently bypassed every guard. Predicate `is_stale_marker()` kept for any future migration.

## Next session candidates (priority order, set by post-session triage)

| Priority | Group | Item | Effort | Blocker |
|---|---|---|---|---|
| **P1** | code-quality | 5 open roborev reviews on today's HEAD commits (`acd58ba`, `7cd3f90`, 3× `73770e6c`). Triage: close or fix while context is fresh. | S | — |
| P2 | code-quality | 18 older open roborev reviews — backlog rot risk, some likely moot. | M | — |
| P2 | CI/automation | **#239** — wire pytest into CI + add `raw_yield==0.20` boundary test. | M | CI config decisions |
| P3 | housekeeping | **#238** — delete 9 stale WIP branches + 7 worktrees (sonnet-0508 alone = 142 MB; all 4 mapped GH issues CLOSED). | S | **User sign-off required (destructive-fs-guard)** |

### Discovery: open-review backlog larger than predicted
`roborev list --open` returned **23** open reviews at session-end, not the 3 predicted from "round-6 auto-refine noise." 5 are on today's HEAD commits; the remaining 18 pre-date today.

### Carried-over follow-ups (independent of the table above)
- **Capture agent-worktree-push-discipline** as a memory file or rule. Pattern: when delegating with `isolation:"worktree"`, explicitly tell the agent to NOT push and to verify its branch is not `main`.
- **Retention policy** for `inst/extdata/results/results_*.parquet` artifacts.
