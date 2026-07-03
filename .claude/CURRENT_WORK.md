# Current Work — session 21 end (2026-07-03, ENDED)

## State: all work merged + deployed

Everything below is on `origin/main` (PRs #500–#538) and the dashboards are rendered + deployed (Pages serves committed `docs/*.html`). lychee link-audit is **green**.

### Shipped this session
- **#507 MVO remedy set — COMPLETE**: `hd_returns_shrink` (#512), `hd_black_litterman` (#513), `hd_min_var_weights_penalised` (#517), `hd_weight_stability_diagnostic` (#521) + surfaced on falsification `#wstab` (#523). wstab caption/plot corrected for accuracy + plain language (#533).
- **#514 dashboard-first — COMPLETE**: rule + `docs/DASHBOARDS.md` (#515), master Mermaid map (#519), 3 consolidations (#516/#524/#526) → **15→11 dashboards**.
- **#534 caption-link hygiene**: caption *targets* → HTML anchors site-wide (#536/#537); lychee 404 fixed. 0 raw links on falsification/leaderboard/evidence.
- **#530 bdbb-sol render bug** fixed (#531).
- "Class C" → "publish gate" rename in the global HITL rule.

### Open follow-ups (issues filed, not started)
- **#518** — Phase 3b: no-short/box/L1-turnover/robust MVO via a QP solver (quadprog) + nix regen. Do as a dedicated PR, not a background fan-out.
- **#520** tidyfinance gap analysis · **#522** Carver rolling-vs-expanding (extends the weight-stability diagnostic with an `estimation` axis) · **#525** Schmerling slope/strength (R²-strength signal, MONITOR) · **#528** Quantpedia AI-agent guardrails audit (dossier card, trade-log fidelity, break-even cost, dual-engine — several genuine gaps).

### Next-session starting point
- Pick from #518 (finishes #507) or the research issues (#522 is the most direct extension of shipped work).
- Note: weight-stability diagnostic only runs the 4-asset universe; a wide-universe demo (where MVO's Sharpe penalty appears) is the natural next enhancement.

### Housekeeping
- 2 unaddressed roborev verdict failures (cumulative counter; pre-existing — not from this session's merged work).
- Main checkout has pre-existing untracked files (`.clone/`, `archive/`, `inst/extdata/results/*.parquet`, a `knowledge/raw/*.pdf`) — left as-is.
