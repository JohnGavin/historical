# Plan: art.* registry seed + QA gate (#347 follow-up)
#
# Targets:
#   art_vignette_seed          — scans docs/*.qmd and idempotently writes one
#                                art.vignette row per .qmd whose rendered .html
#                                exists on disk. Also registers known non-qmd
#                                HTMLs (causal-dag, causal-dag-all, quiz-app).
#   art_diagram_seed           — upserts a static set of known diagrams into
#                                art.diagram. Depends on art_vignette_seed so
#                                FK vignette_id rows exist first.
#   qa_artefact_registry       — invokes check_artefact_registry(strict = TRUE).
#                                Pipeline aborts if any art.vignette row points
#                                at a missing HTML file.
#   qa_legacy_leaderboard_sentinel — soft-sunset signal: cli_inform when the
#                                registry covers all legacy leaderboard strategies.
#                                Never aborts.
#
# All targets are guarded so the pipeline still tar_makes on machines
# without DBI / duckdb installed.

plan_artefact_registry <- function() {
  list(
    targets::tar_target(art_vignette_seed, {
      .art_seed_vignettes(docs_dir = here::here("docs"))
    }),

    targets::tar_target(art_diagram_seed, {
      .art_seed_diagrams(docs_dir = here::here("docs"),
                         vignette_seed = art_vignette_seed)
    }),

    targets::tar_target(qa_artefact_registry, {
      .art_run_gate(docs_dir     = here::here("docs"),
                    vignette_seed = art_vignette_seed,
                    diagram_seed  = art_diagram_seed)
    }),

    targets::tar_target(qa_legacy_leaderboard_sentinel, {
      .art_leaderboard_sentinel()
    })
  )
}

# ── Internals ─────────────────────────────────────────────────────────────

# Scan docs/*.qmd, infer vignette_id from basename, upsert into art.vignette.
# Also registers known non-qmd HTMLs (qmd_path = NA).
# Returns a summary tibble (vignette_id, html_present).
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

  path <- historicaldata::hd_registry_path()
  historicaldata::hd_registry_init(path)
  con <- historicaldata::hd_registry_open(path, read_only = FALSE)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  # ── Pass 1: qmd-backed vignettes ─────────────────────────────────────
  results <- tibble::tibble(
    vignette_id  = character(),
    html_present = logical()
  )

  if (length(qmds) > 0L) {
    basenames <- tools::file_path_sans_ext(basename(qmds))
    htmls <- paste0(basenames, ".html")
    abs_htmls <- file.path(docs_dir, htmls)
    html_present <- file.exists(abs_htmls)

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

    results <- tibble::tibble(
      vignette_id  = basenames,
      html_present = html_present
    )
  }

  # ── Pass 2: known non-qmd HTMLs ──────────────────────────────────────
  # These HTMLs are hand-authored (no source .qmd) so the qmd scan above
  # never picks them up. Without explicit registration they are invisible
  # to check_artefact_registry() — the same gap that allowed
  # mermaid-test.html / examples.html regressions.
  known_static_htmls <- c("causal-dag", "causal-dag-all", "quiz-app")

  static_results <- lapply(known_static_htmls, function(name) {
    html_file <- paste0(name, ".html")
    present   <- file.exists(file.path(docs_dir, html_file))
    historicaldata::hd_art_vignette_upsert(con, list(
      vignette_id = name,
      qmd_path    = NA_character_,
      html_path   = html_file,
      status      = if (present) "published" else "draft"
    ))
    tibble::tibble(vignette_id = name, html_present = present)
  })

  results <- rbind(results, do.call(rbind, static_results))
  results
}

