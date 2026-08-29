# Current Work — session 25 (2026-08-27 → 2026-08-29)

## State

`main` at `90576f5`, working tree clean, pushed. Store built and verified:
19 pages render clean, 0 errored targets.

**11 PRs merged:** #769, #770, #775, #776, #780, #786, #789, #790, #792, plus
publish PRs #772, #777, #781, #787. #791 was yours.

## What this session was

Owner-reported dashboard defects, fixed and published. Then a set of gaps filed
against an external methodology piece.

Root causes were mostly in **vendored CSS**, not our code:
- DataTables ships `div.datatables { color: #333 }` — ~1.3:1 on dark
- Bootstrap ships `caption { font-size: 0.875em }`
- bslib grid rows are `1fr`, so content overflows into the next row
- Quarto's article layout is an 850px `.page-columns` grid — the width
  complaint was a **format** difference (`html` vs `dashboard`), not CSS

And one in our own: `quiz.qmd` never loaded `vignette-shared.css` at all, so
every shared fix this session had bypassed it. It passed every audit because
those checked what the stylesheet contained, never whether a page loaded it.

## The lesson

Nearly every wrong conclusion came from a **check that could not distinguish
the states it was meant to separate**:

| Check | Why it couldn't fail |
|---|---|
| Caption word count | counted hidden `<details>` text |
| Pages `errored` at 0 ms | means *superseded*, not failed |
| Pages `built` in 1253 ms | published nothing; real build is ~27 s |
| Three `until` waiters | broken command ≡ not-finished; cancelled ≡ complete; compared response to itself |
| `grep -c` | counts lines, not occurrences |
| `Working tree` field | always dirty — counted its own render output |

The code defects hunted were the same shape. `checks-must-distinguish-unknown`
applies to throwaway shell, not only to production gates.

## Verified live (OBSERVED, by served bytes)

- `Source tree | clean` on all 11 real dashboards
- Captions >45 visible words: 0 of 11
- `page-layout-full` on evidence/bdbb-sol/quiz; TOC markup 0
- evidence.html: 19 tabs, 4/4 DT tables carrying data (4, 6, 16, 18 rows)
- heatmap PNG hash matches local

## Next session

**Unverified — needs a human at a browser.** Every visual outcome. Specifically
[leaderboard#rankings](https://johngavin.github.io/historical/leaderboard.html#rankings)
in **Chrome** (where the contrast broke; Edge was always fine), and
[evidence](https://johngavin.github.io/historical/evidence.html) — does 457
lines of prose read well at full width? If not, the fix is a max-width on prose
blocks, **not** reverting `page-layout: full`.

**Open, unstarted:**

| Issue | |
|---|---|
| [#793](https://github.com/JohnGavin/historical/issues/793) | No mechanical kill switches — highest priority; unbounded failure mode |
| [#778](https://github.com/JohnGavin/historical/issues/778) | Cost metrics reach 6 of 17 strategies |
| [#794](https://github.com/JohnGavin/historical/issues/794) | Capacity never modelled — sequence behind #778 |
| [#795](https://github.com/JohnGavin/historical/issues/795) | Proxy measurement error undocumented; includes a **revision-risk** finding |
| [#788](https://github.com/JohnGavin/historical/issues/788) | Column hover help — planned, phased, decisions recorded |
| [#779](https://github.com/JohnGavin/historical/issues/779) | XGB DRIF SSR indeterminate — now *less* visible after the uniform labels |
| [#782](https://github.com/JohnGavin/historical/issues/782) | SSR name collision + a **false citation** in roxygen (fix that first) |
| [#771](https://github.com/JohnGavin/historical/issues/771), [#774](https://github.com/JohnGavin/historical/issues/774), [#783](https://github.com/JohnGavin/historical/issues/783), [#784](https://github.com/JohnGavin/historical/issues/784), [#785](https://github.com/JohnGavin/historical/issues/785) | filed with evidence |

**roborev:** 39 verdict failures, 21 addressed → **18 unaddressed**. 0 crashes,
0 quota, consistency check clean.

**Housekeeping:** untracked vendored `docs/*_files/libs/**` — some pages may
reference libraries never committed. Worth a look before it bites.
