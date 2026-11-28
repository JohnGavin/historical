# Current Work — latest: session 2026-11-09 → 11-12 (ended)

- Merged #1051 (commodity momentum timing), #1052 (one cost per strategy on
  the leaderboard), #1053 (commodity labels daily, Sharpe sqrt(252)), #1054
  (re-render 6 pages), #1060 (momentum on the tradeable era #1057; CMR
  captions on one Sharpe basis #1058), #1059 (docs/DATA_SOURCES.md with an
  Econvitals entry). Main at faab923; session worktrees removed.
- Session CHANGELOG entry merged (#1062, 68d460a); its worktree removed.
- Next: #1061: apply CMR's #808 exposure-map rule to momentum (drop the 13
  monthly IMF/FRED indexes from its position pool). Needs no new decision; the
  owner has not yet said "fix #1061".
- Uncommitted: `docs/macro-defense-rotation.html` (fresh render). Blocked by
  private_data_scan false positives (base64 PNG = uk-postcode; a private-term
  entry matching inlined htmlwidgets.js 1.6.4). Raised as llm#1733 (llm side,
  leave alone). Never use --no-verify.
- Private-term matches also already sit on main in public CHANGELOG.md (lines
  1474, 1519, 2277) and in the live macro-defense-rotation.html. Owner to look;
  term not revealed.
- Issues opened: #1055 (Econvitals data review), #1056 (dashboard design
  ideas), #1057, #1058, #1061; llm#1727 (design gaps), llm#1728 (auto-briefing;
  owner chose "draft emailed, owner says publish"), llm#1733 (scanner).
- Stranded work: the #873 Kraken DATA_SOURCES.md, inventory CSV and script are
  only on `feat/cc-20260920-192457`, never merged. Ask before harvesting.
- Known caveats, not fixed: CMR and the stock family still use hand-typed
  turnover; the Credible rule `abs(net_cagr) < 0.20` flags strongly negative
  CAGRs.

---

# Earlier: session 2026-11-07 (ended)

- Merged #1040 (PIT S&P 500 membership universe, 63439e3) and #1042 (OLMAR
  survivorship critique row, 3a47dcb). Closed #816, #977, #691, #668;
  #862 closed as duplicate of #863. Opened #1041 (delisting returns).
- Main checkout on `main` at 3a47dcb; session worktrees removed.
- Pending owner decision: #972 step 2 (switch deflated Sharpe to the logged
  K=13?). Recommendation: hold until the log covers the leaderboard
  strategies (k_eff 14.4, k_raw 17).
- No CHANGELOG entry yet for #1042 and the closes (main is PR-only).
- Parked: bdbb-sol DT migration (blocked on llm#1653).

---

# Earlier: session 2026-11-03 → 11-04 (ended)

- Merged #1019-#1025 (QA gates S47-S50, OLMAR universe + critique rows, SPY
  frequency alignment, 8-dashboard re-render). Session worktrees removed.
- Open: changelog PR #1016 (now holds both 2026-11-03 entries); #937 P3.2;
  #771 bdbb-sol/`fals_dt()`; #977 survivorship magnitude; #976 closed by
  accident (reopen?); privacy scanner should skip base64 `data:` URIs.
- Main checkout is on merged branch `chore/render-dashboards-20261103`:
  switch to `main` next session.
- Inbox alerts not looked at: private-data-history-audit job failing 3x;
  6 high roborev findings (llm-wide); 1 failed cron.

---

# Previous: session 30 (2026-09-11 → 2026-09-12)

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

## Added late in the session (2026-09-13)

