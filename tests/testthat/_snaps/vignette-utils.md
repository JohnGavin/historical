# safe_tar_read: stops in strict mode when target is absent

    Code
      safe_tar_read("nonexistent_target_xyz_12345")
    Condition
      Error:
      ! VIGNETTE_STRICT: Target 'nonexistent_target_xyz_12345' not found. Run tar_make() first.

# safe_tar_read: VIGNETTE_STRICT=1 triggers strict error (issue #232 + #231 integration)

    Code
      safe_tar_read("nonexistent_target_xyz_12345")
    Condition
      Error:
      ! VIGNETTE_STRICT: Target 'nonexistent_target_xyz_12345' not found. Run tar_make() first.

# .parse_vignette_strict: VIGNETTE_STRICT=treu returns FALSE AND triggers cli_warn (typo guard, roborev T1)

    Code
      result <- .parse_vignette_strict()
    Condition
      Warning:
      Unrecognised `VIGNETTE_STRICT` value "treu" — falling back to FALSE
      i Accepted truthy: 1, yes, on, true, t (case-insensitive, whitespace-tolerant)
      i Accepted falsy: 0, no, off, false, f, '' (empty)
      This warning is displayed once per session.

# .parse_vignette_strict: 'n' is unrecognised alias — warns and returns FALSE (safe default)

    Code
      result <- .parse_vignette_strict()
    Condition
      Warning:
      Unrecognised `VIGNETTE_STRICT` value "n" — falling back to FALSE
      i Accepted truthy: 1, yes, on, true, t (case-insensitive, whitespace-tolerant)
      i Accepted falsy: 0, no, off, false, f, '' (empty)
      This warning is displayed once per session.

# .parse_vignette_strict: typo warning fires AT MOST ONCE across N calls (roborev #4263)

    Code
      cat(warnings_seen[[1]])
    Output
      Unrecognised `VIGNETTE_STRICT` value "yse" — falling back to FALSE
      i Accepted truthy: 1, yes, on, true, t (case-insensitive, whitespace-tolerant)
      i Accepted falsy: 0, no, off, false, f, '' (empty)
      This warning is displayed once per session.

# function signatures are stable (catches API drift)

    Code
      args(.parse_vignette_strict)
    Output
      function () 
      NULL

---

    Code
      args(safe_tar_read)
    Output
      function (name, strict = .parse_vignette_strict()) 
      NULL

---

    Code
      args(is_stale_marker)
    Output
      function (x) 
      NULL

---

    Code
      args(show_code)
    Output
      function (target_name) 
      NULL

---

    Code
      args(.hd_tree_status_display)
    Output
      function (status_lines, max_shown = 10L) 
      NULL

---

    Code
      args(.hd_tree_status_cmd)
    Output
      function (repo_root) 
      NULL

---

    Code
      args(.hd_branch_display)
    Output
      function (raw_branch, sha_short) 
      NULL

