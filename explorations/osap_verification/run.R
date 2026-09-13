# Verify four presumptions about Open Source Asset Pricing (Chen & Zimmermann)
# data, per https://github.com/JohnGavin/historical/issues/862.
#
# This is a NON-GOAL-EXTENDING exploration script: no backtests, no
# leaderboard rows, no strategy work. It downloads the free OSAP files to a
# SCRATCH directory (never the worktree, never committed) and answers:
#
#   P1 -- is the data actually delisting-inclusive?
#   P2 -- are monthly returns in the free firm-level download?
#   P3 -- data licence (documented in FINDINGS.md -- not computable here)
#   P4 -- does the free download need WRDS credentials?
#
# Every number in explorations/osap_verification/FINDINGS.md comes from this
# script's output in explorations/osap_verification/results/.
#
# Usage:
#   nix develop <repo> --command Rscript explorations/osap_verification/run.R
#
# Data location: OSAP_DATA_DIR (default /tmp/osap_scratch). Files are
# downloaded there if missing. NOTHING under OSAP_DATA_DIR is committed --
# see .claude/rules/public-private-repo-boundary.md and the P3 licence
# finding in FINDINGS.md (data licence unverified -> local-only).
#
# Source URLs (Google Drive, as listed on https://www.openassetpricing.com/data/,
# release current as of 2026-09-11):
#   SignalDoc.csv (signal documentation, ~180KB):
#     https://drive.google.com/file/d/1Sev9s6cPFUGgxp1pFiej0lGzpsMqJCI2/view
#   Portfolio returns, wide (~3.3MB):
#     https://drive.google.com/file/d/10sOryk_ddjkXagaajTKUk1nwJs2ZLRiI/view
#   Firm-level signals, wide (zipped ~2.2GB, unzipped ~8.3GB):
#     https://drive.google.com/file/d/1avFIMjz_7LoF3p3nO26eqLW5KdRTOdhW/view

suppressMessages({
  library(dplyr)
})

