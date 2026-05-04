#!/usr/bin/env Rscript
# parse_nyt_tedalcorn.R
#
# Parse pre-processed NYT data from tedalcorn/nyt project and write
# data/raw/nyt_keywords.parquet.
#
# Sources:
#   /tmp/tedalcorn-nyt/subjects.json  — person/org annual mention counts
#   /tmp/tedalcorn-nyt/dashboard.json — articles_per_month array
#   /tmp/tedalcorn-nyt/presidents.json — monthly presidential mention counts
#
# Output schema (nyt_keywords.parquet):
#   date       DATE      — first of month
#   keyword    VARCHAR   — e.g. "Federal Reserve System", "Trump"
#   count      INTEGER   — mentions that month (annual / 12 for subjects.json)
#   source     VARCHAR   — "tedalcorn_subjects" | "tedalcorn_presidents" | "tedalcorn_volume"
#   fetched_at TIMESTAMP — when this file was processed
#
# Granularity note:
#   subjects.json has ANNUAL counts only. These are spread evenly across 12
#   months (annual / 12, rounded). For monthly granularity use presidents.json
#   (actual monthly counts) or dashboard.json articles_per_month (total volume).

library(dplyr)
library(tidyr)
library(jsonlite)
library(arrow)
library(cli)

# ── Configuration ──────────────────────────────────────────────────────────────

SOURCE_DIR  <- "/tmp/tedalcorn-nyt"
OUTPUT_PATH <- here::here("data/raw/nyt_keywords.parquet")

SUBJECTS_URL   <- "https://raw.githubusercontent.com/tedalcorn/nyt/main/subjects.json"
DASHBOARD_URL  <- "https://raw.githubusercontent.com/tedalcorn/nyt/main/dashboard.json"
PRESIDENTS_URL <- "https://raw.githubusercontent.com/tedalcorn/nyt/main/presidents.json"

# Regex patterns for named entities related to financial/economic topics.
# subjects.json contains named entities (persons/organizations), not topical keywords.
# These patterns match organizations that are about those economic domains.
ECONOMY_PATTERNS <- c(
  "federal reserve",    # e.g. "Federal Reserve System", "Federal Reserve Board"
  "stock exchange",     # e.g. "New York Stock Exchange", "London Stock Exchange"
  "stock market",       # e.g. "Nasdaq Stock Market"
  "wall street",        # e.g. "Wall Street Journal", "Occupy Wall Street"
  "housing",            # e.g. "Housing and Urban Development Department"
  "budget",             # e.g. "Congressional Budget Office", "Office of Management and Budget"
  "oil",                # e.g. "Lukoil", "China National Offshore Oil", though noisy
  "treasury",           # e.g. "Treasury Department"
  "securities",         # e.g. "Securities and Exchange Commission"
  "exchange commission",
  "world bank",
  "international monetary fund",
  "bank of england",
  "european central bank",
  "goldman sachs",
  "jpmorgan",
  "morgan stanley",
  "citigroup",
  "bank of america",
  "lehman brothers"
)

# ── Helpers ────────────────────────────────────────────────────────────────────

#' Ensure a JSON file exists, downloading if necessary.
#' @param local_path Local file path
#' @param url Remote URL to download from
ensure_file <- function(local_path, url) {
  if (!file.exists(local_path)) {
    cli::cli_alert_info("Downloading {basename(local_path)} from {url}")
    dir.create(dirname(local_path), recursive = TRUE, showWarnings = FALSE)
    result <- tryCatch(
      download.file(url, local_path, method = "curl", quiet = FALSE),
      error = function(e) {
        cli::cli_abort("Failed to download {url}: {e$message}")
      }
    )
    if (!file.exists(local_path)) {
      cli::cli_abort("Download appeared to succeed but {local_path} not found.")
    }
    cli::cli_alert_success("Downloaded {basename(local_path)} ({fs::file_size(local_path)})")
  } else {
    cli::cli_alert_info("Using cached {basename(local_path)} ({fs::file_size(local_path)})")
  }
  invisible(local_path)
}

# ── Ensure source files exist ──────────────────────────────────────────────────

subjects_path   <- file.path(SOURCE_DIR, "subjects.json")
dashboard_path  <- file.path(SOURCE_DIR, "dashboard.json")
presidents_path <- file.path(SOURCE_DIR, "presidents.json")

