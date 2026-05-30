# portfolio output structure is stable

    Code
      str(result)
    Output
      tibble [10 x 5] (S3: tbl_df/tbl/data.frame)
       $ as_of_date  : Date[1:10], format: "2026-01-31" "2026-01-31" ...
       $ ticker      : chr [1:10] "T01" "T02" "T03" "T04" ...
       $ signal_value: num [1:10] 0.02 0.04 0.06 0.08 0.1 0.92 0.94 0.96 0.98 1
       $ decile      : int [1:10] 1 1 1 1 1 10 10 10 10 10
       $ weight      : num [1:10] -0.2 -0.2 -0.2 -0.2 -0.2 0.2 0.2 0.2 0.2 0.2

