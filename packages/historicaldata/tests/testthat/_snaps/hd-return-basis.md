# registry schema is stable

    list(names = c("strategy", "basis", "cash_weight_col", "evidence"
    ), classes = c(strategy = "character", basis = "character", cash_weight_col = "character", 
    evidence = "character"), strategy = c("Value (HML)", "Managed Futures", 
    "Risk State", "Avoid Worst", "TOM", "OLMAR-1", "Mom Pre-Peak", 
    "Mom Post-Peak", "Mom 12-2", "LTR", "CMR", "CMR Conditioned", 
    "Stock MAX", "Stock DRIF", "XGB DRIF", "Factor MAX", "Factor DRIF", 
    "PSO Optimal", "PSO Regime-Adjusted"), basis = c("total", "total", 
    "total", "total", "total", "total", "excess", "excess", "excess", 
    "excess", "excess", "blend", "excess", "excess", "excess", "excess", 
    "excess", "excess", "blend"), cash_weight_col = c(NA, NA, NA, 
    NA, NA, NA, NA, NA, NA, NA, NA, "cash_weight", NA, NA, NA, NA, 
    NA, NA, "cash_weight"))

# an unregistered strategy aborts (never a silent default)

    Code
      hd_return_basis_of("Not A Strategy")
    Condition
      Error in `hd_return_basis_of()`:
      x Strategy "Not A Strategy" is not registered in `hd_return_basis()`.
      i Registered strategies: "Value (HML)", "Managed Futures", "Risk State", "Avoid Worst", "TOM", "OLMAR-1", "Mom Pre-Peak", "Mom Post-Peak", "Mom 12-2", "LTR", "CMR", "CMR Conditioned", "Stock MAX", "Stock DRIF", "XGB DRIF", "Factor MAX", "Factor DRIF", "PSO Optimal", and "PSO Regime-Adjusted".
      i Add it to 'packages/historicaldata/R/hd_return_basis.R' with a file:line evidence string; a silent default would put its Sharpe on an unknown basis.

---

    Code
      hd_return_basis_of(NA_character_)
    Condition
      Error in `hd_return_basis_of()`:
      x `strategy` must be a single non-NA string.
      i Got <character> of length 1.

# blend without a valid cash_weight aborts

    Code
      hd_rf_for_basis(c(0.1, 0.2), "CMR Conditioned")
    Condition
      Error in `.hd_check_cash_weight()`:
      x `hd_rf_for_basis()`: "CMR Conditioned" is a "blend" strategy, so `cash_weight` must be a numeric vector (never NULL).
      i Got <NULL>.
      i The registry names the column: `hd_return_basis()$cash_weight_col`.

---

    Code
      hd_excess_returns(c(0.1, 0.2), c(0.1, 0.2), "CMR Conditioned", cash_weight = 0.5)
    Condition
      Error in `.hd_check_cash_weight()`:
      x `cash_weight` must be the same length as the return series.
      i Got length 1 and 2.

---

    Code
      hd_excess_returns(c(0.1, 0.2), c(0.1, 0.2), "CMR Conditioned", cash_weight = c(
        0.5, 1.5))
    Condition
      Error in `.hd_check_cash_weight()`:
      x `cash_weight` must lie in [0, 1].
      i Got range [0.5, 1.5].

# invalid inputs abort with cli errors

    Code
      hd_rf_for_basis("a", "Value (HML)")
    Condition
      Error in `hd_rf_for_basis()`:
      x `rf` must be a numeric vector.
      i Got <character>.

---

    Code
      hd_excess_returns(c(1, 2), c(1), "Value (HML)")
    Condition
      Error in `hd_excess_returns()`:
      x `ret` and `rf` must be the same length.
      i Got length 2 and 1.

---

    Code
      hd_excess_returns(c(1, 2), NULL, "Value (HML)")
    Condition
      Error in `hd_excess_returns()`:
      x `rf` must be a numeric vector (never NULL -- a missing rf is not zero).
      i Got <NULL>.

# function signatures are stable

    Code
      args(hd_return_basis_of)
    Output
      function (strategy) 
      NULL

---

    Code
      args(hd_rf_for_basis)
    Output
      function (rf, strategy, cash_weight = NULL) 
      NULL

---

    Code
      args(hd_excess_returns)
    Output
      function (ret, rf, strategy, cash_weight = NULL) 
      NULL

