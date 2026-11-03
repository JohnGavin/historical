# Append two CRITIQUE rows recording the OLMAR-1 universe findings
# (Refs #976, #977). Findings: docs/olmar-universe-findings-976-977.md.
#
#   * #976 (defect_class `universe-mismatch`): the ten sector SPDRs (XLF XLE XLV
#     XLK XLI XLP XLU XLB XLY XLRE) were declared but never tested.
#     `equity_daily` holds 0 rows for each; `olmar_prices` dropped them without
#     a warning. The declared universe now equals the 20 tested tickers (PR #1021).
#   * #977 (defect_class `survivorship-bias`, the value the log already uses):
#     the 20-ticker list was written 2026-05-23, after the whole test window,
#     mostly from current mega-caps; 19 of 20 have a first bar before 2010-01-04
#     (META starts 2012-05-18). Verdict: probably biased upward, size unknown.
#
# `universe-mismatch` is a NEW defect_class value: the log's existing values
# (look_ahead, omitted_costs, metric-basis, metric-selection, insufficient-power,
# survivorship-bias) describe other defects and none fits a declared-vs-tested
# universe disagreement.
#
# Same pattern as scripts/seed_olmar_results_correction.R: rows go in the
# `critiques` table (a defect found in an existing result), parented on the
# newest OLMAR results row, never touching `hypotheses` (ledger status
# unchanged) or `results`. Existing rows are never edited or deleted. S47 scans
# only R/*.R and docs/_targets.R, so a script under scripts/ needs no allow-list
# entry (same as the other seed scripts).
#
# Computed at run time: the OLMAR results rows and the parent uuid/timestamp.
# QUOTED, not recomputed: the ticker facts (0 rows per SPDR; first-bar dates),
# read once on 2026-11-03 from data/dist/equity_daily.parquet (which this script
# does not load); see the findings document.
#
# Idempotent per defect_class: a class that already has a critique on any OLMAR
# results row is skipped; if both exist nothing is written.
#
# Exit codes: 0 rows appended, 1 nothing to write, 3 INDETERMINATE (log
# unreadable or the OLMAR lineage not found; nothing written).
#
# Run (repo root):
#   nix develop . --command Rscript scripts/seed_olmar_universe_critique.R
#
# Optional first argument: a base_dir override (tests/dry runs); default is the
# tracked inst/extdata/research_log/.

pkgload::load_all(here::here("packages", "historicaldata"), quiet = TRUE)

args <- commandArgs(trailingOnly = TRUE)
base_dir <- if (length(args) >= 1L) args[[1]] else NULL

OLMAR_CLAIM_PREFIX     <- "Equity prices mean-revert toward a short moving average"
OLMAR_PREDICTOR_PREFIX <- "MA/price ratio (OLMAR-1)"
CLASS_976 <- "universe-mismatch"
CLASS_977 <- "survivorship-bias"
GH <- "https://github.com/JohnGavin/historical"

indeterminate <- function(msg) {
  cat("seed_olmar_universe_critique: INDETERMINATE -", msg, "\n")
  quit(save = "no", status = 3L)
}

state <- tryCatch({
  hyp  <- hd_rlog_query("hypotheses", base_dir = base_dir)
  impl <- hd_rlog_query("implementations", base_dir = base_dir)
  res  <- hd_rlog_query("results", base_dir = base_dir)
  crit <- hd_rlog_query("critiques", base_dir = base_dir)
  list(hyp = hyp, impl = impl, res = res, crit = crit)
}, error = function(e) indeterminate(paste("research log unreadable:", conditionMessage(e))))

olmar <- state$hyp[startsWith(state$hyp$economic_claim, OLMAR_CLAIM_PREFIX) &
                     startsWith(state$hyp$predictor, OLMAR_PREDICTOR_PREFIX), ,
                   drop = FALSE]
if (nrow(olmar) == 0L) indeterminate("no OLMAR-1 hypothesis row found")
impl_olmar <- state$impl[state$impl$parent_uuid %in% olmar$uuid, , drop = FALSE]
res_olmar  <- state$res[state$res$parent_uuid %in% impl_olmar$uuid &
                          state$res$strategy_id == "olmar", , drop = FALSE]
if (nrow(res_olmar) == 0L) indeterminate("no OLMAR results rows reachable via implementations")

res_olmar <- res_olmar[order(res_olmar$timestamp, res_olmar$uuid), , drop = FALSE]
newest <- res_olmar[nrow(res_olmar), , drop = FALSE]
n_total <- nrow(res_olmar)

