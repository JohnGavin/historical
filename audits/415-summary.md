# Audit summary — #415 Alpha Architect factor strategies vs our 14

**Date:** 2026-06-04
**Worktree:** `worktree-agent-adaaa38b4004a8bcb`
**Branch:** `worktree-agent-adaaa38b4004a8bcb`
**Subtasks completed:** 1–4 (extraction, digest, gap matrix, summary)
**Subtasks deferred to user:** 5 (file new issues), 6 (acceptance), 7 (decisions)

## Method used

| Layer | Result |
|---|---|
| Direct `curl` on `/factor-strategies/` (browser UA) | **HTTP 403** — Cloudflare JS challenge, every AA URL globally |
| Wayback Machine for `/factor-strategies/` | **No snapshot** of that exact URL |
| Wayback for related pages | **HTTP 200** — `/focusedfactors/` (2025-08-04), `/research-category-list/` (2026-01-29), `/alpha-architect-white-papers/` (2025-08-04), `/managedfutures/` (2025-08-04) |
| Live RSS at `/feed/` | **HTTP 200** — only unblocked live endpoint; contains the full `/factor-strategies/` post body under `<content:encoded>` |

## CRITICAL reframe (consistent with #279)

The URL `alphaarchitect.com/factor-strategies/` is **not a taxonomy page**.
It is a single Larry Swedroe blog post (2026-05-22) titled "When Everyone
Trades the Same Factor Playbook," digesting the Posselt & Kjær (March 2026)
ADD paper. This was already noted in issue #279 (closed) and the underlying
paper is fully digested at [[anomaly-driven-demand]] (compiled 2026-05-25).

We therefore did the broader gap analysis the user almost certainly wanted:
**AA's actual published factor lineup vs our 14 strategies**, reconstructed
from `/focusedfactors/`, `/research-category-list/`, `/alpha-architect-white-papers/`,
plus the Wesley Gray reference books (cleanly tagged `> ⚠ AI-inferred:`).

## AA's taxonomy (verified)

Top-level: **Value · Momentum · Trend · White Papers · More**. Long-only
lineup: **Quantitative Value · Quantitative Momentum · Global Value Momentum
Trend (combined) · Managed Futures · Custom Solutions · 1042 QRP**. AA does
NOT publish standalone Quality, Low-Vol, or Size strategies — by design.

## Numbers extracted

- AA strategy / research themes catalogued in matrix: **22** (5 strategies + 17 research themes)
- White-paper titles verified: **23** (full list in raw extract)
- Top-level research categories verified: **5**

## Counts

| Classification | Count |
|---|---|
| COVERED | 5 |
| PARTIAL | 6 |
| GAP | 6 |
| DELIBERATELY EXCLUDED | 2 |
| NOT APPLICABLE | 5 |
| **Total** | **24** |

(Some rows in the matrix appear in two branches; counted once each.)

## Top 3 gaps ranked by leverage

1. **Fundamental Value sleeve** (Quantitative-Value-style EV/EBIT long-only).
   Highest leverage — our 14 are price-only and systematically load against
   the fundamental Value factor. Adding even a basic EV/EBIT screen would
   diversify the leaderboard's factor exposure. See Stub 1 in gap-analysis.
2. **Cross-asset TS-momentum (managed futures)**. Zero coverage of bonds,
   FX, or commodity TS-momentum. AA's Managed Futures uses Moskowitz-
   Ooi-Pedersen 2012 — one of the most-replicated premia in the
   literature. See Stub 2.
3. **Path-quality / "frog-in-the-pan" (FIP) screen on our momentum
   strategies**. Da-Gurun-Warachka 2014. Applied by AA's QMOM; not by our
   LTR, Mom 12-2, Pre-Peak, or Post-Peak. Low-effort, well-evidenced
   enhancement to four existing strategies. See Stub 3.

(Stubs 4-7 cover International Momentum, ADD-aware crowding column,
long-history trend backtest, and asset-class-vs-factor audit.)

## Files written (all under `$WORKTREE_PATH`)

| Path | Purpose |
|---|---|
| `knowledge/raw/alphaarchitect-factor-strategies-2026-06-04.html` | Raw HTML capture with full provenance header and 5 inline source bodies |
| `knowledge/raw/alphaarchitect-taxonomy-2026-06-04.md` | Structured taxonomy extract per AA's actual categories |
| `knowledge/wiki/alphaarchitect-factor-strategies.md` | Wiki digest with Sources + Methodology + AI disclosure |
| `knowledge/wiki/alphaarchitect-gap-analysis-2026-06-04.md` | GAP/COVERED matrix + 7 issue stubs (DO NOT FILE) |
| `audits/415-summary.md` | This summary |

## Subtasks 5–7 — DEFERRED

Per dispatch: no new GitHub issues filed. The seven recommended issue
stubs in the gap-analysis file are for the user to triage and file
selectively. Each stub names: title, rationale, applicable rules,
template, effort estimate, priority. Subtask 6 (acceptance) and 7
(decisions) similarly deferred.

## Push status

`knowledge/PRIVATE` marker: **absent**. No project-level policy was
discovered preventing push of `knowledge/` to remote. All files were
pushed to the worktree branch per the dispatch's normal push instruction.

> If the project DOES have an unwritten policy of keeping knowledge/
> local-only (matches the global `wiki-storage-policy` rule for some
> projects), the next session should revert the push of the two
> `knowledge/wiki/*.md` files and the `knowledge/raw/*.md` file; the
> raw HTML file is mostly sourced from already-public RSS/Wayback and
> contains no PHI.

## Confidence

- Direct ground truth (RSS + Wayback HTML): AA's 5-category taxonomy,
  long-only lineup names, white-paper titles, the full Swedroe ADD post.
- AI-inferred (tagged): construction details (EV/EBIT, FIP screen,
  quarterly rebalance, vol-targeting) sourced from Gray & Carlisle (2012)
  and Gray & Vogel (2016) reference books — not from AA's HTML, which is
  largely image-rendered marketing material. Every such claim is tagged
  `> ⚠ AI-inferred:` in the extract and wiki files.
- External-code-zero-trust: no code snippets copied from AA pages or
  AA-hosted SaaS tools. All inferences are from published books in our
  reading list.
