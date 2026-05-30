# Plan: art.* registry seed + QA gate (#347 follow-up)
#
# Two targets:
#   art_vignette_seed     — scans docs/*.qmd and idempotently writes one
#                           art.vignette row per .qmd whose rendered .html
#                           exists on disk.
#   qa_artefact_registry  — invokes check_artefact_registry(strict = TRUE).
#                           Pipeline aborts if any art.vignette row points
#                           at a missing HTML file. This would have caught
#                           the mermaid-test.html / examples.html
#                           regressions in 2026-05.
#
# Both targets are guarded so the pipeline still tar_makes on machines
# without DBI / duckdb installed.

plan_artefact_registry <- function() {
  list(
    targets::tar_target(art_vignette_seed, {
      .art_seed_vignettes(docs_dir = here::here("docs"))
    }),

    targets::tar_target(qa_artefact_registry, {
      .art_run_gate(docs_dir = here::here("docs"), seed = art_vignette_seed)
    })
  )
}

# ── Internals ─────────────────────────────────────────────────────────────

# Scan docs/*.qmd, infer vignette_id from basename, upsert into
# art.vignette. Returns a summary tibble (vignette_id, html_present).
.art_seed_vignettes <- function(docs_dir) {
  if (!requireNamespace("DBI", quietly = TRUE) ||
      !requireNamespace("duckdb", quietly = TRUE)) {
    return(tibble::tibble(
      vignette_id  = character(),
      html_present = logical()
    ))
  }

  qmds <- list.files(docs_dir, pattern = "\\.qmd$", full.names = TRUE)
  # Skip Quarto partials (filenames starting with "_").
  qmds <- qmds[!grepl("^_", basename(qmds))]
  if (length(qmds) == 0L) {
    return(tibble::tibble(
      vignette_id  = character(),
      html_present = logical()
    ))
  }

  basenames <- tools::file_path_sans_ext(basename(qmds))
  htmls <- paste0(basenames, ".html")
  abs_htmls <- file.path(docs_dir, htmls)
  html_present <- file.exists(abs_htmls)

  path <- historicaldata::hd_registry_path()
  historicaldata::hd_registry_init(path)
  con <- historicaldata::hd_registry_open(path, read_only = FALSE)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  # qmd_path is stored relative to the project root for portability.
  qmd_rel <- paste0("docs/", basename(qmds))

  for (i in seq_along(basenames)) {
    historicaldata::hd_art_vignette_upsert(con, list(
      vignette_id = basenames[i],
      qmd_path    = qmd_rel[i],
      html_path   = htmls[i],
      status      = if (html_present[i]) "published" else "draft"
    ))
  }

  tibble::tibble(
    vignette_id  = basenames,
    html_present = html_present
  )
}

# Run the QA gate. The `seed` arg exists only so this target depends on
# `art_vignette_seed` — the seed must run first.
.art_run_gate <- function(docs_dir, seed) {
  if (!requireNamespace("DBI", quietly = TRUE) ||
      !requireNamespace("duckdb", quietly = TRUE)) {
    return(tibble::tibble(
      vignette_id = character(),
      html_path   = character(),
      abs_path    = character()
    ))
  }

  path <- historicaldata::hd_registry_path()
  con <- historicaldata::hd_registry_open(path, read_only = TRUE)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  # strict = TRUE in CI / pipeline → abort on any missing artefact.
  # The empty-issues tibble is returned for tar_read inspection.
  historicaldata::check_artefact_registry(con,
                                         docs_dir = docs_dir,
                                         strict   = TRUE)
}
