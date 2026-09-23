# resolve_ticker_cik aborts (does not silently keep first) on a duplicate ticker

    Code
      resolve_ticker_cik(cik_map, c("APC", "AAPL"))
    Condition
      Error in `resolve_ticker_cik()`:
      x SEC's ticker->CIK map returned 1 ticker with multiple CIK candidates.
      i Refusing to silently keep the first candidate (#865) -- resolve manually:
      i "APC": CIK 0000773910 (ANADARKO PETROLEUM CORP) vs CIK 0001835022 (ARKO CORP)

# #865 regression: validate_cik_filing_overlap rejects ARKO's CIK for a pre-2019 APC window

    Code
      validate_cik_filing_overlap("APC", "0001835022", "ARKO CORP", rng, data_start = as.Date(
        "2010-01-01"), data_end = as.Date("2018-12-31"))
    Condition
      Error in `validate_cik_filing_overlap()`:
      x Ticker "APC" resolves to CIK 0001835022 (ARKO CORP), whose 10-K/10-Q filings (2021-03-10 to 2022-03-08) do not overlap the 2010-01-01 to 2018-12-31 window we hold data for.
      i This is the ticker-recycling failure mode (#865): "APC" may refer to a different, earlier company than SEC's current ticker map resolves to.
      i Verify the correct CIK manually rather than trusting a ticker-string match from the current SEC map.

# validate_cik_filing_overlap aborts when the candidate has no KEEP_FORMS filings

    Code
      validate_cik_filing_overlap("ZZZZ", "0000000001", "GHOST CORP", na_range)
    Condition
      Error in `validate_cik_filing_overlap()`:
      x No 10-K/10-Q filings found for candidate CIK 0000000001 (GHOST CORP), resolved from ticker "ZZZZ".
      i Cannot verify this CIK is the company our data is actually about -- refusing a ticker-string-only match (#865).

