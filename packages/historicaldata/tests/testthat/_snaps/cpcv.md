# hd_cpcv_purge removes contaminated training observations

    Code
      args(hd_cpcv_purge)
    Output
      function (train_idx, test_idx, label_horizon = 1L) 
      NULL

# hd_cpcv_purge rejects negative label_horizon

    Code
      hd_cpcv_purge(1L:15L, 16L:20L, label_horizon = -1L)
    Condition
      Error in `hd_cpcv_purge()`:
      x `label_horizon` must be >= 0.
      i Got -1.

# hd_cpcv_embargo rejects negative embargo_n

    Code
      hd_cpcv_embargo(1L:15L, 16L:20L, embargo_n = -1L)
    Condition
      Error in `hd_cpcv_embargo()`:
      x `embargo_n` must be >= 0.
      i Got -1.

# hd_cpcv_paths rejects invalid inputs

    Code
      hd_cpcv_paths(1L, 1L)
    Condition
      Error in `hd_cpcv_paths()`:
      x `n_groups` must be an integer >= 2.
      i Got 1.

---

    Code
      hd_cpcv_paths(6L, 0L)
    Condition
      Error in `hd_cpcv_paths()`:
      x `n_test_groups` must be between 1 and 5.
      i Got 0 with `n_groups` = 6.

---

    Code
      hd_cpcv_paths(6L, 6L)
    Condition
      Error in `hd_cpcv_paths()`:
      x `n_test_groups` must be between 1 and 5.
      i Got 6 with `n_groups` = 6.

# hd_pbo returns near 1 when IS/OOS are perfectly anti-correlated

    Code
      args(hd_pbo)
    Output
      function (is_scores, oos_scores) 
      NULL

# hd_pbo rejects dimension mismatch

    Code
      hd_pbo(is_scores, oos_scores)
    Condition
      Error in `hd_pbo()`:
      x `is_scores` and `oos_scores` must have the same dimensions.
      i is_scores: 5 and 2, oos_scores: 5 and 3.

# hd_pbo rejects fewer than 2 paths

    Code
      hd_pbo(matrix(rnorm(4L), 1L, 4L), matrix(rnorm(4L), 1L, 4L))
    Condition
      Error in `hd_pbo()`:
      x At least 2 paths are required to compute PBO.
      i Got 1 path(s).

# hd_pbo rejects fewer than 2 strategies

    Code
      hd_pbo(matrix(rnorm(5L), 5L, 1L), matrix(rnorm(5L), 5L, 1L))
    Condition
      Error in `hd_pbo()`:
      x At least 2 strategies are required to compute PBO.
      i Got 1 strategy/strategies.

