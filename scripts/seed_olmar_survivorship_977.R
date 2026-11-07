# Append ONE critiques row recording the SIZE of the OLMAR-1 survivorship bias
# (Refs #977). Method and verdicts: docs/olmar-universe-findings-976-977.md,
# section "#977 addendum (2026-11-04)". Producer of the numbers:
# scripts/olmar_survivorship_977.R; its committed output is
# docs/olmar-survivorship-977/*.csv.
#
# Every number in the finding is computed here from those CSVs (results.csv,
# deltas.csv, draws.csv, membership_classes.csv); none is typed. The qualitative
# survivorship row (defect_class survivorship-bias, "size unknown", written by
# scripts/seed_olmar_universe_critique.R) stays as it is: the log is
# append-only. This row adds the estimate and is told apart from it by its
# `cell_ref` (CELL_REF below), which is also the idempotency key. The defect_class
# is the log's existing value `survivorship-bias`.
#
# Why no hypothesis row: the tracked OLMAR-1 hypothesis rows already carry
# sample_spec "20 large-cap + ETF tickers" (none says 30), so there is no
# 30-ticker declaration in the log to correct. The ten absent SPDRs are recorded
# by the universe-mismatch critique (scripts/seed_olmar_universe_critique.R).
#
# Parent: the newest OLMAR results row (strategy_id "olmar", partition "full").
#
# Exit codes: 0 row appended, 1 nothing to write (already recorded), 3
# INDETERMINATE (log or CSVs unreadable, lineage missing; nothing written).
#
# Run (repo root):
#   nix develop . --command Rscript scripts/seed_olmar_survivorship_977.R
#
# Optional arguments: 1) research-log base_dir (tests/dry runs; default is the
# tracked inst/extdata/research_log/), 2) the CSV directory (default
# docs/olmar-survivorship-977).

pkgload::load_all(here::here("packages", "historicaldata"), quiet = TRUE)

args <- commandArgs(trailingOnly = TRUE)
base_dir <- if (length(args) >= 1L && nzchar(args[[1]])) args[[1]] else NULL
csv_dir  <- if (length(args) >= 2L) args[[2]] else
  here::here("docs", "olmar-survivorship-977")

OLMAR_CLAIM_PREFIX     <- "Equity prices mean-revert toward a short moving average"
OLMAR_PREDICTOR_PREFIX <- "MA/price ratio (OLMAR-1)"
DEFECT_CLASS <- "survivorship-bias"
CELL_REF_TAIL <- "survivorship size estimate (scripts/olmar_survivorship_977.R)"
GH <- "https://github.com/JohnGavin/historical"

indeterminate <- function(msg) {
  cat("seed_olmar_survivorship_977: INDETERMINATE -", msg, "\n")
  cat("  nothing was written\n")
  quit(save = "no", status = 3L)
}

rd <- function(f) {
  p <- file.path(csv_dir, f)
  if (!file.exists(p)) indeterminate(paste("missing input", p))
  tryCatch(utils::read.csv(p, stringsAsFactors = FALSE),
           error = function(e) indeterminate(paste("cannot read", p, conditionMessage(e))))
}

state <- tryCatch(list(
  hyp  = hd_rlog_query("hypotheses", base_dir = base_dir),
  impl = hd_rlog_query("implementations", base_dir = base_dir),
  res  = hd_rlog_query("results", base_dir = base_dir),
  crit = hd_rlog_query("critiques", base_dir = base_dir)
), error = function(e) indeterminate(paste("research log unreadable:", conditionMessage(e))))

olmar <- state$hyp[startsWith(state$hyp$economic_claim, OLMAR_CLAIM_PREFIX) &
                     startsWith(state$hyp$predictor, OLMAR_PREDICTOR_PREFIX), ,
                   drop = FALSE]
if (nrow(olmar) == 0L) indeterminate("no OLMAR-1 hypothesis row found")
impl_olmar <- state$impl[state$impl$parent_uuid %in% olmar$uuid, , drop = FALSE]
res_olmar  <- state$res[state$res$parent_uuid %in% impl_olmar$uuid &
                          state$res$strategy_id == "olmar" &
                          state$res$partition == "full", , drop = FALSE]
if (nrow(res_olmar) == 0L) indeterminate("no OLMAR full-period results rows via implementations")
res_olmar <- res_olmar[order(res_olmar$timestamp, res_olmar$uuid), , drop = FALSE]
newest <- res_olmar[nrow(res_olmar), , drop = FALSE]
n_total <- nrow(res_olmar)
# The idempotency key is the stable CELL_REF_TAIL, matched as a fixed substring:
# the full cell_ref embeds the row count at write time, which grows when a later
# OLMAR results row is appended, so it cannot be the key.
CELL_REF <- paste0("results:strategy_id=olmar partition=full (", n_total,
                   " rows); ", CELL_REF_TAIL)

if (any(grepl(CELL_REF_TAIL, state$crit$cell_ref, fixed = TRUE) &
          state$crit$parent_uuid %in% res_olmar$uuid, na.rm = TRUE)) {
  cat("seed_olmar_survivorship_977: written=0 skipped=1\n")
  cat("  skipped (the survivorship size estimate is already recorded)\n")
  quit(save = "no", status = 1L)
}

