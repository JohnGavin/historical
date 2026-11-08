# hd_alpaca_bars aborts with the HTTP status and API message on non-200

    Code
      httr2::with_mocked_responses(fake, hd_alpaca_bars(c("AAA", "BBB"), "2020-01-01",
      "2020-01-31", key = "k", secret = "s"))
    Condition
      Error in `hd_alpaca_bars()`:
      x Alpaca bars request failed: HTTP 403.
      i API message: "subscription does not permit querying recent SIP data"
      i Symbols in this batch (2): "AAA" and "BBB".

# hd_alpaca_bars aborts on bad input and missing credentials

    Code
      hd_alpaca_bars(character(), "2020-01-01", "2020-01-31", key = "k", secret = "s")
    Condition
      Error in `hd_alpaca_bars()`:
      x `symbols` must be a non-empty character vector without NA or empty strings.

---

    Code
      hd_alpaca_bars("A", "2020-02-01", "2020-01-31", key = "k", secret = "s")
    Condition
      Error in `hd_alpaca_bars()`:
      x `start` and `end` must be single dates with `start` <= `end`.

---

    Code
      hd_alpaca_bars("A", "2020-01-01", "2020-01-31")
    Condition
      Error in `hd_alpaca_bars()`:
      x Alpaca credentials missing.
      i Set `ALPACA_KEY` and `ALPACA_SECRET` in '~/.Renviron' (then restart R), or pass `key`/`secret` explicitly.

# hd_alpaca_exit_bars_path: aborts naming the fetch script when absent

    Code
      hd_alpaca_exit_bars_path(tmp)
    Condition
      Error in `hd_alpaca_exit_bars_path()`:
      x Alpaca exit-bars file not found: '<TMP>/alpaca_exit_bars.parquet'.
      i Fetch it first (needs `ALPACA_KEY` and `ALPACA_SECRET`): `Rscript scripts/fetch_alpaca_exit_bars.R`
      i Or set `ALPACA_BARS_DIR` to a directory that holds 'alpaca_exit_bars.parquet'.

# hd_alpaca_exit_prices validates its inputs

    Code
      hd_alpaca_exit_prices(data.frame(x = 1), .ep_exit("AAA"))
    Condition
      Error in `hd_alpaca_exit_prices()`:
      x `bars` must be a data frame with symbol, date, close, and volume (Date date, numeric close and volume).
      i Build it with `hd_alpaca_bars()`.

---

    Code
      hd_alpaca_exit_prices(bad, .ep_exit("AAA"))
    Condition
      Error in `hd_alpaca_exit_prices()`:
      ! `bars` has missing symbol, date, close or volume values.

---

    Code
      hd_alpaca_exit_prices(bars, rbind(.ep_exit("AAA"), .ep_exit("AAA")))
    Condition
      Error in `hd_alpaca_exit_prices()`:
      ! `exits` must have one row per ticker.

