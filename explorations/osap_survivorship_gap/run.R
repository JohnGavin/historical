# OSAP survivorship-gap comparison (#816, #862)
#
# Compares a 12-2 cross-sectional momentum long-short built from OUR OWN
# equity_daily-derived panel (survivorship_biased = TRUE, known_delistings
# = 0) against Open Source Asset Pricing's `Mom12m` -- the same signal,
# built by Chen & Zimmermann from CRSP, a delisting-inclusive universe
# (#862 P1: 86.7% of firm-level permnos exit >1yr before the panel end,
# vs 0% for our equity_daily universe).
#
# This is NOT a clean survivorship-only measurement. Beyond the
# delisting/survivorship difference, the two series differ in universe
# size and composition (our 529-name LTR universe of currently-listed
# large/mid caps vs. CRSP's full common-stock universe), portfolio
# construction (our independent terciles vs. OSAP's own documented sort),
# and possibly value- vs. equal-weighting. Any gap reported here is the
# COMBINED effect of survivorship bias AND universe/construction
# differences -- it cannot be attributed to survivorship alone. Labelled
# as such throughout, per this exploration's brief.
#
# Momentum construction below follows the same signal definition used and
# validated in explorations/momentum_max_lottery/run.R (12-2 momentum,
# skip month t-1, hold month t+1, look-ahead guarded by dplyr::lag()/
# lead() only) -- re-implemented here against a tar_read()'d monthly
# panel rather than re-querying equity_daily from scratch, per this
# exploration's write-scope (read-only access to the main checkout's
# targets store).
#
# NOTHING panel-shaped from OSAP is committed here (#862 P3 -- no data
# licence found; operating position is compute-freely/publish-derived-
# statistics-only). Only scalar/summary statistics are written to
# results/.
#
# CORRECTION (#900 review round): the first version of this script keyed
# the aggregated strategy return by the FORMATION month (`midx`) while
# `hold_ret` is actually the return EARNED the following month (formation
# `midx` + 1, from `dplyr::lead(monthly_ret, 1L)`). OSAP's `Mom12m` is keyed
# by the month the return is earned (see `hd_osap_load()`'s `date` field
# docs). Joining our formation-keyed series to OSAP's earn-keyed series by
# raw `midx` therefore compared our month-(t+1) return to OSAP's month-t
# return -- a one-month misalignment. Fixed below by explicitly relabelling
# our aggregated return with `earn_midx = midx + 1L` (the month it is
# actually earned) BEFORE any join, in the construction itself rather than
# as a `+1` patched onto the join call. An alignment guard (section 1b)
# and a plausibility guard on the resulting correlation (section 5) both
# exist so this defect cannot silently reappear.

suppressMessages(pkgload::load_all("packages/historicaldata", quiet = TRUE))
suppressMessages({
  library(dplyr)
  library(tidyr)
})

RESULTS_DIR <- "explorations/osap_survivorship_gap/results"
dir.create(RESULTS_DIR, showWarnings = FALSE, recursive = TRUE)

# Main checkout's targets store -- READ ONLY (per this dispatch's task
# scope; this worktree has no store of its own and must never write one).
MAIN_STORE <- Sys.getenv(
  "HD_MAIN_TARGETS_STORE",
  "/Users/johngavin/docs_gh/proj/finance/data/historical/docs/_targets"
)

MIN_STOCKS_PER_MONTH <- 30L  # matches explorations/momentum_max_lottery/run.R

cat("========================================================\n")
cat("OSAP survivorship-gap comparison -- exploration run\n")
cat("========================================================\n\n")

# ── 1. Our own 12-2 momentum long-short, from the tar-read monthly panel ────
cat("=== 1. Load stock_returns_monthly from the main checkout's store ===\n")
if (!dir.exists(MAIN_STORE)) {
  cli::cli_abort(c(
    "x" = "Main targets store not found at {.path {MAIN_STORE}}.",
    "i" = "Set HD_MAIN_TARGETS_STORE to the main checkout's docs/_targets path."
  ))
}
monthly <- targets::tar_read(stock_returns_monthly, store = MAIN_STORE)
cat(sprintf(
  "loaded %d rows, %d tickers, %s to %s\n\n",
  nrow(monthly), dplyr::n_distinct(monthly$ticker),
  format(min(monthly$date)), format(max(monthly$date))
))

