# a non-first-row NA close (with adjusted_close still present) aborts as an unaccounted drop

    Code
      hd_return_legs(toy, quiet = TRUE)
    Condition
      Error in `hd_return_legs()`:
      x 1 row dropped for an unrecognised reason (not first-row-per-ticker, not missing open, not missing adjusted_close).
      i This usually means `close` (or another required value) is NA for some row.
      i Inspect rows where close is NA to find the cause.

# missing required columns aborts with an informative message

    Code
      hd_return_legs(toy)
    Condition
      Error in `hd_return_legs()`:
      x `data` is missing required column: close.
      i hd_return_legs() needs date, ticker, open, and close (plus optional adjusted_close).

# no adjusted_close and unadjusted_ok = FALSE (default) aborts

    Code
      hd_return_legs(toy)
    Condition
      Error in `hd_return_legs()`:
      x `data` has no adjusted_close column.
      i hd_return_legs() needs adjusted_close to correct the overnight leg for splits/dividends occurring between close_(t-1) and open_t -- using raw open/close alone can fabricate large fake overnight jumps on ex-dates.
      i Pass `unadjusted_ok = TRUE` to proceed anyway, only if this panel has been independently verified to contain no corporate actions over the requested window.

# a non-positive price aborts with an informative message

    Code
      hd_return_legs(toy, quiet = TRUE)
    Condition
      Error in `hd_return_legs()`:
      x 1 row found with a non-positive price in open, close, and adjusted_close.
      i First offender: "A" on "2024-01-02".
      i Prices must be strictly positive; a non-positive quote is a data error, not a real return.

# hd_return_legs() argument list is stable (catches API drift)

    Code
      args(hd_return_legs)
    Output
      function (data, unadjusted_ok = FALSE, tolerance = 1e-06, quiet = FALSE) 
      NULL

# .hd_check_compounding aborts when observed and expected diverge beyond tolerance

    Code
      historicaldata:::.hd_check_compounding(observed = c(0.04, 0.01), expected = c(0,
        0.01), ticker = c("X", "X"), date = as.Date("2024-01-03") + 0:1, tolerance = 1e-06)
    Condition
      Error in `historicaldata:::.hd_check_compounding()`:
      x 1 row failed the overnight x intraday compounding check (tolerance 1e-06).
      i Worst offender: "X" on "2024-01-03" -- (1+overnight)(1+intraday)-1 = 0.04, expected 0.
      i This usually means `open` is not on the same (unadjusted) price scale as `close`/`adjusted_close`, or the overnight/intraday formulas were changed inconsistently.

# .hd_check_compounding aborts on non-finite observed or expected values

    Code
      historicaldata:::.hd_check_compounding(observed = c(NaN, 0.01), expected = c(0,
        0.01), ticker = c("X", "X"), date = as.Date("2024-01-03") + 0:1, tolerance = 1e-06)
    Condition
      Error in `historicaldata:::.hd_check_compounding()`:
      x 1 row failed the overnight x intraday compounding check (tolerance 1e-06).
      i Worst offender: "X" on "2024-01-03" -- (1+overnight)(1+intraday)-1 = NaN, expected 0.
      i This usually means `open` is not on the same (unadjusted) price scale as `close`/`adjusted_close`, or the overnight/intraday formulas were changed inconsistently.

