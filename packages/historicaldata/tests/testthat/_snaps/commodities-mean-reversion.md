# hd_commodity_mr_dedupe_universe: unmapped series_id aborts loudly, naming the offending id (fail-loud-not-null)

    Code
      hd_commodity_mr_dedupe_universe(tbl)
    Condition
      Error in `hd_commodity_mr_dedupe_universe()`:
      x 1 series_id in `returns_tbl` is not in the CMR exposure map.
      i Unmapped: "NOT_A_REAL_TICKER".
      i Add "NOT_A_REAL_TICKER" to .HD_CMR_EXPOSURE_MAP (packages/historicaldata/R/commodities_mean_reversion.R) with its underlying_exposure and keep decision before it can be ranked -- see #751 item B.

# hd_commodity_mr_dedupe_universe: input validation — not a data frame / missing series_id

    Code
      hd_commodity_mr_dedupe_universe(list(a = 1))
    Condition
      Error in `hd_commodity_mr_dedupe_universe()`:
      x `returns_tbl` must be a data frame, not <list>.

---

    Code
      hd_commodity_mr_dedupe_universe(tibble::tibble(date = Sys.Date()))
    Condition
      Error in `hd_commodity_mr_dedupe_universe()`:
      x `returns_tbl` has no series_id column.
      i Cannot deduplicate the CMR universe without it -- see #751 item B.

