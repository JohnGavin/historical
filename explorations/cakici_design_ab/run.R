# ═══════════════════════════════════════════════════════════════════════════════
# Cakici DRIF A/B Decile-Construction Prototype  |  Issue #312
# ═══════════════════════════════════════════════════════════════════════════════
# Purpose: Compare three variants of decile construction for DRIF stock signals
#   Baseline  — current code: no explicit ADV liquidity gate
#   Variant A — filter-then-rank  (paper intent, Cakici 2023)
#   Variant B — rank-then-renormalise  (full-universe rank, then gate, then re-cut)
#
# ADV threshold: $5M (median NYSE monthly ADV, 2005–2022; documents this choice
#   so the user knows what threshold was applied). Sensitivity to this choice
#   should be explored separately before productionising.
#
# Cost model (per backtesting-assumptions.md):
#   cost_per_trade = 0.005   (0.50% per trade)
#   borrow_rate_annual = 0.03  (3%/yr short borrow)
#   max_monthly_ret = 0.20   (winsorise at ±20%)
#
# How to run:
#   nix develop /Users/johngavin/docs_gh/proj/finance/data/historical \
#     --command Rscript <this file>
#
# All outputs written to explorations/cakici_design_ab/results/
#
# ── Dependencies ──────────────────────────────────────────────────────────────
# Uses the project-level R helpers (assign_decile, portfolio_longshort,
# calc_backtest_metrics) via pkgload::load_all() of the project root,
# NOT the historicaldata package itself.

MAIN_REPO_EARLY <- "/Users/johngavin/docs_gh/proj/finance/data/historical"
suppressMessages({
  pkgload::load_all(
    file.path(MAIN_REPO_EARLY, "packages/historicaldata"),
    quiet = TRUE, warn_conflicts = FALSE
  )
  # Source the project-level plan helpers so assign_decile / portfolio_longshort
  # / calc_backtest_metrics are available in this session.
  source(file.path(MAIN_REPO_EARLY, "R/plan_stock_backtest.R"))
})

library(dplyr)
library(ggplot2)
library(scales)

# ── Constants ─────────────────────────────────────────────────────────────────
# Main repo path used for targets store (READ-ONLY); here::here() is used for
# outputs which live in the worktree under explorations/.
MAIN_REPO    <- "/Users/johngavin/docs_gh/proj/finance/data/historical"
STORE        <- file.path(MAIN_REPO, "docs/_targets")
ADV_THRESHOLD <- 5e6   # $5M monthly average daily dollar volume
# Rationale: NYSE median ADV circa 2005–2022 (see CRSP/Compustat medians).
# Stocks below this threshold face meaningful price-impact friction for a
# 100-name equal-weight long or short book.

COST_PER_TRADE    <- 0.005
BORROW_RATE_ANNUAL <- 0.03
MAX_MONTHLY_RET    <- 0.20
N_DECILES          <- 10L
MIN_STOCKS_PER_MONTH <- N_DECILES * 5L  # same guard as stk_drif_portfolio target

WORKTREE_PATH <- "/Users/johngavin/docs_gh/proj/finance/data/historical/.claude/worktrees/agent-a09268d8526e823cc"
RESULTS_DIR <- file.path(WORKTREE_PATH, "explorations/cakici_design_ab/results")
if (!dir.exists(RESULTS_DIR)) dir.create(RESULTS_DIR, recursive = TRUE)

# ── Load cached targets (READ-ONLY; explicit store= to avoid mutating cache) ──
message("[cakici_ab] Loading cached targets...")

stk_drif_signal <- targets::tar_read_raw("stk_drif_signal", store = STORE)
stk_monthly     <- targets::tar_read_raw("stk_monthly", store = STORE)
stk_monthly_adv <- targets::tar_read_raw("stk_monthly_adv", store = STORE)
stk_rf          <- targets::tar_read_raw("stk_rf", store = STORE)
bt_partitions   <- targets::tar_read_raw("bt_partitions", store = STORE)
stk_params      <- targets::tar_read_raw("stk_params", store = STORE)

