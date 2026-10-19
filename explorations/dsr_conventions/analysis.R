# Deflated-Sharpe "V" conventions: multiplier (a) vs standard (b).  Refs #959.
#
# (a) multiplier : hurdle_pp = E[max Z_K] * sqrt(V_mult) / sqrt(T)
#                  (what hd_deflated_sharpe() does; trial_sharpe_var = V_mult)
# (b) standard   : hurdle_pp = E[max Z_K] * sqrt(V_stat)
#                  V_stat = variance of the K trial Sharpe ratios in the
#                  statistic's units (per period).  V_stat = V_ann / ann_factor.
# V_mult = T * V_stat makes (a) and (b) identical.  Everything is per period
# unless suffixed _ann.  (a) is always evaluated by the real
# hd_deflated_sharpe(); (b) is computed directly from hd_expected_max_normal().
#
# Run:  nix develop <worktree> --command Rscript explorations/dsr_conventions/analysis.R
# Output goes to stdout (saved as results/analysis_output.txt) and CSVs in results/.

options(width = 140, digits = 5)
args <- commandArgs(FALSE)
script_file <- sub("^--file=", "", args[grep("^--file=", args)])
script_dir <- dirname(normalizePath(script_file))
root <- normalizePath(file.path(script_dir, "..", ".."))
res_dir <- file.path(script_dir, "results")
dir.create(res_dir, showWarnings = FALSE)

pkgload::load_all(file.path(root, "packages", "historicaldata"), quiet = TRUE)

emax <- local({
  cache <- new.env()
  function(K) {
    key <- as.character(K)
    if (is.null(cache[[key]])) cache[[key]] <- hd_expected_max_normal(K)
    cache[[key]]
  }
})

# ---- the two conventions -----------------------------------------------------
h_a_pp <- function(K, T, Vm) emax(K) * sqrt(Vm) / sqrt(T)   # multiplier
h_b_pp <- function(K, Vs) emax(K) * sqrt(Vs)                # standard
dsr_p <- function(sr_pp, T, h_pp, m3 = 0, m4 = 3) {         # same stat as hd_deflated_sharpe()
  v <- (1 - m3 * sr_pp + (m4 - 1) / 4 * sr_pp^2) / T
  1 - stats::pnorm((sr_pp - h_pp) / sqrt(pmax(v, .Machine$double.eps)))
}
dsr_p_series <- function(r, h_pp) {
  mu <- mean(r); s <- stats::sd(r); sr <- mu / s; n <- length(r)
  m3 <- sum((r - mu)^3) / n / s^3; m4 <- sum((r - mu)^4) / n / s^4
  dsr_p(sr, n, h_pp, m3, m4)
}
mc_se <- function(p, n) sqrt(p * (1 - p) / n)

cat("== 0. Premise check and self-tests ==\n")
cat("Premise: hd_deflated_sharpe() hurdle = hd_expected_max_normal(K) * sqrt(trial_sharpe_var) / sqrt(T_obs),",
    "compared with the per-period Sharpe (packages/historicaldata/R/falsification.R lines 910-914). CONFIRMED by reading the code.\n")
set.seed(1)
r_chk <- stats::rnorm(500, 0.0004, 0.01)
for (K in c(2, 14, 50)) for (Vm in c(1, 0.3, 4)) {
  fn <- hd_deflated_sharpe(r_chk, K_trials = K, ann_factor = 252L, trial_sharpe_var = Vm)$dsr_pvalue
  own <- dsr_p_series(r_chk, h_a_pp(K, length(r_chk), Vm))
  stopifnot(isTRUE(all.equal(fn, own, tolerance = 1e-12)))
}
cat("Parity: own DSR p-value reproduces hd_deflated_sharpe() to 1e-12 for 9 (K, V) cells.\n")

