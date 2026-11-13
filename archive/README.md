# archive/

Vignettes and artefacts moved here are **not part of the published Quarto site**.

## 2026-05-30

- **`examples.qmd`** — render was silently failing despite the source being in `docs/`. Investigation tracked in [#341](https://github.com/JohnGavin/historical/issues/341). Archived pending diagnosis (was the file excluded from the project render, or did the render fail mid-build?) and a decision on whether to re-introduce it or rewrite the data-access showcase elsewhere.

## 2026-11-12

Root-level files with no live consumer (no reference from `docs/*.qmd`, `.github/`, `scripts/`, `R/`, `tests/`, `.claude/`, or the `llm` repo; only `CHANGELOG.md` history mentions) were moved here with `git mv`, so history is kept.

| File | Moved on | Why |
|------|----------|-----|
| `prompts/prompt_backtesting.md` | 2026-11-12 | Prompt fragment: backtesting focus (risk control); nothing references it. |
| `prompts/prompt_backtesting_chatgpt.md` | 2026-11-12 | Prompt fragment: backtesting and methodology rules (ChatGPT-formatted variant); unreferenced. |
| `prompts/prompt_backtesting_gemini.md` | 2026-11-12 | Prompt fragment: same rules, Gemini-formatted variant; unreferenced. |
| `prompts/prompt_database.md` | 2026-11-12 | Prompt fragment: objective to build a clean historical database for backtesting; unreferenced. |
| `prompts/prompt_stratedies.md` | 2026-11-12 | Prompt fragment: write a vignette backtesting one strategy using a prior one as template (filename spelling is original); unreferenced. |
| `ZAKAMULIN_FINDINGS.md` | 2026-11-12 | Findings on Zakamulin continuous regime allocation (dated 2026-05-11, issue 123 follow-up); unreferenced. |
| `RECOVERY.md` | 2026-11-12 | Backup/restore notes for non-reproducible state; unreferenced by this repo. Read it before relying on it, it may be out of date. |

## Removed from `docs/` in this PR

- `docs/mermaid-test.html` — orphaned rendered artefact (no `.qmd` source on `main`); was an internal Mermaid sandbox. Removed outright rather than archived since there is nothing to preserve.

## Convention

Anything in this directory:

- Should not appear in `docs/_quarto.yml` `project.render` or `website.navbar`/`website.sidebar`.
- Retains its history (`git log archive/<file>` works).
- May be re-introduced by `git mv archive/<file> docs/<file>` if the underlying issue is resolved.