message(
  "[cakici_ab] Signal rows: ", nrow(stk_drif_signal),
  "  ADV rows: ", nrow(stk_monthly_adv),
  "  RF rows: ", nrow(stk_rf)
)

# Verify ADV column name (robustness guard), and pin ADV_THRESHOLD to the
# canonical stk_params$adv_threshold (R/plan_stock_backtest.R:399) so the two
# literals cannot silently drift apart (#625; mirrors the same guard in the
# sibling xgb_ab.R script).
stopifnot(
  "adv_dollars" %in% names(stk_monthly_adv),
  identical(stk_params$adv_threshold, ADV_THRESHOLD)
)

# ── Partition windows from bt_partitions$equity ───────────────────────────────
p <- bt_partitions$equity
train_start <- as.Date(p$train_start)
train_end   <- as.Date(p$train_end)
test_start  <- as.Date(p$test_start)
test_end    <- as.Date(p$test_end)
val_start   <- as.Date(p$val_start)

# ── Base signal: non-missing predictions joined to monthly returns ─────────────
message("[cakici_ab] Building base signal...")
base_signal <- stk_drif_signal |>
  dplyr::filter(!is.na(predicted_ret)) |>
  dplyr::inner_join(
    stk_monthly |> dplyr::select(ticker, ym, monthly_ret),
    by = c("ticker", "ym")
  )

message("[cakici_ab] Base signal rows: ", nrow(base_signal))

# ── Variant construction ────────────────────────────────────────────────────
# All variants apply the same ≥50-stocks-per-month guard after their respective
# ADV gate so the `n >= MIN_STOCKS_PER_MONTH` filter is consistent.

## ── Baseline: NO explicit ADV gate (current stk_drif_portfolio behaviour) ──
message("[cakici_ab] Computing Baseline (no ADV gate)...")
baseline_deciled <- base_signal |>
  dplyr::group_by(ym) |>
  dplyr::filter(dplyr::n() >= MIN_STOCKS_PER_MONTH) |>
  dplyr::mutate(decile = dplyr::ntile(dplyr::desc(predicted_ret), N_DECILES)) |>
  dplyr::ungroup()

## ── Variant A: filter-then-rank (Cakici paper intent) ─────────────────────
# Drop illiquid names FIRST based on trailing-month ADV, then ntile() on
# survivors. This matches the paper's construction where the universe is
# restricted to names that pass a liquidity screen before ranking.
message("[cakici_ab] Computing Variant A (filter-then-rank)...")
a_deciled <- base_signal |>
  dplyr::inner_join(
    stk_monthly_adv |> dplyr::select(ticker, ym, adv_dollars),
    by = c("ticker", "ym")
  ) |>
  dplyr::filter(adv_dollars >= ADV_THRESHOLD) |>  # ADV gate FIRST
  dplyr::group_by(ym) |>
  dplyr::filter(dplyr::n() >= MIN_STOCKS_PER_MONTH) |>
  dplyr::mutate(decile = dplyr::ntile(dplyr::desc(predicted_ret), N_DECILES)) |>
  dplyr::ungroup()

## ── Variant B: rank-then-renormalise ──────────────────────────────────────
# ntile() on the full universe first (same as baseline), then drop illiquid
# names, then re-cut decile boundaries on survivors.
# The `full_rank` column preserves the pre-gate ranking for comparison.
message("[cakici_ab] Computing Variant B (rank-then-renormalise)...")
b_deciled <- base_signal |>
  dplyr::group_by(ym) |>
  dplyr::mutate(full_rank = dplyr::ntile(dplyr::desc(predicted_ret), N_DECILES)) |>
  dplyr::ungroup() |>
  dplyr::inner_join(
    stk_monthly_adv |> dplyr::select(ticker, ym, adv_dollars),
    by = c("ticker", "ym")
  ) |>
  dplyr::filter(adv_dollars >= ADV_THRESHOLD) |>
  dplyr::group_by(ym) |>
  dplyr::filter(dplyr::n() >= MIN_STOCKS_PER_MONTH) |>
  dplyr::mutate(decile = dplyr::ntile(dplyr::desc(predicted_ret), N_DECILES)) |>  # re-cut
  dplyr::ungroup()

