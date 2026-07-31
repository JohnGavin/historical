# Test the aligrithm "use SPX to time VIX, not vice versa" claim on our data.
#
# Source article:
#   https://aligrithm.com/chicken-and-egg-use-the-spx-to-time-the-vix-not-vice-versa/
# Issue: historical#611
#
# Exploration of data already in the canonical store (allowed under the
# reproducible-ingestion rule). No new source is being ingested here.
#
# Run:  nix develop . --command Rscript explorations/vix_spx_leadlag/run.R
# Last output committed at results/run_output.txt (8351 rows, 1993-02 to 2026-04).
#
# READ THE CAVEATS BEFORE QUOTING ANY NUMBER FROM THIS:
#
#  1. Daily closes cannot resolve intraday causality. VIX is computed from SPX
#     options quoted at the same instant, so at daily frequency the two are
#     contemporaneous by construction (measured cor = -0.79). The article's
#     mechanical claim ("VIX is a reaction to SPX") is true by definition and
#     is NOT testable at this frequency.
#  2. Section 3's two regressors are 79% correlated (VIF ~2.7), so standard
#     errors are inflated roughly 1.6x. The asymmetry reported is large enough
#     to survive that, but the coefficients are not precisely identified.
#  3. Section 4's t-statistics are NOT valid inference. The rolling windows
#     overlap n-deep, so effective sample size is far below the reported n.
#     See historical#601 (K_eff_xs). They are printed as a magnitude cue only.
#  4. We hold VIX SPOT, not VX FUTURES. The article's headline backtest is a
#     short-VX strategy and CANNOT be replicated here. Sections 2-5 test the
#     lead-lag and filter-quality claims, not the tradeable one.
#  5. In-sample throughout. No train/test split, no walk-forward.

suppressMessages(pkgload::load_all("packages/historicaldata", quiet = TRUE))
suppressMessages(library(dplyr))

cat("=== 1. Load and align ===\n")
spy <- hd_ohlcv("SPY")
vix <- hd_macro("VIXCLS")

# Memory: Date vs POSIXct silently joins to 0 rows. Coerce defensively.
cat("SPY date class:", paste(class(spy$date), collapse = "/"), "\n")
cat("VIX date class:", paste(class(vix$date), collapse = "/"), "\n")

spy <- spy |> mutate(date = as.Date(date)) |> arrange(date)
vix <- vix |> mutate(date = as.Date(date)) |> arrange(date)

cat("SPY rows:", nrow(spy), " range:", format(min(spy$date)), "-", format(max(spy$date)), "\n")
cat("VIX rows:", nrow(vix), " NA values:", sum(is.na(vix$value)), "\n")

px_col <- if ("adjusted_close" %in% names(spy)) "adjusted_close" else "close"
cat("SPY price column used:", px_col, "\n")

d <- spy |>
  select(date, px = all_of(px_col)) |>
  inner_join(vix |> select(date, vix = value), by = "date") |>
  arrange(date) |>
  mutate(
    spx_ret = (px - lag(px)) / lag(px),
    vix_chg = vix - lag(vix)
  )

cat("joined rows:", nrow(d), "\n")
d <- d |> filter(!is.na(spx_ret), !is.na(vix_chg), !is.na(vix))
cat("complete rows after NA filter:", nrow(d),
    " range:", format(min(d$date)), "-", format(max(d$date)), "\n")
cat("contemporaneous cor(spx_ret, vix_chg):",
    round(cor(d$spx_ret, d$vix_chg), 4), "\n\n")

cat("=== 2. Cross-correlation lead-lag ===\n")
cat("cor( spx_ret[t] , vix_chg[t+k] ). k>0 means SPX moves FIRST.\n")
for (k in -5:5) {
  if (k >= 0) {
    x <- d$spx_ret[seq_len(nrow(d) - k)]
    y <- d$vix_chg[(1 + k):nrow(d)]
  } else {
    x <- d$spx_ret[(1 - k):nrow(d)]
    y <- d$vix_chg[seq_len(nrow(d) + k)]
  }
  cat(sprintf("  k = %+d : %+.4f%s\n", k, cor(x, y),
              if (k == 0) "   <- contemporaneous" else ""))
}

cat("\n=== 3. Predictive asymmetry (the actual thesis) ===\n")
cat("Does SPX predict tomorrow's VIX more than VIX predicts tomorrow's SPX?\n")
cat("Each direction controls for the target's own lag.\n\n")

d2 <- d |>
  mutate(
    spx_next = lead(spx_ret),
    vix_next = lead(vix_chg)
  ) |>
  filter(!is.na(spx_next), !is.na(vix_next))

