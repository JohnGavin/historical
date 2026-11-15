# snapshot: weight table (documented formula)

    Code
      print(c(info = hl_weight("allPerpMetas"), candles_5000 = hl_weight(
        "candleSnapshot", HL_CANDLE_PAGE_MAX), candles_168 = hl_weight(
        "candleSnapshot", 168), funding_500 = hl_weight("fundingHistory",
        HL_FUNDING_PAGE_MAX), funding_168 = hl_weight("fundingHistory", 168)))
    Output
              info candles_5000  candles_168  funding_500  funding_168 
                20          103           22           45           28 

# snapshot: sample ranks for a realistic group

    Code
      print(hl_sample_ranks(179, 10))
    Output
       [1]   1  21  41  60  80 100 120 139 159 179

# perp volumes parse by name inside one response; mismatch aborts (snapshot)

    Code
      hl_parse_perp_volumes(mac)
    Condition
      Error in `hl_parse_perp_volumes()`:
      ! metaAndAssetCtxs universe (3) and contexts (2) differ

# snapshot: scaled totals on fixtures

    Code
      print(tot[c("backfill_weight", "weekly_weight", "state_snapshot_weight_per_day")])
    Output
      $backfill_weight
      [1] 446
      
      $weekly_weight
      [1] 1064
      
      $state_snapshot_weight_per_day
      [1] 100
      

---

    Code
      print(A$counts)
    Output
      $perp_live
      [1] 4
      
      $perp_delisted
      [1] 2
      
      $spot_live
      [1] 2
      

# `[]` for a live listed market makes the run INDETERMINATE (problems)

    Code
      print(est$problems)
    Output
      [1] "BTC: empty 1d reply for a live market (INDETERMINATE)"
      [2] "BTC: empty 1h reply for a live market (INDETERMINATE)"

# markdown table helper renders a pipe table

    Code
      cat(hl_md_table(data.frame(a = c(1, 2.5), b = c("x", NA))), sep = "\n")
    Output
      | a | b |
      |---|---|
      | 1 | x |
      | 2.5 |  |

