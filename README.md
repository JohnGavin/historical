# historical

Historical finance data and a backtesting pipeline, written in R.

The repository has three parts:

- **`historicaldata`**, an R package in `packages/historicaldata`. It is a
  code-only package: a registry of datasets (equities, crypto, macro series,
  factors) and query functions over Parquet files. The data itself is hosted on
  Hugging Face Datasets and read through DuckDB.
- **A backtesting pipeline** in `docs/_targets.R`, built with
  [`targets`](https://docs.ropensci.org/targets/) (an R package that caches each
  pipeline step and rebuilds only what changed). It produces the strategy
  leaderboard and every figure and table the dashboards show.
- **Quarto dashboards**, the `docs/*.qmd` pages (Quarto renders R and prose to
  HTML), published at <https://johngavin.github.io/historical/>.

## Quick start

The build system is `flake.nix` (a Nix flake that pins every R package), not
`default.nix`. There is no R on the bare PATH, so run everything inside the
flake shell.

```bash
git clone https://github.com/JohnGavin/historical.git
cd historical
nix develop
scripts/verify.sh --quick   # fast: parses both _targets.R files only
scripts/verify.sh           # full: also validates the pipeline and runs both test suites
scripts/build.sh            # rebuilds the pipeline (see the note below)
```

`scripts/verify.sh` is the one command to run before calling a change verified.
It is necessary but not sufficient: it checks that the pipeline is structurally
sound, but runs no target body, so it cannot show that `tar_make()` still
succeeds. Run `scripts/build.sh` as well when a change could break a target.

Run `scripts/build.sh` in the **main checkout only**. The `targets` store (the
cache of built results) lives only there, and a git worktree has no store;
two concurrent builds corrupt it. Cold builds take 10+ minutes.

## Which pipeline is real

There are two `_targets.R` files.

- **`docs/_targets.R` is the real pipeline.** It produces the leaderboard and
  everything the site publishes. Always pass `script = "docs/_targets.R"` to
  `targets` functions, because the `_targets.yaml` that would otherwise select
  it is gitignored and absent in worktrees.
- **`_targets.R` at the repository root is a separate, small validation
  pipeline.** It runs inside the T-language "rn node" sandbox prototype (T is
  a pipeline orchestrator that this project tried and did not adopt as planned;
  see the banner in `PLAN.md`). It is not what the dashboards are built from.

## Data and credentials

- `data/raw/` is gitignored. Raw data is fetched by the `scripts/fetch_*`
  scripts (R and Python) and is not in the repository.
- The fetch scripts read these environment variable names (set them in
  `~/.Renviron`, never in the repository):
  `FRED_API_KEY`, `GUARDIAN_API_KEY`, `ALPACA_KEY`, `ALPACA_SECRET`.
  Optional settings: `OSAP_DATA_DIR`, `OSAP_FORCE_REFETCH`,
  `SP500_MEMBERSHIP_DIR`, `SP500_FORCE_REFETCH`, `KRAKEN_ZIP_PATH`,
  `KRAKEN_REST_FALLBACK`.
- To work offline, set `HD_USE_SAMPLE_DATA=1`. The package then reads small
  fixture files bundled in `packages/historicaldata/inst/extdata/sample/` instead of
  the remote datasets. `HD_TEST_LIVE=1` opts in to tests that hit the real
  remote.

## Where to look next

- [`CHANGELOG.md`](CHANGELOG.md): dated history of changes.
- [`docs/DATA_SOURCES.md`](docs/DATA_SOURCES.md): data sources and their status.
- [`docs/DASHBOARDS.md`](docs/DASHBOARDS.md): the published dashboards.
- [`docs/notes/README.md`](docs/notes/README.md): point-in-time audit notes.
- [`.claude/CLAUDE.md`](.claude/CLAUDE.md) and
  [`.claude/rules/verification-workflow.md`](.claude/rules/verification-workflow.md):
  the verification rules in full.

Counts (strategies, targets, plan files, functions) are deliberately not stated
here, because they go stale. Read them from the sources: the leaderboard page
for strategies, `docs/_targets.R` for targets, and
`docs/api-historicaldata.md` for the package functions.
