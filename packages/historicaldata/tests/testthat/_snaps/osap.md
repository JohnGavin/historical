# hd_osap_load: aborts when the cache directory is missing files

    Code
      hd_osap_load(tmp)
    Condition
      Error in `hd_osap_load()`:
      x OSAP data not found in '<TMP>'.
      i Missing files: 'SignalDoc.csv' and 'portfolios_wide.csv'
      i Fetch it first: `Rscript scripts/fetch_osap.R`
      i Or set `OSAP_DATA_DIR` to an existing download directory.

# hd_osap_load: aborts on a malformed date

    Code
      hd_osap_load(tmp, min_predictors = 1L)
    Condition
      Error in `hd_osap_load()`:
      x date column in 'portfolios_wide.csv' has 1 unparseable value.
      i Expected an unambiguous date format (e.g. YYYY-MM-DD); got e.g. "not-a-date".

# hd_osap_load: aborts when values look already-fraction scale

    Code
      hd_osap_load(tmp, min_predictors = 1L)
    Condition
      Error in `hd_osap_load()`:
      x OSAP portfolio returns look like they are already in fraction scale (max abs value 0.1243 < 1).
      i hd_osap_load() assumes percent scale, verified empirically 2026-09-25 (Mom12m mean 0.90, sd 8.18) and divides by 100.
      i OSAP may have changed its export format -- update the unit assumption in hd_osap_load() before trusting downstream results.

# hd_osap_load: aborts on a predictor with no SignalDoc match

    Code
      hd_osap_load(tmp, min_predictors = 1L)
    Condition
      Error in `hd_osap_load()`:
      x 1 predictor column in 'portfolios_wide.csv' have no matching row in 'SignalDoc.csv': "SigUnknown".
      i Every predictor is expected to be documented (212/212 matched as of the 2024 release).
      i This may indicate a renamed acronym or a schema change -- do not silently join NA metadata.

# hd_osap_load: aborts when portfolios_wide.csv has no date column

    Code
      hd_osap_load(tmp, min_predictors = 1L)
    Condition
      Error in `hd_osap_load()`:
      x 'portfolios_wide.csv' has no date column.
      i Found columns: not_date and SigA

# hd_osap_load: aborts when SignalDoc.csv is missing expected columns

    Code
      hd_osap_load(tmp, min_predictors = 1L)
    Condition
      Error in `hd_osap_load()`:
      x 'SignalDoc.csv' is missing expected columns: Year, LongDescription, Journal, Cat.Signal, Cat.Data, Cat.Economic, SampleStartYear, SampleEndYear, and Sign.
      i OSAP may have changed its export schema -- update hd_osap_load() before trusting this file.
      i Found columns: Acronym and Authors

# hd_osap_load: aborts when there are fewer predictor columns than min_predictors

    Code
      hd_osap_load(tmp)
    Condition
      Error in `hd_osap_load()`:
      x 'portfolios_wide.csv' has only 3 predictor columns.
      i Expected at least 50 (OSAP has 212 as of the 2024 release).
      i OSAP may have changed its export format -- verify before trusting this download.

