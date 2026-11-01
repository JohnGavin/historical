# a wrong column count aborts naming dataset, expected and found

    Code
      .ff_read_csv_dir(d, "F-F_Research_Data_5_Factors_2x3", "monthly")
    Condition
      Error in `.ff_check_ncol()`:
      ! Unexpected column count in F-F_Research_Data_5_Factors_2x3.
      x Expected 7 columns, found 13.

---

    Code
      .ff_read_csv_dir(d, "F-F_Momentum_Factor", "monthly")
    Condition
      Error in `.ff_check_ncol()`:
      ! Unexpected column count in F-F_Momentum_Factor.
      x Expected 2 columns, found 13.