# Identity check: (a) with V_mult = T * V_stat must equal (b).  This is the
# "ratio check" that the falsification below breaks on purpose.
ratio_check <- function(vm_of, tol = 1e-12) {
  worst <- 0
  for (K in c(2, 14, 50)) for (T in c(74, 1000, 4063)) for (Vs in c(1e-5, 4e-4, 2e-3)) {
    ratio <- h_a_pp(K, T, vm_of(T, Vs)) / h_b_pp(K, Vs)
    worst <- max(worst, abs(ratio - 1))
  }
  list(pass = worst < tol, worst_abs_dev = worst)
}
good <- ratio_check(function(T, Vs) T * Vs)
cat(sprintf("Ratio check, V_mult = T * V_stat      : %s (max |ratio-1| = %.3g)\n",
            if (good$pass) "GREEN" else "RED", good$worst_abs_dev))
bad1 <- ratio_check(function(T, Vs) Vs)
bad2 <- ratio_check(function(T, Vs) Vs * 252)
cat(sprintf("FALSIFICATION, V_mult = V_stat (wrong units)        : %s (max |ratio-1| = %.3g)\n",
            if (bad1$pass) "GREEN" else "RED", bad1$worst_abs_dev))
cat(sprintf("FALSIFICATION, V_mult = 252 * V_stat (annualised)   : %s (max |ratio-1| = %.3g)\n",
            if (bad2$pass) "GREEN" else "RED", bad2$worst_abs_dev))
stopifnot(good$pass, !bad1$pass, !bad2$pass)
cat("Restored: control GREEN, both deliberately broken variants RED, as required.\n\n")

# ---- 1. real inputs ----------------------------------------------------------
cat("== 1. Real inputs ==\n")
store <- Sys.getenv("HD_STORE", unset = "")
if (!nzchar(store)) {
  common <- system2("git", c("-C", root, "rev-parse", "--path-format=absolute", "--git-common-dir"),
                    stdout = TRUE)
  store <- file.path(dirname(common), "docs", "_targets")
}
inp_lb <- file.path(res_dir, "inputs_leaderboard.csv")
inp_drif <- file.path(res_dir, "inputs_drif_multiverse.csv")
inp_aw <- file.path(res_dir, "inputs_aw_multiverse.csv")
if (file.exists(file.path(store, "meta", "meta"))) {
  src <- paste0("targets store (read-only): ", store)
  lb <- targets::tar_read(leaderboard, store = store)
  lb <- as.data.frame(lb[lb$period == "Full Period",
                         c("strategy", "months", "years", "sharpe", "hac_sharpe", "dsr_pvalue",
                           "k_eff_leaderboard", "k_raw_leaderboard")])
  dm <- as.data.frame(targets::tar_read(drif_multiverse, store = store)[, c("n_months", "oos_sharpe")])
  aw <- as.data.frame(targets::tar_read(aw_multiverse, store = store)[, c("n_days", "n_switches", "oos_sharpe")])
  utils::write.csv(lb, inp_lb, row.names = FALSE)
  utils::write.csv(dm, inp_drif, row.names = FALSE)
  utils::write.csv(aw, inp_aw, row.names = FALSE)
} else {
  src <- "tracked inputs_*.csv (store unavailable)"
  lb <- utils::read.csv(inp_lb); dm <- utils::read.csv(inp_drif); aw <- utils::read.csv(inp_aw)
}
cat("Input source:", src, "\n")
cat("Note: the store leaderboard passes trial_sharpe_var = 1 (default) to hd_deflated_sharpe(); no per-strategy V exists.\n")
cat("Note: leaderboard column `months` is the native-frequency observation count (days for daily strategies).\n")
cat("      ann_factor is inferred as 252 if T >= 2000 else 12 (checked against `years` where present).\n\n")

lb$af <- ifelse(lb$months >= 2000, 252, 12)
chk <- !is.na(lb$years)
stopifnot(all(abs(lb$months[chk] / lb$years[chk] - lb$af[chk]) / lb$af[chk] < 0.01))
lb$sr_pp <- lb$sharpe / sqrt(lb$af)

