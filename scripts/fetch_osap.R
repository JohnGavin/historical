#!/usr/bin/env Rscript
# fetch_osap.R
#
# Phase 1 (#816, #862): download the two SMALL free files from Open Source
# Asset Pricing (Chen & Zimmermann, "Open Source Cross-Sectional Asset
# Pricing", Critical Finance Review 2022) --
#   1. SignalDoc.csv         -- documentation for 331 anomaly signals
#   2. portfolios_wide.csv   -- monthly long-short portfolio returns, one
#                               column per predictor (wide format)
#
# Deliberately does NOT download the ~8.3GB firm-level characteristics file.
# It is out of scope for Phase 1 and, per #862's P2 finding, contains no
# return column at all -- it cannot support a custom firm-level double sort
# regardless, so there is no ingestion benefit that would justify the size.
#
# Data licence (#862 P3): no licence is stated anywhere the authors publish
# (GitHub LICENSE is code-only GPL-2.0; README/FAQ/data page/Drive bundle
# all checked, none state data terms). Operating position until the owner
# resolves this explicitly: compute freely, keep the raw download LOCAL
# (never committed, never redistributed), publish only derived statistics.
# See .claude/rules/public-private-repo-boundary.md and #862 comment
# "P3 refinement: derived data is a different question from redistribution".
#
# Source URLs (Google Drive, as listed on https://www.openassetpricing.com/data/,
# release current as of 2026-09-11 -- confirmed still current 2026-09-25):
#   SignalDoc.csv:
#     https://drive.google.com/file/d/1Sev9s6cPFUGgxp1pFiej0lGzpsMqJCI2/view
#   portfolios_wide.csv:
#     https://drive.google.com/file/d/10sOryk_ddjkXagaajTKUk1nwJs2ZLRiI/view
#
# Data location: OSAP_DATA_DIR (default ~/.cache/historical/osap/). Files are
# downloaded there if missing; set OSAP_FORCE_REFETCH=1 to re-download even
# when a file of plausible size is already present. NOTHING under
# OSAP_DATA_DIR is committed to the repo.
#
# A small manifest recording what was downloaded (file name, byte count,
# sha256, source, and download date) IS committed --
# packages/historicaldata/inst/extdata/osap/osap_manifest.csv -- so the
# provenance of the local cache is reviewable without redistributing the
# data itself (a hash and a byte count reveal nothing about the content).
#
# Usage:
#   nix develop <repo> --command Rscript scripts/fetch_osap.R
#   OSAP_DATA_DIR=/custom/path Rscript scripts/fetch_osap.R
#   OSAP_FORCE_REFETCH=1 Rscript scripts/fetch_osap.R

suppressPackageStartupMessages({
  library(cli)
})

osap_data_dir <- function() {
  path.expand(Sys.getenv("OSAP_DATA_DIR", "~/.cache/historical/osap"))
}

MANIFEST_PATH <- here::here(
  "packages", "historicaldata", "inst", "extdata", "osap", "osap_manifest.csv"
)

FILES <- list(
  list(
    name      = "SignalDoc.csv",
    file_id   = "1Sev9s6cPFUGgxp1pFiej0lGzpsMqJCI2",
    min_bytes = 1e4,   # observed ~180KB; floor well below that
    note      = "Documentation for 331 anomaly signals (acronym, authors, sample dates, sign, ...)."
  ),
  list(
    name      = "portfolios_wide.csv",
    file_id   = "10sOryk_ddjkXagaajTKUk1nwJs2ZLRiI",
    min_bytes = 1e6,   # observed ~3.3MB
    note      = "Monthly long-short portfolio returns, wide (date + 212 predictor columns, percent scale)."
  )
)

# ---------------------------------------------------------------------------
# Download a small Google Drive file by direct GET (no auth, no WRDS).
# Files under Google Drive's virus-scan-interstitial size threshold
# (roughly 100MB) are served directly from this single URL form.
# ---------------------------------------------------------------------------
download_osap_file <- function(file_id, dest, min_bytes) {
  url <- sprintf("https://drive.google.com/uc?export=download&id=%s", file_id)
  ok <- tryCatch({
    curl::curl_download(url, dest, quiet = TRUE)
    TRUE
  }, error = function(e) {
    cli::cli_warn("curl_download failed: {conditionMessage(e)}")
    FALSE
  })
  if (!ok || !file.exists(dest) || file.info(dest)$size < min_bytes) {
    got <- if (file.exists(dest)) file.info(dest)$size else 0
    cli::cli_abort(c(
      "x" = "Download of {.path {basename(dest)}} failed or is suspiciously small.",
      "i" = "Got {got} bytes; expected at least {min_bytes}.",
      "i" = "Google Drive may have rotated the file id, or rate-limited this IP -- retry, or download {.url https://www.openassetpricing.com/data/} manually."
    ))
  }
  invisible(dest)
}

dir.create(osap_data_dir(), recursive = TRUE, showWarnings = FALSE)
dir.create(dirname(MANIFEST_PATH), recursive = TRUE, showWarnings = FALSE)

force_refetch <- nzchar(Sys.getenv("OSAP_FORCE_REFETCH", ""))

manifest_rows <- list()

for (f in FILES) {
  dest <- file.path(osap_data_dir(), f$name)
  already_present <- file.exists(dest) && file.info(dest)$size >= f$min_bytes
  if (already_present && !force_refetch) {
    cli::cli_inform("Already present: {.path {dest}} ({file.info(dest)$size} bytes)")
  } else {
    cli::cli_progress_step("Downloading {f$name}")
    download_osap_file(f$file_id, dest, f$min_bytes)
    cli::cli_alert_success("Downloaded {.path {dest}} ({file.info(dest)$size} bytes)")
  }

  manifest_rows[[f$name]] <- data.frame(
    file           = f$name,
    bytes          = file.info(dest)$size,
    sha256         = digest::digest(dest, algo = "sha256", file = TRUE),
    download_date  = as.character(Sys.Date()),
    source_file_id = f$file_id,
    source_url     = sprintf("https://drive.google.com/file/d/%s/view", f$file_id),
    note           = f$note,
    stringsAsFactors = FALSE
  )
}

manifest <- do.call(rbind, manifest_rows)
utils::write.csv(manifest, MANIFEST_PATH, row.names = FALSE)
cli::cli_alert_success("Manifest written: {.path {MANIFEST_PATH}}")

cli::cli_h2("Summary")
print(manifest[, c("file", "bytes", "sha256", "download_date")], row.names = FALSE)
cli::cli_inform("Raw files kept at {.path {osap_data_dir()}} -- NOT committed (see #862 P3 licence note).")
