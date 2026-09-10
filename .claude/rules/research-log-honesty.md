# Rule: Research-Log Honesty — Never Seal After the Fact, Never Collapse an Outcome

## Source

Session 29, 2026-09-10, logging the [#857](https://github.com/JohnGavin/historical/issues/857) momentum x MAX failure into the `hd_rlog_*` store. Two decisions came up that the schema permits but that would each have made the log say something untrue. Writing them down so the next session does not have to re-derive them — and, more to the point, so the tempting wrong answer is visibly the wrong answer.

## When This Applies

Every write to the research-log store (`hd_rlog_append()`), and every reading of one. Both writers today are `R/plan_olmar.R` and `explorations/`; any future writer inherits this.

## CRITICAL: A seal applied after the result is known is a lie about when you committed

`hd_rlog_seal()` hashes the claim fields so a hypothesis cannot be silently reworded once the outcome is in. Its own documentation is unambiguous:

> Seal at **inception**, before the hypothesis is tested. A hash applied after you have seen the result commits to nothing.

The trap is that sealing is *easy* and *looks rigorous*. A sealed row displays a `commit_hash` and a `sealed_at`; an unsealed row displays three NAs. Every instinct says fill in the blanks. **Do not.** The blanks are the honest record.

Sealing a hypothesis you have already tested does not merely fail to add rigour — it actively manufactures evidence of a pre-registration that never happened, and it is indistinguishable, later, from one that did. That is worse than no seal at all, because the whole value of the seal is that a reader can trust it.

| Situation | Seal? | `extra_json` |
|---|---|---|
| Claim written before any test was run | **Yes** — seal now, at inception | — |
| Claim written from a paper/article, then tested in the same session | **No** | `preregistered: false` + `seal_omitted_reason` |
| Claim reconstructed after the fact to describe what was found | **No**, and say so | `preregistered: false`; consider whether this is a hypothesis at all |
| Existing sealed row whose outcome is now known | Leave the seal; update `status` only | `status` is deliberately excluded from the hash |

**Record the omission, do not just leave it blank.** Three NAs are ambiguous between "deliberately unsealed" and "nobody got round to it" — the `checks-must-distinguish-unknown` failure mode applied to provenance. State it:

```r
extra_json = jsonlite::toJSON(list(
  preregistered       = FALSE,
  seal_omitted_reason = "outcome known before logging; sealing post-hoc commits to nothing"
), auto_unbox = TRUE)
```

### The corollary worth internalising

If you find yourself wanting the seal because the row "looks unfinished" without it, that is the feeling the rule exists to override. The unsealed row is not unfinished. It is accurate.

## CRITICAL: One status per outcome — never collapse pass, fail, and unknown

The vocabulary is `hd_rlog_statuses()`. Use it; do not invent values.

The value to be most careful with is the legacy `"tested"`. It says a test happened and nothing about what it concluded, collapsing three genuinely different outcomes into one label — the exact distinction `checks-must-distinguish-unknown` exists to preserve. It is retained only so existing writers keep working and must not be used in new code.

The two `inconclusive-*` values are not interchangeable, and the difference decides what to do next:

| status | means | what it implies |
|---|---|---|
| `refuted` | Tested with adequate power; the claim failed. | The claim is wrong. Stop. |
| `inconclusive-underpowered` | Tested; the sample cannot resolve it either way. | **More data of the same kind would help.** |
| `inconclusive-unmeasurable` | The required population or variable is absent. | **More data of the same kind would NOT help.** A different source is needed. |

Reporting an underpowered result as `refuted` throws away a claim that was never actually tested. Reporting an unmeasurable one as `inconclusive-underpowered` sends the next session off to gather more of a sample that can never answer the question.

Worked example, both from #857 on the same run:

- *"MAX-filtering momentum improves risk-adjusted return"* → `inconclusive-underpowered`. Measured; every long/short Sharpe needs 126–8,468 years against 52.8 available. A longer sample would settle it.
- *"Low-momentum high-MAX stocks return −14.8%"* → `inconclusive-unmeasurable`. `equity_daily` contains 0 delistings, so the population the claim concerns is absent. **No sample length fixes this** — only a delisting-inclusive panel ([#816](https://github.com/JohnGavin/historical/issues/816)) will.

Both "failed". Only one of them is about the amount of data.

## Log the failures

A research log that contains only successes is a marketing document. The failures are the higher-value rows: they are what stops the next session spending a week re-deriving a dead end, and #857's null result is more useful to a future reader than any of its positive numbers.

If an experiment ran, it gets a row — including when the answer is "we could not tell".

## Every metric read from a file, none typed

Metrics written to the log come from the committed result files, read by committed code (`explorations/momentum_max_lottery/log_to_research_db.R` is the reference implementation). A hand-typed Sharpe carrying a `# from the run` comment is a violation, not a confirmation — the global reproducible-ingestion rule applies to the log exactly as it applies to a dashboard.

Corollary: **do not write a naive value into a column named for a corrected one.** `results.sharpe_hac` means the HAC-adjusted Sharpe. If only a naive Sharpe was computed, either derive the HAC one (`hd_hac_sharpe()`, then `hac_tstat * sqrt(ann_factor / T)`) or leave the column NA and put the naive figure in `extra_json` under its own name. Silently aliasing one for the other is the `fail-loud-not-null` mislabelling defect, and it is invisible on read.

Equally: **do not leave a column NA when the value is computable.** An NA that stands in for "nobody derived it" is indistinguishable from "not applicable" ([#728](https://github.com/JohnGavin/historical/issues/728)). If a series exists in the results directory, compute the metric from it.

## Forbidden Patterns

| Pattern | Why wrong | Fix |
|---|---|---|
| Sealing a hypothesis after seeing the result | Manufactures a pre-registration that never happened; indistinguishable later from a real one | Leave unsealed; record `preregistered: false` and the reason |
| Unsealed row with no `seal_omitted_reason` | Ambiguous between deliberate and forgotten | State the reason in `extra_json` |
| `status = "tested"` in new code | Collapses supported / refuted / inconclusive | Use a precise value from `hd_rlog_statuses()` |
| Underpowered result recorded as `refuted` | Discards a claim that was never tested | `inconclusive-underpowered` |
| Unmeasurable result recorded as `inconclusive-underpowered` | Sends the next session after more of a sample that cannot answer | `inconclusive-unmeasurable` |
| Only logging experiments that worked | The failures are the higher-value rows | Log the null results |
| Naive Sharpe written to `sharpe_hac` | Mislabelling; invisible on read | Derive it, or NA + `extra_json` |
| NA in a column whose value sits in a results file | NA standing in for "not computed" | Compute it |
| Metrics typed by hand into the log script | Not reproducible, no audit trail | Read them from the committed result files |

## Self-test

Before appending a hypothesis:

> **If someone reads this row in a year, will they correctly infer whether I committed to this claim before or after I knew the answer?**

And before appending a result:

> **Does my status distinguish "it's wrong" from "I couldn't tell" — and if I couldn't tell, does it say whether more data would help?**

## Related

- `hd_rlog_seal()` / `hd_rlog_statuses()` — the mechanisms this rule governs
- [`checks-must-distinguish-unknown`](../../.claude/rules/checks-must-distinguish-unknown.md) (global) — the three-state discipline the status vocabulary implements
- [`fail-loud-not-null`](fail-loud-not-null.md) — the mislabelling and NA-as-silence defects
- [`detection-power-required`](detection-power-required.md) — what makes a result `inconclusive-underpowered` rather than `refuted`
- [`resulting-prohibition`](resulting-prohibition.md) — why the claim must precede the outcome
- [#857](https://github.com/JohnGavin/historical/issues/857) — origin
- [#859](https://github.com/JohnGavin/historical/issues/859), [#860](https://github.com/JohnGavin/historical/issues/860) — research-log defects found alongside
