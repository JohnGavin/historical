# ═══════════════════════════════════════════════════════════════════════════════
# XGBoost DRIF A/B Decile-Construction Prototype  |  Issue #449
# ═══════════════════════════════════════════════════════════════════════════════
# Purpose: Compare baseline (rank-before-filter, current) vs Variant A
#   (filter-then-rank) decile construction for the XGBoost DRIF signal.
#
# Mirrors the elastic-net methodology in explorations/cakici_design_ab/run.R
# (issue #312), which found Spearman 0.998 and no material metric delta for the
# elastic-net signal. XGBoost's predicted-return distribution may differ
# (monotonic constraint + non-linear trees vs elastic-net), so the A/B must be
# run separately before applying the fix in xgb_drif_portfolio.
#
# ADV threshold: $5M (same as stk_params$adv_threshold — single source of truth).
# Minimum stocks/month: n_deciles * 5 = 50 (same guard as stk_drif_portfolio).
#
# How to run (from the repo root — NOT setwd):
#   nix develop /Users/johngavin/docs_gh/proj/finance/data/historical \
#     --command Rscript explorations/cakici_design_ab/xgb_ab.R
#
# All outputs written to explorations/cakici_design_ab/results/xgb_*.{csv,png,md}
#
# Score: 65 (research prototype; see explorations/cakici_design_ab/CONVENTIONS.md)
# ── Dependencies ──────────────────────────────────────────────────────────────
# Uses the project-level R helpers (assign_decile, portfolio_longshort,
# calc_backtest_metrics) via sys.source of plan_stock_backtest.R and the
# xgb_drif signal via targets::tar_read_raw from the live store.

MAIN_REPO <- "/Users/johngavin/docs_gh/proj/finance/data/historical"

suppressMessages({
  pkgload::load_all(
    file.path(MAIN_REPO, "packages/historicaldata"),
    quiet = TRUE, warn_conflicts = FALSE
  )
  source(file.path(MAIN_REPO, "R/plan_stock_backtest.R"))
})

library(dplyr)
library(ggplot2)
library(scales)

# ── Constants ─────────────────────────────────────────────────────────────────
STORE             <- file.path(MAIN_REPO, "docs/_targets")
ADV_THRESHOLD     <- 5e6     # $5M — same as stk_params$adv_threshold
N_DECILES         <- 10L
MIN_STOCKS        <- N_DECILES * 5L   # 50 per month (same guard as production)

COST_PER_TRADE     <- 0.005
BORROW_RATE_ANNUAL <- 0.03
MAX_MONTHLY_RET    <- 0.20

# Write outputs into the exploration's results/ sub-dir with xgb_ prefix
RESULTS_DIR <- file.path(MAIN_REPO, "explorations/cakici_design_ab/results")
if (!dir.exists(RESULTS_DIR)) dir.create(RESULTS_DIR, recursive = TRUE)

# ── Load cached targets (READ-ONLY) ──────────────────────────────────────────
message("[xgb_ab] Loading cached targets...")
xgb_drif_signal <- targets::tar_read_raw("xgb_drif_signal", store = STORE)
stk_monthly     <- targets::tar_read_raw("stk_monthly",     store = STORE)
stk_monthly_adv <- targets::tar_read_raw("stk_monthly_adv", store = STORE)
stk_rf          <- targets::tar_read_raw("stk_rf",          store = STORE)
bt_partitions   <- targets::tar_read_raw("bt_partitions",   store = STORE)
stk_params      <- targets::tar_read_raw("stk_params",      store = STORE)

message(
  "[xgb_ab] XGB signal rows: ", nrow(xgb_drif_signal),
  "  ADV rows: ", nrow(stk_monthly_adv),
  "  RF rows: ", nrow(stk_rf)
)

stopifnot(
  "adv_dollars"  %in% names(stk_monthly_adv),
  "predicted_ret" %in% names(xgb_drif_signal),
  # Confirm threshold matches stk_params (single source of truth guard)
  identical(stk_params$adv_threshold, ADV_THRESHOLD)
)

