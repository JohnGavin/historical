# a rename cycle aborts

    Code
      hd_pit_monthly_returns(bars, .pr_members(`2019-12-31` = "AAA"), ex)
    Condition
      Error in `hd_pit_monthly_returns()`:
      x Ticker-change chain has a cycle: "AAB", "BBA", and "AAB".
      i A rename must lead to a ticker that is not renamed back; check new_ticker in `exit_prices`.

# invalid or empty input aborts with a structured message

    Code
      hd_pit_monthly_returns(data.frame(x = 1), mem, .pr_exit())
    Condition
      Error in `hd_pit_monthly_returns()`:
      x `bars_adj` must be a data frame with symbol, date, close, and volume (Date date, numeric close and volume).
      i Build it with `hd_alpaca_bars()`.

---

    Code
      hd_pit_monthly_returns(.pr_aaa()[0, ], mem, .pr_exit())
    Condition
      Error in `hd_pit_monthly_returns()`:
      x `bars_adj` has no bar with volume > 0.
      i Fetch them with `Rscript scripts/fetch_alpaca_member_bars.R`.

---

    Code
      hd_pit_monthly_returns(.pr_aaa(), mem[0, ], .pr_exit())
    Condition
      Error in `hd_pit_monthly_returns()`:
      x `members` must be a non-empty data frame with character ticker and Date date (no NA).
      i Use `hd_sp500_pit_universe()` output, such as `stk_universe_pit`.

---

    Code
      hd_pit_monthly_returns(.pr_aaa(), data.frame(ticker = "AAA"), .pr_exit())
    Condition
      Error in `hd_pit_monthly_returns()`:
      x `members` must be a non-empty data frame with character ticker and Date date (no NA).
      i Use `hd_sp500_pit_universe()` output, such as `stk_universe_pit`.

---

    Code
      hd_pit_monthly_returns(.pr_aaa(), mem, data.frame(ticker = "AAA"))
    Condition
      Error in `hd_pit_monthly_returns()`:
      x `exit_prices` must be a data frame with ticker, index_exit_date, exit_type, new_ticker, last_trade_date, last_close, exit_price_upper, exit_price_lower, and has_bars.
      i Build it with `hd_alpaca_exit_prices()`.

---

    Code
      hd_pit_monthly_returns(dup, mem, .pr_exit())
    Condition
      Error in `hd_pit_monthly_returns()`:
      ! `bars_adj` has more than one row for some symbol and date.

---

    Code
      hd_pit_monthly_returns(bars, .pr_members(`2019-12-31` = c("AAA", "TTT")), bad)
    Condition
      Error in `hd_pit_monthly_returns()`:
      x 1 takeover or failure exit cannot be priced: "TTT".
      i Each needs last_trade_date, a positive last_close, exit_price_upper and exit_price_lower.

# hd_alpaca_member_bars_adj_path aborts naming the fetch script when absent

    Code
      hd_alpaca_member_bars_adj_path(tmp)
    Condition
      Error in `hd_alpaca_member_bars_adj_path()`:
      x Alpaca member-bars file not found: '<TMP>/alpaca_member_bars_adj.parquet'.
      i Fetch it first (needs `ALPACA_KEY` and `ALPACA_SECRET`): `Rscript scripts/fetch_alpaca_member_bars.R`
      i Or set `ALPACA_BARS_DIR` to a directory that holds 'alpaca_member_bars_adj.parquet'.