ensure_file(subjects_path,   SUBJECTS_URL)
ensure_file(dashboard_path,  DASHBOARD_URL)
ensure_file(presidents_path, PRESIDENTS_URL)

fetched_at <- Sys.time()

# ── 1. Parse subjects.json ─────────────────────────────────────────────────────
# Structure: list(persons = [...], organizations = [...], last_year = 2024)
# Each element: {name, total, annual: {year: count, ...}}
# Granularity: ANNUAL only. We spread evenly across 12 months.

cli::cli_h2("Parsing subjects.json")

subjects_raw <- jsonlite::fromJSON(subjects_path, simplifyDataFrame = FALSE)

# Combine persons and organizations into one list
all_subjects <- c(
  subjects_raw$persons       %||% list(),
  subjects_raw$organizations %||% list()
)

cli::cli_alert_info(
  "Total subjects: {length(all_subjects)} ({length(subjects_raw$persons)} persons, ",
  "{length(subjects_raw$organizations)} orgs)"
)

# Filter to subjects matching economy patterns (case-insensitive regex)
matches_keyword <- function(name) {
  name_lower <- tolower(name)
  any(vapply(ECONOMY_PATTERNS, function(pat) grepl(pat, name_lower, perl = TRUE), logical(1)))
}

filtered_subjects <- Filter(function(s) matches_keyword(s$name), all_subjects)

cli::cli_alert_info(
  "Matched {length(filtered_subjects)} subjects containing economy keywords"
)

# Expand annual counts to monthly rows (count = floor(annual / 12))
# First month of the year gets the remainder so annual total is preserved.
expand_subject_to_monthly <- function(s) {
  annual_map <- s$annual
  if (is.null(annual_map) || length(annual_map) == 0) return(NULL)

  years <- as.integer(names(annual_map))
  counts <- as.integer(unlist(annual_map))

  rows <- lapply(seq_along(years), function(i) {
    yr  <- years[i]
    ann <- counts[i]
    if (is.na(ann) || ann == 0L) return(NULL)

    base_count <- ann %/% 12L
    remainder  <- ann %% 12L

    lapply(1:12, function(m) {
      # Give remainder to January (first month)
      monthly_count <- if (m == 1L) base_count + remainder else base_count
      list(
        date    = as.Date(sprintf("%d-%02d-01", yr, m)),
        keyword = s$name,
        count   = monthly_count
      )
    })
  })

  rows <- Filter(Negate(is.null), rows)
  rows <- unlist(rows, recursive = FALSE)
  rows <- Filter(Negate(is.null), rows)
  rows
}

subject_rows <- lapply(filtered_subjects, expand_subject_to_monthly)
subject_rows <- unlist(subject_rows, recursive = FALSE)
subject_rows <- Filter(Negate(is.null), subject_rows)

if (length(subject_rows) == 0) {
  cli::cli_warn("No subject rows extracted — subjects.json may be empty or keywords unmatched")
  subjects_tbl <- tibble(
    date       = as.Date(character()),
    keyword    = character(),
    count      = integer(),
    source     = character(),
    fetched_at = as.POSIXct(character())
  )
} else {
  subjects_tbl <- dplyr::bind_rows(lapply(subject_rows, function(r) {
    tibble(
      date    = r$date,
      keyword = r$keyword,
      count   = as.integer(r$count)
    )
  })) |>
    filter(count > 0L) |>
    mutate(
      source     = "tedalcorn_subjects",
      fetched_at = fetched_at
    )

  cli::cli_alert_success(
    "subjects.json: {nrow(subjects_tbl)} monthly rows from {n_distinct(subjects_tbl$keyword)} keywords"
  )
}

# ── 2. Parse dashboard.json (articles_per_month) ──────────────────────────────
# Structure: articles_per_month is an array of {month: "YYYY-MM", count: N, ...}
# This gives total article VOLUME — used as a normalisation denominator.

cli::cli_h2("Parsing dashboard.json (articles_per_month)")

dashboard_raw <- jsonlite::fromJSON(dashboard_path, simplifyDataFrame = FALSE)

apm <- dashboard_raw$articles_per_month

