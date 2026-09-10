# Current Work — session 29 (2026-09-08 → 2026-09-10)

**Ended 2026-09-10.** Branch `feat/cc-20260908-195542`, 3 commits,
pushed. [PR #858](https://github.com/JohnGavin/historical/pull/858) OPEN,
MERGEABLE — **not merged**, awaiting review.

## What shipped

| Commit | What |
|---|---|
| `2409162` | `.claude/rules/strategy-combination-modes.md` — filter/blend/time/hedge, 7 checks for a filter |
| `e4be0dc` | `explorations/momentum_max_lottery/` — momentum x MAX double sort |
| `a3577fc` | Research-log DB entries for the failure (2 hypotheses, 1 impl, 12 results, 3 critiques) |

Issues touched: [#857](https://github.com/JohnGavin/historical/issues/857)
raised (Thesis A of #549 had no impl issue),
[#549](https://github.com/JohnGavin/historical/issues/549) updated twice,
[#816](https://github.com/JohnGavin/historical/issues/816) labelled
`theme:data`/`high-priority` and given evidence + a vendor comparison.

## Next session — pick one

1. **Trial Norgate Diamond** (3 weeks free, ~$787.50/yr, US back to 1950,
   delisted + PIT index constituents). Run `plan_universe_pit.R`'s own step 3
   against the fixture: Enron, Lehman, Bear Stearns, WorldCom, WaMu — all five
   verified absent from `equity_daily` today. **First question to the vendor is
   not price: does it carry a `delisting_price` / delisting return?** Unknown
   for Norgate; known present for CRSP. This gates #816, #857 and #552.
2. **Build `hd_max_daily_return()` + `hd_realized_skewness()`** (#857
   deliverable 1). Cheap, reusable, needed regardless of how the Zadeh claim
   resolves. Migrate `R/plan_mean_reversion.R:85`'s inline `slider::slide_dbl`
   skew to the exported version so there is one definition, not two. Package
   export changes → run `scripts/regen_api_context.sh`.
3. **Apply the new rule to `plan_mean_reversion.R`** — it applies three
   simultaneous risk filters (`min_skew`, `max_semivar_ratio`, `max_cvar_pct`)
   with hardcoded thresholds, no complement control, no per-filter attribution.
   Zadeh's design with none of the checks. `ablation` appears nowhere in `R/`.
4. **Obtain both papers.** Zadeh (2026) and the datageeek "66-page SSRN study".
   Both #857 sources are second-hand. Step 0 there.

## Carry forward — the finding with the widest blast radius

**Plain 12-2 momentum is underpowered on 52.8 years of our data** (Sharpe
0.163, needs 231 years at 80% power). That is the universe, not momentum. It
applies to every cross-sectional long/short on `equity_daily` — including the
live `ltr_*` leaderboard strategy — not just the experiment that found it.
Worth its own issue if nobody has raised one.

## Loose ends, unfiled

- `hd_rlog_path()` roxygen says "package root"; code returns the **repo** root.
- OLMAR hypothesis duplicated in the append-only research log (same UUID,
  2026-05-23 and 2026-06-16). Breaks any count query.
- Morningstar Direct Web Services docs are unreadable (JS SPA) — the DWS row in
  the #816 comparison is deliberately blank. Paste the pages to fill it.

## Note on session numbering

This session initially self-labelled "26" and collided with `main`, which was
already at **session 28**. Session 28's own notes record it making the same
mistake for the same reason: parallel worktrees, each unaware of what the
others have landed. Renumbered to 29 during the merge. Session 28's handover
is preserved in its `CHANGELOG.md` entry (2026-09-03 → 2026-09-05).

**Before writing a session number, read `git show origin/main:CHANGELOG.md`** —
the local checkout's newest entry is not the repo's.
