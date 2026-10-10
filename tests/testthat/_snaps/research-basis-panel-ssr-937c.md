# .excess_asset_panel aborts on an unregistered label and on a missing date column

    Code
      .excess_asset_panel(toy$wide, toy$rf_tbl, "Not Registered", "toy panel")
    Condition
      Error in `hd_return_basis_of()`:
      x Strategy "Not Registered" is not registered in `hd_return_basis()`.
      i Registered strategies: "Value (HML)", "Managed Futures", "Risk State", "Avoid Worst", "TOM", "OLMAR-1", "Mom Pre-Peak", "Mom Post-Peak", "Mom 12-2", "LTR", "CMR", "CMR Conditioned", "Stock MAX", "Stock DRIF", "XGB DRIF", "Factor MAX", "Factor DRIF", "PSO Optimal", ..., "Research: JST equity/bills trend", and "Research: asset panel (adjusted-close returns)".
      i Add it to 'packages/historicaldata/R/hd_return_basis.R' with a file:line evidence string; a silent default would put its Sharpe on an unknown basis.

---

    Code
      .excess_asset_panel(toy$wide[, -1], toy$rf_tbl, PANEL_LABEL, "toy panel")
    Condition
      Error in `.excess_asset_panel()`:
      x toy panel: the asset panel must be a data frame with a date column.
      i Got columns "SPY", "TLT", "GLD", and "DBC".

# .ssr_excess_returns aborts on an unregistered label and a length mismatch

    Code
      .ssr_excess_returns(c(1, 2), c(1, 2), "Not Registered", "t")
    Condition
      Error in `hd_return_basis_of()`:
      x Strategy "Not Registered" is not registered in `hd_return_basis()`.
      i Registered strategies: "Value (HML)", "Managed Futures", "Risk State", "Avoid Worst", "TOM", "OLMAR-1", "Mom Pre-Peak", "Mom Post-Peak", "Mom 12-2", "LTR", "CMR", "CMR Conditioned", "Stock MAX", "Stock DRIF", "XGB DRIF", "Factor MAX", "Factor DRIF", "PSO Optimal", ..., "Research: JST equity/bills trend", and "Research: asset panel (adjusted-close returns)".
      i Add it to 'packages/historicaldata/R/hd_return_basis.R' with a file:line evidence string; a silent default would put its Sharpe on an unknown basis.

---

    Code
      .ssr_excess_returns(c(1, 2, 3), c(1, 2), "Value (HML)", "t")
    Condition
      Error in `.ssr_excess_returns()`:
      x t: `rf` must be a numeric vector the same length as the return series (never NULL).
      i Got <numeric> of length 2 for 3 returns.
      i A missing rf must not be treated as zero: the SSR of a "Value (HML)" series would silently stay on the total-return basis (#937).

---

    Code
      .ssr_excess_returns(c(1, 2), NULL, "Value (HML)", "t")
    Condition
      Error in `.ssr_excess_returns()`:
      x t: `rf` must be a numeric vector the same length as the return series (never NULL).
      i Got <NULL> of length 0 for 2 returns.
      i A missing rf must not be treated as zero: the SSR of a "Value (HML)" series would silently stay on the total-return basis (#937).

# .ssr_ext_entries aborts if the excess table lacks a column the wide table has

    Code
      .ssr_ext_entries(wide, wide_ex, c(value_hml = "Value (HML)"), function(r, l) 1,
      function(r) 1)
    Condition
      Error in `.ssr_ext_entries()`:
      x SSR for "Value (HML)": column value_hml is in strat_returns_wide but not in strat_returns_wide_excess.
      i A fall-back to the total-basis column would put its SSR on the wrong basis (#937).
      i Check STRAT_RETURNS_WIDE_CODES / STRAT_CODE_LABELS in R/plan_strategy_correlation.R.