compare_row <- function(name, K, T, af, sr_pp, V_ann, se_pp = NULL, note = "") {
  Vs <- V_ann / af
  ha <- h_a_pp(K, T, V_ann); hb <- h_b_pp(K, Vs); h1 <- h_a_pp(K, T, 1)
  p_of <- function(h) if (is.null(se_pp)) dsr_p(sr_pp, T, h) else 1 - stats::pnorm((sr_pp - h) / se_pp)
  data.frame(name = name, K = K, T = T, af = af, sharpe_ann = sr_pp * sqrt(af), V_ann = V_ann,
             hurdle_a1_ann = h1 * sqrt(af), hurdle_a_ann = ha * sqrt(af), hurdle_b_ann = hb * sqrt(af),
             ratio_a_over_b = ha / hb, ratio_a1_over_b = h1 / hb,
             p_a1 = p_of(h1), p_a = p_of(ha), p_b = p_of(hb), note = note)
}
pool_rows <- rbind(
  compare_row("DRIF pool as filed in #933", 16, 74, 12, 0.1034, 0.05687,
              note = "V, K, T, best per-period Sharpe as quoted in #933"),
  compare_row("DRIF pool, current store", 16, 74, 12,
              max(dm$oos_sharpe) / sqrt(12), stats::var(dm$oos_sharpe), note = "live var(oos_sharpe) of 16 specs"),
  compare_row("Avoid Worst pool, T = n_switches", 16, aw$n_switches[which.max(aw$oos_sharpe)], 252,
              max(aw$oos_sharpe) / sqrt(252), stats::var(aw$oos_sharpe),
              note = "T as coded in plan_avoid_worst_v2.R"),
  compare_row("Avoid Worst pool, T = n_days", 16, aw$n_days[which.max(aw$oos_sharpe)], 252,
              max(aw$oos_sharpe) / sqrt(252), stats::var(aw$oos_sharpe), note = "T = trading days")
)
pool_rows$b95_lo <- sqrt(stats::qchisq(0.025, pool_rows$K - 1) / (pool_rows$K - 1))
pool_rows$b95_hi <- sqrt(stats::qchisq(0.975, pool_rows$K - 1) / (pool_rows$K - 1))
pool_rows$a_inside_b95 <- pool_rows$ratio_a_over_b >= pool_rows$b95_lo & pool_rows$ratio_a_over_b <= pool_rows$b95_hi
print(pool_rows[, c("name", "K", "T", "af", "sharpe_ann", "V_ann", "hurdle_a1_ann", "hurdle_a_ann", "hurdle_b_ann")],
      row.names = FALSE, digits = 4)
print(pool_rows[, c("name", "ratio_a_over_b", "ratio_a1_over_b", "b95_lo", "b95_hi", "a_inside_b95", "p_a1", "p_a", "p_b")],
      row.names = FALSE, digits = 4)
cat("(a1 = default V = 1; a = V_mult set to the annual pool variance, i.e. the documented 'pass var(trial_sharpes)' usage;",
    "b = V_stat = V_ann/af.  Hurdles in annual Sharpe units.)\n\n")

# V_pool proxy for leaderboard: variance of the annual Full-Period Sharpes of all leaderboard rows
V_lb <- stats::var(lb$sharpe, na.rm = TRUE)
cat(sprintf("Leaderboard-wide proxy pool: var of annual Full-Period Sharpes over %d strategies = %.4f (a proxy, not the K_eff trial pool)\n",
            sum(!is.na(lb$sharpe)), V_lb))
