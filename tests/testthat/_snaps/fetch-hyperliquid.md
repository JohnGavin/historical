# an unknown interval aborts (snapshot)

    Code
      hl_fetch_candles("BTC", 0, 1e+12, interval = "5m")
    Condition
      Error in `hl_check_interval()`:
      x Unsupported candle interval "5m"
      i Allowed: "1d" and "1h"

---

    Code
      hl_parse_candles(.candles, "", "SOL", interval = "15m")
    Condition
      Error in `hl_check_interval()`:
      x Unsupported candle interval "15m"
      i Allowed: "1d" and "1h"

# an unknown instrument type aborts (snapshot)

    Code
      hl_parse_candles(.candles, "", "SOL", instrument_type = "future")
    Condition
      Error in `hl_parse_candles()`:
      x Unsupported instrument type "future"
      i Allowed: "perp" and "spot"

# `[]` for a listed live market is INDETERMINATE, never a silent success

    Code
      hl_empty_reply("candle", "BTC")
    Condition
      Error in `hl_empty_reply()`:
      x BTC: empty candle reply for a listed, live market
      i INDETERMINATE: cannot tell 'no data' from 'window outside retention'

# snapshot: funding cap table (capped delisted markets)

    Code
      print(res$funding_cap, row.names = FALSE)
    Output
               item    cap funding_end_ms
             :MATIC capped   1.762387e+12
       flx:flx:TSLA capped   1.762387e+12

---

    Code
      print(res[c("n_funding_capped", "n_funding_no_traded_bar")])
    Output
      $n_funding_capped
      [1] 2
      
      $n_funding_no_traded_bar
      [1] 0
      

# snapshot: funding cap table (delisted market with no traded bar)

    Code
      print(res$funding_cap, row.names = FALSE)
    Output
               item           cap funding_end_ms
             :MATIC no_traded_bar             NA
       flx:flx:TSLA        capped   1.762387e+12

# a `null` reply (unknown coin) is an error, not an empty window (snapshot)

    Code
      hl_fetch_candles("NOSUCH", 0, 1e+12, function(b) NULL)
    Condition
      Error in `hl_reply_list()`:
      x candleSnapshot NOSUCH: reply was null
      i an unknown coin returns null; this is not an empty window

# an unrecognised market form aborts (snapshot)

    Code
      hl_classify_coin("weird thing!")
    Condition
      Error in `FUN()`:
      x Unrecognised market form "weird thing!"
      i known classes: "main_perp", "builder_perp", "spot_pair", "spot_unlisted", and "outcome"

---

    Code
      hl_classify_coin("PURR/USDC", character())
    Condition
      Error in `FUN()`:
      x Unrecognised market form "PURR/USDC"
      i known classes: "main_perp", "builder_perp", "spot_pair", "spot_unlisted", and "outcome"

# allPerpMetas guards abort on empty or non-perp input (snapshot)

    Code
      hl_parse_perp_markets(list())
    Condition
      Error in `hl_parse_perp_markets()`:
      ! allPerpMetas payload is empty or not a list

---

    Code
      hl_parse_perp_markets(list(list(universe = list())))
    Condition
      Error in `FUN()`:
      ! allPerpMetas holds an exchange with an empty universe

---

    Code
      hl_parse_perp_markets(list(list(universe = list(list(name = "@1")))))
    Condition
      Error in `hl_parse_perp_markets()`:
      ! allPerpMetas holds a non-perp market form

# spot guards abort on empty universe or bad payload (snapshot)

    Code
      hl_parse_spot_markets(list(universe = list()), .spot_ctx)
    Condition
      Error in `hl_parse_spot_markets()`:
      ! spotMeta universe is empty

---

    Code
      hl_parse_spot_markets(.spot_meta, list(1, 2, 3))
    Condition
      Error in `hl_parse_spot_markets()`:
      ! spotMetaAndAssetCtxs payload must be [meta, ctxs]

# duplicate (coin, time) funding rows abort (snapshot)

    Code
      hl_parse_funding_raw(c(.f_offset, .f_offset[2]), "", "BTC")
    Condition
      Error in `hl_parse_funding_raw()`:
      x BTC: duplicate (coin, time) funding rows

# paging that repeats a boundary row aborts (snapshot)

    Code
      hl_fetch_funding("SOL", 0, 4e+12, post, page_max = 2L)
    Condition
      Error in `hl_fetch_funding()`:
      x SOL: duplicate funding timestamps after paging
      i 1 repeated time value

# snapshot: perp market table from allPerpMetas

    Code
      print(hl_parse_perp_markets(.apm))
    Output
        dex       coin symbol market_class instrument_type is_delisted day_ntl_vlm
      1            BTC    BTC    main_perp            perp       FALSE          NA
      2          MATIC  MATIC    main_perp            perp        TRUE          NA
      3            SOL    SOL    main_perp            perp       FALSE          NA
      4 xyz xyz:XYZ100 XYZ100 builder_perp            perp       FALSE          NA
      5 xyz   xyz:TSLA   TSLA builder_perp            perp       FALSE          NA
      6 flx   flx:TSLA   TSLA builder_perp            perp        TRUE          NA
        traded_24h
      1         NA
      2         NA
      3         NA
      4         NA
      5         NA
      6         NA

