# check_no_lead_ym detects lead(ym) pattern

    Code
      names(hits)
    Output
      [1] "file" "line" "code"

# qa look-ahead-bias scanner function signatures are stable (catches API drift)

    Code
      args(check_no_lead_ym)
    Output
      function (files) 
      NULL

---

    Code
      args(check_no_unleaded_slider)
    Output
      function (files) 
      NULL

---

    Code
      args(check_no_na_approx)
    Output
      function (files) 
      NULL

---

    Code
      args(check_no_forward_cumulative)
    Output
      function (files) 
      NULL