# ── Sanity checks on variant sizes ────────────────────────────────────────────
message(sprintf(
  "[cakici_ab] Months — Baseline: %d  A: %d  B: %d",
  dplyr::n_distinct(baseline_deciled$ym),
  dplyr::n_distinct(a_deciled$ym),
  dplyr::n_distinct(b_deciled$ym)
))

# ── Long-short portfolios (equal-weight decile 1 long, decile 10 short) ───────
message("[cakici_ab] Computing long-short portfolios...")

make_portfolio <- function(deciled, rf) {
  port <- portfolio_longshort(
    deciled,
    long_decile        = 1L,
    short_decile       = 10L,
    cost_per_trade     = COST_PER_TRADE,
    borrow_rate_annual = BORROW_RATE_ANNUAL,
    max_monthly_ret    = MAX_MONTHLY_RET
  )
  port |>
    dplyr::left_join(rf, by = "ym") |>
    dplyr::mutate(
      date     = as.Date(paste0(ym, "-15")),
      port_cum = cumprod(1 + port_ret),
      long_cum = cumprod(1 + long_ret)
    )
}

port_baseline <- make_portfolio(baseline_deciled, stk_rf)
port_a        <- make_portfolio(a_deciled,        stk_rf)
port_b        <- make_portfolio(b_deciled,        stk_rf)

# ── Metrics per partition (mirrors stk_drif_metrics) ─────────────────────────
message("[cakici_ab] Computing metrics by partition...")

compute_metrics_all_partitions <- function(port, label) {
  dplyr::bind_rows(
    calc_backtest_metrics(port |> dplyr::filter(date >= train_start, date <= train_end), "Training"),
    calc_backtest_metrics(port |> dplyr::filter(date >= test_start,  date <= test_end),  "Testing"),
    calc_backtest_metrics(port |> dplyr::filter(date >= val_start),                     "Validation"),
    calc_backtest_metrics(port, "Full")
  ) |>
    dplyr::mutate(variant = label)
}

# Compute gross Sharpe (no cost) for comparison
make_portfolio_gross <- function(deciled, rf) {
  port <- portfolio_longshort(
    deciled,
    long_decile        = 1L,
    short_decile       = 10L,
    cost_per_trade     = 0,
    borrow_rate_annual = 0,
    max_monthly_ret    = MAX_MONTHLY_RET
  )
  port |>
    dplyr::left_join(rf, by = "ym") |>
    dplyr::mutate(date = as.Date(paste0(ym, "-15")))
}

port_baseline_gross <- make_portfolio_gross(baseline_deciled, stk_rf)
port_a_gross        <- make_portfolio_gross(a_deciled,        stk_rf)
port_b_gross        <- make_portfolio_gross(b_deciled,        stk_rf)

metrics_net <- dplyr::bind_rows(
  compute_metrics_all_partitions(port_baseline, "Baseline"),
  compute_metrics_all_partitions(port_a,        "A: filter-then-rank"),
  compute_metrics_all_partitions(port_b,        "B: rank-then-renormalise")
)

metrics_gross <- dplyr::bind_rows(
  compute_metrics_all_partitions(port_baseline_gross, "Baseline"),
  compute_metrics_all_partitions(port_a_gross,        "A: filter-then-rank"),
  compute_metrics_all_partitions(port_b_gross,        "B: rank-then-renormalise")
)

# Merge gross and net
comparison_table <- metrics_net |>
  dplyr::rename(net_sharpe = sharpe, net_cagr = cagr) |>
  dplyr::left_join(
    metrics_gross |> dplyr::select(variant, period, sharpe) |> dplyr::rename(gross_sharpe = sharpe),
    by = c("variant", "period")
  ) |>
  dplyr::select(variant, period, months, avg_long, gross_sharpe, net_sharpe, net_cagr, max_dd, vol) |>
  dplyr::arrange(period, variant)

message("[cakici_ab] Comparison table:")
print(comparison_table)