# snapshot: spot market table and out-of-scope counts

    Code
      print(s$markets)
    Output
        dex      coin    symbol market_class instrument_type is_delisted day_ntl_vlm
      1     PURR/USDC PURR/USDC    spot_pair            spot       FALSE   2254455.9
      2            @1        @1    spot_pair            spot       FALSE    112097.2
      3            @3        @3    spot_pair            spot       FALSE         0.0
        traded_24h
      1       TRUE
      2       TRUE
      3      FALSE

---

    Code
      print(s$out_of_scope)
    Output
         market_class n
      1 spot_unlisted 2
      2       outcome 2

# snapshot: hourly bars incl. n_trades, traded and close_time

    Code
      print(h[c("time", "coin", "open", "close", "n_trades", "traded", "close_time")])
    Output
                       time coin  open close n_trades traded          close_time
      1 2026-11-15 10:00:00  BTC 65342 65580    14274   TRUE 2026-11-15 10:59:59
      2 2026-11-15 11:00:00  BTC 65581 65329    11152   TRUE 2026-11-15 11:59:59
      3 2026-11-15 12:00:00  BTC 65330 65494    11429   TRUE 2026-11-15 12:59:59
      4 2026-11-15 13:00:00  BTC 65495 65432    14141   TRUE 2026-11-15 13:59:59
      5 2026-11-15 14:00:00  BTC 65432 64921    18584   TRUE 2026-11-15 14:59:59

# snapshot: delisted MATIC daily and hourly bars

    Code
      print(hl_parse_candles(.matic_1d, "", "MATIC")[c("date", "close", "n_trades",
        "traded")])
    Output
              date   close n_trades traded
      1 2024-09-07 0.36952     2368   TRUE
      2 2024-09-08 0.37629     2499   TRUE
      3 2024-09-09 0.37621      779   TRUE

---

    Code
      print(hl_parse_candles(.matic_1h, "", "MATIC", "1h")[c("time", "close",
        "traded")])
    Output
                       time   close traded
      1 2024-09-09 05:00:00 0.37367   TRUE
      2 2024-09-09 06:00:00 0.37563   TRUE
      3 2024-09-09 07:00:00 0.37621   TRUE

# snapshot: funding offset slice keeps and flags the 24-minute row

    Code
      print(f[c("time", "funding_rate", "interval_hours", "offset_min",
        "offset_outlier")])
    Output
                       time  funding_rate interval_hours   offset_min offset_outlier
      1 2023-05-23 00:00:00 -0.0001899086              8 3.666667e-04          FALSE
      2 2023-05-23 08:23:53 -0.0001754061              8 2.388400e+01           TRUE
      3 2023-05-23 16:00:00 -0.0001552822              8 1.316667e-03          FALSE

# snapshot: funding 8h -> 1h switch read from the gaps

    Code
      print(data.frame(interval_hours = r$values, n_rows = r$lengths))
    Output
        interval_hours n_rows
      1              8      4
      2              1     23

---

    Code
      print(f[f$time >= as.POSIXct("2023-06-07 23:00:00", tz = "UTC") & f$time <=
        as.POSIXct("2023-06-08 02:00:00", tz = "UTC"), c("time", "interval_hours",
        "rate_per_hour")])
    Output
                       time interval_hours rate_per_hour
      4 2023-06-08 00:00:00              8      1.25e-05
      5 2023-06-08 01:00:00              1      1.25e-05

# snapshot: hl_run summary (happy path, and the `[]` live-market case)

    Code
      print(ok[c("status", "n_markets", "n_in_progress_dropped")])
    Output
      $status
      [1] 0
      
      $n_markets
      [1] 8
      
      $n_in_progress_dropped
      [1] 8
      

---

    Code
      print(ok$out_of_scope)
    Output
         market_class n
      1 spot_unlisted 2
      2       outcome 2

---

    Code
      print(bad$failed, row.names = FALSE)
    Output
       item
       :BTC
                                                                                                                            reason
       x BTC: empty candle reply for a listed, live market\ni INDETERMINATE: cannot tell 'no data' from 'window outside retention'

# snapshot: output files written by hl_run

    Code
      print(sort(list.files(out)))
    Output
      [1] "perp_daily.parquet"         "perp_funding.parquet"      
      [3] "perp_funding_daily.parquet" "perp_hourly.parquet"       
      [5] "perp_oi_snapshot.parquet"   "spot_daily.parquet"        
      [7] "spot_hourly.parquet"       

---

    Code
      print(names(arrow::read_parquet(file.path(out, "perp_hourly.parquet"))))
    Output
       [1] "time"            "dex"             "coin"            "symbol"         
       [5] "instrument_type" "source"          "open"            "high"           
       [9] "low"             "close"           "volume_base"     "n_trades"       
      [13] "traded"          "close_time"      "market_class"    "is_delisted"    

---

    Code
      print(names(arrow::read_parquet(file.path(out, "perp_funding.parquet"))))
    Output
       [1] "dex"            "coin"           "time_ms"        "time"          
       [5] "funding_rate"   "premium"        "interval_hours" "rate_per_hour" 
       [9] "offset_min"     "offset_outlier"

# snapshot: raw store layout (dated dir, never overwritten)

    Code
      print(sort(list.files(d, recursive = TRUE)))
    Output
      [1] "2026-11-15/allPerpMetas_all_na.json"           
      [2] "2026-11-15/fundingHistory_at107_na.json"       
      [3] "2026-11-15/fundingHistory_at107_na_100000.json"

