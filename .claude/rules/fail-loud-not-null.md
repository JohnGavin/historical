# Rule: Fail Loud, Never Null — Unrecognised Values Must Abort, Not Coerce

## Source

Generalised from the same defect recurring three times in two days (2026-08-03 → 2026-08-05), each time in a different vocabulary, each time discovered by accident rather than by a gate:

| Issue | The unexpected value | What it was silently coerced to | How it surfaced |
|---|---|---|---|
| [#637](https://github.com/JohnGavin/historical/issues/637) | a metric in percent where fractions were assumed | a number 100× wrong, ranked against its peers as if comparable | a reader noticed a vol of 6.82 next to a vol of 0.18 |
| [#643](https://github.com/JohnGavin/historical/issues/643) | period label `"Full"` where `"Full Period"` was assumed | a dropped row — the strategy vanished from the ranking | someone counted the leaderboard rows |
| [#640](https://github.com/JohnGavin/historical/issues/640) | absent `metric_unit` | `NA_character_`, written to the registry as a bare unitless number | found while fixing #637, not by any check |
| [#641](https://github.com/JohnGavin/historical/issues/641) | a month missing from one of four constituents | the month deleted from the portfolio for **all** constituents | someone asked why the heatmap had no March |

Earlier instances of the identical shape, recorded before it was named: `as.logical("1")` returning `NA` and silently disabling `VIGNETTE_STRICT`; a `Date`/`POSIXct` mismatch making `full_join` produce zero matches; NAs cascading through `roll_mean`/`roll_sd`.

## The defect shape

> An unexpected value is silently coerced to a null-ish state — `NA`, `NULL`, a dropped row, a zero-row join, a skipped test — instead of raising an error.

Null-ish states are indistinguishable from *legitimately absent* data. That is what makes this class expensive: the failure produces output that looks exactly like a correct answer to a smaller question. Nobody sees a stack trace. The number just quietly becomes wrong, gets published, and is then used as an input somewhere else — #641's truncated PSO Optimal vol was about to be adopted as the book-level risk anchor in [#635](https://github.com/JohnGavin/historical/issues/635).

The three carriers seen so far are **units**, **vocabularies**, and **factor levels / join keys**. Expect a fourth.

## When This Applies

Any code that maps an incoming value onto a known, finite set, or that assumes a value's scale or type. Concretely:

- Reading or writing a metric that has a unit (`fraction`, `percent`, `ratio`, `count`, `days`)
- Any comparison, `filter()`, `case_when()`, `switch()`, or `match.arg()` against a controlled vocabulary (`period` labels, `partition` names, strategy names, severity levels, `directionality`)
- Any join key, factor level, or enum crossing a boundary between two targets, two packages, or a package and a database
- Any environment variable or config value parsed into a type (`as.logical`, `as.numeric`, `as.Date`)

## CRITICAL: An unrecognised value is an error, not a missing value

There are exactly two acceptable responses to a value outside the known set:

1. **`cli::cli_abort()`**, naming the offending value, the field it came from, and the allowed set.
2. **An explicit, commented, deliberate default** — with a test asserting that default holds.

`NA`, `NULL`, silent row-drop, and `else` branches that swallow the unknown case are never acceptable.

## Required Pattern

### 1. Name the vocabulary once

Every controlled vocabulary gets a single exported constant that is the sole source of truth — the way `PERIOD_LABELS_ALLOWED` in `R/plan_partitions.R` is for period labels. No file may inline a literal from that set.

### 2. Validate at every boundary, in both directions

Validate on **write** (reject the bad value before it is stored) *and* on **read** (reject or normalise it before it is used). #640 is the cautionary case: `bt.metric` correctly *recorded* `metric_unit` but validated it on neither side, so the column was decoration.

### 3. Normalise on read, and say what you normalised to

A reader must never need to know the storage convention. A function returning a value plus its unit must return the **canonical** unit it converted to, not the one it happened to find.

### 4. Make the drop observable

Where a row, month, or observation legitimately *may* be dropped, count what was dropped and report it:

```r
n_before <- nrow(x)
x <- x |> dplyr::filter(...)
if (nrow(x) < n_before) {
  cli::cli_warn(c("!" = "Dropped {n_before - nrow(x)} row{?s} at <site>: {.val {dropped_keys}}."))
}
```

A silent `return(NULL)` inside an `lapply()` is the single most common instance of this in `R/` — it removes a whole period from a series and leaves no trace.

### 5. Guard where the value ENTERS, not only where it is used

A correct guard on the wrong code path is silent. Validate at the point a value is
**supplied**, not only at the point it is **consumed** — because the consuming path
is frequently the harder one to reach, and a value supplied on a path that never
consumes it escapes validation entirely.

The tell: the guard lives inside an `if`, a mode flag, a command-line branch, or a
target that only some runs build. Ask **"on which invocations does my guard not
run, and can a bad value arrive on one of those?"** If yes, the guard is
mis-placed, however correct its logic.

| instance | guard was correct, but ran only… | so what escaped |
|---|---|---|
| #693/#694 | when the extractor found a `tibble()` | a refactor to `data.frame()` returned `character(0)`, so `required` was empty and the coverage check passed vacuously |
| #710 | in `--data-staleness` mode, which needs a store | a malformed `HD_STALE_DASHBOARD_DATA_THRESHOLD_DAYS` is silently ignored in default mode *and in the weekly CI job* |

Both were written to satisfy **this rule**, by someone who had read it, and both
left a hole one level up. That is the evidence that "add a guard" is not sufficient
guidance on its own — placement is a separate decision from existence, and it is
the one that keeps going wrong.

**A related but distinct failure — the guard fires and nobody sees it.** #691 is
often cited alongside the two above and it is not the same thing:
`hd_metric_record()`'s unit guard was correctly placed and *did* fire, erroring
eleven registry writers. What failed is that `error = "continue"` in
`docs/_targets.R` made `tar_make()` exit 0 anyway, so the guard's output was
invisible for four commits.

Keep the two apart, because the fixes differ. A mis-placed guard is fixed by moving
it; an unseen guard is fixed by making its output reachable — which is why
`scripts/build.sh` and `scripts/check_pipeline_errors.R` exist. Both defeat the
same intent, so when a guard fails to protect you, ask **which** of the two it was
before reaching for a fix.

Corollary for configuration: **if a variable is set, validate it — even if this
code path ignores it.** Setting an environment variable is an expression of intent;
silently ignoring a malformed one is the null-coercion this rule prohibits, applied
to config instead of data.

### 6. Add a QA gate, not just a test

Every instance of this class that we fix gets a gate target in `R/plan_qa_gates.R` so it runs on every `tar_make()`, not only under `testthat`. A test proves the fix once; a gate stops the next occurrence. The gate must abort, and its `cli_abort` message needs `expect_snapshot(error = TRUE, ...)` coverage per `snapshot-test-policy`.

Gates in this family so far:

| Gate | Guards | Introduced |
|---|---|---|
| S9 `qa_leaderboard_metric_ranges` | units — cagr/vol/max_dd within fractional range | #637 |
| S10 `qa_leaderboard_period_vocab` | vocabulary — canonical `period` labels | #643 |

The gap this rule closes: **#640 (registry units) and #641 (join-key coverage) had no gate**, which is exactly why they survived the session that fixed the first two.

## Forbidden Patterns

| Pattern | Why wrong | Fix |
|---|---|---|
| `metric_unit = if ("metric_unit" %in% names(tbl)) ... else NA_character_` | The absent case is the dangerous one; defaulting it to `NA` licenses unitless numbers | `cli_abort` naming the allowed set |
| `inner_join()` across strategy series by `ym` / `date` | One series' gap silently deletes the period for all of them | `full_join` onto an explicit spine; decide the missing case in code |
| `case_when(...)` / `switch(...)` with no terminal `.default` that aborts | Unknown level falls through to `NA` | Terminal branch calls `cli_abort` |
| `filter(period == "Full Period")` against un-normalised upstream labels | A spelling variant becomes a dropped strategy | Compare against the shared vocabulary constant after normalising |
| `if (length(y_train) < 200) return(NULL)` inside `lapply()` | Removes a whole month from the series with no signal | Count and `cli_warn` the dropped keys |
| `isTRUE(as.logical(Sys.getenv("X")))` | `as.logical("1")` is `NA`, so the flag silently defaults off | Parse explicitly against `c("1","true","TRUE","yes")` |
| A validator called only inside `if (mode)` / a branch / an optional target | The guard cannot fire on the paths that do not enter that branch, so a bad value supplied there is silently accepted | Validate where the value is supplied; see Required Pattern 5 |
| `Sys.getenv("X")` read and validated only where `X` is used | A malformed value set on a path that ignores `X` is never reported — the user believes it took effect | Validate whenever the variable is non-empty, regardless of mode |
| `suppressWarnings(as.numeric(x))` | Converts a parse failure into `NA` and hides it | Check `is.na()` after conversion and abort |
| Fixing an instance with a test but no gate | The next instance is unguarded | Add the `R/plan_qa_gates.R` target |

## Self-test

Before merging any code that reads a value from another target, a database, an env var, or a file, answer:

> If this value arrives with an unexpected spelling, scale, or type, does my code **stop**, or does it produce a plausible-looking number?

If the answer is "produces a number", it is not finished.

Then a second question, about the guard you just wrote:

> On which invocations does this guard **not** run — and can a bad value arrive on
> one of those?

If it can, the guard is mis-placed however correct its logic. This second question
is the one that keeps being skipped: #694 and #710 both passed the first test and
failed the second, in code written by people who had read this rule.

## Related

- `.claude/rules/backtest-partitions.md` — the canonical partition vocabulary this rule protects
- `.claude/rules/strategy-name-consistency.md` — the same single-source-of-truth discipline applied to strategy names
- `.claude/rules/snapshot-test-policy.md` — new `cli_abort` messages require snapshot coverage
- `data-glossary-and-entity-resolution` (global) — canonical units and canonical entity names are the same problem
- `data-validation-timeseries` (global) — temporal-coverage checks belong in the pipeline as targets, not only in tests
- [#637](https://github.com/JohnGavin/historical/issues/637), [#640](https://github.com/JohnGavin/historical/issues/640), [#641](https://github.com/JohnGavin/historical/issues/641), [#643](https://github.com/JohnGavin/historical/issues/643) — the four instances that motivated this rule
- [#693](https://github.com/JohnGavin/historical/issues/693), [#710](https://github.com/JohnGavin/historical/issues/710) — the two instances that motivated Required Pattern 5 (guard placement). Both post-date the rule and were written in compliance with it, which is the point: existence and placement are separate decisions, and the rule previously governed only the first.
- [#691](https://github.com/JohnGavin/historical/issues/691) — the adjacent failure named in Pattern 5: a correctly-placed guard whose output was invisible because `error = "continue"` let `tar_make()` exit 0. Fixed by [#693](https://github.com/JohnGavin/historical/issues/693)'s `scripts/build.sh`, not by moving any guard.
