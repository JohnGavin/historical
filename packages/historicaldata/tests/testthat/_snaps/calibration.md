# hd_interval_score rejects invalid alpha

    Code
      hd_interval_score(2, 1, 3, alpha = 0)
    Condition
      Error in `hd_interval_score()`:
      x `alpha` must be a single number in (0, 1).
      i A 90% interval has `alpha = 0.1`.
      x Got: 0

---

    Code
      hd_interval_score(2, 1, 3, alpha = 1.5)
    Condition
      Error in `hd_interval_score()`:
      x `alpha` must be a single number in (0, 1).
      i A 90% interval has `alpha = 0.1`.
      x Got: 1.5

# hd_interval_score rejects crossed bounds

    Code
      hd_interval_score(2, lower = 3, upper = 1, alpha = 0.1)
    Condition
      Error in `hd_interval_score()`:
      x `upper` is below `lower` at 1 position.
      i First offending index: 1 (3 > 1).
      i Bounds may have been supplied in the wrong order.

# hd_interval_coverage rejects an out-of-range nominal

    Code
      hd_interval_coverage(0, -1, 1, nominal = 1.2)
    Condition
      Error in `hd_interval_coverage()`:
      x `nominal` must be a single number in (0, 1).
      i A 5th-95th percentile interval has `nominal = 0.9`.
      x Got: 1.2

# hd_interval_coverage rejects a non-positive overlap

    Code
      hd_interval_coverage(0, -1, 1, nominal = 0.9, overlap = 0)
    Condition
      Error in `hd_interval_coverage()`:
      x `overlap` must be a single number >= 1.
      i Pass `horizon / step` for rolling-origin windows; `1` means independent.
      x Got: 0

# block bootstrap rejects a series shorter than one block

    Code
      hd_block_boot_sharpe_ci(c(0.01, 0.02), block_size = 3L)
    Condition
      Error in `hd_block_boot_sharpe_ci()`:
      x Series has 2 non-NA observations but `block_size` is 3.
      i A block bootstrap needs at least one full block.
      i Either lengthen the series or reduce `block_size`.

# block bootstrap rejects returns at or below -100%

    Code
      hd_block_boot_sharpe_ci(c(0.01, -1, 0.02, 0.01, 0.03))
    Condition
      Error in `hd_block_boot_sharpe_ci()`:
      x 1 return at or below -100% at index 2.
      i The geometric Sharpe is undefined once `prod(1 + ret)` is non-positive.
      i This is a data defect - investigate the source series rather than filtering it.

# calibration function signatures are stable

    Code
      args(hd_interval_score)
    Output
      function (y, lower, upper, alpha) 
      NULL

---

    Code
      args(hd_interval_coverage)
    Output
      function (y, lower, upper, nominal, overlap = 1, p_threshold = 0.05) 
      NULL

---

    Code
      args(hd_fpr_equipoise)
    Output
      function (p) 
      NULL

---

    Code
      args(hd_block_boot_sharpe_ci)
    Output
      function (ret, n_draws = 1000L, block_size = 3L, ci_lo = 0.05, 
          ci_hi = 0.95, seed = NULL, periods_per_year = 12L) 
      NULL