m_spx_to_vix <- lm(vix_next ~ spx_ret + vix_chg, data = d2)
m_vix_to_spx <- lm(spx_next ~ vix_chg + spx_ret, data = d2)

s1 <- summary(m_spx_to_vix); s2 <- summary(m_vix_to_spx)
c1 <- coef(s1)["spx_ret", ]; c2 <- coef(s2)["vix_chg", ]

report <- function(label, cf, sm) {
  p <- cf["Pr(>|t|)"]
  # NB: sm$r.squared is the FULL-MODEL R2 (both regressors), not the partial
  # R2 of the named coefficient. Labelled accordingly.
  cat(sprintf("%s\n  beta = %+.4f  t = %+.2f  p = %.3g  FPR@equipoise = %s  model R2 = %.5f\n",
              label, cf["Estimate"], cf["t value"], p,
              ifelse(is.na(hd_fpr_equipoise(p)), "n/a (p >= 1/e)",
                     sprintf("%.3f", hd_fpr_equipoise(p))),
              sm$r.squared))
}
report("SPX_t -> VIX_{t+1}  (controlling VIX_t)", c1, s1)
report("VIX_t -> SPX_{t+1}  (controlling SPX_t)", c2, s2)

cat("\n=== 4. Levy area: does SPX lead VIX within the window? ===\n")
cat("hd_levy_area sign convention: positive = FIRST series leads.\n")
for (n in c(5L, 10L, 21L, 63L)) {
  la <- hd_roll_levy_area(d$spx_ret, d$vix_chg, n = n, scale = TRUE)
  ok <- !is.na(la)
  frac_pos <- mean(la[ok] > 0)
  tt <- t.test(la[ok])
  cat(sprintf("  window %2d: mean = %+.4f  frac>0 = %.3f  t = %+.2f  n = %d\n",
              n, mean(la[ok]), frac_pos, tt$statistic, sum(ok)))
}

cat("\n=== 5. RSI(2) conditional asymmetry (the article's own signal) ===\n")
rsi2 <- function(x, n = 2L) {
  ch <- c(NA, diff(x))
  g <- pmax(ch, 0); l <- pmax(-ch, 0)
  ag <- slider::slide_dbl(g, mean, .before = n - 1L, .complete = TRUE)
  al <- slider::slide_dbl(l, mean, .before = n - 1L, .complete = TRUE)
  ifelse(al == 0, 100, 100 - 100 / (1 + ag / al))
}

d3 <- d |>
  mutate(
    spx_rsi2 = rsi2(px),
    vix_rsi2 = rsi2(vix),
    spx_next = lead(spx_ret),
    vix_next = lead(vix_chg)
  ) |>
  filter(!is.na(spx_rsi2), !is.na(vix_rsi2), !is.na(spx_next), !is.na(vix_next))

sig_spx <- d3 |> filter(spx_rsi2 <= 20)
sig_vix <- d3 |> filter(vix_rsi2 <= 20)

cat(sprintf("SPX RSI(2) <= 20  : n = %4d (%.1f%% of days)\n",
            nrow(sig_spx), 100 * nrow(sig_spx) / nrow(d3)))
cat(sprintf("   next-day SPX ret : mean %+.4f%%  win rate %.1f%%\n",
            100 * mean(sig_spx$spx_next), 100 * mean(sig_spx$spx_next > 0)))
cat(sprintf("   next-day VIX chg : mean %+.4f    down-rate %.1f%%\n",
            mean(sig_spx$vix_next), 100 * mean(sig_spx$vix_next < 0)))

cat(sprintf("\nVIX RSI(2) <= 20  : n = %4d (%.1f%% of days)\n",
            nrow(sig_vix), 100 * nrow(sig_vix) / nrow(d3)))
cat(sprintf("   next-day SPX ret : mean %+.4f%%  win rate %.1f%%\n",
            100 * mean(sig_vix$spx_next), 100 * mean(sig_vix$spx_next > 0)))
cat(sprintf("   next-day VIX chg : mean %+.4f    down-rate %.1f%%\n",
            mean(sig_vix$vix_next), 100 * mean(sig_vix$vix_next < 0)))

cat(sprintf("\nunconditional     : n = %4d\n", nrow(d3)))
cat(sprintf("   next-day SPX ret : mean %+.4f%%  win rate %.1f%%\n",
            100 * mean(d3$spx_next), 100 * mean(d3$spx_next > 0)))
cat(sprintf("   next-day VIX chg : mean %+.4f    down-rate %.1f%%\n",
            mean(d3$vix_next), 100 * mean(d3$vix_next < 0)))
