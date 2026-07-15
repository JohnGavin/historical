# Current Work — session 24 end (2026-07-15)

## State: 1 code commit (leaderboard link metadata) + 4 gap issues

## What happened

- Fable-model analysis of dashboard simplifications beyond #514. Ranked opportunities; full Phase-0 plan for items 2–5, recommended sequence **5→3→2→4** (5=extend #481 relationship map, 3=fold bdbb-sol→evidence, 2=de-dup leaderboard hub, 4=centralise momentum-prepeak gauntlet). Plan is in the session transcript, NOT yet filed as issues.
- Fixed 4 leaderboard `definition` URLs → GitHub source anchors (commit `3971943`, parse-verified). Reframed as a metadata fix, not a live-404 fix — the field isn't rendered as links anywhere (only stored in the parquet digest snapshot + a QA coverage check).
- Filed 4 gap issues: #559 (momentum life cycle / AA), #560 (Quantitativo Weekly 4f8 triage), #561 (Cushing EIA storage), #562 (OWID food_trade eval spike).

## Next session

- **Push** commit `3971943` + this CHANGELOG entry (branch ahead of origin) or open a PR.
- **File Phase-0 tracking issues** for Fable items 5→3→2→4 (one umbrella or four) — offered to user, not yet done.
- Optional user-visible follow-up: add TOM/CMR/Value/Managed-Futures rows to the static Definition table at `leaderboard.qmd:202-211` (they're absent; that's the table readers actually see).
- Investigate failing **Link audit (lychee)** CI job.
- Spawn strategy issues from #560 triage (reversal-tilt momentum #1 first).

## Branch

- `feat/cc-20260707-174758` — ahead of origin (leaderboard fix committed; CHANGELOG + CURRENT_WORK edits pending commit).