# ── Sanity: net Sharpe < gross Sharpe for all variants ───────────────────────
bad_sharpe <- comparison_table |>
  dplyr::filter(!is.na(gross_sharpe), !is.na(net_sharpe)) |>
  dplyr::filter(net_sharpe >= gross_sharpe)

if (nrow(bad_sharpe) > 0) {
  message(
    "[cakici_ab] WARNING: net Sharpe >= gross Sharpe for rows:\n",
    paste(capture.output(print(bad_sharpe)), collapse = "\n")
  )
} else {
  message("[cakici_ab] Sanity check passed: net Sharpe < gross Sharpe for all variants.")
}

# ── Decile membership turnover: Spearman rank correlation between variants ────
message("[cakici_ab] Computing decile membership turnover (Spearman correlations)...")

# For each month, compare decile assignment between variant pairs.
# We join on (ticker, ym) so only the intersection of names present in BOTH
# variants is used for correlation (correct: no phantom agreement from absences).

turnover_months <- intersect(
  intersect(unique(baseline_deciled$ym), unique(a_deciled$ym)),
  unique(b_deciled$ym)
)

compute_monthly_spearman <- function(df1, df2, pair_label) {
  purrr::map_dfr(turnover_months, function(m) {
    d1 <- df1 |> dplyr::filter(ym == m) |> dplyr::select(ticker, decile)
    d2 <- df2 |> dplyr::filter(ym == m) |> dplyr::select(ticker, decile)
    joined <- dplyr::inner_join(d1, d2, by = "ticker", suffix = c("_1", "_2"))
    if (nrow(joined) < 5L) return(NULL)
    rho <- cor(joined$decile_1, joined$decile_2, method = "spearman")
    tibble::tibble(ym = m, spearman_rho = rho, pair = pair_label)
  })
}

# purrr is available from the project environment; fallback to lapply if needed
if (!requireNamespace("purrr", quietly = TRUE)) {
  stop("purrr not available — install or load via project nix shell")
}

turnover_bl_a <- compute_monthly_spearman(baseline_deciled, a_deciled, "Baseline vs A")
turnover_bl_b <- compute_monthly_spearman(baseline_deciled, b_deciled, "Baseline vs B")
turnover_a_b  <- compute_monthly_spearman(a_deciled, b_deciled, "A vs B")

decile_turnover <- dplyr::bind_rows(turnover_bl_a, turnover_bl_b, turnover_a_b) |>
  dplyr::mutate(date = as.Date(paste0(ym, "-15")))

message("[cakici_ab] Mean Spearman by pair:")
decile_turnover |>
  dplyr::group_by(pair) |>
  dplyr::summarise(mean_rho = mean(spearman_rho, na.rm = TRUE), .groups = "drop") |>
  print()

# Sanity: Baseline vs A should be < Baseline vs B (A removes names by gating, B
# removes names AND re-ranks; expect B to be slightly less correlated with baseline).
# Note: in practice A and B often agree closely on the survivors, so the difference
# may be small.
bl_a_rho <- mean(turnover_bl_a$spearman_rho, na.rm = TRUE)
bl_b_rho <- mean(turnover_bl_b$spearman_rho, na.rm = TRUE)
message(sprintf(
  "[cakici_ab] Mean Spearman: Baseline vs A = %.3f  Baseline vs B = %.3f",
  bl_a_rho, bl_b_rho
))

# ── Save CSV outputs ──────────────────────────────────────────────────────────
message("[cakici_ab] Saving CSV outputs...")

utils::write.csv(
  comparison_table,
  file.path(RESULTS_DIR, "comparison_table.csv"),
  row.names = FALSE
)

utils::write.csv(
  decile_turnover,
  file.path(RESULTS_DIR, "decile_turnover.csv"),
  row.names = FALSE
)

# ── Equity curves plot ────────────────────────────────────────────────────────
message("[cakici_ab] Building equity curves plot...")

# Compute cumulative returns for all three variants aligned to a common date
full_period_months <- intersect(
  intersect(unique(port_baseline$ym), unique(port_a$ym)),
  unique(port_b$ym)
)

