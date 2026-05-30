# Tests for hd_art_vignette_upsert + hd_art_diagram_upsert +
# check_artefact_registry (#347 PR 4/4)

.init_art_registry <- function() {
  tmp <- tempfile(fileext = ".duckdb")
  hd_registry_init(tmp)
  con <- hd_registry_open(tmp, read_only = FALSE)
  list(tmp = tmp, con = con)
}

test_that("hd_art_vignette_upsert inserts and is idempotent", {
  skip_if_not_installed("DBI"); skip_if_not_installed("duckdb")
  s <- .init_art_registry()
  withr::defer({ DBI::dbDisconnect(s$con, shutdown = TRUE); unlink(s$tmp) })

  row <- tibble::tibble(
    vignette_id = "leaderboard",
    qmd_path    = "docs/leaderboard.qmd",
    html_path   = "leaderboard.html",
    url         = "https://example.org/leaderboard.html",
    status      = "published"
  )
  hd_art_vignette_upsert(s$con, row)
  hd_art_vignette_upsert(s$con, row)

  n <- DBI::dbGetQuery(s$con,
    "SELECT COUNT(*) AS n FROM art.vignette")$n
  expect_equal(n, 1L)

  got <- DBI::dbGetQuery(s$con,
    "SELECT html_path, status FROM art.vignette")
  expect_equal(got$html_path, "leaderboard.html")
  expect_equal(got$status, "published")
})

test_that("hd_art_vignette_upsert rejects empty vignette_id", {
  skip_if_not_installed("DBI"); skip_if_not_installed("duckdb")
  s <- .init_art_registry()
  withr::defer({ DBI::dbDisconnect(s$con, shutdown = TRUE); unlink(s$tmp) })

  expect_error(
    hd_art_vignette_upsert(s$con, tibble::tibble(vignette_id = "")),
    regexp = "vignette_id"
  )
})

test_that("hd_art_diagram_upsert inserts with FK to art.vignette", {
  skip_if_not_installed("DBI"); skip_if_not_installed("duckdb")
  s <- .init_art_registry()
  withr::defer({ DBI::dbDisconnect(s$con, shutdown = TRUE); unlink(s$tmp) })

  hd_art_vignette_upsert(s$con,
    list(vignette_id = "leaderboard", html_path = "leaderboard.html"))

  hd_art_diagram_upsert(s$con, list(
    diagram_id   = "leaderboard-keff-vertox",
    vignette_id  = "leaderboard",
    section      = "robustness",
    diagram_type = "plotly",
    target_name  = "strat_keff_vertox",
    purpose      = "Effective number of strategies (Vertox)"
  ))

  got <- DBI::dbGetQuery(s$con,
    "SELECT diagram_id, vignette_id, diagram_type FROM art.diagram")
  expect_equal(nrow(got), 1L)
  expect_equal(got$diagram_type, "plotly")
})

test_that("hd_art_diagram_upsert FK rejects orphan vignette_id", {
  skip_if_not_installed("DBI"); skip_if_not_installed("duckdb")
  s <- .init_art_registry()
  withr::defer({ DBI::dbDisconnect(s$con, shutdown = TRUE); unlink(s$tmp) })

  expect_error(
    hd_art_diagram_upsert(s$con, list(
      diagram_id = "orphan", vignette_id = "no-such-vignette"
    )),
    regexp = "Constraint|FOREIGN KEY|Violates|foreign|not present"
  )
})

test_that("check_artefact_registry returns empty when all HTMLs exist", {
  skip_if_not_installed("DBI"); skip_if_not_installed("duckdb")
  s <- .init_art_registry()
  withr::defer({ DBI::dbDisconnect(s$con, shutdown = TRUE); unlink(s$tmp) })

  docs <- tempfile("docs_")
  dir.create(docs)
  withr::defer(unlink(docs, recursive = TRUE))
  writeLines("<html></html>", file.path(docs, "leaderboard.html"))

  hd_art_vignette_upsert(s$con,
    list(vignette_id = "leaderboard", html_path = "leaderboard.html"))

  issues <- check_artefact_registry(s$con, docs_dir = docs, strict = FALSE)
  expect_equal(nrow(issues), 0L)
})

test_that("check_artefact_registry detects missing HTML", {
  skip_if_not_installed("DBI"); skip_if_not_installed("duckdb")
  s <- .init_art_registry()
  withr::defer({ DBI::dbDisconnect(s$con, shutdown = TRUE); unlink(s$tmp) })

  docs <- tempfile("docs_"); dir.create(docs)
  withr::defer(unlink(docs, recursive = TRUE))

  # Registry references a file that does NOT exist on disk —
  # exactly the mermaid-test.html / examples.html scenario.
  hd_art_vignette_upsert(s$con,
    list(vignette_id = "mermaid-test", html_path = "mermaid-test.html"))

  issues <- check_artefact_registry(s$con, docs_dir = docs, strict = FALSE)
  expect_equal(nrow(issues), 1L)
  expect_equal(issues$vignette_id, "mermaid-test")
})

test_that("check_artefact_registry aborts in strict mode", {
  skip_if_not_installed("DBI"); skip_if_not_installed("duckdb")
  s <- .init_art_registry()
  withr::defer({ DBI::dbDisconnect(s$con, shutdown = TRUE); unlink(s$tmp) })

  docs <- tempfile("docs_"); dir.create(docs)
  withr::defer(unlink(docs, recursive = TRUE))

  hd_art_vignette_upsert(s$con,
    list(vignette_id = "missing", html_path = "missing.html"))

  expect_error(
    check_artefact_registry(s$con, docs_dir = docs, strict = TRUE),
    regexp = "missing HTML"
  )
})

test_that("check_artefact_registry skips draft and NA html_path rows", {
  skip_if_not_installed("DBI"); skip_if_not_installed("duckdb")
  s <- .init_art_registry()
  withr::defer({ DBI::dbDisconnect(s$con, shutdown = TRUE); unlink(s$tmp) })

  docs <- tempfile("docs_"); dir.create(docs)
  withr::defer(unlink(docs, recursive = TRUE))

  # draft row — should not be checked
  hd_art_vignette_upsert(s$con,
    list(vignette_id = "wip", html_path = "wip.html", status = "draft"))
  # NA html_path — also skipped
  hd_art_vignette_upsert(s$con,
    list(vignette_id = "no-html", html_path = NA))

  issues <- check_artefact_registry(s$con, docs_dir = docs, strict = TRUE)
  expect_equal(nrow(issues), 0L)
})
