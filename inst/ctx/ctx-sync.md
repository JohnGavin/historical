# ctx.yaml Sync Guide

## What is ctx.yaml?

`ctx.yaml` at the project root is an LLM-optimised API specification for the
`historicaldata` R package. It follows the same schema as `coMMpass.ctx.yaml`
in the `~/docs_gh/proj/data/coMMpass/` project (schema version 1.1).

The central `llm` project at `~/docs_gh/llm/` uses `plan_pkgctx.R` to manage
a ctx-file cache at `~/docs_gh/proj/data/llm/content/inst/ctx/external/` for
CRAN and Bioconductor packages. `ctx.yaml` here serves a different but
complementary role: it describes the *local* package API so any Claude Code
agent working in the `historical` project can import it rather than reading
all 22 source files.

## Schema

Each `ctx.yaml` is a multi-document YAML file (documents separated by `---`).
Document types:

| kind             | Required fields                            | Purpose                              |
|------------------|--------------------------------------------|--------------------------------------|
| `context_header` | `llm_instructions`                         | Prompt preamble for the LLM consumer |
| `package`        | `schema_version`, `name`, `version`, `language`, `description` | Package metadata, data source catalogue |
| `function`       | `name`, `exported`, `signature`            | One record per exported function     |

Optional function fields: `arguments`, `returns`, `family`.

## When to regenerate

Regenerate `ctx.yaml` after any of:

- A new `@export` function is added to `packages/historicaldata/R/`
- An existing exported function's signature changes (new argument, changed default, removed argument)
- A new dataset is added to `hd_datasets()` in `registry.R`
- A major package version bump (e.g. 0.1.x → 0.2.0)

Minor internal changes (bug fixes, docstring rewording, non-exported helpers) do
not require regeneration.

## How to regenerate

### Option A: pkgctx tool (preferred when available)

```bash
nix run github:b-rodrigues/pkgctx -- r \
  /Users/johngavin/docs_gh/proj/finance/data/historical/packages/historicaldata \
  --compact \
  > /Users/johngavin/docs_gh/proj/finance/data/historical/ctx.yaml
```

pkgctx reads package source on demand and emits compact YAML. The output will
match schema_version 1.1. Inspect the diff before committing — pkgctx may
omit `data_sources` and `last_synced`; add them manually if missing.

### Option B: manual extraction (fallback)

1. Grep exported functions: `grep -rn "@export" packages/historicaldata/R/`
2. For each, copy the roxygen block and function signature into a `kind: function` record.
3. Update `last_synced` to today's date (YYYY-MM-DD).
4. Verify with R:
   ```r
   yaml::yaml.load_file("ctx.yaml")
   ```
   Must complete without error.

## Validation

```r
# Must succeed without error
doc <- yaml::yaml.load_file("ctx.yaml")
stopifnot(
  any(vapply(doc, function(x) identical(x$kind, "context_header"), logical(1))),
  any(vapply(doc, function(x) identical(x$kind, "package"), logical(1))),
  sum(vapply(doc, function(x) identical(x$kind, "function"), logical(1))) > 0
)
message("ctx.yaml valid: ", sum(vapply(doc, function(x) identical(x$kind, "function"), logical(1))), " functions")
```

## Where the output ends up

The llm project's `plan_pkgctx.R` manages a central cache at:

```
~/docs_gh/proj/data/llm/content/inst/ctx/external/
```

Files there are named `{pkg}@{version}.ctx.yaml` (e.g. `dplyr@1.1.4.ctx.yaml`)
for CRAN packages. For local/private packages like `historicaldata`, the
recommended approach is to copy or symlink `ctx.yaml` to that cache as
`historicaldata@0.1.0.ctx.yaml` after each regeneration:

```bash
cp /Users/johngavin/docs_gh/proj/finance/data/historical/ctx.yaml \
   ~/docs_gh/proj/data/llm/content/inst/ctx/external/historicaldata@0.1.0.ctx.yaml
```

Update the version tag to match the DESCRIPTION `Version:` field.

## Using ctx.yaml in agent prompts

Pass the ctx.yaml content to any agent that needs to write code against
`historicaldata`:

```bash
cat /Users/johngavin/docs_gh/proj/finance/data/historical/ctx.yaml
```

Or reference it in a prompt:

```
Package API spec (use instead of reading source files):
$(cat /path/to/ctx.yaml)
```

This replaces ~22 source-file reads with a single compact spec, saving
roughly 60% of token consumption for package-level code work.

## Current function count

As of 2026-05-18 (version 0.1.0): 52 exported functions across 9 families:

| Family            | Functions |
|-------------------|-----------|
| discovery         | 10        |
| data-access       | 5         |
| infrastructure    | 6         |
| curated-groups    | 2         |
| quality-audit     | 4         |
| falsification     | 12        |
| scoring           | 5         |
| kelly             | 3         |
| external-data     | 8         |
| trades            | 4         |
| vintages          | 2         |
| results-db        | 3         |
| visualisation     | 2         |
