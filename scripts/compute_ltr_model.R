#!/usr/bin/env Rscript
# Pre-compute LTR model + portfolio outside targets pipeline.
# Must run inside nix develop (xgboost compiled for project's R).
#
# Usage:
#   nix develop . --command Rscript scripts/compute_ltr_model.R
#
# Reads: data/raw/ltr_features.parquet (from compute_ltr_features.R)
# Writes: data/raw/ltr_portfolio.parquet, data/raw/ltr_model_importance.parquet

suppressPackageStartupMessages({
  library(dplyr)
  library(arrow)
  library(cli)
  library(xgboost)
})

cli_h1("LTR Model Training + Portfolio Construction")

# ── Load features ────────────────────────────────────────────────
feat_path <- "data/raw/ltr_features.parquet"
if (!file.exists(feat_path)) {
  cli_abort("Features not found. Run: Rscript scripts/compute_ltr_features.R")
}
feat <- read_parquet(feat_path)
cli_inform(c("v" = "Features: {nrow(feat)} rows, {n_distinct(feat$ticker)} tickers"))

# ── Parameters ───────────────────────────────────────────────────
train_years <- 10L
min_stocks <- 30L
n_quantiles <- 10L
cost_per_trade <- 0.0010  # 10bps
borrow_cost_annual <- 0.03  # 3% for shorts
oos_start <- as.Date("2020-01-01")

xgb_params <- list(
  objective = "rank:pairwise",
  eval_metric = "ndcg",
  max_depth = 5L,
  eta = 0.1,
  nthread = 2L
)
nrounds <- 200L

feature_cols <- c(
  "ret_1d", "ret_5d", "ret_10d", "ret_21d", "ret_63d", "ret_126d",
  "nret_1d", "nret_5d", "nret_10d", "nret_21d", "nret_63d", "nret_126d",
  "mom_1_3", "mom_3_6", "mom_1_6",
  "vol_21d", "vol_63d", "vol_ratio", "turnover_21d", "size_rank"
)

# ── Walk-forward: expanding window, retrain annually ──────────────
all_months <- sort(unique(feat$ym))
# Start predictions from 2005 (need 10+ years of training data)
start_predict <- "2005-01"
predict_months <- all_months[all_months >= start_predict]
years_to_predict <- unique(substr(predict_months, 1, 4))

cli_inform(c("i" = "Walk-forward: {length(years_to_predict)} years from {min(years_to_predict)}"))

all_predictions <- vector("list", length(years_to_predict))
all_importance <- vector("list", length(years_to_predict))

for (yi in seq_along(years_to_predict)) {
  yr <- years_to_predict[yi]
  year_months <- predict_months[substr(predict_months, 1, 4) == yr]

  # Training data: all months before this year
  train_cutoff <- paste0(yr, "-01")
  train_data <- feat |>
    filter(ym < train_cutoff, !is.na(next_ret)) |>
    filter(!is.na(ret_21d), !is.na(vol_21d))

  if (nrow(train_data) < 1000) {
    cli_inform(c("!" = "  Year {yr}: only {nrow(train_data)} training rows, skipping"))
    next
  }

  # Prepare XGBoost DMatrix
  train_mat <- as.matrix(train_data[feature_cols])
  train_mat[is.na(train_mat)] <- 0
  train_groups <- train_data |> count(ym) |> pull(n)

  dtrain <- xgb.DMatrix(data = train_mat, label = train_data$next_ret)
  setinfo(dtrain, "group", as.integer(train_groups))

  # Train model
  model <- xgb.train(
    params = xgb_params,
    data = dtrain,
    nrounds = nrounds,
    verbose = 0
  )

  # Feature importance (save per year for stability analysis)
  imp <- xgb.importance(model = model)
  imp$year <- yr
  all_importance[[yi]] <- imp

  # Predict for each month in this year
  year_preds <- lapply(year_months, function(m) {
    test_data <- feat |>
      filter(ym == m, !is.na(next_ret)) |>
      filter(!is.na(ret_21d), !is.na(vol_21d))

    if (nrow(test_data) < min_stocks) return(NULL)

    test_mat <- as.matrix(test_data[feature_cols])
    test_mat[is.na(test_mat)] <- 0

    preds <- predict(model, test_mat)
    test_data$predicted_rank <- preds
    test_data |> select(ticker, ym, date, next_ret, predicted_rank)
  })

  all_predictions[[yi]] <- bind_rows(Filter(Negate(is.null), year_preds))
  cli_inform(c("v" = "  Year {yr}: {nrow(train_data)} train rows -> {nrow(all_predictions[[yi]])} predictions"))
}

predictions <- bind_rows(Filter(Negate(is.null), all_predictions))
importance <- bind_rows(Filter(Negate(is.null), all_importance))

cli_inform(c("v" = "Total predictions: {nrow(predictions)} rows, {n_distinct(predictions$ym)} months"))

# ── Portfolio construction: long D10, short D1 ───────────────────
portfolio <- predictions |>
  group_by(ym) |>
  mutate(
    decile = ntile(predicted_rank, n_quantiles),
    n_stocks = n()
  ) |>
  filter(n_stocks >= min_stocks) |>
  summarise(
    date = max(date),
    long_ret = mean(next_ret[decile == n_quantiles]),
    short_ret = mean(next_ret[decile == 1]),
    n_long = sum(decile == n_quantiles),
    n_short = sum(decile == 1),
    n_stocks = first(n_stocks),
    .groups = "drop"
  ) |>
  mutate(
    # L/S return before costs
    ls_ret_gross = long_ret - short_ret,
    # Costs: turnover estimate ~100% monthly (cross-sectional rebalance)
    # Each side turns over ~100%, so ~2 * cost_per_trade
    cost = 2 * cost_per_trade,
    # Borrow cost on short side
    borrow = borrow_cost_annual / 12,
    ls_ret_net = ls_ret_gross - cost - borrow,
    # Also compute long-only (top decile) return
    long_only_ret = long_ret - cost_per_trade
  ) |>
  arrange(ym)

# ── Write outputs ────────────────────────────────────────────────
dir.create("data/raw", recursive = TRUE, showWarnings = FALSE)
write_parquet(portfolio, "data/raw/ltr_portfolio.parquet", compression = "zstd")
write_parquet(importance, "data/raw/ltr_model_importance.parquet", compression = "zstd")

cli_h2("Portfolio Summary")
cli_inform(c(
  "v" = "{nrow(portfolio)} months, {format(min(portfolio$date), '%Y-%m')} to {format(max(portfolio$date), '%Y-%m')}",
  "i" = "Mean L/S gross: {round(mean(portfolio$ls_ret_gross) * 100, 2)}% per month",
  "i" = "Mean L/S net: {round(mean(portfolio$ls_ret_net) * 100, 2)}% per month",
  "i" = "Mean long-only: {round(mean(portfolio$long_only_ret) * 100, 2)}% per month",
  "i" = "Files: data/raw/ltr_portfolio.parquet, data/raw/ltr_model_importance.parquet"
))
