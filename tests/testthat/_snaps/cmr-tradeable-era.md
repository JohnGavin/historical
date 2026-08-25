# missing source column aborts with an informative error

    Code
      .cmr_tradeable_cutoff_date(bad_tbl)
    Condition
      Error in `.cmr_tradeable_cutoff_date()`:
      x `returns_tbl` has no source column.
      i Cannot distinguish tradeable (Yahoo futures/ETF) series from untradeable (FRED/IMF index) series without it.
      i See #751 item 1 and scripts/fetch_commodities.R for the source-tagging contract that calculate_commodity_returns() relies on.

# an all-FRED/IMF universe (no tradeable rows) aborts rather than returning NA/Inf

    Code
      .cmr_tradeable_cutoff_date(all_fred)
    Condition
      Error in `.cmr_tradeable_cutoff_date()`:
      x No tradeable (non-FRED/IMF) commodity observations found in `returns_tbl`.
      i Cannot derive the CMR tradeable-era cutoff -- see #751 item 1.

