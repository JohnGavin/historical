# Data Sourcing: Lessons Learned

Retrospective on `macro_daily` / `equity_daily` going permanently stale
(#619, #655, #673). Follows the format of `docs/t-lang-lessons.md` — a
project-local lessons doc, not a wiki page, because this is an engineering
process failure rather than research content.

## Status (decided, not pending)

`macro_daily` and `equity_daily` — the two HuggingFace-backed datasets read
by `historicaldata::hd_macro()` and `historicaldata::hd_ohlcv()` — are
**archived**, not "temporarily stale" or "an outage awaiting resolution":

- `macro_daily`: frozen at 2026-04-20 (measured 2026-08-01, #619)
- `equity_daily`: frozen at 2026-04-13 (measured 2026-08-09, #673)

No active work is sourcing a replacement. This is a deliberate decision, not
an oversight — see "What we decided" below. If that decision changes, update
this file and the code comments in `R/plan_partitions.R` and
`R/plan_risk_state.R` that reference it.

## What happened

Both datasets were seeded once, on 2026-05-06, by duplicating
`dsfefvx/finance-historical-data` on HuggingFace into our own
`JohnGavin/finance-data` repo. Nothing in this repo has refreshed either
file since (#619, root-cause comment, 2026-08-01):

- The weekly data poll (`.github/workflows/data-poll.yml`) covers `kalshi`,
  `ecb`, `guardian`, `commodities`, `cboe_vol` (and later `macro`,
  `intl_vol` — see below) — it never covered `macro_daily` or `equity_daily`
  as combined, served datasets.
- The fetch scripts that exist (`scripts/fetch_macro.R`,
  `scripts/fetch_equity.py`) write to different filenames
  (`data/raw/fred_macro.parquet`, `data/raw/yfinance_equity.parquet`) than
  what `hd_macro()`/`hd_ohlcv()` actually read
  (`macro_daily.parquet`, `equity_daily.parquet`) — so even a manual run of
  the fetch scripts would not have refreshed the served data.
- Only one uploader script existed at all (`scripts/upload_kraken_hf.sh`),
  and it is kraken-only.

So this was never a job that broke — it was work that was never scheduled.
No CI failure, no alert, nothing "red" anywhere: `hd_macro()` and
`hd_ohlcv()` kept returning perfectly valid-looking rows, just with a
tail that stopped moving. That is why it went unnoticed for roughly three
months, and why it was found by chance — a one-off coverage baseline for a
different issue (#617) — rather than by any dedicated check.

The same silent staleness held the Validation seal open on `rsc_subperiod`
(#673): `bt_partitions$equity$val_start` is 2026-05-01, and with
`equity_daily`'s boundary stuck at 2026-04-13, the Validation window looked
"correctly empty, as designed" (the #660 partition re-cut's stated
rationale) when it was actually empty because the feed had stopped, not
because the calendar hadn't caught up. The first successful
`fetch_equity.py` run would have carried the boundary past `val_start` and
pulled sealed Validation returns into an unbounded window
(`rsc_subperiod`'s old trailing slice), unlabelled, in the same action that
was supposed to produce the fix. `rsc_subperiod` is now explicitly bounded
at `holdout_end` so this is safe regardless of whether/when a refresh
happens — but the near-miss is the lesson: a comment asserting "this window
is empty, that's expected" needs to say **why** it expects that, because
the assumption behind it (the data will eventually catch up) can quietly
stop being true.

## What was tried

`#619`'s investigation (2026-08-01) ran the root-cause chain to the end
rather than stopping at "the pipe is broken":

1. Confirmed no GitHub Actions workflow references `fetch_macro`,
   `fetch_equity`, `fetch_factors`, or `fetch_crypto`.
2. Confirmed the fetch-script output filenames do not match the served
   dataset filenames (an undocumented rename+upload step that was never
   built).
3. Ran `scripts/fetch_macro.R` by hand and confirmed it still works —
   167,150 observations, current to the day it was run, no bit rot.
4. Checked composition against the upstream's own last commit message
   ("78 series = 27 FRED + 46 CBOE + 5 international") and found two of the
   three components (`fetch_macro.R`, `fetch_cboe_vol.R`) already run and
   already write a compatible schema — the missing piece was only the
   combine step, not new data-fetching work. `scripts/build_macro_daily.R`
   was written to close that gap (concatenate the three raw parquets into
   the served schema; publishing is a separate, deliberate step via
   `scripts/upload_hf.sh`, gated on `HF_TOKEN`).
5. Checked whether re-syncing from the upstream HuggingFace repo
   (`dsfefvx/finance-historical-data`) would be a cheaper fix than owning
   generation ourselves. Its commit history showed ~11 days of intense
   activity in April 2026 (2026-04-13 through 2026-04-23), then silence —
   100+ days with no commits as of the check. **We had duplicated an
   upstream that had already gone quiet 13 days earlier.** Re-syncing from
   it gains nothing: there is no live source to catch up to.

`#673` separately confirmed the equity side of the same shape (no scheduled
refresh, `.py` fetcher not wired into the `.R`-only poll matrix) and traced
its consequence forward into the Validation-seal near-miss described above.

## What we decided

Given the upstream is confirmed dead and building/scheduling our own
`equity_daily` producer (1,622 tickers, 7.1M rows, untested end-to-end) is
real, non-trivial work, the project decision (recorded in #619, #655, #673)
is: **do not treat this as an outage pending resolution.** Mark both
datasets archived, correct the code comments that reasoned about the
Validation-seal boundary as if it would naturally advance
(`R/plan_partitions.R`, `R/plan_risk_state.R`), and leave the partial
producer work that already exists (`scripts/build_macro_daily.R`,
`scripts/fetch_macro.R`, `scripts/fetch_cboe_vol.R`,
`scripts/fetch_intl_vol.R`) in place, unscheduled, as a starting point for
if and when a future decision is made to source new data. `dv_freshness`
(#617) — a check that would have surfaced this in days rather than months —
remains open and unbuilt.

## Lessons for next time

1. **Vet an upstream's maintenance activity before depending on it as a
   sole source.** A one-line check of `dsfefvx/finance-historical-data`'s
   commit history (`GET /api/datasets/.../commits/main`) would have shown
   it had already gone quiet before we ever duplicated it. That check takes
   seconds and would have changed the decision at seed time, not three
   months later.

2. **A one-time duplication is not a producer, and nothing marks the
   difference.** `hd_macro()`/`hd_ohlcv()` returned valid-looking data the
   entire time; there was no error state to distinguish "actively
   refreshed" from "seeded once, frozen forever." Any dataset brought in
   this way needs either a real scheduled refresh wired up before it ships,
   or an explicit, visible "archived / no refresh" marker from day one —
   not silence that looks identical to health.

3. **Consider mirroring/vendoring critical data with a generation path we
   own**, rather than relying indefinitely on a duplicated third-party
   snapshot with no maintenance guarantee from the source. The 2026-05-06
   duplication was a reasonable fast start; the mistake was never following
   it with our own producer, not the duplication itself.

4. **Decide, explicitly, what "stale" means vs. "archived" for a dataset
   with no active refresh — and say so in the code that reasons about data
   boundaries**, not just in an issue thread. `R/plan_partitions.R` had a
   comment calling the empty Validation window "expected, not a bug"
   without saying whether that expectation depended on the boundary moving
   naturally (it doesn't) — a comment that was accurate about the symptom
   and silent about the cause is exactly the kind of gap `fail-loud-not-null`
   is meant to close, applied to documentation rather than code.

5. **A staleness check needs to distinguish "hasn't caught up yet" from
   "there is no producer at all."** These have different fixes (wait, vs.
   build something) and different implications for anything downstream that
   assumes the boundary will move — like a Validation seal keyed to "the
   first month past the current data boundary." `dv_freshness` (#617) is
   still the right fix for surfacing this quickly next time; it did not
   exist when this outage started, which is a large part of why it ran for
   three months undetected.

## Related

- [#619](https://github.com/JohnGavin/historical/issues/619) — root-cause
  investigation; confirmed no producer, confirmed upstream dead
- [#655](https://github.com/JohnGavin/historical/issues/655) — a distinct
  but adjacent case: `leaderboard_snapshot.parquet` is *deliberately* frozen
  (a digest baseline, not a live feed) — worth reading alongside #619/#673
  as the contrast case for lesson 4: sometimes staleness is a bug that
  became permanent, sometimes it is the intended design, and the failure
  mode in both directions is not saying which, explicitly, where a reader
  will find it
- [#673](https://github.com/JohnGavin/historical/issues/673) — `equity_daily`
  staleness and the Validation-seal near-miss
- [#617](https://github.com/JohnGavin/historical/issues/617) — the still-open
  `dv_freshness` check that would have caught this sooner
- `.claude/rules/backtest-partitions.md` — the Validation-seal rule this
  incident's near-miss bears on
- `.claude/rules/fail-loud-not-null.md` — the general pattern this
  retrospective's lesson 4 and 5 are instances of
- `R/plan_partitions.R`, `R/plan_risk_state.R` — code comments updated
  alongside this document to reflect the archived status