OSAP_DATA_DIR <- Sys.getenv("OSAP_DATA_DIR", "/tmp/osap_scratch")
RESULTS_DIR <- "explorations/osap_verification/results"
dir.create(OSAP_DATA_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(RESULTS_DIR, recursive = TRUE, showWarnings = FALSE)

SIGNALDOC_CSV <- file.path(OSAP_DATA_DIR, "SignalDoc.csv")
PORTFOLIOS_WIDE_CSV <- file.path(OSAP_DATA_DIR, "portfolios_wide.csv")
FIRM_ZIP <- file.path(OSAP_DATA_DIR, "signed_predictors_dl_wide.zip")
FIRM_CSV <- file.path(OSAP_DATA_DIR, "signed_predictors_dl_wide.csv")

FIRM_FILE_ID <- "1avFIMjz_7LoF3p3nO26eqLW5KdRTOdhW"
PORTFOLIOS_FILE_ID <- "10sOryk_ddjkXagaajTKUk1nwJs2ZLRiI"
SIGNALDOC_FILE_ID <- "1Sev9s6cPFUGgxp1pFiej0lGzpsMqJCI2"

# ---------------------------------------------------------------------------
# Download helpers -- direct HTTP against Google Drive, no auth, no WRDS.
# Small files (<~100MB) work with a single GET. Large files trigger a
# "Google Drive can't scan this file for viruses" interstitial that must be
# confirmed via a `uuid` token before the real bytes are served.
# ---------------------------------------------------------------------------

download_gdrive_small <- function(file_id, dest) {
  if (file.exists(dest)) {
    cli::cli_inform("Already present: {dest}")
    return(invisible(dest))
  }
  url <- sprintf("https://drive.google.com/uc?export=download&id=%s", file_id)
  status <- system2(
    "curl",
    c("-sL", "-o", shQuote(dest), shQuote(url)),
    stdout = TRUE, stderr = TRUE
  )
  if (!file.exists(dest) || file.info(dest)$size < 100) {
    cli::cli_abort(c(
      "x" = "Download failed or suspiciously small: {dest}",
      "i" = "curl output: {paste(status, collapse = ' | ')}"
    ))
  }
  invisible(dest)
}

download_gdrive_large <- function(file_id, dest) {
  if (file.exists(dest)) {
    cli::cli_inform("Already present: {dest}")
    return(invisible(dest))
  }
  cookie_jar <- tempfile()
  interstitial <- tempfile()
  url1 <- sprintf("https://drive.google.com/uc?export=download&id=%s", file_id)
  system2(
    "curl",
    c("-sL", "-c", shQuote(cookie_jar), "-o", shQuote(interstitial), shQuote(url1)),
    stdout = TRUE, stderr = TRUE
  )
  html <- paste(readLines(interstitial, warn = FALSE), collapse = "")
  uuid_match <- regmatches(html, regexpr('name="uuid" value="[a-f0-9-]{36}"', html))
  if (length(uuid_match) == 0) {
    cli::cli_abort(c(
      "x" = "Could not find the Google Drive large-file confirm token (uuid).",
      "i" = "Google may have changed the interstitial page format, or this file no longer requires it.",
      "i" = "Interstitial saved at {interstitial} for inspection."
    ))
  }
  # Capture the UUID with a group rather than re-matching a substring of
  # `uuid_match`: that string ends in the literal closing double-quote, so a
  # trailing-anchored "[a-f0-9-]{36}$" can never match and silently yields
  # character(0) -- which then makes sprintf() below return character(0) and
  # curl run with no URL at all. Caught by roborev on job 13443.
  uuid <- regmatches(html, regexec('name="uuid" value="([a-f0-9-]{36})"', html))[[1]][2]
  if (is.na(uuid) || !nzchar(uuid)) {
    cli::cli_abort(c(
      "x" = "Matched the Google Drive confirm-token block but could not extract the uuid.",
      "i" = "Interstitial saved at {interstitial} for inspection."
    ))
  }
  url2 <- sprintf(
    "https://drive.usercontent.google.com/download?id=%s&export=download&confirm=t&uuid=%s",
    file_id, uuid
  )
  cli::cli_inform("Downloading large file (this can take several minutes): {dest}")
  system2(
    "curl",
    c("-sL", "-b", shQuote(cookie_jar), "-o", shQuote(dest), shQuote(url2)),
    stdout = TRUE, stderr = TRUE
  )
  if (!file.exists(dest) || file.info(dest)$size < 1e8) {
    cli::cli_abort(c(
      "x" = "Large-file download failed or suspiciously small: {dest}",
      "i" = "Got {if (file.exists(dest)) file.info(dest)$size else 0} bytes; expected > 1e8."
    ))
  }
  invisible(dest)
}

download_gdrive_small(SIGNALDOC_FILE_ID, SIGNALDOC_CSV)
download_gdrive_small(PORTFOLIOS_FILE_ID, PORTFOLIOS_WIDE_CSV)

if (!file.exists(FIRM_CSV)) {
  download_gdrive_large(FIRM_FILE_ID, FIRM_ZIP)
  cli::cli_inform("Unzipping firm-level signals file...")
  utils::unzip(FIRM_ZIP, exdir = OSAP_DATA_DIR)
  if (!file.exists(FIRM_CSV)) {
    cli::cli_abort("Unzip did not produce the expected file: {FIRM_CSV}")
  }
  # Free the zip immediately -- the unzipped CSV alone is ~8.3GB; keeping
  # both would needlessly triple the scratch footprint.
  unlink(FIRM_ZIP)
}

# ===========================================================================
# P4 -- Does the free download need WRDS credentials?
# ===========================================================================
# We never set any WRDS/CRSP/Postgres credential in this session. Record
# that fact plus confirmation that the interstitial we passed through was a
# virus-scan size warning, not a login page.
wrds_env_vars <- c(
  "WRDS_USER", "WRDS_PASSWORD", "PGHOST", "PGUSER", "PGPASSWORD",
  "WRDS_USERNAME", "WRDS_HOST"
)
wrds_env_set <- vapply(wrds_env_vars, function(v) nzchar(Sys.getenv(v)), logical(1))
p4_result <- data.frame(
  check = c(
    "any_wrds_env_var_set",
    "signaldoc_downloaded_no_auth",
    "portfolios_wide_downloaded_no_auth",
    "firm_level_downloaded_no_auth"
  ),
  result = c(
    any(wrds_env_set),
    file.exists(SIGNALDOC_CSV),
    file.exists(PORTFOLIOS_WIDE_CSV),
    file.exists(FIRM_CSV)
  )
)
write.csv(p4_result, file.path(RESULTS_DIR, "osap_p4_wrds_check.csv"), row.names = FALSE)
cli::cli_inform("P4 -- WRDS env vars set: {any(wrds_env_set)} (should be FALSE)")

# ===========================================================================
# P2 -- Are monthly returns / Price / Size / STreversal in the firm-level file?
# ===========================================================================
header_line <- readLines(FIRM_CSV, n = 1)
firm_cols <- strsplit(header_line, ",")[[1]]

target_present <- c("MaxRet", "Mom12m", "CoskewACX", "ReturnSkew")
target_absent <- c("Price", "Size", "STreversal")
return_like <- grep("^(ret|return|RET|Ret)$", firm_cols, value = TRUE, ignore.case = FALSE)

p2_result <- data.frame(
  column = c(target_present, target_absent, "any_return_like_column"),
  present_in_firm_level_file = c(
    target_present %in% firm_cols,
    target_absent %in% firm_cols,
    length(return_like) > 0
  )
)
write.csv(p2_result, file.path(RESULTS_DIR, "osap_p2_column_check.csv"), row.names = FALSE)
writeLines(firm_cols, file.path(RESULTS_DIR, "osap_firmlevel_columns.txt"))
cli::cli_inform("P2 -- {length(firm_cols)} columns total in firm-level file (permno, yyyymm + {length(firm_cols) - 2} signals)")

# ===========================================================================
# P1 -- Is the data actually delisting-inclusive?
# ===========================================================================
con <- duckdb::dbConnect(duckdb::duckdb())
on.exit(duckdb::dbDisconnect(con, shutdown = TRUE), add = TRUE)

DBI::dbExecute(con, sprintf(
  "CREATE TABLE osap_min AS SELECT permno, yyyymm FROM read_csv_auto('%s')",
  FIRM_CSV
))

# --- per-year distinct-permno panel shape (delisting-inclusive panels rise
#     then fall; survivorship-biased snapshots are flat/monotone) ---
yearly <- DBI::dbGetQuery(con, "
  SELECT CAST(yyyymm / 100 AS INTEGER) AS yr,
         count(*) AS n_obs,
         count(DISTINCT permno) AS n_permno
  FROM osap_min
  GROUP BY yr
  ORDER BY yr
")
write.csv(yearly, file.path(RESULTS_DIR, "osap_permno_by_year.csv"), row.names = FALSE)

peak_row <- yearly[which.max(yearly$n_permno), ]
last_full_year <- max(yearly$yr[yearly$n_permno >= 0.9 * max(yearly$n_permno)])

# --- monthly counts, to locate the "dense panel end" (last month before the
#     data-completeness tail thins out due to accounting-signal reporting
#     lag -- NOT delisting; see FINDINGS.md) ---
monthly <- DBI::dbGetQuery(con, "
  SELECT yyyymm, count(DISTINCT permno) AS n_permno
  FROM osap_min
  GROUP BY yyyymm
  ORDER BY yyyymm
")
write.csv(monthly, file.path(RESULTS_DIR, "osap_monthly_permno_counts.csv"), row.names = FALSE)

n_months <- nrow(monthly)
trailing_median <- vapply(seq_len(n_months), function(i) {
  lo <- max(1, i - 11)
  stats::median(monthly$n_permno[lo:i])
}, numeric(1))
dense_mask <- monthly$n_permno >= 0.8 * trailing_median
# dense_end = last month in the longest trailing run of dense months
# walk backwards from the very end to find where the SUSTAINED drop begins
run_end <- n_months
while (run_end > 1 && !dense_mask[run_end]) run_end <- run_end - 1
panel_end_raw <- monthly$yyyymm[n_months]
panel_end_dense <- monthly$yyyymm[run_end]

# --- exit test, mirroring explorations/momentum_max_lottery's equity_daily
#     methodology exactly, for direct comparability: for each permno, does
#     its LAST observation fall more than 12 months before the panel end? ---
last_obs <- DBI::dbGetQuery(con, "
  SELECT permno, max(yyyymm) AS last_yyyymm, min(yyyymm) AS first_yyyymm
  FROM osap_min
  GROUP BY permno
")

yyyymm_to_months <- function(x) {
  yr <- x %/% 100
  mo <- x %% 100
  yr * 12L + mo
}

n_permno_total <- nrow(last_obs)

compute_exit_stat <- function(panel_end) {
  end_m <- yyyymm_to_months(panel_end)
  last_m <- yyyymm_to_months(last_obs$last_yyyymm)
  n_exit <- sum((end_m - last_m) > 12)
  list(
    panel_end = panel_end,
    n_total = n_permno_total,
    n_exit_gt_1yr = n_exit,
    pct_exit_gt_1yr = n_exit / n_permno_total
  )
}

stat_raw <- compute_exit_stat(panel_end_raw)
stat_dense <- compute_exit_stat(panel_end_dense)

# --- entries/exits per calendar year (bonus check) ---
entries <- last_obs |>
  mutate(entry_yr = first_yyyymm %/% 100, exit_yr = last_yyyymm %/% 100) |>
  count(entry_yr, name = "n_entries") |>
  rename(yr = entry_yr)
exits <- last_obs |>
  mutate(exit_yr = last_yyyymm %/% 100) |>
  count(exit_yr, name = "n_exits") |>
  rename(yr = exit_yr)
entries_exits <- full_join(entries, exits, by = "yr") |>
  arrange(yr) |>
  mutate(across(c(n_entries, n_exits), \(x) tidyr::replace_na(x, 0L)))
write.csv(entries_exits, file.path(RESULTS_DIR, "osap_entries_exits_by_year.csv"), row.names = FALSE)

# --- equity_daily comparator, hardcoded from the verified figure in
#     explorations/momentum_max_lottery/SUMMARY.md section (d): "of 502
#     tickers ... zero have a return series ending more than one year
#     before the panel's end date" ---
equity_daily_comparator <- data.frame(
  dataset = "equity_daily",
  n_total = 502L,
  n_exit_gt_1yr = 0L,
  pct_exit_gt_1yr = 0
)

p1_summary <- rbind(
  data.frame(
    dataset = "osap_firm_level (panel_end = raw max observed month)",
    n_total = stat_raw$n_total,
    n_exit_gt_1yr = stat_raw$n_exit_gt_1yr,
    pct_exit_gt_1yr = stat_raw$pct_exit_gt_1yr
  ),
  data.frame(
    dataset = "osap_firm_level (panel_end = dense-coverage month, excludes lag tail)",
    n_total = stat_dense$n_total,
    n_exit_gt_1yr = stat_dense$n_exit_gt_1yr,
    pct_exit_gt_1yr = stat_dense$pct_exit_gt_1yr
  ),
  equity_daily_comparator
)
write.csv(p1_summary, file.path(RESULTS_DIR, "osap_p1_exit_summary.csv"), row.names = FALSE)

p1_metadata <- data.frame(
  metric = c(
    "n_distinct_permno_total", "peak_year", "peak_year_n_permno",
    "last_year_at_or_above_90pct_of_peak", "panel_end_raw_yyyymm",
    "panel_end_dense_yyyymm"
  ),
  value = c(
    n_permno_total, peak_row$yr, peak_row$n_permno,
    last_full_year, panel_end_raw, panel_end_dense
  )
)
write.csv(p1_metadata, file.path(RESULTS_DIR, "osap_p1_metadata.csv"), row.names = FALSE)

cli::cli_inform("P1 -- distinct permno total: {n_permno_total}")
cli::cli_inform("P1 -- peak year {peak_row$yr}: {peak_row$n_permno} distinct permnos")
cli::cli_inform("P1 -- panel_end_raw={panel_end_raw}, exits >1yr before: {stat_raw$n_exit_gt_1yr} ({round(100*stat_raw$pct_exit_gt_1yr,1)}%)")
cli::cli_inform("P1 -- panel_end_dense={panel_end_dense}, exits >1yr before: {stat_dense$n_exit_gt_1yr} ({round(100*stat_dense$pct_exit_gt_1yr,1)}%)")
cli::cli_inform("Comparator -- equity_daily: 0/502 (0.0%)")

# --- tail-artifact-immune robustness check: count permnos whose LAST
#     observation falls before a series of fixed historical cutoffs, all
#     decades before any 2025-2026 data-completeness tail issue could touch
#     them. This isolates genuine mid-history exits from the recency
#     artifact discussed above. ---
historical_cutoffs <- c(199912L, 200912L, 201912L, 202312L)
historical_exit_check <- data.frame(
  cutoff_yyyymm = historical_cutoffs,
  n_exited_before_cutoff = vapply(
    historical_cutoffs,
    \(cutoff) sum(last_obs$last_yyyymm < cutoff),
    integer(1)
  )
) |>
  mutate(pct_of_total = n_exited_before_cutoff / n_permno_total)
write.csv(
  historical_exit_check,
  file.path(RESULTS_DIR, "osap_p1_historical_exit_robustness.csv"),
  row.names = FALSE
)
cli::cli_inform("P1 robustness -- exited before 1999-12 (tail-artifact-immune): {historical_exit_check$n_exited_before_cutoff[1]} ({round(100*historical_exit_check$pct_of_total[1],1)}%)")

# ===========================================================================
# Optional named-bankrupt sub-check (P1 supporting evidence)
# ===========================================================================
# OSAP is keyed by CRSP permno, not ticker or company name. The firm-level
# file carries NO name/ticker column (see osap_firmlevel_columns.txt), and
# no free permno<->ticker crosswalk is bundled with this download or
# reachable without WRDS. We deliberately do NOT guess a permno for Enron
# etc. -- see FINDINGS.md for the INDETERMINATE verdict on this sub-check.
has_identifier_column <- any(grepl(
  "ticker|comnam|cusip|name",
  firm_cols,
  ignore.case = TRUE
))
writeLines(
  sprintf(
    "has_ticker_or_name_column_in_firm_level_file: %s",
    has_identifier_column
  ),
  file.path(RESULTS_DIR, "osap_named_bankrupt_subcheck.txt")
)
cli::cli_inform("Named-bankrupt sub-check -- ticker/name column present: {has_identifier_column} (expect FALSE -> INDETERMINATE, no free crosswalk)")

cli::cli_inform("Done. Results written to {RESULTS_DIR}/")
