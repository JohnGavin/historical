#!/usr/bin/env Rscript
# Pre-compute LTR momentum features outside targets pipeline.
# Saves to data/raw/ltr_features.parquet.
#
# Memory-intensive: processes 530 US equities × ~8K days each
# in chunks of 50 tickers to limit peak memory.
#
# Usage: Rscript scripts/compute_ltr_features.R

suppressPackageStartupMessages({
  library(dplyr)
  library(arrow)
  library(cli)
})

# Bootstrap slider from nix store
if (!requireNamespace("slider", quietly = TRUE)) {
  paths <- Sys.glob("/nix/store/*-r-slider-*/library")
  paths <- paths[file.exists(file.path(paths, "slider"))]
  if (length(paths) > 0) .libPaths(c(.libPaths(), paths[[1]]))
}

pkgload::load_all(
  file.path(here::here(), "packages/historicaldata"),
  quiet = TRUE
)

# ── Fetch US equities ───────────────────────────────────────────
cli_h1("LTR Feature Computation")

ds <- hd_datasets()[["equity_daily"]]
con <- hd_connect()
all_data <- DBI::dbGetQuery(con, sprintf(
  "SELECT date, ticker, adjusted, volume FROM read_parquet('%s') WHERE ticker NOT LIKE '%%.%%' ORDER BY ticker, date",
  ds$url
))
DBI::dbDisconnect(con, shutdown = TRUE)

cli_inform(c("v" = "{length(unique(all_data$ticker))} US tickers, {nrow(all_data)} rows"))

# Filter to tickers with >= 252 days
min_history <- 252L
ticker_counts <- all_data |>
  count(ticker) |>
  filter(n >= min_history)
all_data <- all_data |> filter(ticker %in% ticker_counts$ticker)
cli_inform(c("v" = "{length(unique(all_data$ticker))} tickers with >= {min_history} days"))

# ── Compute daily returns ────────────────────────────────────────
daily <- all_data |>
  arrange(ticker, date) |>
  group_by(ticker) |>
  mutate(
    daily_ret = adjusted / lag(adjusted) - 1,
    log_vol = log(pmax(volume, 1))
  ) |>
  filter(!is.na(daily_ret)) |>
  ungroup()

rm(all_data); gc(verbose = FALSE)

# ── Month-end dates ──────────────────────────────────────────────
month_ends <- daily |>
  mutate(ym = format(date, "%Y-%m")) |>
  group_by(ticker, ym) |>
  filter(date == max(date)) |>
  ungroup() |>
  select(ticker, date, ym)

# ── Feature computation helpers ──────────────────────────────────
compute_window_return <- function(ret, n) {
  slider::slide_dbl(ret, function(r) prod(1 + r) - 1,
                    .before = n - 1L, .complete = TRUE)
}

compute_rolling_vol <- function(ret, n) {
  slider::slide_dbl(ret, function(r) if (length(r) < 5) NA_real_ else sd(r) * sqrt(252),
                    .before = n - 1L, .complete = TRUE)
}

compute_rolling_mean <- function(x, n) {
  slider::slide_dbl(x, mean, .before = n - 1L, .complete = TRUE)
}

compute_ticker_features <- function(tk, daily_df) {
  d <- daily_df |> filter(ticker == tk) |> arrange(date)
  if (nrow(d) < min_history) return(NULL)

  ret <- d$daily_ret
  lvol <- d$log_vol

  r1   <- compute_window_return(ret, 1L)
  r5   <- compute_window_return(ret, 5L)
  r10  <- compute_window_return(ret, 10L)
  r21  <- compute_window_return(ret, 21L)
  r63  <- compute_window_return(ret, 63L)
  r126 <- compute_window_return(ret, 126L)
  r252 <- compute_window_return(ret, 252L)

  v21 <- compute_rolling_vol(ret, 21L)
  v63 <- compute_rolling_vol(ret, 63L)

  mv21 <- compute_rolling_mean(lvol, 21L)
  mv63 <- compute_rolling_mean(lvol, 63L)

  tibble::tibble(
    ticker = tk, date = d$date,
    ret_1d = r1, ret_5d = r5, ret_10d = r10, ret_21d = r21,
    ret_63d = r63, ret_126d = r126, ret_252d = r252,
    nret_1d = r1 / pmax(v21 / sqrt(252), 1e-8),
    nret_5d = r5 / pmax(v21 / sqrt(252) * sqrt(5), 1e-8),
    nret_10d = r10 / pmax(v21 / sqrt(252) * sqrt(10), 1e-8),
    nret_21d = r21 / pmax(v21, 1e-8),
    nret_63d = r63 / pmax(v21, 1e-8),
    nret_126d = r126 / pmax(v21, 1e-8),
    mom_1_3 = r21 - r63, mom_3_6 = r63 - r126,
    mom_1_6 = r21 - r126, mom_6_12 = r126 - r252,
    vol_21d = v21, vol_63d = v63,
    vol_ratio = pmin(pmax(v21 / pmax(v63, 1e-8), 0.1), 10),
    turnover_21d = pmin(pmax(mv21 / pmax(mv63, 1e-8), 0.1), 10),
    size_rank = mv63
  )
}

