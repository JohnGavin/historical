# hd_sp500_membership_path: aborts naming the fetch script when absent

    Code
      hd_sp500_membership_path(tmp)
    Condition
      Error in `hd_sp500_membership_path()`:
      x S&P 500 membership file not found: '<TMP>/sp500_historical_components.csv'.
      i Fetch it first: `Rscript scripts/fetch_sp500_membership.R`
      i Or set `SP500_MEMBERSHIP_DIR` to a directory that holds 'sp500_historical_components.csv'.

# hd_sp500_members_asof: last snapshot on or before the date, inclusive

    Code
      hd_sp500_members_asof(m, "2019-01-01")
    Condition
      Error in `hd_sp500_members_asof()`:
      x No membership snapshot on or before "2019-01-01".
      i Coverage starts "2020-01-01".

---

    Code
      hd_sp500_members_asof(m, NA)
    Condition
      Error in `hd_sp500_members_asof()`:
      ! `asof` must be one non-missing date.

# hd_sp500_membership: aborts on a missing file

    Code
      hd_sp500_membership(file.path(tmp, "nope.csv"))
    Condition
      Error in `hd_sp500_read_snapshots()`:
      ! membership file not found: '<TMP>/nope.csv'

# hd_sp500_membership: aborts on wrong columns

    Code
      hd_sp500_membership(p, min_members = 1L)
    Condition
      Error in `hd_sp500_read_snapshots()`:
      x membership file must have exactly the columns date,tickers.
      i Found: "day" and "syms"

# hd_sp500_membership: aborts on an empty file

    Code
      hd_sp500_membership(p, min_members = 1L)
    Condition
      Error in `hd_sp500_read_snapshots()`:
      ! membership file has no rows.

# hd_sp500_membership: aborts on unparseable or missing dates, never NA

    Code
      hd_sp500_membership(p, min_members = 1L)
    Condition
      Error in `hd_sp500_read_snapshots()`:
      x membership file has 1 missing or unparseable date.
      i Expected YYYY-MM-DD; first offending value: "not-a-date"

# hd_sp500_membership: aborts on duplicate snapshot dates

    Code
      hd_sp500_membership(p, min_members = 1L)
    Condition
      Error in `hd_sp500_read_snapshots()`:
      x membership file has 1 duplicated snapshot date.
      i First duplicate: "2020-01-01". Two snapshots for one date are ambiguous.

# hd_sp500_membership: aborts on empty tokens and repeated tickers

    Code
      hd_sp500_membership(p, min_members = 1L)
    Condition
      Error in `hd_sp500_membership()`:
      x 1 snapshot with an empty ticker token or no tickers.
      i First offending snapshot: "2020-01-01"

---

    Code
      hd_sp500_membership(p2, min_members = 1L)
    Condition
      Error in `hd_sp500_membership()`:
      x 1 snapshot with a ticker listed more than once.
      i First offending snapshot: "2020-01-01"

# hd_sp500_membership: aborts on legacy SYM-YYYYMM marker tokens

    Code
      hd_sp500_membership(p, min_members = 1L)
    Condition
      Error in `hd_sp500_membership()`:
      x 1 snapshot with legacy `SYM-YYYYMM` removal-marker tokens.
      i That is the old file layout. Use the maintained '(Updated)' file via `scripts/fetch_sp500_membership.R`.

# hd_sp500_membership: aborts when a snapshot is thinner than min_members

    Code
      hd_sp500_membership(p, min_members = 4L)
    Condition
      Error in `hd_sp500_membership()`:
      x 4 snapshots with fewer than 4 members.
      i First: "2020-01-01" with 3 members.
      i An S&P 500 snapshot holds about 500; a thin one means a truncated or corrupt download.

# hd_sp500_pit_universe: rejects a malformed membership

    Code
      hd_sp500_pit_universe(data.frame(a = 1))
    Condition
      Error in `.hd_sp500_check_membership()`:
      x `membership` must be a data frame with a Date date and a character ticker.
      i Build it with `hd_sp500_membership()`.

# presence check: an empty price universe is rejected, not vacuously passed

    Code
      hd_sp500_presence_check(.sp_mem(), character(), known = .sp_known)
    Condition
      Error in `hd_sp500_presence_check()`:
      x `universe_tickers` must be a non-empty character vector without NA.
      i A check that passes on an empty price universe proves nothing.

# presence check: rejects a malformed known table

    Code
      hd_sp500_presence_check(.sp_mem(), "A", known = data.frame(ticker = "B"))
    Condition
      Error in `hd_sp500_presence_check()`:
      x `known` must be a non-empty data frame with ticker, name, and member_on and a Date member_on.

# coverage: rejects bad inputs

    Code
      hd_sp500_coverage(.sp_mem(), spans[0, ])
    Condition
      Error in `hd_sp500_coverage()`:
      ! `spans` must be a non-empty data frame with ticker, first_date, and last_date.

---

    Code
      hd_sp500_coverage(.sp_mem(), rbind(spans, spans))
    Condition
      Error in `hd_sp500_coverage()`:
      ! `spans` must have one row per ticker.

---

    Code
      hd_sp500_coverage(.sp_mem(), bad)
    Condition
      Error in `hd_sp500_coverage()`:
      ! `spans` has missing or inverted dates.

---

    Code
      hd_sp500_coverage(.sp_mem(), spans, tol_days = -1)
    Condition
      Error in `hd_sp500_coverage()`:
      ! `tol_days` must be a single non-negative number.

---

    Code
      hd_sp500_coverage(.sp_mem(), late, tol_days = 0L)
    Condition
      Error in `hd_sp500_coverage()`:
      x No membership snapshot falls inside the price window "2030-01-01" to "2030-02-01".

