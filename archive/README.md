# archive/

Vignettes and artefacts moved here are **not part of the published Quarto site**.

## 2026-05-30

- **`examples.qmd`** — render was silently failing despite the source being in `docs/`. Investigation tracked in [#341](https://github.com/JohnGavin/historical/issues/341). Archived pending diagnosis (was the file excluded from the project render, or did the render fail mid-build?) and a decision on whether to re-introduce it or rewrite the data-access showcase elsewhere.

## Removed from `docs/` in this PR

- `docs/mermaid-test.html` — orphaned rendered artefact (no `.qmd` source on `main`); was an internal Mermaid sandbox. Removed outright rather than archived since there is nothing to preserve.

## Convention

Anything in this directory:

- Should not appear in `docs/_quarto.yml` `project.render` or `website.navbar`/`website.sidebar`.
- Retains its history (`git log archive/<file>` works).
- May be re-introduced by `git mv archive/<file> docs/<file>` if the underlying issue is resolved.