lb_rows <- do.call(rbind, lapply(seq_len(nrow(lb)), function(i) {
  if (is.na(lb$k_eff_leaderboard[i]) || is.na(lb$sharpe[i])) return(NULL)
  compare_row(lb$strategy[i], lb$k_eff_leaderboard[i], lb$months[i], lb$af[i], lb$sr_pp[i], V_lb)
}))
lb_rows$p_stored <- lb$dsr_pvalue[match(lb_rows$name, lb$strategy)]
print(lb_rows[, c("name", "K", "T", "af", "sharpe_ann", "hurdle_a1_ann", "hurdle_a_ann", "hurdle_b_ann",
                  "ratio_a_over_b", "p_a1", "p_a", "p_b", "p_stored")], row.names = FALSE, digits = 3)
cat("p_a1 is a summary-statistic re-computation (normal moments); p_stored is the raw-series value from the store.\n")
cat(sprintf("max |p_a1 - p_stored| = %.3f (skew/kurtosis, rf basis and K non-integer use explain differences)\n\n",
            max(abs(lb_rows$p_a1 - lb_rows$p_stored), na.rm = TRUE)))

# OLMAR-1
cat("-- OLMAR-1 (K = 14, T = 4063, annual excess Sharpe 0.8117, HAC t 3.723; research-log series not reconstructed,",
    "summary numbers used) --\n")
ol_af <- 252; ol_sr <- 0.8117 / sqrt(ol_af); ol_T <- 4063; ol_K <- 14
ol_rows <- rbind(
  transform(compare_row("OLMAR-1, iid-normal SE, V_pool = leaderboard proxy", ol_K, ol_T, ol_af, ol_sr, V_lb)),
  compare_row("OLMAR-1, HAC-implied SE (sr/t), V_pool = leaderboard proxy", ol_K, ol_T, ol_af, ol_sr, V_lb,
              se_pp = ol_sr / 3.723),
  compare_row("OLMAR-1, HAC-implied SE, V_pool = 0.05", ol_K, ol_T, ol_af, ol_sr, 0.05, se_pp = ol_sr / 3.723),
  compare_row("OLMAR-1, HAC-implied SE, V_pool = 0.25", ol_K, ol_T, ol_af, ol_sr, 0.25, se_pp = ol_sr / 3.723)
)
print(ol_rows[, c("name", "hurdle_a1_ann", "hurdle_a_ann", "hurdle_b_ann", "ratio_a_over_b", "ratio_a1_over_b")],
      row.names = FALSE, digits = 4)
print(ol_rows[, c("name", "p_a1", "p_a", "p_b")], row.names = FALSE, digits = 4)
cat("(HAC-implied SE = per-period Sharpe / 3.723; the iid row uses the normal-moment SE.  The first two rows differ only in SE.)\n")
cat("\n")
utils::write.csv(pool_rows, file.path(res_dir, "real_inputs_pools.csv"), row.names = FALSE)
utils::write.csv(ol_rows, file.path(res_dir, "real_inputs_olmar.csv"), row.names = FALSE)
utils::write.csv(lb_rows, file.path(res_dir, "real_inputs_leaderboard.csv"), row.names = FALSE)

# ---- 2. grid -----------------------------------------------------------------
cat("== 2. Grid (ann_factor 252) ==\n")
grid <- expand.grid(K = c(2, 5, 10, 14, 17, 50), T = c(74, 252, 1000, 4063),
                    V_ann = c(0.01, 0.05, 0.1, 0.25, 0.5, 1.0))
af <- 252
grid$hurdle_a1_ann <- mapply(h_a_pp, grid$K, grid$T, 1) * sqrt(af)
grid$hurdle_a_ann <- mapply(h_a_pp, grid$K, grid$T, grid$V_ann) * sqrt(af)
grid$hurdle_b_ann <- mapply(h_b_pp, grid$K, grid$V_ann / af) * sqrt(af)
grid$ratio_a_over_b <- grid$hurdle_a_ann / grid$hurdle_b_ann
grid$ratio_a1_over_b <- grid$hurdle_a1_ann / grid$hurdle_b_ann
grid$a_within10 <- abs(grid$ratio_a_over_b - 1) <= 0.10
grid$a1_within10 <- abs(grid$ratio_a1_over_b - 1) <= 0.10
utils::write.csv(grid, file.path(res_dir, "grid.csv"), row.names = FALSE)
cat("Analytically ratio_a_over_b = sqrt(252 / T): independent of K and V.  Check:",
    isTRUE(all.equal(grid$ratio_a_over_b, sqrt(af / grid$T), tolerance = 1e-12)), "\n")
