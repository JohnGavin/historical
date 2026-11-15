# pacing sleeps weight / (pace x 1200/60) per request (snapshot)

    Code
      print(round(v$env$slept, 4))
    Output
      [1] 1.3333 8.0000 3.0000

# an invalid pace aborts (snapshot)

    Code
      hl_make_post(tempdir(), pace = 2)
    Condition
      Error in `hl_bad_arg()`:
      x Invalid `pace`
      i must be a number in (0, 1]

---

    Code
      hl_make_post(tempdir(), pace = 0)
    Condition
      Error in `hl_bad_arg()`:
      x Invalid `pace`
      i must be a number in (0, 1]

# hl_post turns HTTP 429 into hl_rate_limited, other 4xx into unavailable (snapshot)

    Code
      httr2::with_mocked_responses(resp(429L), hl_post(list(type = "spotMeta")))
    Condition
      Error in `hl_post()`:
      x Hyperliquid rate limit (HTTP 429)
      i the request was refused for exceeding the per-IP weight limit

# persistent 429 aborts as rate-limited after the bounded attempts (snapshot)

    Code
      suppressMessages(post(list(type = "allPerpMetas")))
    Condition
      Error in `post()`:
      x Hyperliquid still rate-limited after 3 attempts
      i backed off 60 s between attempts; the market is reported failed, never skipped

# invalid batch / max_markets abort (snapshot)

    Code
      hl_run(.mock_post(), out_dir = tempdir(), batch = 0)
    Condition
      Error in `hl_bad_arg()`:
      x Invalid `batch`
      i must be a whole number >= 1

---

    Code
      hl_run(.mock_post(), out_dir = tempdir(), max_markets = 0)
    Condition
      Error in `hl_bad_arg()`:
      x Invalid `max_markets`
      i must be NULL or a whole number >= 1

# a rate-limited market is reported failed and the run is INDETERMINATE (snapshot)

    Code
      print(res[c("status", "n_done", "n_skipped", "n_failed", "n_not_attempted")])
    Output
      $status
      [1] 3
      
      $n_done
      [1] 7
      
      $n_skipped
      [1] 0
      
      $n_failed
      [1] 1
      
      $n_not_attempted
      [1] 0
      

# each market prints a progress line with elapsed time and weight rate (snapshot)

    Code
      cat(sub("elapsed [0-9:]+", "elapsed H:MM:SS", lines), sep = "")
    Output
      [1/2] :BTC done | elapsed H:MM:SS | 900 weight/min
      [2/2] :MATIC done | elapsed H:MM:SS | 900 weight/min

