# output tibble structure includes blown_up and bankrupt_month columns

    Code
      str(result)
    Output
      tibble [1 x 8] (S3: tbl_df/tbl/data.frame)
       $ strategy      : chr "test_struct"
       $ n_months      : int 24
       $ sharpe        : num -0.59
       $ cagr          : num NA
       $ vol           : num 85.6
       $ max_dd        : num -100
       $ blown_up      : logi TRUE
       $ bankrupt_month: int 13

