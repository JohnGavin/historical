# Kinlay Agentic Alpha-Research Workflow — Gap Audit

Gap-check of Kinlay's 5-pillar agentic alpha-research build order vs the
`historical` project's current stack, audited 2026-05-23 against commit
`feat/192-kinlay-audit`.

## Sources

- Kinlay, J. (2026-05). *Agentic Workflows for Alpha Research*.
  <https://jonathankinlay.com/2026/05/agentic-workflows-for-alpha-research/>
- GitHub issue #192 (audit spec, schema, failure-mode table)
- GitHub issue #200 (OLMAR — first concrete research-log DB use case)
- Files read during audit:
  - `packages/historicaldata/R/query.R`
  - `packages/historicaldata/R/vintages.R`
  - `packages/historicaldata/R/registry.R`
  - `packages/historicaldata/R/amendments.R`
  - `packages/historicaldata/R/alphavantage.R`
  - `packages/historicaldata/R/results_db.R`
  - `R/plan_qa_gates.R`
  - `.claude/rules/look-ahead-bias-prevention.md`
  - `knowledge/INDEX.md`
  - `tests/testthat/` directory listing

---

## Per-Pillar Verdict Table

| Pillar | Kinlay requirement | Verdict | File refs |
|--------|--------------------|---------|-----------|
| 1. PIT data wrapper | Any data access by date `t` returns only data available at or before `t`; hard error on future-data access | **PARTIAL** | See Pillar 1 detail |
| 2. Research-log DB | DuckDB with 5 tables: `hypotheses`, `implementations`, `results`, `critiques`, `robustness`; per-row UUID + parent_uuid + git_commit + sandbox_image_hash | **MISSING** | Not found after searching `R/`, `packages/`, `tests/` |
| 3. Proposer/Implementer/Critic/Replicator roles | 4 typed agent roles with fixed JSON handoffs; each role scoped to prevent anchoring | **PARTIAL / NEEDS_RENAME** | See Pillar 3 detail |
| 4. Critic validation suite (catch-rate measurement) | Seeded-defect benchmark; catch rate measured across 6 defect classes | **PARTIAL** | `R/plan_qa_gates.R` (1 of 6 classes); no benchmark harness |
| 5. Human-gate UI | Single page showing (hypothesis, notebook, critique, robustness) with approve/reject/send-back | **MISSING** | PR review is the implicit gate; no dedicated UI found |
| Free-tier data | Entire loop runnable on free FRED + AlphaVantage | **PARTIAL** | FRED: HAVE. AlphaVantage: HAVE (merged #194). Free-tier profile: MISSING |

---

## Pillar 1 — Point-in-Time Data Wrapper

**Verdict: PARTIAL**

### What we have

| Component | Status | File |
|-----------|--------|------|
| Macro vintages (FRED/ALFRED revisions) | HAVE | `packages/historicaldata/R/vintages.R` — `hd_macro_vintages()` exposes `pub_date` column and a `release =` filter for first/nth/latest revision |
| Vintage triangle schema in registry | HAVE | `packages/historicaldata/R/registry.R` — `macro_vintages` dataset: schema `(series_id, date, pub_date, value)` |
| Metadata amendment PIT log | HAVE | `packages/historicaldata/R/amendments.R` — `hd_amendments()` and `hd_metadata_amendments()` return the PIT log with `amended_at` timestamps |
| OHLCV `to` date filter (equities + crypto) | HAVE | `packages/historicaldata/R/query.R` — `hd_ohlcv()` and `hd_ohlcv_single()` accept a `to` argument that filters `date <= to` |
| Survivorship-bias warning | HAVE | `packages/historicaldata/R/query.R` — `hd_check_survivorship_bias()` emits a cli warning for `equity_daily` |

### What is missing

| Gap | Detail |
|-----|--------|
| Hard error / raised exception on `to > Sys.Date()` | `hd_ohlcv()` accepts any `to` date silently. Kinlay requires the wrapper to *raise* if asked for data later than the reference date. No such guard exists in `query.R`. |
| PIT enforcement for equities (no revision history) | Yahoo Finance does not publish revision history. `equity_daily` has no `pub_date` column. The caller is responsible for applying `to` correctly. |
| PIT enforcement for crypto | Same as equities — no `pub_date`, no revision history, caller responsibility. |
| `hd_pit()` or equivalent single entry-point with `as_of` semantics | No single wrapper function that unifies macro (vintage-aware) and OHLCV (simple `to` filter) access behind a common `as_of` argument. |

> ⚠ AI-inferred: the missing hard-error guard is the gap with the highest practical impact. A caller that accidentally passes `to = Sys.Date() + 30` will get whatever data exists with no warning, making the wrapper a lookahead risk vector rather than a lookahead guard.

### Relationship to look-ahead-bias-prevention rule

The project-local rule at `.claude/rules/look-ahead-bias-prevention.md` and the `qa_look_ahead_bias` target in `R/plan_qa_gates.R` (4 static-analysis patterns: S1–S4) are the current defence. They are complementary to a PIT wrapper but do not replace it: static analysis catches known forbidden call patterns; a PIT wrapper enforces temporal correctness at the data-access boundary.

---

## Pillar 2 — Research-Log DB

**Verdict: MISSING**

No `hypotheses`, `implementations`, `results`, `critiques`, or `robustness` tables were found anywhere in the repository. Searched:

- `R/` (83 `.R` plan files) — no file named `plan_research*`, `research_log*`, or containing `CREATE TABLE hypotheses`
- `packages/historicaldata/R/results_db.R` — this file exists and provides `hd_results_schema()` / `hd_results_append()` / `hd_results_query()`, but it is a **performance results log**, not the Kinlay research-log. It captures 73 typed backtest metric columns (Sharpe, CAGR, drawdown, trade analysis, falsification stats) keyed by `(run_date, strategy_id, partition)`. It has no `uuid`, `parent_uuid`, `git_commit`, or `sandbox_image_hash` columns. It does not capture the hypothesis or critique artifact rows Kinlay specifies.
- `tests/testthat/` — no `test-research-log*` file

### Closest partial: `results_db.R` + `analysis-rationale-logging` skill

| Kinlay table | Closest analogue | Gap |
|---|---|---|
| `results` | `hd_results_schema()` in `results_db.R` | No UUID/parent lineage; no git_commit column |
| `hypotheses` | Global `analysis-rationale-logging` skill (markdown DECISIONS.md) | Markdown, not typed rows; no UUID; not queryable |
| `implementations` | Git commit SHA (implicit) | Not stored as a DB artifact |
| `critiques` | `roborev` findings (separate tool) | Not linked to a hypothesis UUID |
| `robustness` | `R/plan_bootstrap_ci.R`, `backtest-robustness.md` rule | Results exist but not stored as a linked DB row |

### The first concrete use case: OLMAR (#200)

Issue #200 explicitly identifies OLMAR as the first strategy that would exercise the research-log DB: it has a leverage parameter to sweep, multiple variants, high-turnover cost sensitivity, and survivorship-bias caveats — exactly the multi-variant scenario where the 5-table schema earns its keep over markdown logs. See [[OLMAR — issue #200]].

> ⚠ AI-inferred: extending `results_db.R` to add the 5 Kinlay columns (`uuid`, `parent_uuid`, `hypothesis_text`, `git_commit`, `sandbox_image_hash`) and splitting the schema into the 5 logical tables would be the minimal-viable implementation path. The parquet-based append pattern in `hd_results_append()` is already sound; the gap is lineage tracking and the hypothesis/critique tables.

---

## Pillar 3 — Proposer / Implementer / Critic / Replicator Roles

**Verdict: PARTIAL / NEEDS_RENAME**

Our agent roster uses different names. The mapping is:

| Kinlay role | Our agent | Scope match | Gap |
|---|---|---|---|
| **Proposer** — generates a single falsifiable hypothesis in JSON (economic claim, dependent var, predictor, sample, null); no code execution | (none named Proposer) | No direct match; hypotheses are implicit in PR descriptions and issue text | No fixed JSON schema for hypothesis artifacts; no agent scoped to hypothesis-only output |
| **Implementer** — converts hypothesis JSON to a notebook; has no access to prior implementation results | `fixer` (sonnet) | Partial — `fixer` implements from critic reports but has broad file access, no anchoring prevention | `fixer` can read prior implementation results; the Kinlay isolation guarantee is not enforced |
| **Critic** — adversarial validation of notebook + outputs; checks look-ahead, sample drift, omitted costs, regime cherry-picking, unstable params, feature-name collision; does NOT fix | `critic` (sonnet), `roborev` | HAVE — `critic` agent is read-only, adversarial. `roborev` auto-reviews commits. `look-ahead-bias-prevention` rule guides critic checks | Kinlay's Critic checks 6 defect classes; our `qa_look_ahead_bias` covers 1 (look-ahead). Regime cherry-picking, unstable parameters, feature-name collision are not yet instrumented |
| **Replicator** — reimplements from hypothesis schema (NOT from original feature code) for independent validation | `r-debugger` (sonnet), `reviewer` (sonnet) | Partial — `reviewer` reviews code; `r-debugger` debugs failures. Neither is scoped to independent reimplementation from a typed hypothesis artifact | No independent-reimplementation protocol; no typed hypothesis schema to reimplement from |

### What exists in `.claude/`

- `.claude/rules/` contains 18 project-local rules covering backtest quality but no agent-role definitions
- No `.claude/agents/` directory exists with Proposer/Implementer/Critic/Replicator YAML definitions
- Global `CLAUDE.md` agent table defines `critic`, `fixer`, `reviewer`, `r-debugger` as general-purpose agents

> ⚠ AI-inferred: the closest path to Kinlay compliance is (a) defining a JSON hypothesis schema target in `R/plan_research_log.R`, (b) adding project-local agent prompts to `.claude/` that enforce role boundaries (Proposer: no code output; Implementer: no reading of prior results; Replicator: reads hypothesis JSON only, not prior implementation code).

---

## Pillar 4 — Critic Validation Suite (Catch-Rate Measurement)

**Verdict: PARTIAL**

Kinlay's benchmark: 25 defective notebooks + 25 clean controls, measured 80% overall catch rate across 6 defect classes:

| Kinlay defect class | Our coverage | File |
|---|---|---|
| 1. Look-ahead bias (rolling window includes current obs) | HAVE — S1–S4 patterns in `qa_look_ahead_bias` target | `R/plan_qa_gates.R` |
| 2. Sample period drift (Implementer anchors after a drawdown) | MISSING — no check detects post-drawdown start-date selection | Not found |
| 3. Omitted costs (transaction costs excluded) | PARTIAL — `backtest-robustness.md` rule requires cost sensitivity; no automated gate | `.claude/rules/backtest-robustness.md` |
| 4. Regime cherry-picking | MISSING — no automated check | Not found |
| 5. Unstable parameters (parameter sensitivity not reported) | PARTIAL — `backtesting-assumptions.md` rule, `backtest-robustness.md` rule; manual only | `.claude/rules/backtesting-assumptions.md` |
| 6. Feature-name collision | MISSING — no automated check | Not found |

No `tests/critic_validation/` directory of paired clean+defective notebooks exists. No CI target reports an aggregate catch rate. The `roborev` tool is the closest analogue (automated code review on every commit) but its catch rate is not measured against a seeded-defect benchmark.

---

## Pillar 5 — Human-Gate UI

**Verdict: MISSING**

Kinlay specifies two explicit gates:
1. Proposer → Implementer: is the hypothesis worth coding?
2. Replicator → Promotion: is the robustness evidence convincing?

Both surfaces should show (hypothesis, notebook, critique, robustness) on a single page with approve / reject / send-back-with-comment.

Our current gate is implicit PR review on GitHub. No dedicated Shiny or static UI reading from a research-log DB exists. This is consistent with the research-log DB being absent (Pillar 2) — the gate UI depends on the DB.

> ⚠ AI-inferred: until the research-log DB (Pillar 2) exists, building the gate UI is premature. The recommended sequencing is: Pillar 2 first, then Pillar 5.

---

## Free-Tier Data Sources

**Verdict: PARTIAL**

| Source | Status | Detail |
|--------|--------|--------|
| FRED (macro) | HAVE | `hd_macro()` and `hd_macro_vintages()` in `query.R` / `vintages.R`; no API key required for the cached parquet |
| AlphaVantage (equities) | HAVE | `hd_alphavantage()` in `packages/historicaldata/R/alphavantage.R` — merged in #194; requires `ALPHAVANTAGE_API_KEY` in `~/.Renviron`; free tier: 5 req/min, 500/day |
| Free-tier-only `tar_make()` profile | MISSING | No documented profile that constrains pipeline targets to free-tier data only. No `CONTRIBUTING.md` describing which strategies need paid tiers. |

---

## Failure Modes from Kinlay vs Our Mitigations

| Kinlay failure mode | Kinlay mitigation | Our status |
|---|---|---|
| Plausible-feature contamination (rolling window includes current obs) | PIT wrapper + Critic (defence in depth) | `qa_look_ahead_bias` gate (S1–S4) covers look-ahead patterns; PIT wrapper is partial (Pillar 1) |
| Backtest period drift (Implementer anchors after a drawdown) | Proposer fixes sample in hypothesis schema; Critic flags deviations | Not addressed — requires typed hypothesis schema (Pillar 2 dependency) |
| Confident-wrong synthesis (Critic summary contradicts notebook numbers) | Require Critic to quote specific cell outputs verbatim with line refs | Not enforced; `roborev` findings reference code lines but no verbatim-quote requirement |

---

## Recommended Next Steps (Priority Order)

Kinlay's explicit priority is: **build order matters more than components**. The sequence is fixed — each pillar is a prerequisite for the next.

### Step 1 (Highest value): Research-Log DB — Pillar 2

File a dedicated implementation issue (do not bundle with Pillar 3 or 5).
Minimum viable schema:
- DuckDB persistent file at `inst/extdata/research_log.duckdb`
- 5 tables: `hypotheses`, `implementations`, `results`, `critiques`, `robustness`
- Each row: `uuid UUID PRIMARY KEY`, `parent_uuid UUID`, `timestamp TIMESTAMP`, `git_commit VARCHAR`, `sandbox_image_hash VARCHAR`
- R functions: `rl_log_hypothesis()`, `rl_log_implementation()`, `rl_log_result()`, `rl_log_critique()`, `rl_log_robustness()`

Use the OLMAR strategy from [[#200]] as the first end-to-end test.

Extend `hd_results_schema()` / `hd_results_append()` in `results_db.R` to add UUID lineage columns, or implement as a separate `R/plan_research_log.R` file. The latter is preferred to avoid schema drift in the existing performance log.

### Step 2: PIT Wrapper Hard Error — Pillar 1

Add a guard in `hd_ohlcv_single()` and `hd_macro()` that `cli::cli_abort()`s when `to > Sys.Date()`. This is a 5-line change in `packages/historicaldata/R/query.R`. Separately, file an issue to decide whether a unified `hd_pit(dataset, as_of)` entry point is worth the API surface.

### Step 3: Critic Defect Classes — Pillar 4

Add S5 (sample-period drift: start date follows a >20% drawdown) and S6 (omitted costs: no `cost_bps` parameter) checks to `R/plan_qa_gates.R`. Add S7 (feature-name collision: same column name produced by two plan files) as an R-level duplicate-column check. These extend the existing `qa_look_ahead_bias` target pattern.

### Step 4: Hypothesis JSON Schema — Pillar 3 prerequisite

Define a typed hypothesis schema (as an R list or JSON file) that Proposer-role agents must produce. Without a typed hypothesis record, the Replicator cannot do an independent reimplementation. This is a prerequisite for Pillar 3 compliance and for Pillar 5 (the gate UI needs something to display).

### Step 5: Human Gate — Pillar 5 (last)

Only meaningful after Pillar 2 and the hypothesis schema exist. A minimal gate can be a Shiny app reading from the research-log DuckDB with three action buttons (approve / reject / send-back). Build this last.

### Not recommended: Pillar 5 before Pillar 2

Building a gate UI against markdown logs or ad-hoc PR comments recreates the problem Kinlay identifies: the gate becomes cumbersome (no structured data to display), reviewers start waving things through, and the system collapses.

---

## Related Issues

- [[#192]] — this audit (source issue)
- [[#200]] — OLMAR strategy; first concrete use case for research-log DB
- [[#191]] — `qa_look_ahead_bias` gate (PR merged; Pillar 4, 1 of 6 defect classes)
- [[#194]] — AlphaVantage integration (merged; Pillar free-tier)
- [[#150]] — survivorship-biased `equity_daily` (affects Pillar 1 completeness for equities)
- [[#186]] — registry/parquet schema drift (related to PIT integrity)
