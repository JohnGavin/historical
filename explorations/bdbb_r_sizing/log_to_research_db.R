# Record this exploration's results in the research-log database (hd_rlog_*).
#
# DO NOT RUN THIS AUTOMATICALLY AS PART OF THE DISPATCH -- per the task
# instructions, this script is written but NOT executed here. The
# orchestrator reviews results/ first and runs this deliberately.
#
# WHY THIS SCRIPT EXISTS RATHER THAN AN AD-HOC Rscript -e: every metric
# written to the log is READ FROM the committed result files in results/,
# never re-typed (reproducible-ingestion rule). run.R already computes both
# sharpe_naive and sharpe_hac directly into summary_metrics.csv, so this
# script reads sharpe_hac straight from that column -- it does not
# re-derive it from a raw return series the way the momentum_max_lottery
# template does, because run.R already did that derivation once, correctly,
# with hd_hac_sharpe()'s own hac_tstat.
#
# LINEAGE: this script does NOT create or seal any hypothesis rows. The two
# hypotheses this exploration tests are ALREADY SEALED (commit 7706205,
# "research(prereg): seal BDBB R-sizing overlay hypotheses at inception
# (#443)") and must not be touched -- rewording or resealing them after
# seeing the result is exactly what research-log-honesty.md prohibits. This
# script only appends implementations/results/critiques rows with
# parent_uuid pointing at the existing sealed hypothesis uuids.
#
# Run:
#   nix develop . --command Rscript explorations/bdbb_r_sizing/log_to_research_db.R
#
# The store is append-only: re-running APPENDS a second set of rows, it does
# not overwrite. Do not run it twice for the same result set without meaning to.

suppressPackageStartupMessages({
  library(dplyr)
})
pkgload::load_all(here::here("packages", "historicaldata"), quiet = TRUE)

RES <- here::here("explorations", "bdbb_r_sizing", "results")

read_res <- function(name) {
  p <- file.path(RES, name)
  if (!file.exists(p)) {
    cli::cli_abort(c(
      "x" = "Missing result file {.path {p}}.",
      "i" = "Run run.R first: it produces every input this script reads."
    ))
  }
  readr::read_csv(p, show_col_types = FALSE)
}

summary_metrics <- read_res("summary_metrics.csv")
decision_table   <- read_res("decision_table.csv")
corr_checks      <- read_res("correlation_checks.csv")
turnover_tbl     <- read_res("turnover.csv")

# Sealed hypothesis uuids (BTC, SOL) -- NOT written here, only referenced.
# Verify they are actually present in the research log before linking to
# them: a broken parent_uuid reference would be a silent lineage defect.
hyp_uuids <- c(
  BTC = "c0e60522-5a51-4563-a619-14b4a557779c",
  SOL = "e9357c9b-d162-4317-bd6e-960736809c69"
)

existing_hyps <- tryCatch(
  hd_rlog_query("hypotheses"),
  error = function(e) tibble::tibble(uuid = character())
)
missing_hyps <- setdiff(hyp_uuids, existing_hyps$uuid)
if (length(missing_hyps) > 0) {
  cli::cli_abort(c(
    "x" = "Sealed hypothesis uuid{?s} not found in the research log: {.val {missing_hyps}}.",
    "i" = "This exploration must link to the EXISTING sealed rows (commit 7706205), never create new ones.",
    "i" = "If the seal commit has not been merged into this checkout yet, merge it first."
  ))
}

# One implementation row per asset, parented to that asset's sealed hypothesis.
impl_uuids <- c(BTC = hd_rlog_uuid(), SOL = hd_rlog_uuid())