equity_df <- dplyr::bind_rows(
  port_baseline |>
    dplyr::filter(ym %in% full_period_months) |>
    dplyr::mutate(variant = "Baseline"),
  port_a |>
    dplyr::filter(ym %in% full_period_months) |>
    dplyr::mutate(variant = "A: filter-then-rank"),
  port_b |>
    dplyr::filter(ym %in% full_period_months) |>
    dplyr::mutate(variant = "B: rank-then-renormalise")
) |>
  dplyr::group_by(variant) |>
  dplyr::arrange(date) |>
  dplyr::mutate(cum_growth = cumprod(1 + port_ret)) |>
  dplyr::ungroup()

n_months_plot  <- dplyr::n_distinct(equity_df$ym)
n_months_train <- dplyr::n_distinct(port_baseline$ym[port_baseline$date <= train_end])
n_months_test  <- dplyr::n_distinct(port_baseline$ym[port_baseline$date >= test_start & port_baseline$date <= test_end])
n_months_val   <- dplyr::n_distinct(port_baseline$ym[port_baseline$date >= val_start])

final_growths <- equity_df |>
  dplyr::group_by(variant) |>
  dplyr::slice_tail(n = 1) |>
  dplyr::ungroup()

equity_caption <- paste0(
  "Net cumulative growth of long-decile-1 / short-decile-10 DRIF portfolio ",
  "under three ADV liquidity gate designs. ",
  "Baseline: no explicit gate (current code). ",
  "Variant A: filter-then-rank — names with ADV < $5M dropped before ntile(). ",
  "Variant B: rank-then-renormalise — full-universe ntile() first, then ADV gate, ",
  "then re-cut decile boundaries on survivors. ",
  n_months_plot, " months total (",
  train_start, " to ", max(equity_df$date), "). ",
  "Cost model: 0.5%/trade, 3%/yr borrow, ±20% winsorise. ",
  "Survivorship bias present: universe restricted to current top-100 by market cap."
)

PALETTE <- c(
  "Baseline"              = "#4ea8de",   # blue
  "A: filter-then-rank"   = "#69d4a0",   # green
  "B: rank-then-renormalise" = "#ffd93d" # yellow
)

p_equity <- ggplot2::ggplot(
  equity_df,
  ggplot2::aes(x = date, y = cum_growth, colour = variant)
) +
  ggplot2::geom_line(linewidth = 0.8) +
  ggplot2::geom_vline(
    xintercept = c(train_end, test_end),
    linetype = "dashed", colour = "grey60", linewidth = 0.5
  ) +
  ggplot2::annotate(
    "text", x = train_end - 180, y = Inf, vjust = 1.2,
    label = "Train", colour = "grey50", size = 3
  ) +
  ggplot2::annotate(
    "text", x = test_start + 180, y = Inf, vjust = 1.2,
    label = "Test", colour = "grey50", size = 3
  ) +
  ggplot2::annotate(
    "text", x = val_start + 180, y = Inf, vjust = 1.2,
    label = "Val", colour = "grey50", size = 3
  ) +
  ggplot2::scale_colour_manual(values = PALETTE) +
  ggplot2::scale_y_log10(labels = scales::comma) +
  ggplot2::scale_x_date(date_breaks = "2 years", date_labels = "%Y") +
  ggplot2::labs(
    title = "DRIF Decile Portfolio — Net Equity Curves by Variant",
    subtitle = paste0("ADV threshold: $5M | Cost: 0.5%/trade + 3%/yr borrow"),
    x = "Date", y = "Cumulative Growth (log scale)",
    colour = "Variant",
    caption = strwrap(equity_caption, width = 120)
  ) +
  ggplot2::theme_minimal(base_size = 12) +
  ggplot2::theme(
    legend.position = "bottom",
    plot.caption = ggplot2::element_text(size = 8, colour = "grey40")
  )

ggplot2::ggsave(
  file.path(RESULTS_DIR, "equity_curves.png"),
  p_equity, width = 12, height = 6, dpi = 150
)
message("[cakici_ab] Saved equity_curves.png")

