# .cdf_extract_read_targets aborts informatively on a non-literal, non-symbol first argument (#695)

    Code
      .cdf_extract_read_targets(exprs, "toy_dashboard.qmd")
    Condition
      Error in `walk()`:
      x `tar_read()` called with a non-literal, non-symbol first argument in 'toy_dashboard.qmd'.
      i Argument was: `paste0("prefix_", "suffix")`
      i This checker can only statically resolve a string literal or a bare symbol target name.

# .cdf_extract_read_targets aborts informatively on a zero-argument read call (#695)

    Code
      .cdf_extract_read_targets(exprs, "toy_dashboard.qmd")
    Condition
      Error in `walk()`:
      x `tar_read()` call with no arguments in 'toy_dashboard.qmd'.
      i Expected a target name as the first argument.

# .cdf_extract_qmd_targets aborts when a chunk fence is present but purl() extracts zero expressions (#695)

    Code
      .cdf_extract_qmd_targets(file)
    Condition
      Error in `.cdf_purl_and_extract()`:
      x knitr::purl() extracted zero R expressions from 'toy_dashboard.qmd', but the file contains R chunk fence(s).
      i This is more likely a broken extractor (e.g. a non-r engine, an unusual chunk header) than a page with no code.
      i Investigate before trusting this check; do not add an exception without confirming the file genuinely has no executable R.

# .cdf_extract_qmd_targets aborts informatively when knitr::purl() itself fails (#695)

    Code
      .cdf_extract_qmd_targets(missing_file)
    Condition
      Error in `value[[3L]]()`:
      x knitr::purl() failed on 'toy_dashboard.qmd'.
      i cannot open the connection

# .cdf_resolve_include_path aborts informatively when the include target does not exist (#695 follow-up)

    Code
      .cdf_resolve_include_path("toy_missing_child.qmd", including)
    Condition
      Error in `.cdf_resolve_include_path()`:
      x 'toy_dashboard.qmd' includes 'toy_missing_child.qmd', but that file does not exist.
      i Looked for it relative to 'toy_dashboard.qmd''s own directory (Quarto's include-resolution rule).
      i A dead include target fails at Quarto render time; fix the path or restore the file.

# .cdf_extract_qmd_targets aborts when a page includes a file that does not exist (#695 follow-up)

    Code
      .cdf_extract_qmd_targets(parent)
    Condition
      Error in `.cdf_resolve_include_path()`:
      x 'toy_parent.qmd' includes 'toy_missing_child.qmd', but that file does not exist.
      i Looked for it relative to 'toy_parent.qmd''s own directory (Quarto's include-resolution rule).
      i A dead include target fails at Quarto render time; fix the path or restore the file.

# .cdf_data_staleness_threshold_hours aborts informatively on an unparseable value (#695 rescope, fail-loud-not-null.md)

    Code
      .cdf_data_staleness_threshold_hours()
    Condition
      Error in `.cdf_data_staleness_threshold_hours()`:
      x `HD_STALE_DASHBOARD_DATA_THRESHOLD_DAYS` is set to "not-a-number", which is not a non-negative number of days.
      i Unset it to use the default (14 days), or set it to a non-negative number.

# .cdf_data_staleness_threshold_hours aborts informatively on a negative value

    Code
      .cdf_data_staleness_threshold_hours()
    Condition
      Error in `.cdf_data_staleness_threshold_hours()`:
      x `HD_STALE_DASHBOARD_DATA_THRESHOLD_DAYS` is set to "-1", which is not a non-negative number of days.
      i Unset it to use the default (14 days), or set it to a non-negative number.

# key .cdf_* function signatures are stable

    Code
      args(.cdf_extract_qmd_targets)
    Output
      function (qmd_path, visited = character(0)) 
      NULL

---

    Code
      args(.cdf_extract_read_targets)
    Output
      function (exprs, qmd_basename) 
      NULL

---

    Code
      args(.cdf_extract_include_paths)
    Output
      function (qmd_path) 
      NULL

---

    Code
      args(.cdf_resolve_include_path)
    Output
      function (raw_path, including_path) 
      NULL

---

    Code
      args(.cdf_purl_and_extract)
    Output
      function (qmd_path) 
      NULL

---

    Code
      args(.cdf_check_dead_references)
    Output
      function (page_targets, manifest_names) 
      NULL

---

    Code
      args(.cdf_is_redirect_stub)
    Output
      function (qmd_path) 
      NULL

---

    Code
      args(.cdf_check_source_staleness)
    Output
      function (qmd_files, repo_root, is_stub_fn = .cdf_is_redirect_stub) 
      NULL

---

    Code
      args(.cdf_check_data_staleness)
    Output
      function (qmd_files, page_targets, meta_time, repo_root, note_fn = NULL) 
      NULL

---

    Code
      args(.cdf_page_render_time)
    Output
      function (html_path, repo_root) 
      NULL

---

    Code
      args(.cdf_git_last_commit_time)
    Output
      function (abs_path, repo_root) 
      NULL

---

    Code
      args(.cdf_data_staleness_threshold_hours)
    Output
      function () 
      NULL

---

    Code
      args(.cdf_data_staleness_over_threshold)
    Output
      function (data_stale, threshold_hrs) 
      NULL

---

    Code
      args(.cdf_main)
    Output
      function (data_staleness = FALSE, repo_root = here::here()) 
      NULL

