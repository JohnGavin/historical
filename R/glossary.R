# Entity glossary + alias resolution registry (#668)
#
# Escalates the unit/vocabulary defect class (seven instances in three days:
# #637, #640, #641, #643, #645, #663, #664, #667, plus #677 defect B found
# after this issue was filed) from "one QA gate per instance" to a single
# declared registry that every controlled vocabulary and unit-bearing column
# is checked against.
#
# This is the implementation of the global `data-glossary-and-entity-
# resolution` rule (~/.claude/rules/data-glossary-and-entity-resolution.md),
# which prescribed exactly this file layout and was never executed in this
# repo until now.
#
#   data/glossary.yaml           — canonical name, description, and unit or
#                                   allowed value set for every entity
#   data/entity_resolution.yaml  — alias -> canonical mapping
#
# Both are loaded once via the functions below. R/plan_partitions.R's
# PERIOD_LABELS_ALLOWED is migrated to DERIVE from the glossary (a consumer,
# not a second source of truth) -- see that file's own comment. The
# metric_unit entity mirrors the pre-existing, already-canonical
# `historicaldata::hd_metric_units()` (packages/historicaldata/R/
# registry_metrics.R, #640/#691) rather than re-declaring it as a second
# source of truth -- tests/testthat/test-glossary.R asserts the two stay in
# sync, the same bidirectional-consistency pattern QA gate S11 uses
# (check_s11_registry_consistency(), R/plan_qa_gates.R, #667/#673).
#
# This file is sourced BEFORE R/plan_partitions.R in docs/_targets.R (root
# _targets.R never sources plan_partitions.R, so it never needs this file).

#' Load the canonical entity glossary (data/glossary.yaml)
#'
#' @param path Character. Path to the glossary YAML file.
#' @return A named list, one element per entity. Each entity is itself a
#'   list with at least `canonical` and `description`; vocabulary entities
#'   also carry `values` (character vector of allowed values), unit entities
#'   carry `canonical_value`.
#' @noRd
load_glossary <- function(path = here::here("data", "glossary.yaml")) {
  if (!file.exists(path)) {
    cli::cli_abort(c(
      "x" = "Glossary file not found: {.path {path}}.",
      "i" = "load_glossary() (#668) expects {.path data/glossary.yaml} at the repo root."
    ))
  }
  parsed <- yaml::read_yaml(path)
  if (is.null(parsed$entities) || length(parsed$entities) == 0L) {
    cli::cli_abort(c(
      "x" = "Glossary file {.path {path}} has no {.field entities} section, or it is empty.",
      "i" = "Every controlled vocabulary or unit-bearing column must be registered under `entities:`."
    ))
  }
  parsed$entities
}

#' Load the entity-resolution alias map (data/entity_resolution.yaml)
#'
#' @param path Character. Path to the entity-resolution YAML file.
#' @return A named list of tibbles (columns `alias`, `canonical`), one per
#'   entity that has at least one registered alias. An entity absent from
#'   this file has no known aliases -- `resolve_entity()` then returns its
#'   input unchanged.
#' @noRd
load_entity_resolution <- function(path = here::here("data", "entity_resolution.yaml")) {
  if (!file.exists(path)) {
    cli::cli_abort(c(
      "x" = "Entity-resolution file not found: {.path {path}}.",
      "i" = "load_entity_resolution() (#668) expects {.path data/entity_resolution.yaml} at the repo root."
    ))
  }
  raw <- yaml::read_yaml(path)
  if (is.null(raw) || length(raw) == 0L) {
    return(list())
  }
  lapply(raw, function(entries) {
    tibble::tibble(
      alias     = vapply(entries, function(e) as.character(e$alias), character(1L)),
      canonical = vapply(entries, function(e) as.character(e$canonical), character(1L))
    )
  })
}

#' Resolve a vector of observed values against one entity's alias map
#'
#' Single point of resolution so every consumer of a controlled vocabulary
#' normalises aliases the same way, rather than each writing its own
#' `ifelse(x == "Full", "Full Period", x)`-style inline rename (the pattern
#' that made #643's fix easy to apply to `.norm_mf`/`.norm_value` but easy to
#' forget for the next strategy's normaliser).
#'
#' @param x Character vector of observed values (may include aliases).
#' @param entity Character scalar. Which entity's alias map to use.
#' @param resolution The list returned by `load_entity_resolution()`.
#' @return Character vector, same length as `x`. Values with a matching
#'   alias entry are replaced by their canonical form; every other value
#'   (including `NA`) passes through unchanged.
#' @noRd
resolve_entity <- function(x, entity, resolution) {
  map <- resolution[[entity]]
  if (is.null(map) || nrow(map) == 0L) {
    return(x)
  }
  idx <- match(x, map$alias)
  out <- x
  hit <- !is.na(idx)
  out[hit] <- map$canonical[idx[hit]]
  out
}
