#!/usr/bin/env Rscript
# fetch_sp500_membership.R
#
# #816: download the free point-in-time S&P 500 membership history
# (fja05680/sp500 on GitHub, the maintained "(Updated)" file: one row per
# index-change date, `tickers` = full membership after that change, 1996 to
# the latest upstream update) and write a committed manifest.
#
# DATA only: no code from that repository is used (external-code-zero-trust).
# The older plain "Historical Components & Changes.csv" is NOT fetched here: it
# stops in 2019-01 and carries SYM-YYYYMM alias tokens that
# hd_sp500_membership() rejects.
#
# Licence (checked 2026-11-07 via the GitHub API `license` field and the raw
# LICENSE file): MIT License, Copyright (c) 2019-2020 Farrell J. Aultman. MIT
# permits redistribution, but the LICENSE text addresses "the Software" and
# does not separately address the constituent data, whose underlying facts
# are S&P Dow Jones Indices' index membership. Operating position, the same
# as OSAP (scripts/fetch_osap.R): keep the raw download LOCAL (never
# committed); commit only the manifest (a hash and byte count reveal
# nothing about the content) and publish derived statistics.
#
# Data location: SP500_MEMBERSHIP_DIR (default
# ~/.cache/historical/sp500_membership/). Set SP500_FORCE_REFETCH=1 to
# re-download when a plausible file is already present.
#
# Manifest: packages/historicaldata/inst/extdata/sp500/sp500_membership_manifest.csv
#
# Usage:
#   nix develop <repo> --command Rscript scripts/fetch_sp500_membership.R

suppressPackageStartupMessages({
  library(cli)
})

REPO_API   <- "https://api.github.com/repos/fja05680/sp500"
SOURCE_FILE <- "S&P 500 Historical Components & Changes (Updated).csv"
SOURCE_URL <- paste0(
  "https://raw.githubusercontent.com/fja05680/sp500/master/",
  utils::URLencode(SOURCE_FILE, reserved = TRUE)
)
MIN_BYTES  <- 1e6   # observed ~5.5 MB; floor well below that
DEST_NAME  <- "sp500_historical_components.csv"

MANIFEST_PATH <- here::here(
  "packages", "historicaldata", "inst", "extdata", "sp500",
  "sp500_membership_manifest.csv"
)

data_dir <- path.expand(Sys.getenv("SP500_MEMBERSHIP_DIR", "~/.cache/historical/sp500_membership"))
dir.create(data_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(dirname(MANIFEST_PATH), recursive = TRUE, showWarnings = FALSE)
dest <- file.path(data_dir, DEST_NAME)

api_get <- function(url) {
  tmp <- tempfile(fileext = ".json")
  on.exit(unlink(tmp), add = TRUE)
  ok <- tryCatch({
    curl::curl_download(url, tmp, quiet = TRUE,
                        handle = curl::new_handle(useragent = "historical-fetch-sp500"))
    TRUE
  }, error = function(e) {
    cli::cli_warn("GitHub API call failed ({url}): {conditionMessage(e)}")
    FALSE
  })
  if (!ok) return(NULL)
  jsonlite::fromJSON(tmp, simplifyVector = FALSE)
}

force_refetch <- nzchar(Sys.getenv("SP500_FORCE_REFETCH", ""))
present <- file.exists(dest) && file.info(dest)$size >= MIN_BYTES
if (present && !force_refetch) {
  cli::cli_inform("Already present: {.path {dest}} ({file.info(dest)$size} bytes)")
} else {
  cli::cli_progress_step("Downloading {SOURCE_FILE}")
  ok <- tryCatch({
    curl::curl_download(SOURCE_URL, dest, quiet = TRUE)
    TRUE
  }, error = function(e) {
    cli::cli_warn("curl_download failed: {conditionMessage(e)}")
    FALSE
  })
  got <- if (file.exists(dest)) file.info(dest)$size else 0
  if (!ok || got < MIN_BYTES) {
    cli::cli_abort(c(
      "x" = "Download of {.path {DEST_NAME}} failed or is suspiciously small.",
      "i" = "Got {got} bytes; expected at least {MIN_BYTES}.",
      "i" = "The upstream file may have been renamed: check {.url https://github.com/fja05680/sp500}."
    ))
  }
  cli::cli_alert_success("Downloaded {.path {dest}} ({got} bytes)")
}

# Provenance from the GitHub API. Unavailable values are recorded as the
# string "unavailable", never silently dropped (a manifest that hides a failed
# lookup would read as a complete one).
repo   <- api_get(REPO_API)
licence <- if (!is.null(repo) && !is.null(repo$license)) repo$license$spdx_id else "unavailable"
commits <- api_get(sprintf("%s/commits?path=%s&per_page=1", REPO_API,
                           utils::URLencode(SOURCE_FILE, reserved = TRUE)))
up_sha  <- if (length(commits) >= 1L) commits[[1L]]$sha else "unavailable"
up_date <- if (length(commits) >= 1L) commits[[1L]]$commit$committer$date else "unavailable"

# Smoke-read through the package loader so a bad download is caught here, and
# record the coverage actually obtained.
pkgload::load_all(here::here("packages", "historicaldata"), quiet = TRUE)
mem <- historicaldata::hd_sp500_membership(dest)

manifest <- data.frame(
  file                 = DEST_NAME,
  bytes                = file.info(dest)$size,
  sha256               = digest::digest(dest, algo = "sha256", file = TRUE),
  download_date        = as.character(Sys.Date()),
  source_url           = SOURCE_URL,
  upstream_commit_sha  = up_sha,
  upstream_commit_date = up_date,
  licence_spdx         = licence,
  first_snapshot       = as.character(min(mem$date)),
  last_snapshot        = as.character(max(mem$date)),
  n_snapshots          = length(unique(mem$date)),
  note                 = "Membership dates only: no prices, returns or delisting data. Raw file kept LOCAL, not committed.",
  stringsAsFactors     = FALSE
)
utils::write.csv(manifest, MANIFEST_PATH, row.names = FALSE)
cli::cli_alert_success("Manifest written: {.path {MANIFEST_PATH}}")
cli::cli_h2("Summary")
print(manifest[, c("file", "bytes", "sha256", "licence_spdx", "first_snapshot",
                   "last_snapshot", "n_snapshots")], row.names = FALSE)
cli::cli_inform("Raw file kept at {.path {data_dir}} -- NOT committed (see header: licence posture).")