- **[#865](https://github.com/JohnGavin/historical/issues/865) — ticker
  recycling.** A distinct problem from #816: not "which companies are
  missing" but "which company did this symbol mean at the time".
  `fetch_fundamentals_edgar.R` resolves ticker to CIK with no date check.
  Latent today, wrong by construction.
- **[#816](https://github.com/JohnGavin/historical/issues/816) — a free third
  route.** Reconstruct S&P 500 membership from `fja05680/sp500` + SEC + CIK
  overlap validation, then join to our own prices. Complements OSAP rather
  than replacing it.
- **[llm#1193](https://github.com/JohnGavin/llm/issues/1193) — Wikidata** as
  a data-generation and cross-check stack. Travel is the best first candidate
  (private project). Confirm-only, never refute.
- **Fixed a High roborev finding in my own commit** (`79a8992`) — the OSAP
  script's Drive confirm-token regex could never match. Caught by roborev,
  not by me; verified by direct test before fixing.

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

roborev-inbox: 58 new finding(s) (jobs 12637,12646,12652,12655,12656,12659,12661,12668,12672,12679,12681,12682,12691,12692,12693,12705,12708,12709,12711,12714,12716,12724,12726,12727,12728,12732,12734,12738,12749,12761,12763,12767,12770,12772,12773,12781,12785,12786,12787,12789,12791,12792,12797,12800,12811,12810,12816,12821,12825,12826,12830,12835,12867,12868,12870,12872,12873,12874) -- see `~/.roborev/findings/<job>.md` or `roborev show <job>`

roborev-inbox: 42 new finding(s) (jobs 12885,12890,12949,12951,12950,12953,12954,12955,12982,12991,12985,12992,12994,12993,12998,13001,13012,13013,13017,13020,13034,13035,13037,13040,13038,13039,13041,13046,13051,13053,13054,13052,13056,13057,13058,13059,13060,13062,13091,13233,13234,13268) -- see `~/.roborev/findings/<job>.md` or `roborev show <job>`

roborev-inbox: 8 new finding(s) (jobs 13395,13396,13397,13404,13426,13427,13428,13440) -- see `~/.roborev/findings/<job>.md` or `roborev show <job>`

roborev-inbox: 2 new finding(s) (jobs 13443,13459) -- see `~/.roborev/findings/<job>.md` or `roborev show <job>`

roborev-inbox: 21 new finding(s) (jobs 13564,13565,13583,13602,13603,13605,13607,13615,13619,13620,13623,13622,13626,13627,13628,13629,13630,13652,13665,13666,13667) -- see `~/.roborev/findings/<job>.md` or `roborev show <job>`

roborev-inbox: 20 new finding(s) (jobs 13684,13685,13700,13707,13719,13717,13718,13721,13723,13750,13755,13756,13759,13773,13781,13793,13797,13808,13821,13841) -- see `~/.roborev/findings/<job>.md` or `roborev show <job>`

## Session 2026-11-03 (end state)

- **Merged:** #1008-#1015 (census, S45, Hyperliquid, CIK, rule fix, rf-basis item 4, S46 gate, inner-join audit). Closed #959, #554, #555.
- **Open PR:** [#1016](https://github.com/JohnGavin/historical/pull/1016) CHANGELOG entry (needs "merge").
- **Open PRs, both agents finished and re-verified by tests:**
  - [#1019](https://github.com/JohnGavin/historical/pull/1019) SPY benchmark-correlation join (issue [#1017](https://github.com/JohnGavin/historical/issues/1017)). Build in progress at /bye time.
  - [#1020](https://github.com/JohnGavin/historical/pull/1020) builds stop writing the research log, seed script + S47 gate (issue [#1018](https://github.com/JohnGavin/historical/issues/1018)). Build NOT yet run; touches `.claude/rules/` so needs "merge".
  - [#1016](https://github.com/JohnGavin/historical/pull/1016) CHANGELOG entry.
- **Main checkout is on a DETACHED HEAD at `origin/fix/spy-benchmark-join-657` (4bf53c6)** with `fals_results_db` invalidated and `scripts/build.sh` running in background (log: scratchpad `build_spy.log`). Before anything else: `pgrep -fl build.sh`; if a build is running, wait for it (never start a second); then read the log for `build.sh: PASS`, run `git checkout main`, then do the same for #1020 (detached checkout of `origin/fix/rlog-readonly-builds-968c`, then `scripts/build.sh`).
- A rebuild on a later day adds a new `inst/extdata/results/results_<date>.parquet`; old files keep the old wrong `correlation_benchmark` values (owner decision: keep as record or add a basis marker).
- **Uncommitted in main checkout:** re-rendered dashboards and `docs/_targets_meta_snapshot.csv` (publication = separate PR, needs "merge").
- **Owner decisions still open:** none queued; S46 allow-list entry (uuid d2ccd873) kept as merged.
- **Telemetry export:** skipped, another export was running; rerun `~/.claude/scripts/export_and_deploy_data.sh`.

roborev-inbox: 10 new finding(s) (jobs 13903,13912,13916,13918,13917,13945,13947,13958,13957,13959) -- see `~/.roborev/findings/<job>.md` or `roborev show <job>`