have <- state$crit$defect_class[state$crit$parent_uuid %in% res_olmar$uuid]

FINDING_976 <- paste0(
  "UNIVERSE MISMATCH: OLMAR-1 declared 30 tickers but tested 20. The ten sector ",
  "SPDRs (XLF XLE XLV XLK XLI XLP XLU XLB XLY XLRE) were declared and never ",
  "tested: data/dist/equity_daily.parquet holds 0 rows for each, so hd_ohlcv() ",
  "returned nothing and olmar_prices dropped them without a warning. Verdict: ",
  "data-source gap, not a deliberate cut and not short history. The ", n_total,
  " OLMAR results rows are append-only and unchanged; every one of them was ",
  "computed on the 20 tickers SPY QQQ IWM DIA AAPL MSFT GOOGL AMZN META JPM BAC ",
  "GS JNJ PFE UNH XOM CVX HD WMT PG. Any earlier text that says 30 tickers is ",
  "wrong for these results. The declared universe now equals the 20 tested ",
  "(PR #1021) and gate S48 fails when they differ. A run with the ten added ",
  "must be logged as a new implementation row, not a re-tune. Ticker facts are ",
  "QUOTED from a read on 2026-11-03, not recomputed by this script. Details: ",
  "docs/olmar-universe-findings-976-977.md. Tracked in [#976](", GH,
  "/issues/976). This row is not a verdict on the strategy."
)

FINDING_977 <- paste0(
  "SURVIVORSHIP: probably biased upward, size unknown. The 20-ticker list was ",
  "written on 2026-05-23, after the whole 2010-2026 test window, mostly from ",
  "today's mega-caps (16 of 20 are current large US stocks). The only price ",
  "source, equity_daily, records no delistings. 19 of 20 tickers have a first ",
  "bar before 2010-01-04, so they existed then (existence, not liquidity); META ",
  "starts 2012-05-18 and enters mid-sample. The four index ETFs (SPY QQQ IWM ",
  "DIA) are not selected by survivorship. The magnitude cannot be told without ",
  "2010 point-in-time constituents or market caps plus delisting records, which ",
  "are not in the repo (#150); the literature figure of +1 to +3 pp/year CAGR is ",
  "not quantified for this list. The equal-weight comparison on the same 20 ",
  "shares the bias, so it is less affected than the absolute Sharpe. The ",
  n_total, " OLMAR results rows are append-only and unchanged. First-bar dates ",
  "are QUOTED from a read on 2026-11-03, not recomputed by this script. ",
  "Details: docs/olmar-universe-findings-976-977.md. Tracked in [#977](", GH,
  "/issues/977). This row is not a verdict on the strategy."
)

rows <- list()
if (!(CLASS_976 %in% have)) {
  rows[[CLASS_976]] <- tibble::tibble(
    parent_uuid = newest$uuid, defect_class = CLASS_976, severity = "major",
    finding = FINDING_976,
    cell_ref = paste0("results:strategy_id=olmar (", n_total, " rows); universe"),
    resolved = FALSE
  )
}
if (!(CLASS_977 %in% have)) {
  rows[[CLASS_977]] <- tibble::tibble(
    parent_uuid = newest$uuid, defect_class = CLASS_977, severity = "major",
    finding = FINDING_977,
    cell_ref = paste0("results:strategy_id=olmar (", n_total, " rows); universe"),
    resolved = FALSE
  )
}

if (length(rows) == 0L) {
  cat("seed_olmar_universe_critique: written=0 skipped=2\n")
  cat("  skipped (", CLASS_976, "and", CLASS_977,
      "critiques already hang off an OLMAR results row)\n")
  quit(save = "no", status = 1L)
}

before <- state$crit$uuid
tryCatch(
  invisible(hd_rlog_append("critiques", dplyr::bind_rows(rows), base_dir = base_dir)),
  error = function(e) indeterminate(paste("append failed:", conditionMessage(e)))
)

after <- hd_rlog_query("critiques", base_dir = base_dir)
new_rows <- after[!(after$uuid %in% before), , drop = FALSE]
cat("seed_olmar_universe_critique: written=", nrow(new_rows),
    " skipped=", 2L - length(rows), "\n", sep = "")
for (i in seq_len(nrow(new_rows))) {
  cat("  uuid:", new_rows$uuid[[i]], " defect_class:", new_rows$defect_class[[i]], "\n")
}
cat("  parent_uuid:", newest$uuid, "\n")
quit(save = "no", status = 0L)
