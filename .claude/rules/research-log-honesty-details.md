---
paths:
  - "R/plan_olmar.R"
  - "explorations/**"
  - "packages/historicaldata/R/research_log*.R"
  - "packages/historicaldata/R/admission_preregister.R"
  - "scripts/dedupe_research_log*.R"
---

# Details: Research-Log Honesty — origin and worked examples

Companion to [`research-log-honesty`](research-log-honesty.md). That file holds
every normative requirement; this one holds the origin and worked examples.
Nothing here adds or relaxes a requirement.

## Source

Session 29, 2026-09-10, logging the [#857](https://github.com/JohnGavin/historical/issues/857) momentum x MAX failure into the `hd_rlog_*` store. Two decisions came up that the schema permits but that would each have made the log say something untrue. Written down so the next session does not have to re-derive them — and so the tempting wrong answer is visibly the wrong answer.

Both writers at the time were `R/plan_olmar.R` and `explorations/`; any future writer inherits the rule.

## Why a post-hoc seal is worse than none

The trap is that sealing is *easy* and *looks rigorous*. A sealed row displays a `commit_hash` and a `sealed_at`; an unsealed row displays three NAs. Every instinct says fill in the blanks. The blanks are the honest record.

Sealing a hypothesis you have already tested does not merely fail to add rigour — it actively manufactures evidence of a pre-registration that never happened, and it is indistinguishable, later, from one that did. That is worse than no seal at all, because the whole value of the seal is that a reader can trust it.

### The corollary worth internalising

If you find yourself wanting the seal because the row "looks unfinished" without it, that is the feeling the rule exists to override. The unsealed row is not unfinished. It is accurate.

### Recording the omission — snippet

```r
extra_json = jsonlite::toJSON(list(
  preregistered       = FALSE,
  seal_omitted_reason = "outcome known before logging; sealing post-hoc commits to nothing"
), auto_unbox = TRUE)
```

Three NAs are ambiguous between "deliberately unsealed" and "nobody got round to it" — the `checks-must-distinguish-unknown` failure mode applied to provenance.

## Status vocabulary — worked example

Both from #857 on the same run:

- *"MAX-filtering momentum improves risk-adjusted return"* → `inconclusive-underpowered`. Measured; every long/short Sharpe needs 126–8,468 years against 52.8 available. A longer sample would settle it.
- *"Low-momentum high-MAX stocks return −14.8%"* → `inconclusive-unmeasurable`. `equity_daily` contains 0 delistings, so the population the claim concerns is absent. **No sample length fixes this** — only a delisting-inclusive panel ([#816](https://github.com/JohnGavin/historical/issues/816)) will.

Both "failed". Only one of them is about the amount of data.

Reporting an underpowered result as `refuted` throws away a claim that was never actually tested. Reporting an unmeasurable one as `inconclusive-underpowered` sends the next session off to gather more of a sample that can never answer the question.

## Why log the failures

A research log that contains only successes is a marketing document. The failures are the higher-value rows: they are what stops the next session spending a week re-deriving a dead end, and #857's null result is more useful to a future reader than any of its positive numbers.

## Metrics read from files

`explorations/momentum_max_lottery/log_to_research_db.R` is the reference implementation of reading metrics from committed result files.

If only a naive Sharpe was computed, either derive the HAC one (`hd_hac_sharpe()`, then `hac_tstat * sqrt(ann_factor / T)`) or leave the column NA and put the naive figure in `extra_json` under its own name. An NA that stands in for "nobody derived it" is indistinguishable from "not applicable" ([#728](https://github.com/JohnGavin/historical/issues/728)).

## Related issues

- [#857](https://github.com/JohnGavin/historical/issues/857) — origin
- [#859](https://github.com/JohnGavin/historical/issues/859), [#860](https://github.com/JohnGavin/historical/issues/860) — research-log defects found alongside
