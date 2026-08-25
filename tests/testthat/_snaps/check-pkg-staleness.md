# key .cps_* function signatures are stable

    Code
      args(.cps_discover_consuming_targets)
    Output
      function (r_dir = here::here("R")) 
      NULL

---

    Code
      args(.cps_main)
    Output
      function (store_path = here::here("docs", "_targets"), r_dir = here::here("R")) 
      NULL