cat("ratio_a_over_b by T:\n"); print(unique(data.frame(T = grid$T, ratio = grid$ratio_a_over_b)), row.names = FALSE)
cat(sprintf("\nCells with (a, V_mult = V_ann)/(b) within +/-10%% of 1: %d of %d (T values: %s)\n",
            sum(grid$a_within10), nrow(grid), paste(sort(unique(grid$T[grid$a_within10])), collapse = ", ")))
cat(sprintf("Cells with (a1, default V = 1)/(b) within +/-10%% of 1: %d of %d\n", sum(grid$a1_within10), nrow(grid)))
cat("Those (K, T, V_ann) cells:\n")
print(unique(grid[grid$a1_within10, c("T", "V_ann")]), row.names = FALSE)
cat("\nAnnual-Sharpe hurdle, K = 14, wide view (a1 = V=1 default, a = V_mult=V_ann, b = standard):\n")
w <- grid[grid$K == 14, c("T", "V_ann", "hurdle_a1_ann", "hurdle_a_ann", "hurdle_b_ann", "ratio_a_over_b", "ratio_a1_over_b")]
print(w, row.names = FALSE, digits = 3)
cat("\n")

# ---- 3. statistical difference ----------------------------------------------
cat("== 3. Is (a) inside the sampling interval of (b)? ==\n")
set.seed(20261019)
Ks <- c(2, 5, 10, 14, 17, 50)
nsim_v <- 200000L
Vs_true <- 4e-4
var_rows <- do.call(rbind, lapply(Ks, function(K) {
  vh <- replicate(nsim_v, stats::var(stats::rnorm(K, 0, sqrt(Vs_true))))
  data.frame(K = K,
             relsd_V_theory = sqrt(2 / (K - 1)), relsd_V_sim = stats::sd(vh) / Vs_true,
             relsd_sqrtV_approx = 0.5 * sqrt(2 / (K - 1)), relsd_sqrtV_sim = stats::sd(sqrt(vh)) / sqrt(Vs_true),
             bias_sqrtV_sim = mean(sqrt(vh)) / sqrt(Vs_true),
             q025_sim = stats::quantile(sqrt(vh / Vs_true), 0.025), q975_sim = stats::quantile(sqrt(vh / Vs_true), 0.975),
             q025_chisq = sqrt(stats::qchisq(0.025, K - 1) / (K - 1)),
             q975_chisq = sqrt(stats::qchisq(0.975, K - 1) / (K - 1)),
             row.names = NULL)
}))
cat(sprintf("sd formula verified by simulation: %d draws of K normal trial Sharpes per K (true V_stat = %g)\n", nsim_v, Vs_true))
print(var_rows, row.names = FALSE, digits = 4)
cat(sprintf("max |sim - theory| of the relative sd of V_hat: %.4f\n\n", max(abs(var_rows$relsd_V_sim - var_rows$relsd_V_theory))))

