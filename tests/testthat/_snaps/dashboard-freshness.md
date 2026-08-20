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
      Error in `.cdf_extract_qmd_targets()`:
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

# key .cdf_* function signatures are stable

    Code
      args(.cdf_extract_qmd_targets)
    Output
      function (qmd_path) 
      NULL

---

    Code
      args(.cdf_extract_read_targets)
    Output
      function (exprs, qmd_basename) 
      NULL

---

    Code
      args(.cdf_check_dead_references)
    Output
      function (page_targets, manifest_names) 
      NULL

---

    Code
      args(.cdf_check_source_staleness)
    Output
      function (qmd_files, repo_root) 
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
      args(.cdf_main)
    Output
      function (data_staleness = FALSE, repo_root = here::here()) 
      NULL

