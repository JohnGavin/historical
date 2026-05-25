#!/usr/bin/env Rscript
# Fetch and parse AQR "Commodities for the Long Run" index data (#280)
#
# Source: Levine, Ooi, Richardson & Sasseville (2018), FAJ 74(2): 55-68
# Data:   AQR Insights — Commodities for the Long Run: Index Level Data, Monthly
# URL:    https://www.aqr.com/Insights/Datasets/Commodities-for-the-Long-Run-Index-Level-Data-Monthly
# Excel:  https://www.aqr.com/-/media/AQR/Documents/Insights/Data-Sets/Commodities-for-the-Long-Run-Index-Level-Data-Monthly.xlsx
#
# Coverage: 1877-02 through ~present (monthly, equal-weight collateralised futures)
#
# Output: data/raw/commodities_long_run.parquet
# Columns:
#   date             Date   — end-of-month date
#   ret_ew           dbl    — excess return, equal-weight commodities portfolio (decimal)
#   ret_spot_ew      dbl    — excess spot return, equal-weight portfolio (decimal)
#   carry_ir_ew      dbl    — interest rate adjusted carry, equal-weight portfolio
#   ret_spot_raw_ew  dbl    — spot return (total, not excess), equal-weight portfolio
#   carry_ew         dbl    — carry (roll yield), equal-weight portfolio
#   ret_ls           dbl    — excess return, long/short (backwardation/contango) portfolio
#   ret_spot_ls      dbl    — excess spot return, long/short portfolio
#   carry_ir_ls      dbl    — interest rate adjusted carry, long/short portfolio
#   state            chr    — "Backwardation" / "Contango" / NA
#
# Usage: Rscript scripts/fetch_commodities_long_run.R [path/to/existing.xlsx]
#   If an xlsx path is given, it skips the download and uses that file.

suppressPackageStartupMessages({
  library(readxl)
  library(dplyr)
  library(arrow)
  library(cli)
})

WORKTREE <- here::here()
RAW_DIR  <- file.path(WORKTREE, "data", "raw")
OUT_PATH <- file.path(RAW_DIR, "commodities_long_run.parquet")
XLSX_URL <- paste0(
  "https://www.aqr.com/-/media/AQR/Documents/Insights/Data-Sets/",
  "Commodities-for-the-Long-Run-Index-Level-Data-Monthly.xlsx?sc_lang=en"
)
XLSX_LOCAL <- file.path(RAW_DIR, "aqr_commodities_long_run.xlsx")

cli_h1("AQR Commodities for the Long Run — fetch & parse (#280)")

# ── 1. Locate or download the Excel file ─────────────────────────────────────

args <- commandArgs(trailingOnly = TRUE)
if (length(args) > 0 && file.exists(args[1])) {
  xlsx_path <- args[1]
  cli_inform(c("i" = "Using provided file: {.path {xlsx_path}}"))
} else if (file.exists(XLSX_LOCAL)) {
  xlsx_path <- XLSX_LOCAL
  cli_inform(c("i" = "Found cached file: {.path {xlsx_path}}"))
} else {
  cli_inform(c("i" = "Downloading AQR Excel from {.url {XLSX_URL}}"))
  dir.create(RAW_DIR, recursive = TRUE, showWarnings = FALSE)
  resp <- tryCatch(
    download.file(
      url     = XLSX_URL,
      destfile = XLSX_LOCAL,
      method   = "curl",
      extra    = c(
        "--user-agent",
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
        "-L"
      ),
      quiet = FALSE
    ),
    error = function(e) e
  )
  if (inherits(resp, "error") || !file.exists(XLSX_LOCAL) || file.size(XLSX_LOCAL) < 1000) {
    cli_abort(c(
      "x" = "Download failed or file too small.",
      "i" = "Error: {conditionMessage(resp)}",
      "i" = "Hard rule: STOP — never fabricate or substitute data. Resolve manually.",
      "i" = "Manual step: download from {.url https://www.aqr.com/Insights/Datasets/Commodities-for-the-Long-Run-Index-Level-Data-Monthly}"
    ))
  }
  cli_inform(c("v" = "Downloaded: {.path {XLSX_LOCAL}} ({round(file.size(XLSX_LOCAL)/1e3)} KB)"))
  xlsx_path <- XLSX_LOCAL
}

sz_kb <- round(file.size(xlsx_path) / 1e3)
cli_inform(c("i" = "File size: {sz_kb} KB"))
if (sz_kb < 100) {
  cli_abort("File appears too small ({sz_kb} KB) — likely a download error or HTML error page.")
}

# ── 2. Inspect sheets ─────────────────────────────────────────────────────────

sheets <- excel_sheets(xlsx_path)
cli_inform(c("i" = "Sheets: {paste(sheets, collapse = ', ')}"))
stopifnot("Commodities for the Long Run" %in% sheets)

# ── 3. Read the data sheet ────────────────────────────────────────────────────
# The sheet has:
#   - Rows 1-10: header/metadata text
#   - Row 11: column names
#   - Rows 12+: data rows, mixed with summary rows ("Inflation Up/Down", "Backwardation")
#
# readxl behaviour:
#   - Dates stored as text (pre-1900, YYYY-MM-DD strings) come through as character
#   - Dates stored as Excel serials (post-1900) come through as Date when col_types
#     specifies "date", but since the column is mixed (text + serial), we read as
#     "text" and parse manually.

cli_inform(c("i" = "Reading sheet 'Commodities for the Long Run'..."))

