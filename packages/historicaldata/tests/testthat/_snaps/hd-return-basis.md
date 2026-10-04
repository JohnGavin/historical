# registry schema is stable

    list(names = c("strategy", "basis", "evidence"), classes = c(strategy = "character", 
    basis = "character", evidence = "character"), strategy = c("Value (HML)", 
    "Managed Futures", "Risk State", "Avoid Worst", "TOM", "OLMAR-1", 
    "Mom Pre-Peak", "Mom Post-Peak", "Mom 12-2", "LTR", "CMR", "CMR Conditioned", 
    "Stock MAX", "Stock DRIF", "XGB DRIF", "Factor MAX", "Factor DRIF", 
    "PSO Optimal"), basis = c("total", "total", "total", "total", 
    "total", "total", "excess", "excess", "excess", "excess", "excess", 
    "indeterminate", "excess", "excess", "excess", "excess", "excess", 
    "excess"))

# an unregistered strategy aborts (never a silent default)

    Code
      hd_return_basis_of("Not A Strategy")
    Condition
      Error in `hd_return_basis_of()`:
      x Strategy "Not A Strategy" is not registered in `hd_return_basis()`.
      i Registered strategies: "Value (HML)", "Managed Futures", "Risk State", "Avoid Worst", "TOM", "OLMAR-1", "Mom Pre-Peak", "Mom Post-Peak", "Mom 12-2", "LTR", "CMR", "CMR Conditioned", "Stock MAX", "Stock DRIF", "XGB DRIF", "Factor MAX", "Factor DRIF", and "PSO Optimal".
      i Add it to 'packages/historicaldata/R/hd_return_basis.R' with a file:line evidence string; a silent default would put its Sharpe on an unknown basis.

---

    Code
      hd_return_basis_of(NA_character_)
    Condition
      Error in `hd_return_basis_of()`:
      x `strategy` must be a single non-NA string.
      i Got <character> of length 1.

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
      function (rf, strategy) 
      NULL

---

    Code
      args(hd_excess_returns)
    Output
      function (ret, rf, strategy) 
      NULL