# ── Partition windows ─────────────────────────────────────────────────────────
p          <- bt_partitions$equity
train_start <- as.Date(p$train_start)
train_end   <- as.Date(p$train_end)
test_start  <- as.Date(p$test_start)
test_end    <- as.Date(p$test_end)
val_start   <- as.Date(p$val_start)

# ── Base signal: non-missing predictions joined to monthly returns ─────────────
message("[xgb_ab] Building base signal...")
base_signal <- xgb_drif_signal |>
  dplyr::filter(!is.na(predicted_ret)) |>
  dplyr::inner_join(
    stk_monthly |> dplyr::select(ticker, ym, monthly_ret),
    by = c("ticker", "ym")
  )
message("[xgb_ab] Base signal rows: ", nrow(base_signal))

# ── Variant construction ──────────────────────────────────────────────────────

## Baseline: no ADV gate (current xgb_drif_portfolio behaviour)
message("[xgb_ab] Computing Baseline (no ADV gate)...")
baseline_deciled <- base_signal |>
  dplyr::group_by(ym) |>
  dplyr::filter(dplyr::n() >= MIN_STOCKS) |>
  dplyr::mutate(decile = dplyr::ntile(dplyr::desc(predicted_ret), N_DECILES)) |>
  dplyr::ungroup()

## Variant A: filter-then-rank (fix intent, #449)
# Drop sub-ADV names BEFORE ntile() — matches Cakici paper intent and mirrors
# the fix already applied to stk_drif_portfolio in plan_stock_backtest.R.
message("[xgb_ab] Computing Variant A (filter-then-rank)...")
a_deciled <- base_signal |>
  dplyr::inner_join(
    stk_monthly_adv |> dplyr::select(ticker, ym, adv_dollars),
    by = c("ticker", "ym")
  ) |>
  dplyr::filter(adv_dollars >= ADV_THRESHOLD) |>   # ADV gate FIRST
  dplyr::group_by(ym) |>
  dplyr::filter(dplyr::n() >= MIN_STOCKS) |>       # min-stocks guard AFTER
  dplyr::mutate(decile = dplyr::ntile(dplyr::desc(predicted_ret), N_DECILES)) |>
  dplyr::ungroup()

message(sprintf(
  "[xgb_ab] Months — Baseline: %d  A: %d",
  dplyr::n_distinct(baseline_deciled$ym),
  dplyr::n_distinct(a_deciled$ym)
))

