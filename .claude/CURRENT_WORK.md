# Current Work (Session 2026-05-31 #13 — #365 mom_prepeak umbrella closed end-to-end, ENDED)

**Last updated:** session end
**Previous sessions:** #12 (#347 DuckDB registry, 5 PRs), #11 (robustness trio + Pillar 8, 21 PRs), #10 (CI gate, deflated Sharpe)

## This session — 14 PRs merged + 6 follow-up issues filed

### #365 mom_prepeak umbrella (Büsing 2022 — pre-peak / post-peak 12-2 momentum decomposition)
- **#371 PR 1/4** `hd_mom_prepeak_signal()` — pure decomposition function, look-ahead-safe, 10-column output
- **#372 PR 2/4** `plan_mom_prepeak` — 14 targets + 3 sibling strategies registered (`mom_prepeak`, `mom_postpeak`, `mom_combined`)
- **#373** metric bankruptcy guard — `blown_up` + `bankrupt_month` columns; max_dd capped at -100%, cagr NA when blown up
- **#378 PR 3/4** `docs/momentum-prepeak.qmd` — 721-LOC dashboard vignette with peak-date histogram, 84/16 table, cumulative chart, skewness, Methodology block
- **#379** vignette render fix — path-checked `tar_config_set()` + `vignette_utils.R` (Quarto cwd = docs/ trap)
- **#381 PR 4/4** gauntlet — `R/plan_mom_prepeak_gauntlet.R` with 17 targets covering Pillar-8 + WFC + random-day-as-peak null + HAC+FF5+Mom regression + CPCV PBO

### #347 follow-ups
- **#370** `art_diagram_seed` + 3 non-qmd HTMLs registered + `qa_legacy_leaderboard_sentinel`

### Adjacent fixes (uncovered while materialising the gauntlet)
- **#382** lychee `--exclude-mail` removed in v0.23.0 — closed #377
- **#384** 3 link fixes (`historicaldata`→`historical` typo + bad `../..` relative path + DOI `403` accepted). Originally #383, closed for stale base.
- **#385** `mom_prepeak_ff_reg` month-end alignment — `floor_date(., "month")` on both sides of FF↔strategy join
- **#386** WFC field names — `$pearson_rho`→`$pearson`, `$spearman_rho`→`$spearman`
- **#388** `falsification.qmd` setup chunk path-check (same #379 pattern)
- **#390** `falsification.qmd` chunk-level `source(here::here())` path-check
- **#391** deploy — regenerated 3 vignettes (`momentum-prepeak.html` new + jst-dashboard + falsification)

## Pipeline materialisation

- Round 1 (13m 7s) — 15 targets, mom_prepeak signal_raw 5.95 MB, returns 16.87 kB each
- Round 2 (~40m) — 17 gauntlet targets, random-peak signal 11m 47s, PBO 25m 18s (15 CPCV paths)
- Round 3 (2.3s) — refresh metrics for Pillar-8 (helper change didn't auto-invalidate)
- Round 4 (2.2s) — re-run ff_reg + gauntlet_register after month-alignment fix

## Headline numbers (mom_prepeak gauntlet, 51-stock universe, 638 monthly returns 1973-)

| Strategy | Sharpe | max_dd | blown_up | bankrupt_month |
|---|---|---|---|---|
| **mom_prepeak** | **+0.44** | -69.1% | FALSE | — |
| mom_postpeak | -0.46 | -100% (capped) | TRUE | 248 (≈Aug 1993) |
| mom_combined | -0.00 | -100% (capped) | TRUE | 248 |

- HAC t-stat **3.69**; FF5+Mom alpha **1.46%/yr** (t=2.46, R²=0.4%)
- Random-day-as-peak null: actual 0.44 vs random 0.06 → **peak-finding IS the alpha source**
- WFC 3-point grid: Pearson **-0.92**, classification **"spurious_luck"** (small N caveat)
- CPCV PBO **0.40** over 10 paths

Stronger qualitative finding than the paper's 84/16: pre-peak is the only viable leg on this universe; post-peak actively destroys value (not just "smaller"); both bankrupt at the same month.

## Follow-up issues filed (carry to next session)

- **#392** lychee long-tail cleanup (8+ pre-existing dead links + `.lycheeignore` + add `lychee` to `tproject.toml` for nix-pinned local + CI parity) — most user-visible
- **#387** 4 latent vignette `pkgload::load_all(here::here())` bugs
- **#380** mom_prepeak gauntlet v2 (7-null falsification, full WFC grid, CRSP plumbing)
- **#375** `*_register_runs` sentinel idempotency (deterministic-RNG UUID collision)
- **#374** L/S construction caps (prevent `ret_ls < -1` at source)
- #377 closed (by #382)

## Next session

### Recommended priority
1. **#392 lychee cleanup** — scheduled-run failure notifications continue until this lands; bundled cleanup includes nix pinning to prevent the next `--exclude-mail`-style surprise
2. **#375 registry sentinel idempotency** — quality-of-life for every future `tar_make` re-run that touches `*_register_runs`
3. **#374 L/S construction caps** — moves bankruptcy honesty from metric reporting back to portfolio construction

### Or pick from
- **#362** Lazy Man's Momentum — side-by-side crash-avoidance comparison with mom_prepeak; uses same gauntlet
- **#340** snapshot test policy
- **#339** inter-vignette cross-references
- **#345** leaderboard 5-strategy display gap
