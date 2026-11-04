# #865: ticker-only query hitting two issuers warns loudly, names both

    Code
      hd_fundamentals("APC")
    Condition
      Warning:
      ! Recycled-ticker risk (#865): 1 ticker with more than one CIK.
      * APC: 0000773910, 0001835022
      i Pass `cik` to pin the issuer.
    Output
      # A tibble: 2 x 8
        ticker cik        fiscal_period period_end first_filed xbrl_tag original_value
      * <chr>  <chr>      <chr>         <date>     <date>      <chr>             <dbl>
      1 APC    0000773910 2018Q4        2018-12-31 2019-02-20  Revenues    10000000000
      2 APC    0001835022 2018Q4        2024-12-31 2025-03-01  Revenues     2000000000
      # i 1 more variable: source <chr>

# hd_fundamentals aborts on a malformed cik

    Code
      hd_fundamentals(cik = "320193")
    Condition
      Error in `.hd_fundamentals_check_cik()`:
      x `cik` must be a character vector of 10-digit zero-padded CIKs.
      i Got "320193". Pass a string left-padded with zeros to 10 digits, e.g. "0000320193".

# hd_fundamentals aborts when the parquet has no cik column

    Code
      hd_fundamentals("APC")
    Condition
      Error in `hd_fundamentals()`:
      x The "fundamentals" parquet has no cik column.
      i Ticker alone cannot identify an issuer (recycled tickers, #865). Re-run 'scripts/fetch_fundamentals_edgar.R' to publish a CIK-keyed triangle.

