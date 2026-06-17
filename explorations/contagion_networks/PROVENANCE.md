# Provenance — Contagion Networks prototype

## What this is

A prototype investigating whether **stock-correlation community structure predicts
crash propagation**. Rolling correlation networks of ~28 US large-caps (2019–2024)
are built with `igraph`; the analysis tracks how community structure, modularity,
and the leading eigenvalue change around market crashes.

## Origin

- **Source location:** `proj/stats/simulations/claudes_playground/Financial Contagion Network Dashboard/`
  (an untracked scratch playground — not under version control before this move).
- **Authorship:** agent-generated (the source `PLAN.md` credits "Claude-Alpha" and
  "Claude-Beta"). **Not human-authored and not independently audited.**
- **Created:** 2026-03-05. Untouched between then and relocation.
- **Relocated:** 2026-06-17, into this project's `explorations/` area because the
  signal is thematically core to `historical` (cross-asset correlation, regime
  detection, circuit-breaker, falsification machinery).

## What was copied vs left behind

Copied: `engine.R`, `visualize.R`, `main.R`, `PLAN.md`, `PLAN_progress.md`, `CHAT.md`.
Left in the playground: the rendered `dashboard.html` and its `lib/` (5.5 MB of
regenerable htmlwidgets/JS assets — build artifacts, not source).

## ⚠ Caveats — read before trusting any number in here

- **Unaudited statistics.** The "7/7 metrics significant (p<0.001)" and the H2
  leading-indicator claims have **not** been validated against this project's
  falsification or bootstrap-CI standards.
- **Look-ahead / survivorship bias not controlled.** H2 ("metrics move ~20 days
  *before* a crash") is exactly where look-ahead bias bites. The 28-stock universe
  is a fixed present-day list — survivorship-biased.
- **Live-data dependency.** Uses `quantmod::getSymbols()` against live Yahoo Finance —
  not reproducible, not sourced from this project's curated data layer.
- **Universe mismatch.** 28 US large-caps vs this project's multi-asset/global scope
  (ETF, crypto, commodities, European overlay, LSE).

Treat all findings as **hypotheses to be tested**, not results.

## Quality tier

Exploration (relaxed gate). Must meet the production bar before any graduation —
see `GRADUATION.md`.
