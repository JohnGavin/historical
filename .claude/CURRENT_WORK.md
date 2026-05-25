# Current Work (Session 2026-05-25 #9 — external-source digests + Cloudflare/PDF workflow + parallel batch, ENDED)

**Last updated:** session end
**Previous sessions:** 2026-05-24 #8 (research-log DB #270, OLMAR #200, roborev analysis), #7 (merge-queue drain, 25 PRs), #6 (parallel P1+P2 sweep), #5 (roborev cascade fix)

## This session (8 PRs merged to main)
- Digested 3 Cloudflare-blocked sources from user-saved PDFs (extracted via `pdftotext`
  in `nix-shell -p poppler-utils`): ADD (#279), 1871 commodity index (#280), Kinlay (#281).
- Landed: flake-guard CI + poppler-utils + raw sources (#282); ADD & commodity wiki digests
  (#283/#285); PIT hard-error guard / Kinlay Step 2 (#284); green main / registry schema
  fix (#287); AQR long-run commodity dataset 1877–2025 (#290); Turn-of-the-Month overlay
  (#289); leaderboard correlation + redundancy + incremental Sharpe (#291 = #268).
- Filed llm#296 (global-shell poppler → Read tool PDFs) and llm#303 (T-lang template
  closure-rebuild root fix).

## Next task (resume here)
**Leaderboard chain remainder — paused per user, resume after #288:**
1. **#160** — Vertox K_eff (consume `strat_corr_matrix` from #291) + deflated Sharpe leaderboard
   column. Requires renaming the existing time-based `K_eff` → `K_eff_time`/`K_eff_acf` across
   `R/tail_keff.R`, `R/plan_tail_keff.R`, `R/plan_integration.R`, and the `backtest-robustness`
   rule; port the quadrature + Brent-inversion numerical method; name the new one `strat_keff`.
2. **#279** — add a crowding column to the leaderboard + an ADD/flow-pressure clause to the
   `priced-in-prohibition` rule. Cross-link #160/#271.

## Open follow-ups (filed this session)
- **#288** — R-test CI gate: suite not CI-portable (duckdb `httpfs`/network tests; cachix
  trust). Do first so #271/#268 plan code gets runtime verification.
- **#271** — TOM plan is parse-validated only; build + falsify in pipeline, then leaderboard.
- **#280** — use `commodities_long_run` as the long-run benchmark; re-test commodity
  momentum (#134/#138) + a carry signal over 1877–2025.
- llm#296, llm#303 (cross-project, owned by the llm session).

## Notes
- `t update` strips the #211 closure-rebuild shellHook every regen → run `default.post.sh`
  after; flake-guard CI now enforces it.
- `strat_corr_matrix` covers 5 monthly strategies only (daily ones excluded for look-ahead).
- roborev backlog: 133 failed / 80 addressed — standing backlog (#176/#210), not this session.
