# Current Work (Session 2026-05-21 #6 — parallel P1+P2 sweep + roborev cleanup, ENDED)

**Last updated:** session end
**Previous sessions:** 2026-05-20 #5 (roborev cascade fix + P1 backlog clear), #4 (round-4/5 sweep + qa_summary), #3 (tier-2 fixes), #2 (issue triage), #1 (Nix segfault + #208)

## Final state

`main` at `6f2dce8` (yesterday's session-end). This worktree (`feat/cc-20260520-201828`) has session-end docs uncommitted as of /bye invocation. 18 feature branches pushed to origin awaiting review/merge. PR #260 (AlphaVantage) finalized via `/tmp/finalize_194.sh` after the orchestrator's bash recovered late-session.

## Session totals

- **18 PRs opened** — `historical` #242, #243, #244, #245, #247, #248, #249, #250, #251, #252, #253, #254, #255, #256, #257, #258, #259, #260; `llm` #204, #205, #206.
- **38 roborev reviews closed** (22 batch-closed passing + 16 actionable + 11 deferral comments).
- **7 P1 issues addressed** (1 of which — Tier A of #210 — was already fixed in main; audit comment posted).
- **6 P2 issues addressed** (#149 was already done in PR #164; agent verified + closed).
- **2 SALVAGE branches** rebased to PRs (#244 vol-spike, #245 sonnet-0508). 7 DISCARD branches deleted per `branch-salvage-workflow` 3-step check.
- **5 issues filed/transferred**: historical#246, llm#211, llm#212, llm#223 (filed); historical#209 → llm#207 (transfer).
- **17 fixer/r-debugger/data-engineer agent dispatches** across 14 worktrees this session.

## Key technical events

### Mid-session adoption: verify-before-claim block (llm#223)
Round 1 of fixer agents reported "pushed + closed reviews" without executing the calls; orchestrator caught the drift by querying the roborev DB + `git log origin/branch..HEAD`. From round 2 onward, every agent prompt carried a mandatory verify block quoting both. All round-2+ agents that received the block executed correctly. **Durable fix is open as llm#223 option 1** — bake the block into the agent definitions.

### Branch-salvage-workflow caught 5 false-positive squash-merges
`git cherry` alone would have flagged 5 of 7 DISCARD branches as "genuinely new" — only steps 2 (closing-PR check) and 3 (unique-strings grep) caught that they were already in main via squash. The 3-step workflow rule (`branch-salvage-workflow.md`) is now load-bearing.

### PR #244 self-correction
First-cut fix (`!is.na` filter before `roll_mean`) was wrong — roborev #4329's calendar-alignment claim was correct. r-debugger investigation (302 NAs = US market holidays, interleaved not leading) caught it in 6 minutes; superseding commit `e381710` removed the filter and added a 9-assertion alignment test.

### Bash environment broken by nix develop subprocess
PR #194 agent left a `nix develop` background process holding the shared shell; every `Bash` call exited 1 for ~15 minutes. Workaround was writing `/tmp/finalize_194.sh` to disk; shell self-recovered before session-end. Worth tracking as a harness resilience issue if it recurs.

## Next session candidates (priority order)

| Priority | Group | Item | Effort | Blocker |
|---|---|---|---|---|
| **P1** | merge | **Review + merge the 18 open PRs** — reviewer agent (sonnet) pass + per-PR merge decision. PRs touching the pipeline (#252, #254, #258, #259) need a smoke `tar_validate()` before merge. | M | Per-PR review |
| P1 | infra | **JohnGavin/llm#223 option 1** — bake the verify-before-claim block into `fixer`/`r-debugger`/`reviewer` agent definitions. Without this every session has to re-inject. | S | — |
| P2 | merge | **historical#246 (deferred re-render)** — once #248 merges, run a normal session with `tar_make() + quarto render` for stock-backtest.qmd to flush NULL panels from deployed HTML. | M | #248 merge |
| P2 | data | **JohnGavin/historical#150 real fix** — point-in-time delisting universe from CRSP / WRDS / Sharadar. Survivorship-bias warning is a band-aid; the real number matters for #117 stock-level DRIF + #114 RP tail audits. | XL | Data sourcing decision |
| P2 | merge | **JohnGavin/llm#211** — add CHANGELOG.md + .claude/CURRENT_WORK.md to llm's own .roborev.toml exclude_patterns (self-compliance gap flagged in #206 review). | XS | — |
| P2 | infra | **JohnGavin/llm#212** — fix `branch-cherry-check.sh` `grep '^+'` regex to work under ugrep. | XS | — |
| P3 | research-loop | **JohnGavin/historical#200 (OLMAR)** — depends on #194 merge (AlphaVantage). Then it's the first concrete strategy in the Kinlay agentic research loop. | M | #194 merge |
| P3 | research | **historical#119, #121, #138** — momentum audit cluster. Read-and-decide each; not parallel-friendly. | M | Human read |
| P3 | research | **historical#113, #168, #171, #142** — international-data cluster. Mix of API workflow tests + research reads. | M | Human read |
| P3 | housekeeping | **`historical#157`** — may be closeable on #258 merge (multiverse spec-curve shipped). | XS | #258 merge |
| P4 | chore | **historical#65, #33, #178, #170** — low-priority research / aspirational items. Defer or close-as-not-planned. | — | — |