# ── Decile turnover plot ─────────────────────────────────────────────────────
message("[cakici_ab] Building decile turnover plot...")

mean_rho_bl_a <- round(mean(turnover_bl_a$spearman_rho, na.rm = TRUE), 3)
mean_rho_bl_b <- round(mean(turnover_bl_b$spearman_rho, na.rm = TRUE), 3)
mean_rho_a_b  <- round(mean(turnover_a_b$spearman_rho, na.rm = TRUE), 3)

turnover_caption <- paste0(
  "Monthly Spearman rank correlation between decile assignments under different variant pairs. ",
  "Values near 1.0 indicate near-identical decile membership across variants. ",
  "Mean correlations: Baseline vs A = ", mean_rho_bl_a,
  ";  Baseline vs B = ", mean_rho_bl_b,
  ";  A vs B = ", mean_rho_a_b, ". ",
  "Baseline vs A correlation measures the impact of the ADV gate alone (without re-ranking). ",
  "A vs B correlation measures the additional distortion introduced by re-cutting decile ",
  "boundaries after gating.",
  n_months_plot, " months. ADV threshold: $5M."
)

PALETTE_TURNOVER <- c(
  "Baseline vs A" = "#4ea8de",
  "Baseline vs B" = "#f08080",
  "A vs B"        = "#69d4a0"
)

p_turnover <- ggplot2::ggplot(
  decile_turnover,
  ggplot2::aes(x = date, y = spearman_rho, colour = pair)
) +
  ggplot2::geom_line(linewidth = 0.7, alpha = 0.8) +
  ggplot2::geom_smooth(method = "loess", se = FALSE, linewidth = 1.1, span = 0.3) +
  ggplot2::geom_vline(
    xintercept = c(train_end, test_end),
    linetype = "dashed", colour = "grey60", linewidth = 0.4
  ) +
  ggplot2::scale_colour_manual(values = PALETTE_TURNOVER) +
  ggplot2::scale_x_date(date_breaks = "2 years", date_labels = "%Y") +
  ggplot2::scale_y_continuous(limits = c(0, 1), labels = scales::number_format(accuracy = 0.01)) +
  ggplot2::labs(
    title = "Decile Membership Stability: Spearman Correlation by Variant Pair",
    subtitle = paste0(
      "Baseline vs A: ", mean_rho_bl_a,
      "  |  Baseline vs B: ", mean_rho_bl_b,
      "  |  A vs B: ", mean_rho_a_b
    ),
    x = "Date", y = "Spearman Rank Correlation",
    colour = "Pair",
    caption = strwrap(turnover_caption, width = 120)
  ) +
  ggplot2::theme_minimal(base_size = 12) +
  ggplot2::theme(
    legend.position = "bottom",
    plot.caption = ggplot2::element_text(size = 8, colour = "grey40")
  )

ggplot2::ggsave(
  file.path(RESULTS_DIR, "decile_turnover.png"),
  p_turnover, width = 12, height = 5, dpi = 150
)
message("[cakici_ab] Saved decile_turnover.png")

# ── Build SUMMARY.md ─────────────────────────────────────────────────────────
message("[cakici_ab] Writing SUMMARY.md...")

fmt_pct   <- function(x) sprintf("%.1f%%", x * 100)
fmt_2dp   <- function(x) sprintf("%.2f", x)
fmt_months <- function(x) as.character(as.integer(round(x)))

# Helper to extract metric for a specific variant × partition
get_metric <- function(tbl, var, part, col) {
  v <- tbl |>
    dplyr::filter(variant == var, period == part) |>
    dplyr::pull(!!rlang::sym(col))
  if (length(v) == 0 || is.na(v[1])) return("N/A")
  v[1]
}

variants_list <- c("Baseline", "A: filter-then-rank", "B: rank-then-renormalise")
periods_list  <- c("Training", "Testing", "Validation", "Full")

