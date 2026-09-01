# Current Work — session 27 (2026-09-01, roborev daily-report follow-up)

## State

`main` at `b178b96` (S30 fix, PR #836) → `16d5755` (session 26 docs, PR
#835) both merged. This worktree's own branch (`feat/cc-20260829-145821`)
is clean, in sync with its own remote copy, but stale relative to `main`
(its content already landed via PR #835's squash-merge under a different
SHA). Nothing uncommitted.

## What this session was

Short, triggered by a pasted roborev daily report. Fixed the one in-scope
finding (S30 modified z-score double-MAD-scaling bug, historical#9941 →
PR #836), merged the outstanding session-26 docs PR (#835), and filed two
`llm` issues for everything else the report surfaced rather than fixing
another project's tooling from here. Full detail in `CHANGELOG.md`'s
"session 27" entry.

## Verification posture

The S30 fix (PR #836) is structural + unit-test verified only
(`scripts/verify.sh`: PASS, baseline-exact on both suites;
`test-leaderboard-plausibility-amber.R`: 13/13 pass). Root `R/` changes get
**no CI** — confirmed again this session. Not verified against a real
`tar_make()` — low risk given it's an isolated scaling-constant change with
no schema/signature change, but `scripts/build.sh` (main checkout only)
would be the way to see the real CMR amber-flag row update in a built store.

## Open decisions (not code — need a human, or need `llm`)

- [llm#1123](https://github.com/JohnGavin/llm/issues/1123) — `.roborev/`
  gitignore bug (29 non-running reviews), 14 unclassified-severity
  findings, dashboard-button 404 (three candidate causes listed, unresolved)
- [llm#1126](https://github.com/JohnGavin/llm/issues/1126) — whether `/bye`'s
  roborev Y/N gate should scale with session volume
- Everything carried over from session 26's CURRENT_WORK (leverage backstop
  level D1, #586 fat-tail/finite-horizon fallback, #719 Layer 2 full
  provenance checklist) is **unchanged** — this session didn't touch any of
  it. See `CHANGELOG.md`'s session 26 entry for the full list.

## Next session

**Signal Board tiers P2-P5 still untouched** (re-derive from a fresh `gh
issue list`, not the stale Signal Board snapshot — two sessions have moved
issues since it was built).

**Held back, still open, still worth a look** (carried over from session 26,
unchanged this session):

| Issue | Why held |
|---|---|
| [#553](https://github.com/JohnGavin/historical/issues/553)/[#554](https://github.com/JohnGavin/historical/issues/554)/[#555](https://github.com/JohnGavin/historical/issues/555) | Fundamentals pipeline built for a 10-ticker pilot only |
| [#585](https://github.com/JohnGavin/historical/issues/585) G1/G4 | Blocked on #587 Phase 2+ / #463 |
| [#490](https://github.com/JohnGavin/historical/issues/490) Gap 5 | pointblank pilot — low priority |
| [#813](https://github.com/JohnGavin/historical/issues/813) | avoid_worst leaderboard metrics wired to SPY buy-and-hold |
| [#804](https://github.com/JohnGavin/historical/issues/804) | `pkgctx-freshness` CI flake — still unfixed |
| [#830](https://github.com/JohnGavin/historical/issues/830), [#831](https://github.com/JohnGavin/historical/issues/831) | Crypto microstructure + NautilusTrader evaluation — not started |

**roborev at session end:** 54 verdict failures / 43 addressed → 11 net
unaddressed. 0 crashes, 0 quota, consistency check clean. Informational per
[llm#1126](https://github.com/JohnGavin/llm/issues/1126) — not re-asked
this session per explicit user instruction.