# ---- numbers, all from the CSVs -------------------------------------------
results <- rd("results.csv")
deltas  <- rd("deltas.csv")
draws   <- rd("draws.csv")
classes <- rd("membership_classes.csv")

pick <- function(u, s) {
  r <- results[results$universe == u & results$strategy == s &
                 results$period == "Full Period", , drop = FALSE]
  if (nrow(r) != 1L) indeterminate(paste("results.csv lacks one Full Period row for", u, s))
  r
}
cur_o <- pick("current", "OLMAR-1")
cur_e <- pick("current", "EqualWeight")
alt_o <- pick("alt_top_by_2009H2_dollar_volume", "OLMAR-1")
alt_e <- pick("alt_top_by_2009H2_dollar_volume", "EqualWeight")

dr <- draws[draws$period == "Full Period", , drop = FALSE]
do <- dr[dr$strategy == "OLMAR-1", , drop = FALSE]
de <- dr[dr$strategy == "EqualWeight", , drop = FALSE]
do <- do[order(do$draw), ]; de <- de[order(de$draw), ]
n_draws <- nrow(do)
if (n_draws == 0L || n_draws != nrow(de) || !identical(do$draw, de$draw)) {
  indeterminate("draws.csv does not hold paired OLMAR-1 / EqualWeight draws")
}
pct <- function(cur, x) round(100 * mean(cur > x))
gap_draw <- do$sharpe - de$sharpe

n_members <- sum(classes$n)
n_absent <- sum(classes$n[classes$class %in% c("absent_from_equity_daily",
                                               "delisted_per_source")])
if (n_absent == 0L || n_members == 0L) indeterminate("membership_classes.csv is empty")

dd <- function(s) deltas[deltas$strategy == s, , drop = FALSE]
d_o <- dd("OLMAR-1"); d_e <- dd("EqualWeight")
if (nrow(d_o) != 1L || nrow(d_e) != 1L) indeterminate("deltas.csv lacks the two strategy rows")

# Window literals: neither the CSVs nor the log hold the test window, so these
# come from scripts/olmar_survivorship_977.R (the producer: study window
# 2010-2026, membership snapshot S&P 500 as of 2010-01-04).
WINDOW <- "2010-2026"
MEMBERS_AS_OF <- "2010-01-04"

rng <- function(a, b) paste0(sprintf("%+.2f", min(a, b)), " to ", sprintf("%+.2f", max(a, b)))
f3 <- function(x) sprintf("%.3f", x)
f2 <- function(x) sprintf("%.2f", x)

FINDING <- paste0(
  "SURVIVORSHIP SIZE ESTIMATE. Universe is a 2026 list of current mega-caps ",
  "tested over ", WINDOW, "; equity_daily has no delistings and ", n_absent, " of ",
  n_members, " S&P 500 members as of ", MEMBERS_AS_OF, " are absent from it. Against ",
  n_draws, " random same-size universes of 2010 members present in the data, ",
  "OLMAR-1 Sharpe ", f3(cur_o$sharpe), " is at percentile ", pct(cur_o$sharpe, do$sharpe),
  " (median ", f3(stats::median(do$sharpe)), ") and equal-weight Sharpe ",
  f3(cur_e$sharpe), " at percentile ", pct(cur_e$sharpe, de$sharpe), " (median ",
  f3(stats::median(de$sharpe)), "). Hindsight inflates the absolute Sharpe by ",
  "about ", rng(cur_o$sharpe - stats::median(do$sharpe), d_o$d_sharpe),
  " (OLMAR-1) and ", rng(cur_e$sharpe - stats::median(de$sharpe), d_e$d_sharpe),
  " (equal-weight); it does not explain OLMAR-1's gap to ",
  "equal-weight (", f3(cur_o$sharpe - cur_e$sharpe), " vs random median ",
  f3(stats::median(gap_draw)), "). The delta is a floor: failed names cannot be ",
  "tested on this data. Liquidity-ranked alternative: OLMAR-1 Sharpe ",
  f3(alt_o$sharpe), ", equal-weight ", f3(alt_e$sharpe), ". The ", n_total,
  " OLMAR full-period results rows are append-only and unchanged. Script: ",
  "scripts/olmar_survivorship_977.R; details: ",
  "docs/olmar-universe-findings-976-977.md. Tracked in [#977](", GH,
  "/issues/977). This row is not a verdict on the strategy."
)

before <- state$crit$uuid
tryCatch(
  invisible(hd_rlog_append("critiques", tibble::tibble(
    parent_uuid = newest$uuid, defect_class = DEFECT_CLASS, severity = "major",
    finding = FINDING, cell_ref = CELL_REF, resolved = FALSE
  ), base_dir = base_dir)),
  error = function(e) indeterminate(paste("append failed:", conditionMessage(e)))
)

after <- hd_rlog_query("critiques", base_dir = base_dir)
new_rows <- after[!(after$uuid %in% before), , drop = FALSE]
cat("seed_olmar_survivorship_977: written=", nrow(new_rows), " skipped=0\n", sep = "")
cat("  uuid:", new_rows$uuid[[1]], " defect_class:", DEFECT_CLASS, "\n")
cat("  parent_uuid:", newest$uuid, "\n")
quit(save = "no", status = 0L)
