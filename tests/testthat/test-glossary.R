testthat::local_edition(3)
# Tests for the entity glossary + alias resolution registry (#668):
#   1. load_glossary() / load_entity_resolution() — R/glossary.R
#   2. resolve_entity() — alias -> canonical resolution
#   3. PERIOD_LABELS_ALLOWED (R/plan_partitions.R) is now DERIVED from the
#      glossary, not a hand-typed second copy of the same vocabulary
#   4. The glossary's metric_unit entity stays in sync with the REAL single
#      source of truth, historicaldata::hd_metric_units() (#640/#691) — the
#      same bidirectional-consistency shape as QA gate S11's
#      check_s11_registry_consistency() (#667/#673)

source(here::here("R/glossary.R"))

# ── load_glossary() ──────────────────────────────────────────────────────────

test_that("load_glossary reads data/glossary.yaml and returns the registered entities", {
  g <- load_glossary()
  expect_true(is.list(g))
  expect_true(all(c("period_label", "metric_unit") %in% names(g)))
  expect_identical(g$period_label$canonical, "period_label")
  expect_true(is.character(g$period_label$values))
  expect_true("Full Period" %in% g$period_label$values)
})

test_that("load_glossary aborts when the file does not exist", {
  expect_error(
    load_glossary(path = tempfile(fileext = ".yaml")),
    regexp = "not found"
  )
})

test_that("load_glossary aborts when the file has no entities section", {
  f <- tempfile(fileext = ".yaml")
  writeLines("not_entities: {}", f)
  on.exit(unlink(f))
  expect_error(load_glossary(path = f), regexp = "entities")
})

# ── load_entity_resolution() ─────────────────────────────────────────────────

test_that("load_entity_resolution reads data/entity_resolution.yaml as alias/canonical tibbles", {
  r <- load_entity_resolution()
  expect_true(is.list(r))
  expect_true("period_label" %in% names(r))
  expect_true(all(c("alias", "canonical") %in% names(r$period_label)))
  expect_true("Full" %in% r$period_label$alias)
  expect_identical(
    r$period_label$canonical[r$period_label$alias == "Full"],
    "Full Period"
  )
})

test_that("load_entity_resolution aborts when the file does not exist", {
  expect_error(
    load_entity_resolution(path = tempfile(fileext = ".yaml")),
    regexp = "not found"
  )
})

# ── resolve_entity() ──────────────────────────────────────────────────────────

test_that("resolve_entity replaces a registered alias with its canonical form", {
  resolution <- load_entity_resolution()
  expect_identical(
    resolve_entity("Full", "period_label", resolution),
    "Full Period"
  )
})

test_that("resolve_entity passes through values with no alias entry unchanged", {
  resolution <- load_entity_resolution()
  expect_identical(
    resolve_entity(c("Training", "Testing", "OOS"), "period_label", resolution),
    c("Training", "Testing", "OOS")
  )
})

test_that("resolve_entity handles a vector mixing aliased and non-aliased values", {
  resolution <- load_entity_resolution()
  expect_identical(
    resolve_entity(c("Full", "Training", "Full"), "period_label", resolution),
    c("Full Period", "Training", "Full Period")
  )
})

test_that("resolve_entity preserves NA and passes through an unregistered entity untouched", {
  resolution <- load_entity_resolution()
  expect_identical(
    resolve_entity(c("Full", NA_character_), "period_label", resolution),
    c("Full Period", NA_character_)
  )
  expect_identical(
    resolve_entity(c("fraction", "percent"), "no_such_entity", resolution),
    c("fraction", "percent")
  )
})

# ── PERIOD_LABELS_ALLOWED derives from the glossary (#668) ──────────────────

test_that("PERIOD_LABELS_ALLOWED (R/plan_partitions.R) equals the glossary's period_label values", {
  source(here::here("R/plan_partitions.R"))
  expect_identical(PERIOD_LABELS_ALLOWED, load_glossary()$period_label$values)
  # Same six values the constant hand-typed before #668 migrated it onto the
  # glossary -- this is the regression check that the migration changed
  # WHERE the vocabulary lives, not WHAT it contains.
  expect_setequal(
    PERIOD_LABELS_ALLOWED,
    c("Training", "Testing", "Holdout", "Validation", "Full Period", "OOS")
  )
})

# ── metric_unit stays in sync with historicaldata::hd_metric_units() ────────
# (#640/#691's REAL single source of truth; the glossary mirrors it for
# documentation -- see data/glossary.yaml's metric_unit `source` field.)

test_that("glossary metric_unit values match historicaldata::hd_metric_units() exactly", {
  testthat::skip_if_not_installed("historicaldata")
  glossary_units <- load_glossary()$metric_unit$values
  real_units <- historicaldata::hd_metric_units()
  expect_setequal(glossary_units, real_units)
})

test_that("glossary metric_unit canonical_value is a member of its own values", {
  entity <- load_glossary()$metric_unit
  expect_true(entity$canonical_value %in% entity$values)
})
