# Rule: Output-First ("Dashboard-First") Planning — Phase 0

## Source

Issue #514. The dashboard output is the critical deliverable; it must be the
*first* planning artifact, not the last. Paired with a mandatory relationship
diagram and a consolidation review so the dashboard count trends **down** as
features are added.

## When This Applies

Every major feature/issue whose work will (now or later) produce or change a
**visible output** — a table, plot, metric block, or diagram — on any dashboard
in `docs/`. Applies before any production code is written. Pure internal
estimators with no eventual output (e.g. a numeric helper that only feeds
another function) are exempt until the phase that surfaces them.

## CRITICAL: No production code until Phase 0 is approved

Plan-first failure mode this prevents: implement an estimator/strategy, then
bolt a chart onto whatever dashboard is handy (or spawn a new one). The result
is output that is inconsistent with — or duplicates — what already exists, and
yet another standalone surface. Phase 0 forces the output, its relationships,
and its home to be decided and **approved** before the code exists.

## Phase 0 — Output & Relationship Design (6 steps)

Phase 0 slots **ahead** of the normal R-package PR workflow
(architecture → TDD → implement → render → QA).

### 1. Diagram the relationship (start here)

Build or **extend** a Mermaid graph locating the new feature in the existing web
of strategies / diagnostics / data sources — what it depends on, what it feeds,
what it resembles. This is the first artifact attached to the issue/PR.

- If a relevant graph exists (the causal-DAG surface in `falsification.qmd`, or
  the future `strategy_graph` of #481), **extend it** rather than start a new one.
- Nodes MUST carry **clickable code anchors** to the implementing function/file
  at the current commit (per `mermaid-click-anchors`).
- Nodes MUST carry **hover popups**: a short explanation plus links to further
  detail (vignette section, issue, wiki page).
- "No diagram needed" is allowed only with a one-line justification.

### 2. Locate the home

Identify the **target dashboard + exact section** for the new output. Map the
issue → `dashboard:section`. Adding a NEW dashboard is the exception and
requires justifying why no existing surface fits. Default answer: an existing
dashboard. Consult `docs/DASHBOARDS.md` for the current inventory and the
best-template sources.

### 3. Comparable-output audit

List the existing outputs (tables/plots/captions) the new one will sit beside or
resemble. The new output MUST be consistent with them:

- naming per `strategy-name-consistency` (shared `strategy_names` target);
- captions per `visualization-standards` (7-item caption, source links);
- table styling per `dashboard-table-styling`; filters per
  `dashboard-filter-placement`.

### 4. Prototype for approval (Class C gate)

Build a **throwaway prototype of just the visible output** (and the diagram
change), leveraging an existing dashboard chunk as a template — copy the
structure, swap the data with a stub/sample. Render it. Attach the rendered
preview + the diagram to the issue/PR. **Implementation waits for an explicit
"approved"** (a Class C cross-boundary gate per `human-in-the-loop-decision-points`).
See `docs/DASHBOARDS.md` § Template Recipe for which chunk templates which
output type.

### 5. Consolidation review (mandatory)

Re-read the full dashboard inventory (`docs/DASHBOARDS.md`) — each dashboard's
functionality and objective — and the relationship diagram. Identify what the
new feature makes redundant or mergeable, and **propose at least one concrete
simplification**: drop / merge / fold-into-leaderboard / replace-with-diagram-node.
"No change" is allowed only with a one-line justification. **Net dashboard count
should trend down.**

### 6. Then build

Proceed to the normal architecture → TDD → implement → render → QA workflow,
building the real output into the agreed dashboard section and wiring the
diagram anchors to the shipped code.

## Mermaid as the navigation + consolidation layer

A single diagram-driven relationship map (with click-through to source and
hover detail) can **replace several thin standalone dashboards**. Instead of one
surface per strategy, the map shows all strategies and their relationships, with
click-through to the (fewer) dashboards that hold the real output. Strengthening
the diagram layer and reducing dashboard count are the same effort — see #481
(`strategy_graph` backbone) for the canonical graph this layer should grow.

## Forbidden Patterns

| Pattern | Why wrong | Fix |
|---|---|---|
| Implement estimator/strategy, then decide where the chart goes | Output is an afterthought; lands inconsistent/duplicate | Run Phase 0 first |
| Spin up a new dashboard for a new feature by default | Sprawl | Default to extending an existing dashboard (step 2) |
| Ship visible output with no relationship diagram | Reader can't see how it connects; can't spot redundancy | Step 1 is mandatory |
| Mermaid node with no code anchor / no hover detail | Diagram is decoration, not navigation | `mermaid-click-anchors` + hover popup |
| Skip the consolidation review because "the feature is small" | Count never goes down | Step 5 is mandatory; "no change" needs a one-line reason |
| Build production output before the prototype is approved | Bypasses the Class C sign-off | Prototype → approve → build |

## Related

- `docs/DASHBOARDS.md` — living inventory, overlap clusters, consolidation
  proposal, and template recipe this rule reviews against
- `mermaid-dashboard-pattern`, `mermaid-click-anchors` — Mermaid diagram +
  clickable-anchor conventions (step 1)
- `strategy-name-consistency` — single source of truth for strategy names (step 3)
- `visualization-standards`, `dashboard-table-styling`, `dashboard-filter-placement`
  — output consistency (step 3)
- `human-in-the-loop-decision-points` — the prototype sign-off is a Class C gate
- #481 — unified `strategy_graph` backbone (the relationship graph the Mermaid
  layer renders and grows)
- #507 — MVO remedy set; its weight-stability diagnostic is the first feature to
  run through this workflow