monthly <- monthly |>
  mutate(midx = as.integer(format(date, "%Y")) * 12L + as.integer(format(date, "%m")))

# Month-contiguity guard (same rationale as momentum_max_lottery/run.R):
# build a complete per-ticker calendar-month grid so lag()/lead() are safe
# positional operations rather than silently skipping over trading gaps.
full_grid <- monthly |>
  group_by(ticker) |>
  summarise(min_midx = min(midx), max_midx = max(midx), .groups = "drop") |>
  rowwise() |>
  mutate(midx = list(seq.int(min_midx, max_midx))) |>
  ungroup() |>
  select(ticker, midx) |>
  unnest(midx)

monthly_full <- full_grid |>
  left_join(monthly |> select(ticker, midx, monthly_ret), by = c("ticker", "midx")) |>
  arrange(ticker, midx)

sig_all <- monthly_full |>
  group_by(ticker) |>
  arrange(midx, .by_group = TRUE) |>
  mutate(
    shifted2 = dplyr::lag(monthly_ret, 2L),
    mom_12_2 = slider::slide_dbl(shifted2, ~ prod(1 + .x) - 1, .before = 10L, .complete = TRUE),
    # hold_ret is the return EARNED the month AFTER formation -- i.e. the
    # calendar month whose return this portfolio actually holds is
    # (midx + 1), not midx. earn_midx makes that explicit so every
    # downstream aggregation/join uses the correct calendar-month key
    # (see the "CORRECTION" note at the top of this file, #900).
    hold_ret = dplyr::lead(monthly_ret, 1L),
    earn_midx = midx + 1L
  ) |>
  ungroup()

sig <- sig_all |> filter(!is.na(mom_12_2), !is.na(hold_ret))
cat(sprintf("usable formation rows (full mom_12_2 + hold_ret window): %d\n", nrow(sig)))

# ── 1b. Alignment guard (#900 review round) ────────────────────────────────
# This is a STRUCTURAL check, not a modelling result: it verifies that
# hold_ret, keyed to earn_midx, is literally equal to the ORIGINAL
# monthly_ret recorded for that ticker in that same calendar month. This is
# exactly the property that was violated by the pre-fix code (which kept
# the formation month as the join key), and is cheap enough to run on every
# invocation rather than trust the arithmetic silently.
alignment_probe <- sig |>
  select(ticker, earn_midx, hold_ret) |>
  inner_join(
    monthly_full |> select(ticker, midx, monthly_ret),
    by = c("ticker" = "ticker", "earn_midx" = "midx")
  )
if (nrow(alignment_probe) == 0L) {
  cli::cli_abort(c(
    "x" = "Alignment guard could not verify hold_ret against monthly_ret.",
    "i" = "No rows matched on (ticker, earn_midx) between sig and monthly_full -- check the midx/earn_midx bookkeeping before trusting anything below."
  ))
}
if (!isTRUE(all.equal(alignment_probe$hold_ret, alignment_probe$monthly_ret, check.attributes = FALSE))) {
  cli::cli_abort(c(
    "x" = "Alignment guard failed: hold_ret != monthly_ret at earn_midx for one or more rows.",
    "i" = "This is the exact one-month misalignment fixed in #900's review round (formation midx used where the earn month was required) -- do not trust any metric below until this is fixed."
  ))
}
cat(sprintf(
  "alignment guard: hold_ret == monthly_ret at earn_midx for all %d checked (ticker, month) rows (OK)\n\n",
  nrow(alignment_probe)
))

month_counts <- sig |> group_by(midx) |> summarise(n_stocks = dplyr::n(), .groups = "drop")
good_months <- month_counts |> filter(n_stocks >= MIN_STOCKS_PER_MONTH)
sig <- sig |> semi_join(good_months, by = "midx")
cat(sprintf(
  "months with >= %d stocks: %d of %d candidate months; formation rows retained: %d\n\n",
  MIN_STOCKS_PER_MONTH, nrow(good_months), nrow(month_counts), nrow(sig)
))

sig <- sig |>
  group_by(midx) |>
  mutate(mom_tercile = dplyr::ntile(mom_12_2, 3L)) |>
  ungroup()

