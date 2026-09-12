# Current Work — session 30 (2026-09-11 → 2026-09-12)

**Ended 2026-09-12.** Branch `feat/cc-20260912-osap-verification` (fresh from
`origin/main`; the previous branch was squash-merged as `0c68bf4`).

## State

Session 29's work is **merged** ([PR #858](https://github.com/JohnGavin/historical/pull/858)).
This session's OSAP verification is on the new branch, pending a PR.

## The headline

**The survivorship blocker lifts, free — but not all the way.**

| | universe | returns |
|---|---|---|
| OSAP (Chen-Zimmermann) | **right** — 86.7% of 38,870 permnos exit >1yr before panel end | **none** |
| `equity_daily` | wrong — 0 of 502 exit | yes |

Complementary defects. Neither alone reproduces Zadeh's design. The full
thing still needs returns joined to a delisting-inclusive panel — CRSP, or
something supplying both. Norgate deprioritised on cost.

## Next session — pick one

1. **Land the OSAP verification.** Branch is committed, `verify.sh --quick`
   passes, no PR opened yet. Cheapest thing on the list.
2. **#857 portfolio-level interaction test.** The custom double sort is dead
   (no returns), but OSAP ships 212 pre-built long-short series and Ken
   French momentum deciles are already ingested. Ask whether MAX and momentum
   interact at portfolio level — a real test, a weaker claim, and the
   write-up must say which.
3. **#863 freshness split.** Needed before #862 ingestion lands, or a
   ~10-month-lagged source fails a 14-day threshold every run forever. The
   substance is *last-checked* vs *last-changed*, not a bigger number.
4. **#862 open sub-tasks:** find or build a `permno` crosswalk (none free —
   blocks joining OSAP to our ticker-keyed data), and decide how to handle
   the un-filterable non-common-stock securities.
5. **#861 pkgctx CI** — still red, still reporting nothing either way.

## Housekeeping

- **7.8 GB in `/tmp/osap_scratch`**, disk at 93% (60 GB free). Left
  deliberately so a follow-up need not re-download 8.35 GB. Delete when done.

## Carried forward from session 29, still unaddressed

**Plain 12-2 momentum is underpowered on 52.8 years of `equity_daily`**
(Sharpe 0.163, needs 231 years). That is the universe, not momentum, and it
applies to every cross-sectional long/short on this panel — including the
live `ltr_*` leaderboard strategy. Still deserves its own issue.

## Two process notes worth keeping

- **Search before filing.** Two near-misses in two sessions: nearly re-filed
  #816, then actually did duplicate #804 as #861. One
  `gh issue list --search` before writing would have caught both.
- **Check a subagent's supporting argument, not just its verdict.** The OSAP
  report's panel-shape corroboration was wrong (the 2024 count exceeds the
  1998 peak, contradicting the US listing decline) even though its P1 verdict
  was right. Withdrawn in `FINDINGS.md`. A correct conclusion can rest on a
  bad argument, and the argument is what gets quoted onward.
