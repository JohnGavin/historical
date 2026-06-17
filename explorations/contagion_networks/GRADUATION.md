# Graduation criteria — Contagion Networks

This prototype is in `explorations/` (relaxed quality gate). It graduates into the
production pipeline **only** when the items below are met. Until then it is a
research note, not a usable signal.

## Recommended path: signal-only port (not the dashboard)

The valuable artifact is the **network-metric time series** (modularity,
`n_communities`, max eigenvalue, density), not the static HTML dashboard. The
target is a `plan_contagion_network.R` target feeding the existing
regime / circuit-breaker / cross-asset-correlation plans — NOT a standalone app.

## Gate (all required before graduation)

- [ ] **Data:** replace `quantmod::getSymbols()` live Yahoo pulls with this
      project's curated data layer (the `tmp_equity_*.parquet` / dataset-registry
      path). No live-network dependency in the pipeline.
- [ ] **Look-ahead control:** re-test H2 with strictly point-in-time windows; show
      the leading-indicator claim survives a walk-forward / falsification check
      (reuse `plan_falsification.R`, `plan_forecast_eval.R`).
- [ ] **Survivorship:** reconstruct the universe point-in-time, or document and
      bound the survivorship bias.
- [ ] **Uncertainty:** attach bootstrap CIs (reuse `plan_bootstrap_ci.R`) to the
      "7/7 significant" claims; report effect sizes, not just p-values.
- [ ] **Integration:** expose the metric series as a `targets` target consumable by
      the regime / circuit-breaker plans.
- [ ] **Provenance:** re-implement in this project's style (no verbatim carry-over of
      the agent-generated playground code beyond what survives review).
- [ ] **Tests + audit:** add `testthat` coverage and pass the project audit bar.

## If it fails the gate

Archive in place with a one-line reason. The crash-structure finding (H1: community
collapse into a single cluster) may still be worth keeping as a documented
stylised fact even if H2 (leading indicator) does not survive.
