# Current Work — session 25 end (2026-07-15)

## State: provenance correction shipped. #559 re-sourced, #565 filed. No repo code changes.

## What happened

- **#559 misattribution found + fixed.** Session 24 filed #559 ("momentum life cycle") off the Cloudflare-403 URL `alphaarchitect.com/momentum-cycle/`, reconstructing it (wrongly) as Lee-Swaminathan MLC. User supplied the real article text → the URL is actually **"The Intramonth Momentum Cycle"** (Nathan, Suominen & Tasa 2026; Basilico summary): a dash-for-cash / PreTOM mechanism, unrelated to Lee-Swaminathan.
- **Filed #565** — Intramonth Momentum Cycle, accurately sourced (owns the AA URL). Dash-for-cash, ~6-day PreTOM window ending −4, short-side/loser-driven, T+1 causal ID, 19 markets. Framed as a calendar-timing overlay on existing momentum sleeves (reuse #271 machinery), not a new leaderboard row. Falsification bar flags net-of-cost turnover risk + T+2/T+1 regime-aware window.
- **Corrected #559** — Source → Lee & Swaminathan (2000, JoF) + 2021 revisit directly; AA URL removed; retitled; provenance caveat + AC-1 updated; cross-linked #565. Posted a correction comment on #559.

## Open / next session

- **#565 AC-1** — locate + read the Nathan-Suominen-Tasa working paper; digest exact PreTOM window + WML construction + metrics into `knowledge/wiki/` (raw source first) before hardcoding any figure. Current #565 numbers are from the user-supplied AA summary text only.
- **Adjacent issue candidate** — Implied Cost of Capital (Gebhardt-Lee-Swaminathan) noted in #559 as a possible separate issue; not filed.
- **Carried from session 24 (still open):**
  - FRED AI-activity indicator `BFPBF4QNAICS54SAUS` — offer standing to file add-as-indicator issue.
  - Spawn strategy issues from #560 triage (reversal-tilt momentum #1 first).
  - Execute #564 Phase-0 items (start Item 5, relationship map), each behind its own Class-C "approved" gate.
  - Optional: add TOM/CMR/Value/Managed-Futures rows to the static Definition table `leaderboard.qmd:202-211`.

## Known limitations / flags

- roborev **INCONSISTENT(backlog-vs-verdicts)** (590 open, 1 verdict) — pre-existing review-completion health issue, unrelated to this session; raw failure counters clean.
- CI **Link audit (lychee)** still reported failing (carried from session 24) — not investigated.

## Branch

- `feat/cc-20260707-174758`. Session-25 work is GitHub-side (issues #559/#565); only CHANGELOG + this file changed locally.
