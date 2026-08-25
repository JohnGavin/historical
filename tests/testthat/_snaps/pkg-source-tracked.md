# check_pkg_source_tracked throws when too few files are tracked

    Code
      check_pkg_source_tracked(pkg_source_files = character(0), pkg_source_digest = "abc123")
    Condition
      Error in `check_pkg_source_tracked()`:
      x pkg_source_files returned only 0 file(s) -- expected at least 10.
      i check_pkg_source_tracked() (S22) guards the #753 staleness-detection mechanism itself: if pkg_source_files ever silently returns few/no files (e.g. packages/historicaldata/R was renamed or moved), pkg_source_digest keeps producing A digest, just not one that means anything -- and every downstream check built on it would keep passing for the wrong reason. Confirm the packages/historicaldata/R path in docs/_targets.R's pkg_source_files target still points at the real package source directory.

# check_pkg_source_tracked throws when digest is empty, NA, or not length-1

    Code
      check_pkg_source_tracked(files, "")
    Condition
      Error in `check_pkg_source_tracked()`:
      x pkg_source_digest is not a single non-empty string.
      i check_pkg_source_tracked() (S22) requires a well-formed digest -- see R/plan_qa_gates.R for what this guards against.

# key check_pkg_source_tracked() signature is stable

    Code
      args(check_pkg_source_tracked)
    Output
      function (pkg_source_files, pkg_source_digest, min_files = 10L) 
      NULL

