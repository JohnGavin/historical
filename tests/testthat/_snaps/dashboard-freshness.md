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

# .cdf_write_meta_snapshot aborts if a real target collides with the reserved sentinel name

    Code
      .cdf_write_meta_snapshot(meta_time, snapshot_path)
    Condition
      Error in `.cdf_write_meta_snapshot()`:
      x A real target is named "__generated_at__", which collides with the metadata snapshot's reserved sentinel row name.
      i Rename the target, or change .CDF_META_SNAPSHOT_SENTINEL_NAME in scripts/check_dashboard_freshness.R.

# .cdf_read_meta_snapshot aborts informatively when the file does not exist

    Code
      .cdf_read_meta_snapshot(missing_path)
    Condition
      Error in `.cdf_read_meta_snapshot()`:
      x Metadata snapshot not found at 'toy_snapshot.csv'.
      i Run `scripts/build.sh` in the main checkout to generate one.

# .cdf_read_meta_snapshot aborts informatively on unexpected columns

    Code
      .cdf_read_meta_snapshot(snapshot_path)
    Condition
      Error in `.cdf_read_meta_snapshot()`:
      x Metadata snapshot at 'toy_snapshot.csv' does not have the expected `name,time` columns.
      i Found columns: wrong, columns
      i Regenerate it with `scripts/build.sh` rather than hand-editing.

# .cdf_read_meta_snapshot aborts informatively when the sentinel row is missing

    Code
      .cdf_read_meta_snapshot(snapshot_path)
    Condition
      Error in `.cdf_read_meta_snapshot()`:
      x Metadata snapshot at 'toy_snapshot.csv' has 0 "__generated_at__" row(s); expected exactly 1.
      i The file is malformed -- regenerate it with `scripts/build.sh` rather than hand-editing.

# .cdf_read_meta_snapshot aborts informatively when the sentinel row is duplicated

    Code
      .cdf_read_meta_snapshot(snapshot_path)
    Condition
      Error in `.cdf_read_meta_snapshot()`:
      x Metadata snapshot at 'toy_snapshot.csv' has 2 "__generated_at__" row(s); expected exactly 1.
      i The file is malformed -- regenerate it with `scripts/build.sh` rather than hand-editing.

# .cdf_read_meta_snapshot aborts informatively on an unparseable generated_at value

    Code
      .cdf_read_meta_snapshot(snapshot_path)
    Condition
      Error in `.cdf_read_meta_snapshot()`:
      x Metadata snapshot at 'toy_snapshot.csv' has an unparseable generated_at value: "not-a-timestamp"
      i The file is malformed -- regenerate it with `scripts/build.sh` rather than hand-editing.

# .cdf_check3_source_decision propagates a malformed snapshot's error rather than treating it as no_source

    Code
      .cdf_check3_source_decision(store_exists = FALSE, snapshot_path, threshold_hrs = 14 *
        24)
    Condition
      Error in `.cdf_read_meta_snapshot()`:
      x Metadata snapshot at 'toy_snapshot.csv' has 0 "__generated_at__" row(s); expected exactly 1.
      i The file is malformed -- regenerate it with `scripts/build.sh` rather than hand-editing.

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

---

    Code
      args(.cdf_meta_snapshot_path)
    Output
      function (repo_root) 
      NULL

---

    Code
      args(.cdf_write_meta_snapshot)
    Output
      function (meta_time, snapshot_path, generated_at = Sys.time()) 
      NULL

---

    Code
      args(.cdf_read_meta_snapshot)
    Output
      function (snapshot_path) 
      NULL

---

    Code
      args(.cdf_meta_snapshot_age_hours)
    Output
      function (generated_at, now = Sys.time()) 
      NULL

---

    Code
      args(.cdf_check3_source_decision)
    Output
      function (store_exists, snapshot_path, threshold_hrs, now = Sys.time()) 
      NULL

