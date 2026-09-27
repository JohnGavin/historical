# non-numeric/non-finite sharpe_annual aborts

    Code
      hd_prob_sharpe_positive(sharpe_annual = NA_real_, n_obs = 60)
    Condition
      Error in `hd_prob_sharpe_positive()`:
      x `sharpe_annual` must be a single finite number.
      i Got NA.
      i Unlike hd_detection_power(), hd_prob_sharpe_positive() does NOT require a positive claimed effect -- P(SR_true > benchmark) is a meaningful question for a negative or zero observed Sharpe too.

---

    Code
      hd_prob_sharpe_positive(sharpe_annual = Inf, n_obs = 60)
    Condition
      Error in `hd_prob_sharpe_positive()`:
      x `sharpe_annual` must be a single finite number.
      i Got Inf.
      i Unlike hd_detection_power(), hd_prob_sharpe_positive() does NOT require a positive claimed effect -- P(SR_true > benchmark) is a meaningful question for a negative or zero observed Sharpe too.

---

    Code
      hd_prob_sharpe_positive(sharpe_annual = c(0.1, 0.2), n_obs = 60)
    Condition
      Error in `hd_prob_sharpe_positive()`:
      x `sharpe_annual` must be a single finite number.
      i Got 0.1 and 0.2.
      i Unlike hd_detection_power(), hd_prob_sharpe_positive() does NOT require a positive claimed effect -- P(SR_true > benchmark) is a meaningful question for a negative or zero observed Sharpe too.

# n_obs < 2 aborts (distinct from the n_obs < 10 NA-with-reason path)

    Code
      hd_prob_sharpe_positive(sharpe_annual = 0.5, n_obs = 1)
    Condition
      Error in `hd_prob_sharpe_positive()`:
      x `n_obs` must be a single number >= 2.
      i Got 1.

# non-positive ann_factor aborts

    Code
      hd_prob_sharpe_positive(sharpe_annual = 0.5, n_obs = 60, ann_factor = 0)
    Condition
      Error in `hd_prob_sharpe_positive()`:
      x `ann_factor` must be a single positive number.
      i Got 0.

# non-finite skewness aborts

    Code
      hd_prob_sharpe_positive(sharpe_annual = 0.5, n_obs = 60, skewness = NA_real_)
    Condition
      Error in `hd_prob_sharpe_positive()`:
      x `skewness` must be a single finite number.
      i Got NA.

# kurtosis below the theoretical floor (-2) aborts

    Code
      hd_prob_sharpe_positive(sharpe_annual = 0.5, n_obs = 60, kurtosis = -3)
    Condition
      Error in `hd_prob_sharpe_positive()`:
      x `kurtosis` must be a single finite number >= -2.
      i Got -3.
      i -2 is the theoretical floor for the EXCESS kurtosis of any real distribution (raw kurtosis >= 1); a lower value cannot come from a real sample.

# non-finite benchmark_annual aborts

    Code
      hd_prob_sharpe_positive(sharpe_annual = 0.5, n_obs = 60, benchmark_annual = NA_real_)
    Condition
      Error in `hd_prob_sharpe_positive()`:
      x `benchmark_annual` must be a single finite number.
      i Got NA.

# n_tests < 1 aborts

    Code
      hd_prob_sharpe_positive(sharpe_annual = 0.5, n_obs = 60, n_tests = 0)
    Condition
      Error in `hd_prob_sharpe_positive()`:
      x `n_tests` must be a single number >= 1.
      i Got 0.
      i n_tests is the effective number of tests this claim is one of -- a value below 1 would SHRINK the corrected p-value, the opposite of a correction.

# function signature is stable (catches API drift)

    Code
      args(hd_prob_sharpe_positive)
    Output
      function (sharpe_annual, n_obs, ann_factor = 12, skewness = 0, 
          kurtosis = 0, benchmark_annual = 0, n_tests = 1, correction = c("none", 
              "bonferroni")) 
      NULL

