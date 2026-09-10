# hd_drawdown rejects non-numeric or NA input

    Code
      hd_drawdown("not numeric")
    Condition
      Error in `hd_drawdown()`:
      x `ret` must be a numeric vector.
      i Got <character>.

---

    Code
      hd_drawdown(c(0.1, NA, 0.2))
    Condition
      Error in `hd_drawdown()`:
      x `ret` must not contain NA values.
      i Filter NAs before calling `hd_drawdown()` -- a silently dropped period would shift every downstream index (fail-loud-not-null.md).

# hd_stop_rule_backtest validates inputs and reports them via cli_abort

    Code
      hd_stop_rule_backtest("x", threshold = -0.1)
    Condition
      Error in `hd_stop_rule_backtest()`:
      x `ret` must be a numeric vector.
      i Got <character>.

---

    Code
      hd_stop_rule_backtest(c(0.1, NA), threshold = -0.1)
    Condition
      Error in `hd_stop_rule_backtest()`:
      x `ret` must not contain NA values.
      i Filter NAs before calling `hd_stop_rule_backtest()` (fail-loud-not-null.md).

---

    Code
      hd_stop_rule_backtest(c(0.1), threshold = -0.1)
    Condition
      Error in `hd_stop_rule_backtest()`:
      x `ret` must have at least 2 observations.
      i Got length 1.

---

    Code
      hd_stop_rule_backtest(rnorm(10), threshold = "x")
    Condition
      Error in `hd_stop_rule_backtest()`:
      x `threshold` must be numeric.
      i Got <character>.

---

    Code
      hd_stop_rule_backtest(rnorm(10), threshold = c(-0.1, -0.2))
    Condition
      Error in `hd_stop_rule_backtest()`:
      x `threshold` must be a single number or a vector the same length as `ret`.
      i Got length 2, expected 1 or 10.

---

    Code
      hd_stop_rule_backtest(rnorm(10), threshold = 0)
    Condition
      Error in `hd_stop_rule_backtest()`:
      x Every finite `threshold` value must lie in (-1, 0) -- it is a drawdown fraction.
      i 10 values out of range, e.g. 0.
      i Use -Inf to disable the stop for a period (the no-stop arm), never 0 or a value <= -1.

---

    Code
      hd_stop_rule_backtest(rnorm(10), threshold = -1.5)
    Condition
      Error in `hd_stop_rule_backtest()`:
      x Every finite `threshold` value must lie in (-1, 0) -- it is a drawdown fraction.
      i 10 values out of range, e.g. -1.5.
      i Use -Inf to disable the stop for a period (the no-stop arm), never 0 or a value <= -1.

---

    Code
      hd_stop_rule_backtest(rnorm(10), threshold = -0.1, rf = rnorm(5))
    Condition
      Error in `hd_stop_rule_backtest()`:
      x `rf` must be NULL or a numeric vector the same length as `ret`.
      i Got <numeric> of length 5, expected length 10.

---

    Code
      hd_stop_rule_backtest(rnorm(10), threshold = -0.1, cost_bps = -1)
    Condition
      Error in `hd_stop_rule_backtest()`:
      x `cost_bps` must be a single non-negative number.
      i Got -1.

---

    Code
      hd_stop_rule_backtest(rnorm(10), threshold = -0.1, reentry_periods = 0)
    Condition
      Error in `hd_stop_rule_backtest()`:
      x `reentry_periods` must be a single positive integer.
      i Got 0.

# hd_regime_stop_thresholds validates inputs

    Code
      hd_regime_stop_thresholds("x", rep("a", 3))
    Condition
      Error in `hd_regime_stop_thresholds()`:
      x `ret` must be a numeric vector.
      i Got <character>.

---

    Code
      hd_regime_stop_thresholds(rnorm(10), rep("a", 5))
    Condition
      Error in `hd_regime_stop_thresholds()`:
      x `regime` must be the same length as `ret`.
      i Got length 5, expected 10.

---

    Code
      hd_regime_stop_thresholds(rnorm(10), rep("a", 10), percentile = 1.5)
    Condition
      Error in `hd_regime_stop_thresholds()`:
      x `percentile` must be a single number in (0, 1).
      i Got 1.5.

---

    Code
      hd_regime_stop_thresholds(rnorm(10), rep("a", 10), train_idx = 1:3)
    Condition
      Error in `hd_regime_stop_thresholds()`:
      x `train_idx` must be NULL or a logical vector the same length as `ret`.
      i Got <integer> of length 3, expected length 10.

---

    Code
      hd_regime_stop_thresholds(c(rnorm(9), NA), rep("a", 10))
    Condition
      Error in `hd_regime_stop_thresholds()`:
      x `ret` must not contain NA values.
      i Filter NAs before calling `hd_regime_stop_thresholds()` (fail-loud-not-null.md).

# hd_stop_rule_compare_arms requires regime unless run_regime_arm = 'never'

    Code
      hd_stop_rule_compare_arms(ret, regime = NULL, run_regime_arm = "auto")
    Condition
      Error in `hd_stop_rule_compare_arms()`:
      x `regime` must not be NULL when `run_regime_arm` is "auto".
      i Reuse an existing regime label (regime_classification$regime, R/plan_regime.R; or the VVIX hostile/cautious label, R/plan_risk_state.R) -- see #588 G2.
      i Pass run_regime_arm = "never" if this call only needs Arms A/B.

# hd_stop_rule_compare_arms validates its own inputs

    Code
      hd_stop_rule_compare_arms("x")
    Condition
      Error in `hd_stop_rule_compare_arms()`:
      x `ret` must be a numeric vector with no NA values.
      i Filter NAs before calling `hd_stop_rule_compare_arms()` (fail-loud-not-null.md).

---

    Code
      hd_stop_rule_compare_arms(rnorm(10), static_thresholds = numeric(0))
    Condition
      Error in `hd_stop_rule_compare_arms()`:
      x `static_thresholds` must be a non-empty numeric vector.
      i Got <numeric> of length 0.

# function signature is stable (catches API drift)

    Code
      args(hd_stop_rule_backtest)
    Output
      function (ret, threshold, rf = NULL, cost_bps = 5, reentry_periods = 1L) 
      NULL

---

    Code
      args(hd_regime_stop_thresholds)
    Output
      function (ret, regime, percentile = 0.05, train_idx = NULL, min_train_obs = 12L) 
      NULL

---

    Code
      args(hd_stop_rule_compare_arms)
    Output
      function (ret, regime = NULL, static_thresholds = c(-0.1, -0.15, 
          -0.2), regime_percentile = 0.05, rf = NULL, cost_bps = 5, 
          periods_per_year = 12L, train_idx = NULL, reentry_periods = 1L, 
          run_regime_arm = c("auto", "always", "never"), degradation_margin = 0) 
      NULL

