# input validation: invalid sharpe aborts with informative message

    Code
      hd_sharpe_haircut(NA_real_, n_tests = 5, rho = 0.1, T_obs = 100)
    Condition
      Error in `hd_sharpe_haircut()`:
      x `sharpe` must be a single finite numeric value.
      i Got NA.

---

    Code
      hd_sharpe_haircut(Inf, n_tests = 5, rho = 0.1, T_obs = 100)
    Condition
      Error in `hd_sharpe_haircut()`:
      x `sharpe` must be a single finite numeric value.
      i Got Inf.

---

    Code
      hd_sharpe_haircut(c(0.1, 0.2), n_tests = 5, rho = 0.1, T_obs = 100)
    Condition
      Error in `hd_sharpe_haircut()`:
      x `sharpe` must be a single finite numeric value.
      i Got 0.1 and 0.2.

# input validation: invalid n_tests aborts with informative message

    Code
      hd_sharpe_haircut(0.8, n_tests = 0, rho = 0.1, T_obs = 100)
    Condition
      Error in `hd_sharpe_haircut()`:
      x `n_tests` must be a single finite number >= 1.
      i Got 0.
      i Typically the leaderboard-wide effective strategy count (k_eff_leaderboard); see `hd_strat_keff_vertox()`.

---

    Code
      hd_sharpe_haircut(0.8, n_tests = NA_real_, rho = 0.1, T_obs = 100)
    Condition
      Error in `hd_sharpe_haircut()`:
      x `n_tests` must be a single finite number >= 1.
      i Got NA.
      i Typically the leaderboard-wide effective strategy count (k_eff_leaderboard); see `hd_strat_keff_vertox()`.

---

    Code
      hd_sharpe_haircut(0.8, n_tests = -1, rho = 0.1, T_obs = 100)
    Condition
      Error in `hd_sharpe_haircut()`:
      x `n_tests` must be a single finite number >= 1.
      i Got -1.
      i Typically the leaderboard-wide effective strategy count (k_eff_leaderboard); see `hd_strat_keff_vertox()`.

# input validation: invalid rho aborts with informative message

    Code
      hd_sharpe_haircut(0.8, n_tests = 5, rho = -0.1, T_obs = 100)
    Condition
      Error in `hd_sharpe_haircut()`:
      x `rho` must be a single finite number in [0, 1).
      i Got -0.1.
      i It is the average pairwise correlation among the `n_tests` tested strategies; pass 0 when `n_tests` is already correlation-adjusted (see `hd_sharpe_haircut()` Details).

---

    Code
      hd_sharpe_haircut(0.8, n_tests = 5, rho = 1, T_obs = 100)
    Condition
      Error in `hd_sharpe_haircut()`:
      x `rho` must be a single finite number in [0, 1).
      i Got 1.
      i It is the average pairwise correlation among the `n_tests` tested strategies; pass 0 when `n_tests` is already correlation-adjusted (see `hd_sharpe_haircut()` Details).

---

    Code
      hd_sharpe_haircut(0.8, n_tests = 5, rho = NA_real_, T_obs = 100)
    Condition
      Error in `hd_sharpe_haircut()`:
      x `rho` must be a single finite number in [0, 1).
      i Got NA.
      i It is the average pairwise correlation among the `n_tests` tested strategies; pass 0 when `n_tests` is already correlation-adjusted (see `hd_sharpe_haircut()` Details).

# input validation: invalid T_obs aborts with informative message

    Code
      hd_sharpe_haircut(0.8, n_tests = 5, rho = 0.1, T_obs = 1)
    Condition
      Error in `hd_sharpe_haircut()`:
      x `T_obs` must be a single finite number >= 2.
      i Got 1.
      i It is the number of return observations underlying `sharpe`.

---

    Code
      hd_sharpe_haircut(0.8, n_tests = 5, rho = 0.1, T_obs = NA_real_)
    Condition
      Error in `hd_sharpe_haircut()`:
      x `T_obs` must be a single finite number >= 2.
      i Got NA.
      i It is the number of return observations underlying `sharpe`.

# input validation: invalid ann_factor aborts with informative message

    Code
      hd_sharpe_haircut(0.8, n_tests = 5, rho = 0.1, T_obs = 100, ann_factor = 0)
    Condition
      Error in `hd_sharpe_haircut()`:
      x `ann_factor` must be a single positive finite number.
      i Got 0.

# function signature is stable (catches API drift)

    Code
      args(hd_sharpe_haircut)
    Output
      function (sharpe, n_tests, rho, T_obs, ann_factor = 252L, method = c("bonferroni", 
          "holm", "bhy")) 
      NULL

