# Current Work — session 23 end (2026-07-25, ENDED)

## State: research/triage only, no code changes

Pure investigation session — no PRs, no code edits. One GitHub issue filed.

### Shipped this session
- **#591 filed** — SSRN 7072279 (Weibel 2026): edge-preserving filtering
  (Savitzky-Golay/Perona-Malik) of macro regime signals. Confirmed genuinely
  new (zero filtering anywhere in `R/`); scopes a cheap ablation test on our
  four existing regime classifiers (#59/#123/#58/#51) ahead of any new
  sector-rotation strategy.
- **Prop-firm stop-out baseline request resolved without a new issue** —
  algoadvantage #054, delphicalpha, and Varma stop-loss articles are all
  already fully scoped by existing open issues #586 (prop-firm math /
  finite-horizon survival curve — the actual "would we stop out" deliverable)
  and #588 (Varma stop-loss / CDAP fix).

### Next-session starting point
- **#591** — cheapest first move: apply `signal::sgolayfilt` to the existing
  VIX/CISS/VVIX series in `plan_vix_macro_overlay.R`/`plan_regime_momentum.R`/
  `plan_european_overlay.R`/`plan_risk_state.R`; measure regime-switch
  frequency + OOS Sharpe change. No new dashboard (lands on `falsification.qmd`
  if it moves forward).
- **#586** — when prioritized, deliverable #3 (finite-horizon survival curve,
  "P(−10% DD within 12m)" leaderboard column) directly answers the
  prop-firm-stop-out question.
- Carry-forward from session 21 (still open, untouched since): #518 (MVO
  Phase 3b QP solver), #520/#522/#525/#528 research issues.

### Housekeeping
- 1 unaddressed roborev verdict failure (cumulative counter; pre-existing,
  unrelated to this session — same status noted in session 21).
- Main checkout has pre-existing untracked files (`.clone/`, `archive/`,
  `inst/extdata/results/*.parquet`, a `knowledge/raw/*.pdf`) — left as-is.