int_rows <- do.call(rbind, lapply(seq_len(nrow(var_rows)), function(i) {
  K <- var_rows$K[i]
  do.call(rbind, lapply(c(74, 252, 1000, 4063), function(T) {
    ratio <- sqrt(af / T)   # (a, V_mult = V_ann) / (b at the true V)
    lo95 <- var_rows$q025_chisq[i]; hi95 <- var_rows$q975_chisq[i]
    sd2 <- 2 * var_rows$relsd_sqrtV_sim[i]
    data.frame(K = K, T = T, ratio_a_over_b = ratio,
               b95_lo = lo95, b95_hi = hi95, a_inside_95 = ratio >= lo95 & ratio <= hi95,
               b2sd_lo = 1 - sd2, b2sd_hi = 1 + sd2, a_inside_2sd = ratio >= 1 - sd2 & ratio <= 1 + sd2)
  }))
}))
cat("Interval of the (b) hurdle, as a multiple of its true-V value, from chi2_{K-1} (95%) and 1 +/- 2 sd (sim sd of sqrt(V_hat)):\n")
cat("(a with V_mult = V_ann) / (b) = sqrt(252/T); 'inside' = that ratio lies in the (b) interval.\n")
print(int_rows, row.names = FALSE, digits = 3)
utils::write.csv(int_rows, file.path(res_dir, "intervals.csv"), row.names = FALSE)
# default V = 1 variant, over the whole grid
g1 <- merge(grid, var_rows[, c("K", "q025_chisq", "q975_chisq")], by = "K")
g1$a1_inside_95 <- g1$ratio_a1_over_b >= g1$q025_chisq & g1$ratio_a1_over_b <= g1$q975_chisq
g1$a_inside_95 <- g1$ratio_a_over_b >= g1$q025_chisq & g1$ratio_a_over_b <= g1$q975_chisq
cat(sprintf("\nGrid cells (n = %d): (a, V_mult=V_ann) inside (b) 95%% interval in %d; (a1, V=1) inside in %d.\n",
            nrow(g1), sum(g1$a_inside_95), sum(g1$a1_inside_95)))
cat("(a, V_mult=V_ann) inside by T:\n")
print(stats::aggregate(a_inside_95 ~ T, g1, mean), row.names = FALSE)
cat("(a1, V=1) inside, by K and T (share over V_ann):\n")
print(stats::aggregate(a1_inside_95 ~ K + T, g1, mean), row.names = FALSE)
cat("\n")

# ---- 4. simulation under the null --------------------------------------------
cat("== 4. Simulation: best of K zero-Sharpe trials ==\n")
reps <- 4000L
sig <- 0.01
sim_cell <- function(K, T, sr_true_ann, reps) {
  mu1 <- sr_true_ann / sqrt(252) * sig
  rej <- matrix(NA, reps, 3, dimnames = list(NULL, c("a1_V1", "a2_Vann", "b_Vstat")))
  ident <- TRUE
  for (i in seq_len(reps)) {
    x <- matrix(stats::rnorm(T * K, 0, sig), T, K)
    x[, 1] <- x[, 1] + mu1
    mu <- colMeans(x); s <- sqrt((colSums(x^2) - T * mu^2) / (T - 1))
    srk <- mu / s
    j <- which.max(srk); r <- x[, j]
    Vs_hat <- stats::var(srk)
    p_a1 <- hd_deflated_sharpe(r, K_trials = K, ann_factor = 252L, trial_sharpe_var = 1)$dsr_pvalue
    p_a2 <- hd_deflated_sharpe(r, K_trials = K, ann_factor = 252L, trial_sharpe_var = Vs_hat * 252)$dsr_pvalue
    p_b <- dsr_p_series(r, h_b_pp(K, Vs_hat))
    p_ident <- hd_deflated_sharpe(r, K_trials = K, ann_factor = 252L, trial_sharpe_var = T * Vs_hat)$dsr_pvalue
    ident <- ident && isTRUE(all.equal(p_b, p_ident, tolerance = 1e-9))
    rej[i, ] <- c(p_a1, p_a2, p_b) < 0.05
  }
  stopifnot(ident)   # (b) == (a with V_mult = T * V_stat_hat) on every rep
  p <- colMeans(rej)
  data.frame(K = K, T = T, true_sharpe_best_ann = sr_true_ann, reps = reps,
             rej_a1 = p[1], se_a1 = mc_se(p[1], reps),
             rej_a2 = p[2], se_a2 = mc_se(p[2], reps),
             rej_b = p[3], se_b = mc_se(p[3], reps),
             disagree_a1_b = mean(rej[, 1] != rej[, 3]), disagree_a2_b = mean(rej[, 2] != rej[, 3]),
             row.names = NULL)
}
set.seed(20261019)
cells <- expand.grid(K = c(5, 14, 50), T = c(252, 1000))
cat(sprintf("Monte Carlo: %d replications per cell; per-period sd %.2f; ann_factor 252; target false-positive rate 0.05.\n",
            reps, sig))
