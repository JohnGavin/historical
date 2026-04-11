# Fetch Fama-French factor returns directly from Ken French's website
#
# Downloads FF3 daily, FF5 daily, and Momentum daily.
# Free, no API key, academic gold standard (1926+).
#
# Usage:
#   Rscript scripts/fetch_factors.R

library(dplyr)
library(tidyr)
library(arrow)

DATASETS <- list(
  list(
    url = "https://mba.tuck.dartmouth.edu/pages/faculty/ken.french/ftp/F-F_Research_Data_Factors_daily_CSV.zip",
    dataset = "FF3",
    frequency = "daily"
  ),
  list(
    url = "https://mba.tuck.dartmouth.edu/pages/faculty/ken.french/ftp/F-F_Research_Data_5_Factors_2x3_daily_CSV.zip",
    dataset = "FF5",
    frequency = "daily"
  ),
  list(
    url = "https://mba.tuck.dartmouth.edu/pages/faculty/ken.french/ftp/F-F_Momentum_Factor_daily_CSV.zip",
    dataset = "Mom",
    frequency = "daily"
  ),
  list(
    url = "https://mba.tuck.dartmouth.edu/pages/faculty/ken.french/ftp/F-F_Research_Data_Factors_CSV.zip",
    dataset = "FF3",
    frequency = "monthly"
  ),
  list(
    url = "https://mba.tuck.dartmouth.edu/pages/faculty/ken.french/ftp/F-F_Research_Data_5_Factors_2x3_CSV.zip",
    dataset = "FF5",
    frequency = "monthly"
  ),
  list(
    url = "https://mba.tuck.dartmouth.edu/pages/faculty/ken.french/ftp/F-F_Momentum_Factor_CSV.zip",
    dataset = "Mom",
    frequency = "monthly"
  )
)

parse_french_csv <- function(url, dataset_name, frequency) {
  tmp <- tempfile(fileext = ".zip")
  tryCatch({
    download.file(url, tmp, quiet = TRUE)
    csv_file <- unzip(tmp, exdir = tempdir())[1]
    lines <- readLines(csv_file)

    # Find the header row (first row with "Mkt" or "Mom" in it)
    header_idx <- grep("Mkt|Mom", lines)[1]
    if (is.na(header_idx)) {
      cli::cli_warn("No header found in {dataset_name} {frequency}")
      return(NULL)
    }

    # Read from header row, skip anything after blank lines (annual data etc.)
    data_lines <- lines[header_idx:length(lines)]
    # Find first blank/non-data line after header
    end_idx <- which(trimws(data_lines) == "" | grepl("^\\s*[A-Za-z]", data_lines))
    end_idx <- end_idx[end_idx > 1]
    if (length(end_idx) > 0) {
      data_lines <- data_lines[1:(end_idx[1] - 1)]
    }

    df <- read.csv(textConnection(paste(data_lines, collapse = "\n")),
                   strip.white = TRUE, check.names = FALSE)
    names(df)[1] <- "date_raw"

    # Parse date: daily = YYYYMMDD, monthly = YYYYMM
    df <- df |>
      mutate(
        date_raw = trimws(as.character(date_raw)),
        date = if (frequency == "daily") {
          as.Date(date_raw, format = "%Y%m%d")
        } else {
          as.Date(paste0(date_raw, "01"), format = "%Y%m%d")
        }
      ) |>
      filter(!is.na(date))

    # Pivot to long
    factor_cols <- setdiff(names(df), c("date_raw", "date"))
    long <- df |>
      select(-date_raw) |>
      tidyr::pivot_longer(
        cols = all_of(factor_cols),
        names_to = "factor_name",
        values_to = "value"
      ) |>
      mutate(
        value = as.double(value),
        dataset = dataset_name,
        frequency = frequency,
        source = "french"
      )

    cli::cli_inform(c("v" = "  {dataset_name} {frequency}: {nrow(long)} obs, {length(factor_cols)} factors, {min(long$date)} to {max(long$date)}"))
    long
  }, error = function(e) {
    cli::cli_warn("  FAILED {dataset_name} {frequency}: {conditionMessage(e)}")
    NULL
  })
}

cli::cli_h1("Fetching {length(DATASETS)} French factor datasets")

all_data <- lapply(DATASETS, function(ds) {
  Sys.sleep(1)
  parse_french_csv(ds$url, ds$dataset, ds$frequency)
})

combined <- bind_rows(Filter(Negate(is.null), all_data))
dir.create("data/raw", recursive = TRUE, showWarnings = FALSE)
out_path <- "data/raw/french_factors.parquet"
arrow::write_parquet(combined, out_path, compression = "zstd")

cli::cli_h2("Summary")
cli::cli_inform(c(
  "v" = "Total: {nrow(combined)} obs, {n_distinct(combined$factor_name)} factors",
  "i" = "Datasets: {paste(unique(combined$dataset), collapse = ', ')}",
  "i" = "Date range: {min(combined$date)} to {max(combined$date)}",
  "i" = "File: {out_path} ({round(file.info(out_path)$size / 1e3)} KB)"
))