# Cross-sectional tercile membership is (correctly) assigned per FORMATION
# month (midx) -- that is when the ranking is known. But the RETURN each
# name contributes is earned in the following month, so the aggregation
# below groups by earn_midx (not midx), producing a strategy return series
# keyed by the calendar month whose return it actually is -- the same
# convention OSAP's Mom12m uses (see the "CORRECTION" note at the top of
# this file).
bucket_ret <- sig |>
  group_by(earn_midx, mom_tercile) |>
  summarise(ew_ret = mean(hold_ret), n = dplyr::n(), .groups = "drop")

our_long <- bucket_ret |> filter(mom_tercile == 3) |> select(midx = earn_midx, long_ret = ew_ret) |> arrange(midx)
our_short <- bucket_ret |> filter(mom_tercile == 1) |> select(midx = earn_midx, short_ret = ew_ret) |> arrange(midx)
our_mom_strat <- inner_join(our_long, our_short, by = "midx") |>
  mutate(gross_ret = long_ret - short_ret) |>
  arrange(midx)
# NOTE: `midx` in `our_mom_strat` (and everywhere downstream) now denotes
# the EARN month, matching OSAP's `Mom12m` convention -- not the formation
# month used inside `sig` above.

midx_to_ym <- function(m) sprintf("%04d-%02d", (m - 1L) %/% 12L, (m - 1L) %% 12L + 1L)
cat(sprintf(
  "our_mom_plain (equity_daily-based, 12-2, equal-weighted terciles): %d months, %s to %s\n\n",
  nrow(our_mom_strat), midx_to_ym(min(our_mom_strat$midx)), midx_to_ym(max(our_mom_strat$midx))
))

# ── 2. OSAP Mom12m ────────────────────────────────────────────────────────
cat("=== 2. Load OSAP Mom12m via hd_osap_load() ===\n")
osap <- hd_osap_load()
mom12m <- osap |>
  filter(predictor == "Mom12m") |>
  mutate(midx = as.integer(format(date, "%Y")) * 12L + as.integer(format(date, "%m"))) |>
  select(midx, osap_ret = ret) |>
  arrange(midx)
cat(sprintf(
  "OSAP Mom12m: %d months, %s to %s\n\n",
  nrow(mom12m), format(osap$date[osap$predictor == "Mom12m"][1]),
  format(max(osap$date[osap$predictor == "Mom12m"]))
))

# ── 3. Overlap window + comparison ───────────────────────────────────────
cat("=== 3. Overlap window ===\n")
joined <- inner_join(our_mom_strat, mom12m, by = "midx") |> arrange(midx)
cat(sprintf(
  "overlapping months (both series present): %d, midx %d to %d\n\n",
  nrow(joined), min(joined$midx), max(joined$midx)
))

compute_metrics <- function(r, ann_factor = 12) {
  r <- r[!is.na(r)]
  n <- length(r)
  hac <- hd_hac_sharpe(r, ann_factor = ann_factor)
  cagr <- prod(1 + r)^(ann_factor / n) - 1
  list(n_months = n, ann_ret_cagr = cagr, ann_vol = hac$annualised_vol, sharpe = hac$naive_sharpe)
}

detection_verdict <- function(sharpe_annual, n_obs) {
  if (is.na(sharpe_annual) || sharpe_annual <= 0) {
    return(list(power = NA_real_, underpowered = NA, min_n_years = NA_real_,
                verdict = "N/A (non-positive Sharpe)"))
  }
  d <- hd_detection_power(sharpe_annual = sharpe_annual, n_obs = n_obs, ann_factor = 12)
  d$verdict <- if (isTRUE(d$underpowered)) "UNDERPOWERED" else "adequately powered"
  d
}

report_row <- function(label, r) {
  m <- compute_metrics(r)
  dp <- detection_verdict(m$sharpe, m$n_months)
  cat(sprintf("--- %s ---\n", label))
  cat(sprintf(
    "  n=%d months (%.1f yr)  CAGR=%+.2f%%  ann_vol=%.2f%%  sharpe=%+.3f  detection=%s (needs %.1f yr @ 80%% power)\n\n",
    m$n_months, m$n_months / 12, 100 * m$ann_ret_cagr, 100 * m$ann_vol, m$sharpe,
    dp$verdict, if (is.na(dp$min_n_years)) NA_real_ else dp$min_n_years
  ))
  tibble::tibble(
    label = label, n_months = m$n_months, ann_ret_cagr = m$ann_ret_cagr,
    ann_vol = m$ann_vol, sharpe = m$sharpe, detection_verdict = dp$verdict,
    min_n_years_for_80pct_power = dp$min_n_years
  )
}

