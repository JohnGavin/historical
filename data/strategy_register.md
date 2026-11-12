# Strategy register

`strategy_register.csv` has one row per `strategy_names$code_name` (R/plan_strategy_names.R).

It holds ONLY human-judgement fields. It holds NO metric values: net CAGR, DSR p-value,
detection power and the falsification verdict are read from the pipeline, and the
Keep / Watch / Failed verdict is computed from them by `compute_strategy_verdict()`
(R/strategy_verdict.R, thresholds in `STRATEGY_VERDICT_RULE`). Do not type a number
that a target already computes.

| Column | Meaning |
|---|---|
| `strategy_id` | `strategy_names$code_name` (the join key) |
| `family` | Free-text grouping chosen by hand |
| `reason` | Why the strategy is judged as it is, citing evidence (issue, CHANGELOG, research log). REQUIRED when the computed verdict is Failed (QA gate S51). Leave empty rather than invent one. |
| `decided_on` | Date (YYYY-MM-DD) of the cited evidence; empty if it cannot be cited |
| `issue` | GitHub issue number, or empty |
| `hypothesis_uuid` | Research-log hypothesis (`inst/extdata/research_log/hypotheses`) when the match is unambiguous, else empty |
| `revisit_if` | Condition under which the verdict should be reopened, or empty |
| `notes` | Free text |

Gate S51 (`qa_strategy_register`) fails when a ranked strategy has no row, a row names an
unknown strategy, or a Failed strategy has an empty `reason`.

Adding a strategy: add it to `strategy_names` first, then add its row here.
