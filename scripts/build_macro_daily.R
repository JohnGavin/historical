# Build data/raw/macro_daily.parquet from its three components (#619).
#
# Usage:
#   Rscript scripts/build_macro_daily.R
#
# The served dataset hf://datasets/JohnGavin/finance-data/macro_daily.parquet
# is what historicaldata::hd_macro() reads. It was seeded once on 2026-05-06 by
# duplicating an upstream HF repo and never regenerated, leaving it frozen at
# 2026-04-20 — see #619. Nothing in this repo produced it.
#
# The three fetch scripts that between them cover the whole dataset already
# exist and already write compatible parquets; only the combine step was
# missing:
#
#   scripts/fetch_macro.R     -> data/raw/fred_macro.parquet   (27 FRED)
#   scripts/fetch_cboe_vol.R  -> data/raw/cboe_vol.parquet     (46 CBOE)
#   scripts/fetch_intl_vol.R  -> data/raw/intl_vol.parquet     (5 international)
#
# All three emit the same schema — date, value, series_id, source — which is
# also the served schema, so this is a concatenation and not a transformation.
#
# Publishing is deliberately NOT done here. See scripts/upload_hf.sh.

suppressMessages({
  library(dplyr)
  library(arrow)
})

RAW <- here::here("data", "raw")

# component -> expected series count, from the upstream commit that last
# described the composition: "78 series (27 FRED + 46 CBOE + 5 international
# implied vol)". Used as a sanity check, not a hard gate — a component that
# legitimately gains or loses a series should warn, not fail the build.
COMPONENTS <- tibble::tribble(
  ~file,                 ~label,           ~expect_series,
  "fred_macro.parquet",  "FRED",            27L,
  "cboe_vol.parquet",    "CBOE",            46L,
  "intl_vol.parquet",    "international",    5L
)

read_component <- function(file, label, expect_series) {
  path <- file.path(RAW, file)
  if (!file.exists(path)) {
    cli::cli_abort(c(
      "x" = "Missing component: {.path {path}} ({label}).",
      "i" = "Run the matching fetch script first; see this file's header."
    ))
  }

  d <- arrow::read_parquet(path)

  required <- c("date", "value", "series_id", "source")
  missing <- setdiff(required, names(d))
  if (length(missing) > 0L) {
    cli::cli_abort(c(
      "x" = "{.path {file}} is missing column{?s} {.field {missing}}.",
      "i" = "All components must share the served schema: {.field {required}}."
    ))
  }

  # Date-type consistency. hd_ohlcv/hd_macro disagreeing on this is #615; do
  # not let a component reintroduce it here.
  if (!inherits(d$date, "Date")) {
    cli::cli_warn(c(
      "!" = "{.path {file}}: {.field date} is {.cls {class(d$date)}}, coercing to Date.",
      "i" = "See #615 — Date vs POSIXct join keys match zero rows silently."
    ))
    d$date <- as.Date(d$date)
  }

  n_series <- dplyr::n_distinct(d$series_id)
  if (n_series != expect_series) {
    cli::cli_warn(c(
      "!" = "{label}: {n_series} series, expected {expect_series}.",
      "i" = "Composition has drifted. Confirm this is intended before publishing."
    ))
  }

  cli::cli_alert_success(
    "{label}: {nrow(d)} rows, {n_series} series, to {format(max(d$date))}"
  )
  d[required]
}

# Plain loop rather than purrr::pmap: a missing component is the most likely
# failure here, and pmap wraps the abort in a backtrace that buries the one
# line the operator needs to read.
parts <- vector("list", nrow(COMPONENTS))
for (i in seq_len(nrow(COMPONENTS))) {
  parts[[i]] <- read_component(
    COMPONENTS$file[i], COMPONENTS$label[i], COMPONENTS$expect_series[i]
  )
}
combined <- dplyr::bind_rows(parts)

# A (date, series_id) pair must be unique. Components are disjoint by
# construction, so a duplicate means two of them claim the same series —
# worth knowing about rather than silently keeping the first.
dupes <- combined |>
  dplyr::count(date, series_id) |>
  dplyr::filter(n > 1L)

if (nrow(dupes) > 0L) {
  offending <- sort(unique(dupes$series_id))
  cli::cli_warn(c(
    "!" = "{nrow(dupes)} duplicate (date, series_id) pair{?s} across components.",
    "i" = "Series affected: {.val {offending}}",
    "i" = "Keeping the first occurrence in component order (FRED, CBOE, international)."
  ))
  combined <- combined |> dplyr::distinct(date, series_id, .keep_all = TRUE)
}

combined <- combined |> dplyr::arrange(series_id, date)

out_path <- file.path(RAW, "macro_daily.parquet")
arrow::write_parquet(combined, out_path, compression = "zstd")

cli::cli_h2("macro_daily")
cli::cli_alert_success(
  "{nrow(combined)} rows, {dplyr::n_distinct(combined$series_id)} series"
)
cli::cli_alert_info("Range: {format(min(combined$date))} to {format(max(combined$date))}")
cli::cli_alert_info(
  "File: {.path {out_path}} ({round(file.size(out_path) / 1e3)} KB)"
)

# Staleness is the failure this whole issue is about; surface it at build time
# rather than waiting for dv_freshness (#617).
stale_days <- as.numeric(Sys.Date() - max(combined$date))
if (stale_days > 7) {
  cli::cli_warn(c(
    "!" = "Newest observation is {round(stale_days)} days old.",
    "i" = "Expected a few days at most. Check the component fetches actually ran."
  ))
}

cli::cli_alert_info("Publish with: bash scripts/upload_hf.sh {out_path} macro_daily.parquet")