if (is.null(apm) || length(apm) == 0) {
  cli::cli_warn("articles_per_month not found in dashboard.json")
  volume_tbl <- tibble(
    date       = as.Date(character()),
    keyword    = character(),
    count      = integer(),
    source     = character(),
    fetched_at = as.POSIXct(character())
  )
} else {
  volume_tbl <- dplyr::bind_rows(lapply(apm, function(row) {
    tibble(
      date    = as.Date(paste0(row$month, "-01")),
      keyword = "TOTAL_ARTICLES",
      count   = as.integer(row$count)
    )
  })) |>
    mutate(
      source     = "tedalcorn_volume",
      fetched_at = fetched_at
    )

  cli::cli_alert_success(
    "dashboard.json: {nrow(volume_tbl)} monthly total-volume rows from ",
    "{format(min(volume_tbl$date), '%Y-%m')} to {format(max(volume_tbl$date), '%Y-%m')}"
  )
}

# ── 3. Parse presidents.json ───────────────────────────────────────────────────
# Structure: {months: ["YYYY-MM", ...], Trump: [n, n, ...], Biden: [...], ...}
# Actual MONTHLY granularity — no spreading needed.

cli::cli_h2("Parsing presidents.json")

presidents_raw <- jsonlite::fromJSON(presidents_path, simplifyDataFrame = FALSE)

months_vec <- presidents_raw$months
president_names <- setdiff(names(presidents_raw), "months")

cli::cli_alert_info(
  "Presidents found: {paste(president_names, collapse = ', ')} ({length(months_vec)} months)"
)

if (length(months_vec) == 0 || length(president_names) == 0) {
  cli::cli_warn("presidents.json: no months or presidents found")
  presidents_tbl <- tibble(
    date       = as.Date(character()),
    keyword    = character(),
    count      = integer(),
    source     = character(),
    fetched_at = as.POSIXct(character())
  )
} else {
  presidents_tbl <- dplyr::bind_rows(lapply(president_names, function(pname) {
    counts <- presidents_raw[[pname]]
    if (is.null(counts) || length(counts) != length(months_vec)) {
      cli::cli_warn(
        "President {pname}: length mismatch ({length(counts)} counts vs ",
        "{length(months_vec)} months) — skipping"
      )
      return(NULL)
    }
    tibble(
      date    = as.Date(paste0(months_vec, "-01")),
      keyword = pname,
      count   = as.integer(unlist(counts))
    )
  })) |>
    filter(!is.na(count)) |>
    mutate(
      source     = "tedalcorn_presidents",
      fetched_at = fetched_at
    )

  cli::cli_alert_success(
    "presidents.json: {nrow(presidents_tbl)} monthly rows for ",
    "{n_distinct(presidents_tbl$keyword)} presidents"
  )
}

# ── 4. Combine and write parquet ───────────────────────────────────────────────

cli::cli_h2("Combining and writing parquet")

combined <- dplyr::bind_rows(subjects_tbl, presidents_tbl, volume_tbl) |>
  mutate(
    date       = as.Date(date),
    keyword    = as.character(keyword),
    count      = as.integer(count),
    source     = as.character(source),
    fetched_at = as.POSIXct(fetched_at)
  ) |>
  filter(!is.na(date), !is.na(keyword), !is.na(count)) |>
  arrange(source, keyword, date)

cli::cli_alert_info(
  "Combined: {nrow(combined)} rows | ",
  "{n_distinct(combined$keyword)} keywords | ",
  "{n_distinct(combined$source)} sources | ",
  "date range: {format(min(combined$date), '%Y-%m')} to {format(max(combined$date), '%Y-%m')}"
)

dir.create(dirname(OUTPUT_PATH), recursive = TRUE, showWarnings = FALSE)

arrow::write_parquet(combined, OUTPUT_PATH, compression = "zstd")

file_size <- fs::file_size(OUTPUT_PATH)
cli::cli_alert_success(
  "Written: {OUTPUT_PATH} ({file_size}) — {nrow(combined)} rows"
)

# ── 5. Verification summary ────────────────────────────────────────────────────

cli::cli_h2("Verification summary")

check <- arrow::read_parquet(OUTPUT_PATH)
cli::cli_ul(c(
  "Rows:     {nrow(check)}",
  "Keywords: {n_distinct(check$keyword)}",
  "Sources:  {paste(unique(check$source), collapse = ', ')}",
  "Date min: {min(check$date)}",
  "Date max: {max(check$date)}"
))

cli::cli_alert_success("parse_nyt_tedalcorn.R complete.")
