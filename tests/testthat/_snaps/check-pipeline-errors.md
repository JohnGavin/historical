# key .cpe_* function signatures are stable

    Code
      args(.cpe_read_meta)
    Output
      function (store_path) 
      NULL

---

    Code
      args(.cpe_main)
    Output
      function (store_path = here::here("docs", "_targets")) 
      NULL

