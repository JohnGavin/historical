# key .cps_* function signatures are stable

    Code
      args(.cps_discover_consuming_targets)
    Output
      function (r_dir = here::here("R"), pkg = "historicaldata") 
      NULL

---

    Code
      args(.cps_main)
    Output
      function (store_path = here::here("docs", "_targets"), r_dir = here::here("R")) 
      NULL

---

    Code
      args(.cps_contains_pkg_call)
    Output
      function (expr, pkg = "historicaldata") 
      NULL

---

    Code
      args(.cps_target_touches_pkg)
    Output
      function (target_call, helper_touches, pkg = "historicaldata") 
      NULL

---

    Code
      args(.cps_helper_touches_pkg)
    Output
      function (helpers, pkg = "historicaldata") 
      NULL