implementations <- tibble::tibble(
  uuid = unname(impl_uuids),
  parent_uuid = unname(hyp_uuids[names(impl_uuids)]),
  code_ref = "explorations/bdbb_r_sizing/run.R",
  notebook_path = "explorations/bdbb_r_sizing/SUMMARY.md",
  params_json = vapply(names(impl_uuids), function(asset) {
    as.character(jsonlite::toJSON(list(
      window_days = 30L,
      min_frac = 0.7,
      min_history_prior_windows = 250L,
      w_low_grid = c(0.00, 0.25, 0.50, 0.75),
      complement_cap = 2.0,
      fee_rate_per_side = 0.0026,
      ann_factor = 8760L,
      combination_mode = "time",
      asset = asset
    ), auto_unbox = TRUE))
  }, character(1)),
  extra_json = vapply(names(impl_uuids), function(asset) {
    as.character(jsonlite::toJSON(list(
      blocked_by_868_workaround = paste0(
        "bdbb_tail_predict() NOT used (scores the in-window bar, #868). ",
        "Sizing built directly from bdbb_fit()$R, lagged one row by row ",
        "order (not clock arithmetic) before use."
      )
    ), auto_unbox = TRUE))
  }, character(1))
)

# ── results rows: one per (variant, cost_type) per asset, straight from
#    summary_metrics.csv -- sharpe_hac already computed in run.R, not
#    re-derived here. ────────────────────────────────────────────────────
results_rows <- summary_metrics |>
  transmute(
    uuid = vapply(seq_len(n()), function(i) hd_rlog_uuid(), character(1)),
    parent_uuid = unname(impl_uuids[asset]),
    strategy_id = paste(variant, cost_type, sep = "__"),
    partition = "full-sample",
    cagr = ann_ret_cagr,
    sharpe_hac,
    max_dd,
    turnover_annual,
    n_obs = as.integer(n_obs),
    results_db_run_date = Sys.Date(),
    extra_json = vapply(seq_len(n()), function(i) {
      as.character(jsonlite::toJSON(list(
        asset = asset[i],
        w_low = w_low[i],
        cost_type = cost_type[i],
        sharpe_naive = sharpe_naive[i],
        ann_vol = ann_vol[i],
        skew = skew[i],
        detection_verdict = detection_verdict[i],
        detection_min_n_years = detection_min_n_years[i],
        fixed_threshold_used = fixed_threshold_used[i],
        fixed_threshold_underpowered = fixed_threshold_underpowered[i]
      ), auto_unbox = TRUE, na = "null"))
    }, character(1))
  )

# ── decision-table rows folded into critiques (one per asset x w_low,
#    recording the literal pre-registered verdict) ─────────────────────────
critiques <- decision_table |>
  transmute(
    uuid = vapply(seq_len(n()), function(i) hd_rlog_uuid(), character(1)),
    parent_uuid = unname(impl_uuids[asset]),
    defect_class = "graduation-decision",
    severity = dplyr::case_when(
      status == "supported" ~ "info",
      status == "refuted" ~ "high",
      TRUE ~ "medium"
    ),
    finding = sprintf(
      "%s w_low=%.2f: %s (overlay sharpe_hac=%+.3f, sharpe_naive=%+.3f vs benchmark sharpe_hac=%+.3f; fixed detectability threshold=%.2f; n_obs=%d).",
      asset, w_low, status, overlay_sharpe_hac, overlay_sharpe_naive,
      benchmark_sharpe_hac, fixed_threshold_used, n_obs
    ),
    cell_ref = "results/decision_table.csv",
    resolved = TRUE
  )

# ── R-vs-vol correlation check, also folded into critiques (one per asset) ──
corr_critiques <- corr_checks |>
  transmute(
    uuid = vapply(seq_len(n()), function(i) hd_rlog_uuid(), character(1)),
    parent_uuid = unname(impl_uuids[asset]),
    defect_class = "signal-vs-vol-correlation",
    severity = "info",
    finding = sprintf(
      "%s: cor(rank(R), rank(trailing_realised_vol)) = %.3f over %d paired observations (control #2 -- R must not be a repackaged vol filter).",
      asset, r_vol_spearman_cor, n_pairs
    ),
    cell_ref = "results/correlation_checks.csv",
    resolved = TRUE
  )

hd_rlog_append("implementations", implementations)
hd_rlog_append("results", results_rows)
hd_rlog_append("critiques", dplyr::bind_rows(critiques, corr_critiques))

cli::cli_inform(c(
  "v" = "Logged 2 implementations, {nrow(results_rows)} results, {nrow(critiques) + nrow(corr_critiques)} critiques."
))
print(decision_table, n = 20)
