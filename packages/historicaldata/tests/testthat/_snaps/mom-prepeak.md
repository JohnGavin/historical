# hd_mom_prepeak_signal rejects non-data.frame input

    Code
      hd_mom_prepeak_signal("not a data frame", as_of_dates = as.Date("2026-01-31"))
    Condition
      Error in `hd_mom_prepeak_signal()`:
      x `daily_prices` must be a data frame, not <character>.

# hd_mom_prepeak_signal rejects missing columns

    Code
      hd_mom_prepeak_signal(tibble::tibble(ticker = "X"), as_of_dates = as.Date(
        "2026-01-31"))
    Condition
      Error in `hd_mom_prepeak_signal()`:
      x `daily_prices` is missing required columns: date and adjusted.

# output structure is stable

    Code
      str(res)
    Output
      tibble [2 x 10] (S3: tbl_df/tbl/data.frame)
       $ ticker          : chr [1:2] "G" "H"
       $ as_of_date      : Date[1:2], format: "2026-01-31" "2026-01-31"
       $ formation_start : Date[1:2], format: "2025-01-31" "2025-01-31"
       $ formation_end   : Date[1:2], format: "2025-09-07" "2025-09-07"
       $ peak_date       : Date[1:2], format: "2025-09-07" "2025-01-31"
       $ n_obs           : int [1:2] 220 220
       $ pre_peak_return : num [1:2] 0.3 0
       $ post_peak_return: num [1:2] 0 -0.231
       $ total_return    : num [1:2] 0.3 -0.231
       $ peak_position   : num [1:2] 1 0

# peak_position is 1 for all tickers on a monotone-increasing series

    Code
      summary(res$peak_position)
    Output
         Min. 1st Qu.  Median    Mean 3rd Qu.    Max. 
            1       1       1       1       1       1 