# Upsert a static set of known diagrams into art.diagram.
# The `vignette_seed` arg creates a targets dependency so art_vignette_seed
# runs first (ensuring FK vignette_id rows exist).
# Returns a tibble of (diagram_id, vignette_id, target_name).
.art_seed_diagrams <- function(docs_dir, vignette_seed) {
  if (!requireNamespace("DBI", quietly = TRUE) ||
      !requireNamespace("duckdb", quietly = TRUE)) {
    return(tibble::tibble(
      diagram_id  = character(),
      vignette_id = character(),
      target_name = character()
    ))
  }

  # Known diagrams. FK vignette_id MUST already exist in art.vignette
  # (guaranteed by the dependency on art_vignette_seed).
  # Use NA_character_ for target_name when the diagram is hand-authored
  # (no targets target backs it).
  seed_rows <- list(
    list(
      diagram_id   = "leaderboard-keff-vertox",
      vignette_id  = "leaderboard",
      section      = "robustness",
      diagram_type = "plotly",
      target_name  = "strat_keff_vertox",
      purpose      = "Effective number of strategies (Vertox)"
    ),
    list(
      diagram_id   = "leaderboard-deflated-sharpe",
      vignette_id  = "leaderboard",
      section      = "robustness",
      diagram_type = "ggplot",
      target_name  = "strat_deflated_sharpe",
      purpose      = "Deflated Sharpe per strategy"
    ),
    list(
      diagram_id   = "causal-dag-mermaid",
      vignette_id  = "causal-dag",
      section      = "overview",
      diagram_type = "mermaid",
      target_name  = NA_character_,
      purpose      = "Causal-DAG project overview"
    ),
    list(
      diagram_id   = "falsification-pillar8",
      vignette_id  = "falsification",
      section      = "risk",
      diagram_type = "ggplot",
      target_name  = "fals_results_db",
      purpose      = "Pillar-8 risk-architecture metrics"
    )
  )

  path <- historicaldata::hd_registry_path()
  historicaldata::hd_registry_init(path)
  con <- historicaldata::hd_registry_open(path, read_only = FALSE)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  for (row in seed_rows) {
    historicaldata::hd_art_diagram_upsert(con, row)
  }

  tibble::tibble(
    diagram_id  = vapply(seed_rows, `[[`, character(1), "diagram_id"),
    vignette_id = vapply(seed_rows, `[[`, character(1), "vignette_id"),
    target_name = vapply(seed_rows, function(r) {
      tn <- r[["target_name"]]
      if (is.null(tn) || is.na(tn)) NA_character_ else tn
    }, character(1))
  )
}

# Run the QA gate. The `vignette_seed` and `diagram_seed` args exist so
# this target depends on both seeds — they must run first.
.art_run_gate <- function(docs_dir, vignette_seed, diagram_seed) {
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

# Soft-sunset sentinel for the legacy `leaderboard` target.
# Emits cli_inform() messages only — never aborts.
# Returns a tibble of (strategy, in_registry, in_legacy) for tar_read.
.art_leaderboard_sentinel <- function() {
  legacy_strategies <- c(
    "Factor MAX", "Factor DRIF", "Stock MAX",
    "Stock DRIF", "XGB DRIF", "PSO Optimal"
  )

  empty <- tibble::tibble(
    strategy    = legacy_strategies,
    in_registry = FALSE,
    in_legacy   = TRUE
  )

  if (!requireNamespace("DBI", quietly = TRUE) ||
      !requireNamespace("duckdb", quietly = TRUE)) {
    return(empty)
  }

  path <- historicaldata::hd_registry_path()
  if (!file.exists(path)) return(empty)

  con <- tryCatch(
    historicaldata::hd_registry_open(path, read_only = TRUE),
    error = function(e) NULL
  )
  if (is.null(con)) return(empty)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  registry_names <- tryCatch(
    DBI::dbGetQuery(
      con,
      "SELECT short_name FROM bt.strategy"
    )$short_name,
    error = function(e) character()
  )

  # Registry empty → bootstrap still running; silent no-op.
  if (length(registry_names) == 0L) return(empty)

  in_registry <- legacy_strategies %in% registry_names
  missing_in_registry <- legacy_strategies[!in_registry]

  if (all(in_registry)) {
    cli::cli_inform(c(
      "v" = paste0(
        "Registry now covers all legacy leaderboard strategies. ",
        "The {.code leaderboard} target in ",
        "{.file R/plan_leaderboard.R:11} can be retired."
      ),
      "i" = paste0(
        "Consumers should migrate to ",
        "{.code historicaldata::hd_leaderboard_from_registry()}."
      )
    ))
  } else {
    cli::cli_inform(c(
      "i" = paste0(
        "Registry does not yet cover {length(missing_in_registry)} legacy ",
        "leaderboard {?strategy/strategies}:"
      ),
      stats::setNames(
        paste0("{.val ", missing_in_registry, "}"),
        rep("*", length(missing_in_registry))
      )
    ))
  }

  tibble::tibble(
    strategy    = legacy_strategies,
    in_registry = in_registry,
    in_legacy   = TRUE
  )
}
