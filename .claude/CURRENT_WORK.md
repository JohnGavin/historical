# Current Work (Session 2026-05-20 #5 — roborev cascade fix + P1 clear + folder hygiene, ENDED)

**Last updated:** session end
**Previous sessions:** 2026-05-20 #4 (round-4/5 sweep + qa_summary verified), #3 (tier-2 fixes), #2 (issue triage), #1 (Nix segfault + #208)

## Final state

`main` at `a8f1802` (Merge fix/roborev-yield-fields-helper). Pushed to `origin/main`. Working tree clean on both worktrees (main + this session's `historical-feat-cc-20260520-114440`). 6 worktrees remain (main + this session's transient + 5 WIP per #238).

## Session totals

- **Cascade root cause diagnosed + fixed** — exclude_patterns ship + poll-merges SQL fix. Two separate bugs, both addressed.
- **19 roborev findings closed** (16 with merge SHA refs + 1 clean + 2 from earlier W-B/W-C/W-D round). Queue 24 → 20 (all 20 remaining are status=failed ghosts blocked by daemon API).
- **8 sonnet-fixer worktree agents** ran cleanly with isolation:"worktree" — no auto-push-to-main incidents this session (round-5 prompt discipline holds).
- **Folder cleanup** — 6 worktrees + 7 branches removed; disk 2.7 GB → 2.1 GB; cluster-b + cluster-d work pulled into main with proper conflict resolution at stock-backtest.qmd:132.
- **Issues filed:** historical#240, historical#241 (CLOSED), llm#193, llm#198 (CLOSED), llm#199.

## Key technical events

### Diagnostic ROI: stop and look before fixing repeatedly
12 reviews on `11cf813` were the same 5 findings, fired by the 15-min poller on a `commit_id`=range-start storage convention. Inspecting the launchd plist + the poller SQL took 5 minutes and produced a 1-line fix; fixing each review individually would have produced 12 more reviews. The cascade analysis itself became llm#198 and the structural fix prevents future recurrence across all projects.

### exclude_patterns is a daemon-native feature
`.roborev.toml` `exclude_patterns = [...]` is documented in the global config (`# Filenames or glob patterns to exclude from review diffs globally.`). Per-repo override is read on every review request — no daemon restart needed. Probe (CHANGELOG-only edit + `roborev review --dirty`) returned `no uncommitted changes to review`, confirming exclusion at the diff stage, not the review stage.

### Cluster-d merge conflict pattern
Yesterday's cluster-d branch had a 24h-old fix to `stock-backtest.qmd:132` that overlapped today's Group D NA guard fix at the same site. Correct resolution kept Group D's `is.finite()` logic AND applied cluster-d's prose simplification (drop "strongest Testing-period Sharpe" framing). Delegated to fixer/sonnet for proper resolution rather than orchestrator manual edit.

## Next session candidates (priority order)

| Priority | Group | Item | Effort | Blocker |
|---|---|---|---|---|
| **P1** | code-quality | **4263** — cache `.parse_vignette_strict()` result OR use `rlang::warn(.frequency = "once")` to prevent repeated cli_warn during a render. | XS | — |
| P2 | infra | **JohnGavin/llm#199** — decide worktree-location convention (option 1 vs 2 vs 6); migrate existing siblings. | M | Convention decision |
| P2 | docs | **JohnGavin/historical#240** — Mermaid click links → `#L<n>` anchors driven from `R/diagram_node_links.R` helper + QA gate. | M | — |
| P2 | rules | **JohnGavin/llm#193** — promote line-anchor requirement to `visualization-detailed` skill + global rule. | S | — |
| P3 | housekeeping | **JohnGavin/historical#238** — 5 WIP folders (commodities, crypto, momentum-vol, sonnet, zakamulin) per-branch verdict. Sonnet-0508 alone is 142 MB and has 22 unique commits. | M | User sign-off (destructive-fs-guard) |
| P3 | infra | **roborev daemon job-level dismiss feature** — needed to clear the 20 failed-ghost reviews; track as a roborev infra ticket if upstream is responsive, otherwise SQL-direct UPDATE on the daemon DB as a workaround. | M | Upstream / infra decision |
| P3 | housekeeping | **`.archive/` retention** — adopt 30-day manual or 7-day cron. | XS | — |

## Carried-over follow-ups

- Capture `agent-worktree-push-discipline` as a memory file — pattern was reinforced this session: every fixer prompt included verbatim "verify branch is NOT main; do NOT push" and no agents pushed to main.
- Update `nix-agent-shell-protocol` rule to note that `git -C <main-checkout> diff default.nix` after any worktree-isolated agent run is the right post-condition check.
- The Bug 2 fix in `roborev_poll_merges.sh` is now in llm/main and will deploy on the next launchd run. Verify by checking `~/.claude/logs/roborev_poll_merges.log` next session for `skip: historical — HEAD(...) already has N review(s)`.