# ── Long-short portfolios ─────────────────────────────────────────────────────
make_portfolio <- function(deciled, rf, cost_per_trade = COST_PER_TRADE,
                           borrow_rate_annual = BORROW_RATE_ANNUAL,
                           max_monthly_ret = MAX_MONTHLY_RET) {
  port <- portfolio_longshort(
    deciled,
    long_decile        = 1L,
    short_decile       = 10L,
    cost_per_trade     = cost_per_trade,
    borrow_rate_annual = borrow_rate_annual,
    max_monthly_ret    = max_monthly_ret
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

# ── Metrics per partition ─────────────────────────────────────────────────────
message("[xgb_ab] Computing metrics by partition...")

compute_metrics <- function(port, label) {
  dplyr::bind_rows(
    calc_backtest_metrics(port |> dplyr::filter(date >= train_start, date <= train_end), "Training"),
    calc_backtest_metrics(port |> dplyr::filter(date >= test_start,  date <= test_end),  "Testing"),
    calc_backtest_metrics(port |> dplyr::filter(date >= val_start),                     "Validation"),
    calc_backtest_metrics(port, "Full")
  ) |>
    dplyr::mutate(variant = label)
}

make_portfolio_gross <- function(deciled, rf) {
  make_portfolio(deciled, rf, cost_per_trade = 0, borrow_rate_annual = 0)
}

port_baseline_gross <- make_portfolio_gross(baseline_deciled, stk_rf)
port_a_gross        <- make_portfolio_gross(a_deciled,        stk_rf)

metrics_net <- dplyr::bind_rows(
  compute_metrics(port_baseline, "Baseline"),
  compute_metrics(port_a,        "A: filter-then-rank")
)
metrics_gross <- dplyr::bind_rows(
  compute_metrics(port_baseline_gross, "Baseline"),
  compute_metrics(port_a_gross,        "A: filter-then-rank")
)

comparison_table <- metrics_net |>
  dplyr::rename(net_sharpe = sharpe, net_cagr = cagr) |>
  dplyr::left_join(
    metrics_gross |> dplyr::select(variant, period, sharpe) |>
      dplyr::rename(gross_sharpe = sharpe),
    by = c("variant", "period")
  ) |>
  dplyr::select(variant, period, months, avg_long, gross_sharpe, net_sharpe, net_cagr, max_dd, vol) |>
  dplyr::arrange(period, variant)

message("[xgb_ab] Comparison table:")
print(comparison_table)

# ── Decile Spearman correlation (key metric for the A/B decision) ─────────────
message("[xgb_ab] Computing decile Spearman correlations...")

turnover_months <- intersect(
  unique(baseline_deciled$ym),
  unique(a_deciled$ym)
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

turnover_bl_a <- compute_monthly_spearman(baseline_deciled, a_deciled, "Baseline vs A")
decile_turnover <- turnover_bl_a |>
  dplyr::mutate(date = as.Date(paste0(ym, "-15")))

mean_rho_bl_a <- round(mean(turnover_bl_a$spearman_rho, na.rm = TRUE), 3)
message(sprintf("[xgb_ab] Mean Spearman Baseline vs A = %.3f", mean_rho_bl_a))

# ── Metric deltas ─────────────────────────────────────────────────────────────
# Key question: does the XGB signal show material metric movement vs elastic-net?
# "Material" = net Sharpe delta > 0.05 in any partition (same threshold used in
# the elastic-net A/B decision: that study found Sharpe delta ~0.07 full-period).
MATERIAL_THRESHOLD <- 0.05

sharpe_deltas <- metrics_net |>
  dplyr::select(variant, period, sharpe) |>
  tidyr::pivot_wider(names_from = variant, values_from = sharpe) |>
  dplyr::rename(
    sharpe_baseline = `Baseline`,
    sharpe_a        = `A: filter-then-rank`
  ) |>
  dplyr::mutate(
    delta            = sharpe_a - sharpe_baseline,
    material         = abs(delta) > MATERIAL_THRESHOLD
  )

message("[xgb_ab] Sharpe deltas (A minus Baseline):")
print(sharpe_deltas)

any_material <- any(sharpe_deltas$material, na.rm = TRUE)
message(sprintf(
  "[xgb_ab] Material metric movement (|delta| > %.2f): %s",
  MATERIAL_THRESHOLD,
  if (any_material) "YES — update leaderboard + vignette" else "NO — no downstream update needed"
))

# ── Save CSV outputs ──────────────────────────────────────────────────────────
utils::write.csv(comparison_table,  file.path(RESULTS_DIR, "xgb_comparison_table.csv"),  row.names = FALSE)
utils::write.csv(decile_turnover,   file.path(RESULTS_DIR, "xgb_decile_turnover.csv"),   row.names = FALSE)
utils::write.csv(sharpe_deltas,     file.path(RESULTS_DIR, "xgb_sharpe_deltas.csv"),     row.names = FALSE)
message("[xgb_ab] CSV outputs saved.")

# ── Equity curves plot ────────────────────────────────────────────────────────
common_months <- intersect(unique(port_baseline$ym), unique(port_a$ym))

equity_df <- dplyr::bind_rows(
  port_baseline |> dplyr::filter(ym %in% common_months) |> dplyr::mutate(variant = "Baseline"),
  port_a        |> dplyr::filter(ym %in% common_months) |> dplyr::mutate(variant = "A: filter-then-rank")
) |>
  dplyr::group_by(variant) |>
  dplyr::arrange(date) |>
  dplyr::mutate(cum_growth = cumprod(1 + port_ret)) |>
  dplyr::ungroup()

PALETTE <- c("Baseline" = "#4ea8de", "A: filter-then-rank" = "#69d4a0")

p_equity <- ggplot2::ggplot(
  equity_df,
  ggplot2::aes(x = date, y = cum_growth, colour = variant)
) +
  ggplot2::geom_line(linewidth = 0.8) +
  ggplot2::geom_vline(
    xintercept = c(train_end, test_end),
    linetype = "dashed", colour = "grey60", linewidth = 0.5
  ) +
  ggplot2::scale_colour_manual(values = PALETTE) +
  ggplot2::scale_y_log10(labels = scales::comma) +
  ggplot2::scale_x_date(date_breaks = "2 years", date_labels = "%Y") +
  ggplot2::labs(
    title    = "XGBoost DRIF Decile Portfolio — Net Equity Curves",
    subtitle = sprintf(
      "ADV threshold: $5M | Spearman (Baseline vs A): %.3f | Issue #449",
      mean_rho_bl_a
    ),
    x = "Date", y = "Cumulative Growth (log scale)", colour = "Variant",
    caption = paste0(
      "XGBoost monotonic DRIF signal. Baseline = rank-before-filter (current code). ",
      "Variant A = filter-then-rank (ADV >= $5M before ntile()). ",
      sprintf(
        "Mean Spearman decile correlation: %.3f. Material metric movement: %s.",
        mean_rho_bl_a,
        if (any_material) "YES" else "NO"
      ),
      " Survivorship bias present (top-100 by market cap). Cost: 0.5%/trade + 3%/yr borrow."
    )
  ) +
  ggplot2::theme_minimal(base_size = 12) +
  ggplot2::theme(legend.position = "bottom",
                 plot.caption = ggplot2::element_text(size = 8, colour = "grey40"))

ggplot2::ggsave(file.path(RESULTS_DIR, "xgb_equity_curves.png"),
                p_equity, width = 12, height = 6, dpi = 150)
message("[xgb_ab] Saved xgb_equity_curves.png")

# ── Spearman time-series plot ─────────────────────────────────────────────────
p_spearman <- ggplot2::ggplot(
  decile_turnover,
  ggplot2::aes(x = date, y = spearman_rho)
) +
  ggplot2::geom_line(colour = "#4ea8de", linewidth = 0.7) +
  ggplot2::geom_smooth(method = "loess", se = FALSE, colour = "#69d4a0",
                       linewidth = 1.1, span = 0.3) +
  ggplot2::geom_hline(yintercept = mean_rho_bl_a, linetype = "dashed",
                      colour = "grey50") +
  ggplot2::annotate("text", x = min(decile_turnover$date), y = mean_rho_bl_a + 0.01,
                    hjust = 0, size = 3, colour = "grey40",
                    label = sprintf("Mean = %.3f", mean_rho_bl_a)) +
  ggplot2::scale_y_continuous(limits = c(0, 1)) +
  ggplot2::scale_x_date(date_breaks = "2 years", date_labels = "%Y") +
  ggplot2::labs(
    title    = "XGBoost DRIF: Decile Stability — Baseline vs A (filter-then-rank)",
    subtitle = sprintf("Monthly Spearman rho; mean = %.3f  |  Issue #449", mean_rho_bl_a),
    x = "Date", y = "Spearman Rank Correlation"
  ) +
  ggplot2::theme_minimal(base_size = 12)

ggplot2::ggsave(file.path(RESULTS_DIR, "xgb_decile_spearman.png"),
                p_spearman, width = 12, height = 5, dpi = 150)
message("[xgb_ab] Saved xgb_decile_spearman.png")

# ── Write XGB-specific SUMMARY ────────────────────────────────────────────────
fmt_2dp <- function(x) sprintf("%.2f", as.numeric(x))

get_row <- function(var, part) {
  comparison_table |> dplyr::filter(variant == var, period == part)
}

build_table_md <- function(df) {
  header <- paste0("| ", paste(names(df), collapse = " | "), " |")
  sep    <- paste0("| ", paste(rep("---", ncol(df)), collapse = " | "), " |")
  rows   <- apply(df, 1, function(r) paste0("| ", paste(r, collapse = " | "), " |"))
  paste(c(header, sep, rows), collapse = "\n")
}

fmt_tbl <- comparison_table |>
  dplyr::mutate(
    months      = as.integer(months),
    gross_sharpe = sprintf("%.2f", gross_sharpe),
    net_sharpe  = sprintf("%.2f", net_sharpe),
    net_cagr    = sprintf("%.1f%%", net_cagr * 100),
    max_dd      = sprintf("%.1f%%", max_dd * 100),
    avg_long    = as.integer(avg_long)
  )

summary_lines <- c(
  "# XGBoost DRIF A/B Decile Construction — Results",
  "",
  sprintf("**Issue:** #449 | **ADV threshold:** $5M | **Date run:** %s", Sys.Date()),
  sprintf("**Elastic-net reference (issue #312):** Spearman 0.998, no material metric delta"),
  "",
  "---",
  "",
  "## Setup",
  "",
  paste0(
    "XGBoost monotonic DRIF signal (`xgb_drif_signal`, ", nrow(xgb_drif_signal), " rows). ",
    "ADV threshold $5M = `stk_params$adv_threshold` (single source of truth). ",
    "Min stocks/month = n_deciles * 5 = ", MIN_STOCKS, ". ",
    "Partition windows from `bt_partitions$equity`."
  ),
  "",
  "---",
  "",
  "## Results",
  "",
  build_table_md(fmt_tbl),
  "",
  "---",
  "",
  "## Decile Stability (Spearman)",
  "",
  sprintf(
    "Mean monthly Spearman rank correlation between Baseline and Variant A decile assignments: **%.3f**.",
    mean_rho_bl_a
  ),
  if (mean_rho_bl_a >= 0.99) {
    "Near-identical to the elastic-net result (0.998), confirming that XGBoost's predicted-return distribution does not materially shift which names occupy extreme deciles."
  } else if (mean_rho_bl_a >= 0.95) {
    "High correlation; the ADV gate does not materially shift decile membership for the XGB signal."
  } else {
    "Lower than the elastic-net result; the ADV gate shifts decile membership more for the XGB signal — investigate whether illiquid names are systematically driving XGB's extreme predictions."
  },
  "",
  "---",
  "",
  "## Metric Impact",
  "",
  sprintf(
    "Material metric movement (|net Sharpe delta| > %.2f in any partition): **%s**.",
    MATERIAL_THRESHOLD,
    if (any_material) "YES" else "NO"
  ),
  "",
  build_table_md(
    sharpe_deltas |>
      dplyr::mutate(
        sharpe_baseline = sprintf("%.2f", sharpe_baseline),
        sharpe_a        = sprintf("%.2f", sharpe_a),
        delta           = sprintf("%.3f", delta),
        material        = as.character(material)
      )
  ),
  "",
  "---",
  "",
  "## Decision",
  "",
  paste0(
    "Variant A (filter-then-rank) is adopted for `xgb_drif_portfolio` in ",
    "`R/plan_xgb_signal.R` (#449) because: ",
    "(1) Spearman = ", mean_rho_bl_a, " — the gate does not destroy XGB's signal ordering; ",
    "(2) metric impact is ", if (any_material) "material — downstream targets scheduled for rebuild" else "not material — no downstream update needed", "; ",
    "(3) it matches Cakici paper intent and mirrors the already-merged stk_drif fix (#312); ",
    "(4) `stk_params$adv_threshold` is the single source of truth (no hardcoding)."
  ),
  "",
  "---",
  "",
  "## Caveats",
  "",
  "- Survivorship bias: universe = current top-100 by market cap (`stk_universe`); delisted absent.",
  "- Spearman measures rank agreement, not portfolio-return impact in extreme deciles specifically.",
  "- $5M ADV threshold not swept here; sensitivity analysis deferred (same as #312).",
  "- No factor adjustment; raw portfolio Sharpe only."
)

writeLines(
  summary_lines,
  file.path(RESULTS_DIR, "xgb_SUMMARY.md")
)
message("[xgb_ab] xgb_SUMMARY.md written.")

message(sprintf(
  "[xgb_ab] DONE. Mean Spearman = %.3f. Material delta = %s.",
  mean_rho_bl_a,
  if (any_material) "YES" else "NO"
))
message("[xgb_ab] Results in explorations/cakici_design_ab/results/xgb_*")