raw <- read_excel(
  xlsx_path,
  sheet    = "Commodities for the Long Run",
  skip     = 10,         # skip rows 1-10 (metadata), row 11 becomes col names
  col_names = TRUE,
  col_types = "text",    # read everything as text to handle mixed date column
  .name_repair = "minimal"
)

cli_inform(c("i" = "Raw dimensions: {nrow(raw)} rows x {ncol(raw)} cols"))
cli_inform(c("i" = "Column names: {paste(names(raw)[1:min(12, ncol(raw))], collapse = ' | ')}"))

# Rename columns to safe names
# Col 1 is date, cols 2-10 are numeric series, col 11 is backwardation/contango state, col 12 aggregates
colnames(raw)[1] <- "date_raw"
if (ncol(raw) >= 2)  colnames(raw)[2]  <- "ret_ew"
if (ncol(raw) >= 3)  colnames(raw)[3]  <- "ret_spot_ew"
if (ncol(raw) >= 4)  colnames(raw)[4]  <- "carry_ir_ew"
if (ncol(raw) >= 5)  colnames(raw)[5]  <- "ret_spot_raw_ew"
if (ncol(raw) >= 6)  colnames(raw)[6]  <- "carry_ew"
if (ncol(raw) >= 7)  colnames(raw)[7]  <- "ret_ls"
if (ncol(raw) >= 8)  colnames(raw)[8]  <- "ret_spot_ls"
if (ncol(raw) >= 9)  colnames(raw)[9]  <- "carry_ir_ls"
if (ncol(raw) >= 11) colnames(raw)[11] <- "state"

# ── 4. Parse dates and filter to valid data rows ──────────────────────────────
# Valid data rows have a date in column 1, either:
#   (a) ISO text "YYYY-MM-DD" (pre-1900 dates stored as shared strings)
#   (b) Numeric string representing an Excel serial (post-1900)
#
# Non-data rows: "Inflation Up", "Inflation Down", "Backwardation", empty, text headers

parse_date_col <- function(x) {
  # Try ISO text first
  iso_pat <- grepl("^\\d{4}-\\d{2}-\\d{2}$", x, perl = TRUE)
  # Try numeric serial (integer-like)
  num_pat <- grepl("^\\d+$", x, perl = TRUE)

  result <- as.Date(rep(NA, length(x)))

  # ISO text dates
  result[iso_pat] <- as.Date(x[iso_pat])

  # Excel serial dates (epoch = 1899-12-30)
  if (any(num_pat)) {
    serials  <- as.integer(x[num_pat])
    result[num_pat] <- as.Date("1899-12-30") + serials
  }

  result
}

cli_inform(c("i" = "Parsing date column and filtering non-data rows..."))

parsed <- raw |>
  mutate(
    date = parse_date_col(date_raw)
  ) |>
  filter(!is.na(date))

cli_inform(c("i" = "Rows with valid date: {nrow(parsed)}"))

# ── 5. Parse numeric columns and drop all-NA rows ────────────────────────────

numeric_cols <- c(
  "ret_ew", "ret_spot_ew", "carry_ir_ew", "ret_spot_raw_ew", "carry_ew",
  "ret_ls", "ret_spot_ls", "carry_ir_ls"
)

# Only keep numeric cols that exist
numeric_cols <- numeric_cols[numeric_cols %in% names(parsed)]

tidy <- parsed |>
  mutate(across(all_of(numeric_cols), ~ {
    x_num <- suppressWarnings(as.numeric(.x))
    x_num
  })) |>
  # Preserve state column if present
  mutate(
    state = if ("state" %in% names(parsed)) .data$state else NA_character_
  ) |>
  select(date, all_of(numeric_cols), state) |>
  # Filter out rows where ALL numeric cols are NA
  filter(
    rowSums(!is.na(across(all_of(numeric_cols)))) > 0
  ) |>
  arrange(date)

cli_inform(c("i" = "Rows after filtering all-NA: {nrow(tidy)}"))

# ── 6. Validate ───────────────────────────────────────────────────────────────

n_rows <- nrow(tidy)
min_date <- min(tidy$date)
max_date <- max(tidy$date)

if (n_rows < 1000) {
  cli_abort("Row count {n_rows} < 1000 — data parse may have failed.")
}
if (as.integer(format(min_date, "%Y")) > 1880) {
  cli_abort("Earliest date {min_date} is after 1880 — expected data from ~1877.")
}

na_frac <- colMeans(is.na(tidy[numeric_cols]))
bad_cols <- names(na_frac[na_frac > 0.99])
if (length(bad_cols) > 0) {
  cli_abort("Columns with >99% NA: {paste(bad_cols, collapse = ', ')}")
}

cli_h2("Validation passed")
cli_inform(c(
  "v" = "Rows:       {n_rows}",
  "v" = "Date range: {min_date} to {max_date}",
  "v" = "Years:      ~{round(as.numeric(max_date - min_date) / 365.25, 1)}"
))

# ── 7. Write parquet ──────────────────────────────────────────────────────────

dir.create(RAW_DIR, recursive = TRUE, showWarnings = FALSE)
arrow::write_parquet(tidy, OUT_PATH, compression = "zstd")

sz_out <- round(file.size(OUT_PATH) / 1e3)
cli_inform(c("v" = "Written: {.path {OUT_PATH}} ({sz_out} KB)"))

# Summary table
cli_h2("Column NA summary")
for (col in numeric_cols) {
  n_na  <- sum(is.na(tidy[[col]]))
  n_ok  <- n_rows - n_na
  pct   <- round(100 * n_na / n_rows, 1)
  cli_inform(c("i" = "{col}: {n_ok} valid, {n_na} NA ({pct}%)"))
}
