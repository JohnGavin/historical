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

# adjusted-bars and corporate-actions path helpers abort naming the fetch script when absent

    Code
      hd_alpaca_exit_bars_adj_path(tmp)
    Condition
      Error in `hd_alpaca_exit_bars_adj_path()`:
      x Alpaca adjusted-bars file not found: '<TMP>/alpaca_exit_bars_adj.parquet'.
      i Fetch it first (needs `ALPACA_KEY` and `ALPACA_SECRET`): `Rscript scripts/fetch_alpaca_exit_bars.R`
      i Or set `ALPACA_BARS_DIR` to a directory that holds 'alpaca_exit_bars_adj.parquet'.

---

    Code
      hd_alpaca_exit_corp_actions_path(tmp)
    Condition
      Error in `hd_alpaca_exit_corp_actions_path()`:
      x Alpaca corporate-actions file not found: '<TMP>/alpaca_exit_corp_actions.parquet'.
      i Fetch it first (needs `ALPACA_KEY` and `ALPACA_SECRET`): `Rscript scripts/fetch_alpaca_exit_bars.R`
      i Or set `ALPACA_BARS_DIR` to a directory that holds 'alpaca_exit_corp_actions.parquet'.

# hd_alpaca_corporate_actions aborts with the HTTP status and API message on non-200

    Code
      httr2::with_mocked_responses(fake, hd_alpaca_corporate_actions(c("AAA", "BBB"),
      "2016-01-01", "2026-11-08", key = "k", secret = "s"))
    Condition
      Error in `hd_alpaca_corporate_actions()`:
      x Alpaca corporate-actions request failed: HTTP 403.
      i API message: "forbidden"
      i Symbols in this batch (2): "AAA" and "BBB".

# hd_alpaca_corporate_actions validates input

    Code
      hd_alpaca_corporate_actions(character(), "2016-01-01", "2026-11-08", key = "k",
      secret = "s")
    Condition
      Error in `hd_alpaca_corporate_actions()`:
      x `symbols` must be a non-empty character vector without NA or empty strings.

---

    Code
      hd_alpaca_corporate_actions("A", "2016-01-01", "2026-11-08", types = "dividend",
        key = "k", secret = "s")
    Condition
      Error in `hd_alpaca_corporate_actions()`:
      x `types` must be one or more of "name_change", "cash_merger", "stock_merger", "stock_and_cash_merger", and "spin_off".

---

    Code
      hd_alpaca_corporate_actions("A", "2016-01-01", "2026-11-08")
    Condition
      Error in `hd_alpaca_corporate_actions()`:
      x Alpaca credentials missing.
      i Set `ALPACA_KEY` and `ALPACA_SECRET` in '~/.Renviron' (then restart R), or pass `key`/`secret` explicitly.

# hd_alpaca_exit_prices validates its inputs

    Code
      hd_alpaca_exit_prices(data.frame(x = 1), adj, ca, ex)
    Condition
      Error in `hd_alpaca_exit_prices()`:
      x `bars` must be a data frame with symbol, date, close, and volume (Date date, numeric close and volume).
      i Build it with `hd_alpaca_bars()`.

---

    Code
      hd_alpaca_exit_prices(bad, adj, ca, ex)
    Condition
      Error in `hd_alpaca_exit_prices()`:
      ! `bars` has missing symbol, date, close or volume values.

---

    Code
      hd_alpaca_exit_prices(bars, data.frame(x = 1), ca, ex)
    Condition
      Error in `hd_alpaca_exit_prices()`:
      x `bars_adj` must be a data frame with symbol, date, close, and volume (Date date, numeric close and volume).
      i Build it with `hd_alpaca_bars()`.

---

    Code
      hd_alpaca_exit_prices(bars, adj, ca, rbind(ex, ex))
    Condition
      Error in `hd_alpaca_exit_prices()`:
      ! `exits` must have one row per ticker.

---

    Code
      hd_alpaca_exit_prices(bars, adj, data.frame(symbol = "A"), ex)
    Condition
      Error in `hd_alpaca_exit_prices()`:
      x `corp_actions` must be a data frame with type, symbol, new_symbol, acquirer_symbol, rate, cash_rate, acquirer_rate, acquiree_rate, effective_date, and process_date.
      i Build it with `hd_alpaca_corporate_actions()`.

---

    Code
      hd_alpaca_exit_prices(bars, bars, ca, ex)
    Condition
      Error in `hd_alpaca_exit_prices()`:
      x `bars_adj` has no "SPY" rows, so the relative fall cannot be computed.
      i Fetch them with `Rscript scripts/fetch_alpaca_exit_bars.R`.