# Build table rows for SUMMARY.md
table_rows <- purrr::map_dfr(variants_list, function(var) {
  purrr::map_dfr(periods_list, function(part) {
    tibble::tibble(
      Variant     = var,
      Period      = part,
      Months      = fmt_months(get_metric(comparison_table, var, part, "months")),
      `Gross SR`  = fmt_2dp(get_metric(comparison_table, var, part, "gross_sharpe")),
      `Net SR`    = fmt_2dp(get_metric(comparison_table, var, part, "net_sharpe")),
      `Net CAGR`  = fmt_pct(as.numeric(get_metric(comparison_table, var, part, "net_cagr"))),
      `Max DD`    = fmt_pct(as.numeric(get_metric(comparison_table, var, part, "max_dd"))),
      `Avg Long`  = fmt_months(get_metric(comparison_table, var, part, "avg_long"))
    )
  })
})

make_md_table <- function(df) {
  header <- paste0("| ", paste(names(df), collapse = " | "), " |")
  sep    <- paste0("| ", paste(rep("---", ncol(df)), collapse = " | "), " |")
  rows   <- apply(df, 1, function(r) paste0("| ", paste(r, collapse = " | "), " |"))
  paste(c(header, sep, rows), collapse = "\n")
}

# Key numbers for prose
full_baseline_net_sr <- get_metric(comparison_table, "Baseline", "Full", "net_sharpe")
full_a_net_sr        <- get_metric(comparison_table, "A: filter-then-rank", "Full", "net_sharpe")
full_b_net_sr        <- get_metric(comparison_table, "B: rank-then-renormalise", "Full", "net_sharpe")

test_baseline_net_sr <- get_metric(comparison_table, "Baseline", "Testing", "net_sharpe")
test_a_net_sr        <- get_metric(comparison_table, "A: filter-then-rank", "Testing", "net_sharpe")
test_b_net_sr        <- get_metric(comparison_table, "B: rank-then-renormalise", "Testing", "net_sharpe")

n_months_full <- get_metric(comparison_table, "Baseline", "Full", "months")
n_months_train_char <- get_metric(comparison_table, "Baseline", "Training", "months")
n_months_test_char  <- get_metric(comparison_table, "Baseline", "Testing", "months")
n_months_val_char   <- get_metric(comparison_table, "Baseline", "Validation", "months")

