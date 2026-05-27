# Current Work (Session 2026-05-26/27 #10 — #288 CI gate + #160 deflated Sharpe + WFC digest + roborev clean-up, ENDED)

**Last updated:** session end
**Previous sessions:** #9 (external-source digests, Cloudflare/PDF), #8 (research-log DB #270, OLMAR #200), #7 (merge-queue drain)

## This session (4 PRs merged)
- **#293 → closed #288:** CI-portable tests (`skip_if_no_remote_data()`) + restored `r-tests.yml`
  with trusted Cachix (installer `extra-conf` + `trusted-users`). CI gate now active.
- **#296 → closed #160:** `strat_keff_vertox` + `strat_deflated_sharpe` targets (reuse #268
  `strat_corr_matrix`), `deflated_sharpe` leaderboard column, "Deflated Sharpe" vignette tab,
  `backtest-robustness` §5 K_eff-guided stop rule.
- **#298 (#297):** WFC digest from Tinsley SSRN PDF → `wiki/walk-forward-correlation.md`.
- **#300 (#279):** flow-pressure ADD clause in `priced-in-prohibition` (#279 still open: Angle B).
- **Filed:** #297 (WFC gap), #299 (CPCV gap), llm#309 (clean-verdict autoclose gap).
- **Roborev:** closed 39 lingering clean PASS reviews (closure 80%→88%; PASS 68.8%→100%).
  Root cause of the lingering: `roborev_severity_autoclose.sh` skips no-finding reviews → llm#309.
- **Lesson (memory `feedback_fetch-before-building`):** #294/#295 were built on a stale base and
  discarded; ALWAYS `git fetch origin main` + diff for overlap before writing code.

## NEXT TASK (resume here) — triage the 58 open FAIL roborev reviews

The only roborev gap left for `historical`. Plan = **stale-check first, then parallel
file-disjoint worktrees, priority-ordered**. Severity totals: 22 High / 26 Medium / 10 Low
(max per review); all <7d old. Get the finding text per review with `roborev show <job_id>`
(or `roborev log <job_id>`); review id = `r####`, job id = `j####`.

### CRITICAL caveat — many are already-merged / obsolete
39 of 58 review commits are ancestors of origin/main; 19 are squash-merged-content or superseded.
**Being "on main" ≠ finding fixed** — check each finding against CURRENT main code. Known-obsolete:
- **r4497 (j4730, 9b45019)** = the discarded #295 commit — NOT on main, superseded by #296/#300 → **close**.
- **r4484 (j4717, 3f33f9b)** "drop r-tests.yml" — reverted by #293 which restored it → **close**.
- **r4495/r4496/r4498/r4499** (#288/#160 commits) + **r4482** (#287) — now merged; verify findings
  addressed, else fix-forward.

### Phase 0 — obsolete/prose sweep (orchestrator, no worktree, `roborev close <job_id>`)
Verify-then-close: r4497, r4484 (definite); then the Low/Med knowledge-prose findings on
already-merged wiki pages if the page is fine: r4479, r4480, r4396, r4389, r4391, r4388, r4397,
r4462, r4346. Expect to clear ~12–18 of the 58 cheaply.

### Worktree groups (file-disjoint → no cross-WT merge conflict). Each agent: fetch origin/main,
branch fresh, per review read finding → check current main → fix-if-live (commit) → report
obsolete review-ids for orchestrator to close. Then re-tabulate.

| WT | Priority | Theme / files | Reviews (job ids in parens) | Agent |
|----|----------|---------------|------------------------------|-------|
| **A** | P1 | Package data-layer `packages/historicaldata/R/{alphavantage,registry,query,ranked,research_log}.R` | r4380(j4613) r4373(j4606) r4370(j4603) r4359(j4592) r4362(j4595) r4361(j4594) r4458(j4690) r4481(j4713) | `r-debugger` |
| **B** | P1 | Strategy pipelines `R/plan_{turn_of_month,olmar,drif,drif_v2,solana_momentum,volatility_spikes,strategy_correlation,qa_vignette}.R` + `R/solana_defi_data.R` + pkg `olmar.R`/`topological_risk_parity.R` | r4485(j4718) r4461(j4694) r4372(j4605) r4371(j4604) r4337(j4568) r4334(j4567) r4355(j4589) r4329(j4561) r4489(j4721) r4368(j4600) | `r-debugger` |
| **C** | P2 | CI/build `.github/workflows/{pytest,data-poll}.yml`, `flake.nix`, `scripts/` | r4476(j4709, flake→`nix-env`) r4369(j4602) r4331(j4564) r4328(j4562) r4347(j4580) r4025(j4257) | `fixer`+`nix-env` |
| **D** | P3 | Docs/render + Mermaid anchors `docs/{stock-backtest,falsification}.qmd`, `R/diagram_node_links.R`, `R/plan_qa_gates.R`, `docs/vignette_utils.R`, `tests/testthat/test-vignette-utils.R` | r3828(j4037) r4357(j4590) r4296(j4530) r4348(j4582) r4353(j4583) r4294(j4528) r4293(j4529) r4354(j4585) r4344(j4578) r4336(j4570) r4039(j4270) r4030(j4263) r4026(j4250) | `fixer` |
| **E** | P4 | Knowledge prose (whatever Phase 0 didn't close) `knowledge/` | r4333(j4566) + Phase-0 leftovers | `quick-fix` |

**Unassigned / needs finding-read first** (empty file in parse): r4366(j4599, H — `rel=noopener`
security, likely a qmd/generated HTML → put in D), r3854(j4067, tests/testthat.R → A or D),
r4347/r4025 (scripts → C). Read the full finding to locate before assigning.

**Notes for execution:** `plan_qa_gates.R` lives only in WT-D (keep out of B). `plan_leaderboard.R`
findings (r4499/4498/4496) are #160 just-merged → verify in Phase 0, don't re-edit in a WT.
Re-run the roborev tabulation (Python, `~/.roborev/reviews.db` repo_id 16) after each wave.

## Open follow-ups
- llm#309 (clean-verdict autoclose) · #299 (CPCV) · #297 (build `wf_correlation` target) · #279 Angle B
- llm#296/#303, global `statistical-reporting` §2 K_eff-FDR — **llm session** (cross-project scope).

## Notes
- Session-end skipped (cross-project, own-tree-only): `export_and_deploy_data.sh` (pushes to
  llmtelemetry) and `ctx_sync` (reads ~/docs_gh/llm). Leave for the llm session.
- roborev `close <job_id>` (not review id); recoverable with `--reopen`. No `closed_at` column —
  time-to-close is an `updated_at` proxy (true fix = roborev change → out of scope).
