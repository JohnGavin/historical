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
      function (store_path = here::here("docs", "_targets"), r_dir = here::here("R"), 
          pkg_files_target = "pkg_source_files", targets_script = here::here("docs", 
              "_targets.R")) 
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

---

    Code
      args(.cps_pkg_source_changed_at)
    Output
      function (paths) 
      NULL

---

    Code
      args(.cps_evaluate_staleness)
    Output
      function (meta, known_names, pkg_source_changed_at, progress = NULL) 
      NULL

---

    Code
      args(.cps_source_files_paths)
    Output
      function (store_path, pkg_files_target = "pkg_source_files") 
      NULL

# vacuous case: 0 namespaced consumers + imports= declared -> exit 0 but LABELLED VACUOUS-PASS, EXAMINED: 0, never 'PASS: ... (0 checked)'

    Code
      cat(grep("VACUOUS-PASS", out, value = TRUE), sep = "\n")
    Output
      VACUOUS-PASS (0 examined): no target body calls historicaldata:: / historicaldata:::, so there was nothing for this backstop to check. This is NOT evidence that any target is fresh. Coverage rests on tar_option_set(imports = "historicaldata") in fake_docs_targets.R (verified present), which tracks bare-name calls. If a namespaced call is re-introduced this check examines it automatically.

# .cps_imports_declared signature is stable

    Code
      args(.cps_imports_declared)
    Output
      function (targets_script = here::here("docs", "_targets.R"), 
          pkg = "historicaldata") 
      NULL