cat("=== 4. Metrics over the overlap window ===\n\n")
row_ours <- report_row("our_mom_plain (equity_daily, survivorship-biased) -- OVERLAP window", joined$gross_ret)
row_osap <- report_row("OSAP Mom12m (CRSP, delisting-inclusive) -- OVERLAP window", joined$osap_ret)

# Also report OSAP Mom12m over its FULL available sample (not just the
# overlap), since #816's cited figure (Sharpe 0.163, 231yr needed) was
# for our own full-sample 12-2 momentum, not the overlap-restricted one.
row_ours_full <- report_row("our_mom_plain (equity_daily) -- FULL available sample", our_mom_strat$gross_ret)
row_osap_full <- report_row("OSAP Mom12m -- FULL available sample (1927-2024)", mom12m$osap_ret)

corr_overlap <- stats::cor(joined$gross_ret, joined$osap_ret, use = "complete.obs")
cat(sprintf(
  "=== 5. Correlation of monthly returns over the overlap window: %.3f ===\n\n",
  corr_overlap
))

# Plausibility guard (#900 review round), NOT a modelling result: two
# independently-built 12-2 momentum long-short series sharing the same
# underlying signal and largely overlapping calendar months are expected to
# be positively correlated. A negative correlation here is a strong signal
# of a reintroduced month-key misalignment (the exact defect this fix
# addresses -- shifting the pre-fix series by +1 month raised its
# correlation with OSAP from -0.051 to +0.578) rather than evidence about
# survivorship or universe differences. This warns rather than aborts,
# since the alignment_probe check above is the deterministic guard; this is
# a softer, second-line signal in case some other future change drifts the
# keys again.
if (!is.na(corr_overlap) && corr_overlap < 0) {
  cli::cli_warn(c(
    "!" = "Correlation vs OSAP Mom12m over the overlap window is negative ({round(corr_overlap, 3)}).",
    "i" = "Two independently-built 12-2 momentum series sharing the same signal are expected to correlate positively -- re-check the midx/earn_midx keying before trusting the metrics below (see #900)."
  ))
}

common_signal_note <- if (!is.na(corr_overlap) && corr_overlap >= 0.2) {
  paste0(
    "A clearly positive correlation, as found here, means the two series DO ",
    "share real common signal -- so the Sharpe/CAGR/volatility gap reported ",
    "below is more plausibly attributable to universe, construction, and/or ",
    "survivorship differences acting on a shared underlying momentum factor, ",
    "rather than to two unrelated portfolios."
  )
} else {
  paste0(
    "This correlation is not clearly positive, which is more consistent with ",
    "the two portfolios holding substantially different stocks in most ",
    "months than with 'the same signal, minus its worst tail' -- see the ",
    "plausibility guard above before trusting this as a survivorship-only ",
    "finding."
  )
}
cat(paste0(
  "Interpretation: a correlation well below 1 (here, ", sprintf("%.3f", corr_overlap),
  ") confirms the two series are NOT the same portfolio measured twice -- ",
  "independent tercile construction, universe composition (529 ",
  "currently-listed large/mid caps vs. CRSP's full common-stock universe), ",
  "and possibly weighting all differ, on top of the survivorship difference. ",
  common_signal_note,
  " It still cannot, on its own, isolate survivorship's contribution from ",
  "the other differences.\n\n"
))

summary_tbl <- dplyr::bind_rows(row_ours, row_osap, row_ours_full, row_osap_full) |>
  mutate(correlation_vs_osap_overlap = c(corr_overlap, NA, NA, NA))

readr_ok <- requireNamespace("readr", quietly = TRUE)
if (readr_ok) {
  readr::write_csv(summary_tbl, file.path(RESULTS_DIR, "summary_metrics.csv"))
} else {
  write.csv(summary_tbl, file.path(RESULTS_DIR, "summary_metrics.csv"), row.names = FALSE)
}

cat("=== Summary table ===\n")
print(as.data.frame(summary_tbl))

cat("\n========================================================\n")
cat("Run complete. Outputs written to:", RESULTS_DIR, "\n")
cat("========================================================\n")