cat("a1 = hd_deflated_sharpe(V = 1); a2 = hd_deflated_sharpe(V = 252 * V_stat_hat) [documented usage with annual-unit variance];\n")
cat("b = standard with V_stat_hat = var of the K per-period trial Sharpes.  p < 0.05 counts as a rejection.\n\n")
null_tab <- do.call(rbind, lapply(seq_len(nrow(cells)), function(i) sim_cell(cells$K[i], cells$T[i], 0, reps)))
cat("-- Null (all K trials have true Sharpe 0): false-positive rates --\n")
print(null_tab, row.names = FALSE, digits = 3)
alt_tab <- do.call(rbind, lapply(c(1.0, 2.0), function(s)
  do.call(rbind, lapply(seq_len(nrow(cells)), function(i) sim_cell(cells$K[i], cells$T[i], s, reps)))))
cat("\n-- Alternatives (trial 1 has true annual Sharpe 1.0 or 2.0, the rest 0): rejection rate = power --\n")
print(alt_tab, row.names = FALSE, digits = 3)
utils::write.csv(null_tab, file.path(res_dir, "sim_null.csv"), row.names = FALSE)
utils::write.csv(alt_tab, file.path(res_dir, "sim_alt.csv"), row.names = FALSE)
cat("\nIdentity assertion passed on every replication: (b) p-value == hd_deflated_sharpe(V = T * V_stat_hat) p-value to 1e-9.\n\n")

# ---- 5. materiality ------------------------------------------------------------
cat("== 5. Materiality ==\n")
mat <- do.call(rbind, lapply(c(0.01, 0.05, 0.1, 0.25, 0.5, 1.0), function(V) {
  rows <- do.call(rbind, lapply(seq_len(nrow(lb_rows)), function(i) {
    with(lb_rows[i, ], {
      Vs <- V / af
      c(pa1 = p_a1, pa = dsr_p(sr_pp <- sharpe_ann / sqrt(af), T, h_a_pp(K, T, V)),
        pb = dsr_p(sr_pp, T, h_b_pp(K, Vs)))
    })
  }))
  data.frame(V_pool_ann = V, n = nrow(rows),
             pass_a1 = sum(rows[, "pa1"] < 0.05), pass_a = sum(rows[, "pa"] < 0.05), pass_b = sum(rows[, "pb"] < 0.05),
             flips_a_vs_b = sum((rows[, "pa"] < 0.05) != (rows[, "pb"] < 0.05)),
             flips_a1_vs_b = sum((rows[, "pa1"] < 0.05) != (rows[, "pb"] < 0.05)))
}))
cat("Leaderboard Full-Period strategies (summary-statistic recomputation, p < 0.05), pool variance V_pool_ann assumed for all:\n")
print(mat, row.names = FALSE)
utils::write.csv(mat, file.path(res_dir, "materiality_leaderboard.csv"), row.names = FALSE)
cat("\nHurdle shift in annual Sharpe units, (a, V_mult=V_ann) minus (b), K = 14:\n")
shift <- grid[grid$K == 14, c("T", "V_ann", "hurdle_a_ann", "hurdle_b_ann")]
shift$shift_ann <- shift$hurdle_a_ann - shift$hurdle_b_ann
print(shift, row.names = FALSE, digits = 3)
cat("\nDone.\n")