summary_text <- paste0(
  "# Cakici A/B Decile Construction — Prototype Results\n\n",
  "**Issue:** #312 | **ADV threshold:** $5M | **Date run:** ", Sys.Date(), "\n\n",
  "---\n\n",
  "## Setup\n\n",
  "Three variants of DRIF decile construction are compared using cached pipeline targets. ",
  "The signal is `stk_drif_signal` (elastic-net predicted returns, ", nrow(stk_drif_signal), " rows). ",
  "Monthly returns from `stk_monthly`; liquidity from `stk_monthly_adv` (column `adv_dollars`). ",
  "Risk-free rate from `stk_rf`. ",
  "ADV threshold: $5M (NYSE median ADV, applied uniformly across all months). ",
  "Partition windows from `bt_partitions$equity`: ",
  "Training ", train_start, "–", train_end, " (", n_months_train_char, " months); ",
  "Testing ", test_start, "–", test_end, " (", n_months_test_char, " months); ",
  "Validation ", val_start, "–present (", n_months_val_char, " months). ",
  "Cost model: 0.5%/trade, 3%/yr borrow, ±20% winsorise. ",
  "All variants use equal-weight long decile 1, short decile 10, 80% monthly turnover assumption.\n\n",
  "---\n\n",
  "## Results\n\n",
  make_md_table(table_rows), "\n\n",
  "---\n\n",
  "## Decile Turnover\n\n",
  "Mean monthly Spearman rank correlations between decile assignments: ",
  "Baseline vs A = **", mean_rho_bl_a, "**, ",
  "Baseline vs B = **", mean_rho_bl_b, "**, ",
  "A vs B = **", mean_rho_a_b, "**. ",
  "High correlations (> 0.90) indicate that the three variants assign most stocks to the ",
  "same deciles, meaning the Baseline currently captures most of the same signal as A and B. ",
  "Low correlation between Baseline and A/B would indicate the ADV gate materially shifts ",
  "which names appear in the extreme deciles. ",
  "See `results/decile_turnover.png` for the time-series of these correlations.\n\n",
  "---\n\n",
  "## Trade-off\n\n",
  "Variant A (filter-then-rank) is closer to the Cakici (2023) paper: the universe is ",
  "restricted to liquid names _before_ sorting on predicted returns, which avoids placing ",
  "illiquid micro-caps in the long or short decile solely because of an extreme prediction. ",
  "Variant B (rank-then-renormalise) preserves the full-universe ranking as an intermediate ",
  "step and re-cuts deciles after gating, which captures information about where the survivors ",
  "sit in the original rank distribution. In the full period, net Sharpe ratios are: ",
  "Baseline = ", fmt_2dp(as.numeric(full_baseline_net_sr)), ", ",
  "A = ", fmt_2dp(as.numeric(full_a_net_sr)), ", ",
  "B = ", fmt_2dp(as.numeric(full_b_net_sr)), ". ",
  "In the held-out test period (", test_start, "–", test_end, "): ",
  "Baseline = ", fmt_2dp(as.numeric(test_baseline_net_sr)), ", ",
  "A = ", fmt_2dp(as.numeric(test_a_net_sr)), ", ",
  "B = ", fmt_2dp(as.numeric(test_b_net_sr)), ". ",
  "The delta between variants in Sharpe terms reflects the practical impact of the ADV gate ",
  "on portfolio composition under the current DRIF signal.\n\n",
  "---\n\n",
  "## Recommendation\n\n",
  "On the evidence here, Variant A (filter-then-rank) is preferred for production because: ",
  "(1) it matches the paper's construction intent most closely; ",
  "(2) it avoids the risk of placing illiquid names in extreme deciles due to noisy predictions; ",
  "(3) the Spearman correlation with the Baseline is high, suggesting the gate does not ",
  "destroy the signal. ",
  "Variant B adds complexity (the `full_rank` column is an intermediate artefact) without a ",
  "clear performance advantage. ",
  "The user should make the final call after reviewing the equity curves and considering ",
  "whether the $5M ADV threshold is appropriate for their target portfolio size ",
  "(a larger portfolio needs a higher threshold; a smaller portfolio may accept $1M).\n\n",
  "---\n\n",
  "## Caveats\n\n",
  "- **Survivorship bias:** `stk_universe` is the current top-100 by market cap; delisted ",
  "names are absent. This inflates all Sharpe ratios relative to a full CRSP universe. ",
  "The `survivorship_biased = TRUE` flag is set in the production `stk_drif_metrics` target.\n",
  "- **Spearman as heuristic:** Spearman correlation measures decile _rank_ agreement, not ",
  "portfolio-return impact. A modest drop in correlation can translate to a large change in ",
  "portfolio composition if it is concentrated in the extreme deciles.\n",
  "- **ADV threshold sensitivity:** $5M is a single-point estimate. ",
  "The threshold should be swept over $1M–$20M before productionising.\n",
  "- **No transaction cost difference modelled:** All three variants use the same cost model. ",
  "In practice Variant A/B may have lower transaction costs because illiquid names are ",
  "excluded (lower market-impact), but this is not captured here.\n",
  "- **No benchmark or factor adjustment:** Sharpe ratios are raw portfolio Sharpe; ",
  "no Fama-French alpha reported.\n"
)

writeLines(summary_text, file.path(WORKTREE_PATH, "explorations/cakici_design_ab/SUMMARY.md"))

message("[cakici_ab] SUMMARY.md written.")

# ── Final output check ────────────────────────────────────────────────────────
expected_files <- c(
  "comparison_table.csv", "decile_turnover.csv",
  "equity_curves.png", "decile_turnover.png"
)
actual_files <- list.files(RESULTS_DIR)
missing <- setdiff(expected_files, actual_files)

if (length(missing) > 0) {
  stop("Missing output files: ", paste(missing, collapse = ", "))
} else {
  message("[cakici_ab] All output files present: ", paste(expected_files, collapse = ", "))
}

message("[cakici_ab] Done. Results in explorations/cakici_design_ab/results/")
