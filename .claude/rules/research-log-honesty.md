---
paths:
  - "R/plan_olmar.R"
  - "explorations/**"
  - "packages/historicaldata/R/research_log*.R"
  - "packages/historicaldata/R/admission_preregister.R"
  - "scripts/dedupe_research_log*.R"
---

# Rule: Research-Log Honesty — Never Seal After the Fact, Never Collapse an Outcome

Origin (session 29, [#857](https://github.com/JohnGavin/historical/issues/857)) and
worked examples live in [`research-log-honesty-details.md`](research-log-honesty-details.md).

## When This Applies

Every write to the research-log store (`hd_rlog_append()`), and every reading of one. Both writers today are `R/plan_olmar.R` and `explorations/`; any future writer inherits this.

## CRITICAL: A seal applied after the result is known is a lie about when you committed

`hd_rlog_seal()` hashes the claim fields so a hypothesis cannot be silently reworded once the outcome is in. Its own documentation is unambiguous:

> Seal at **inception**, before the hypothesis is tested. A hash applied after you have seen the result commits to nothing.

Sealing is *easy* and *looks rigorous*; an unsealed row displays three NAs. **Do not fill in the blanks.** The blanks are the honest record. Sealing a hypothesis you have already tested manufactures evidence of a pre-registration that never happened, indistinguishable later from a real one — worse than no seal.

| Situation | Seal? | `extra_json` |
|---|---|---|
| Claim written before any test was run | **Yes** — seal now, at inception | — |
| Claim written from a paper/article, then tested in the same session | **No** | `preregistered: false` + `seal_omitted_reason` |
| Claim reconstructed after the fact to describe what was found | **No**, and say so | `preregistered: false`; consider whether this is a hypothesis at all |
| Existing sealed row whose outcome is now known | Leave the seal; update `status` only | `status` is deliberately excluded from the hash |

**Record the omission, do not just leave it blank.** Three NAs are ambiguous between "deliberately unsealed" and "nobody got round to it". State it in `extra_json` (`preregistered = FALSE`, `seal_omitted_reason = "<why>"`; snippet in the details file). If you want the seal only because the row "looks unfinished" without it, that is the feeling this rule exists to override.

## CRITICAL: One status per outcome — never collapse pass, fail, and unknown

The vocabulary is `hd_rlog_statuses()`. Use it; do not invent values.

The legacy `"tested"` says a test happened and nothing about what it concluded, collapsing three different outcomes into one label. It is retained only so existing writers keep working and must not be used in new code.

| status | means | what it implies |
|---|---|---|
| `refuted` | Tested with adequate power; the claim failed. | The claim is wrong. Stop. |
| `inconclusive-underpowered` | Tested; the sample cannot resolve it either way. | **More data of the same kind would help.** |
| `inconclusive-unmeasurable` | The required population or variable is absent. | **More data of the same kind would NOT help.** A different source is needed. |

Reporting an underpowered result as `refuted` throws away a claim that was never tested. Reporting an unmeasurable one as `inconclusive-underpowered` sends the next session after a sample that can never answer the question. (Worked example from #857 in the details file.)

## Log the failures

A research log that contains only successes is a marketing document. If an experiment ran, it gets a row — including when the answer is "we could not tell".

## Every metric read from a file, none typed

Metrics written to the log come from the committed result files, read by committed code (`explorations/momentum_max_lottery/log_to_research_db.R` is the reference implementation). A hand-typed Sharpe carrying a `# from the run` comment is a violation, not a confirmation — the global reproducible-ingestion rule applies to the log exactly as it applies to a dashboard.

Corollary: **do not write a naive value into a column named for a corrected one.** `results.sharpe_hac` means the HAC-adjusted Sharpe. If only a naive Sharpe was computed, either derive the HAC one (`hd_hac_sharpe()`, then `hac_tstat * sqrt(ann_factor / T)`) or leave the column NA and put the naive figure in `extra_json` under its own name. Silently aliasing one for the other is the `fail-loud-not-null` mislabelling defect, and it is invisible on read.

Equally: **do not leave a column NA when the value is computable.** An NA standing in for "nobody derived it" is indistinguishable from "not applicable" ([#728](https://github.com/JohnGavin/historical/issues/728)). If a series exists in the results directory, compute the metric from it.

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