# ── Process in chunks ────────────────────────────────────────────
tickers <- unique(daily$ticker)
chunk_size <- 50L
n_chunks <- ceiling(length(tickers) / chunk_size)
cli_inform(c("i" = "Computing features for {length(tickers)} tickers in {n_chunks} chunks"))

all_features <- vector("list", n_chunks)
for (i in seq_len(n_chunks)) {
  idx_s <- (i - 1L) * chunk_size + 1L
  idx_e <- min(i * chunk_size, length(tickers))
  chunk_tks <- tickers[idx_s:idx_e]

  cli_inform(c("i" = "  Chunk {i}/{n_chunks}: {length(chunk_tks)} tickers"))
  results <- lapply(chunk_tks, compute_ticker_features, daily_df = daily)
  all_features[[i]] <- bind_rows(Filter(Negate(is.null), results))
  rm(results); gc(verbose = FALSE)
}

daily_features <- bind_rows(all_features)
rm(all_features); gc(verbose = FALSE)
cli_inform(c("v" = "Daily features: {nrow(daily_features)} rows"))

# ── Extract month-end features + next-month return ───────────────
month_end_features <- month_ends |>
  inner_join(daily_features, by = c("ticker", "date")) |>
  arrange(ticker, ym)

rm(daily_features, daily); gc(verbose = FALSE)

# Next-month return: use adjusted prices at month-end to compute
# forward return = adjusted[m+1] / adjusted[m] - 1
# Fetch month-end adjusted prices via DuckDB (not loading full dataset)
con2 <- hd_connect()
adj_eom_prices <- DBI::dbGetQuery(con2, sprintf(
  "WITH monthly AS (
     SELECT ticker, date, adjusted,
            date_trunc('month', date) AS month_start
     FROM read_parquet('%s')
     WHERE ticker NOT LIKE '%%.%%'
   ),
   eom AS (
     SELECT ticker, MAX(date) AS date, month_start
     FROM monthly GROUP BY ticker, month_start
   )
   SELECT m.ticker, m.date, m.adjusted
   FROM monthly m INNER JOIN eom e
   ON m.ticker = e.ticker AND m.date = e.date
   ORDER BY m.ticker, m.date",
  ds$url))
DBI::dbDisconnect(con2, shutdown = TRUE)

adj_eom <- month_end_features |>
  left_join(
    adj_eom_prices |>
      mutate(ym = format(date, "%Y-%m")) |>
      select(ticker, ym, adjusted),
    by = c("ticker", "ym")
  ) |>
  group_by(ticker) |>
  arrange(ym) |>
  mutate(next_ret = lead(adjusted) / adjusted - 1) |>
  ungroup()

rm(adj_eom_prices); gc(verbose = FALSE)

# t+1: lag features by 1 month
final <- adj_eom |>
  group_by(ticker) |>
  arrange(ym) |>
  mutate(across(
    c(starts_with("ret_"), starts_with("nret_"), starts_with("mom_"),
      starts_with("vol_"), turnover_21d, size_rank),
    lag
  )) |>
  ungroup() |>
  filter(!is.na(next_ret), !is.na(ret_21d))

# ── Write parquet ────────────────────────────────────────────────
dir.create("data/raw", recursive = TRUE, showWarnings = FALSE)
out_path <- "data/raw/ltr_features.parquet"
arrow::write_parquet(final, out_path, compression = "zstd")

cli_h2("Summary")
cli_inform(c(
  "v" = "{nrow(final)} rows, {length(unique(final$ticker))} tickers",
  "i" = "Date range: {min(final$date)} to {max(final$date)}",
  "i" = "File: {out_path} ({round(file.info(out_path)$size / 1e6, 1)} MB)"
))
