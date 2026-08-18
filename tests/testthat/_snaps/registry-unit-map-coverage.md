# .extract_units_map aborts informatively when the variable is not found

    Code
      .extract_units_map(file, "nonexistent_units")
    Condition
      Error in `.extract_units_map()`:
      x Could not find `nonexistent_units <- c(...)` in 'plan_ltr_momentum.R'.
      i The unit map may have been renamed or restructured.

# .derive_required_from_tibble aborts informatively when no tibble() columns remain (#693 follow-up)

    Code
      .derive_required_from_tibble(file, "toy_fn", exclude = c("strategy", "period"))
    Condition
      Error in `.derive_required_from_tibble()`:
      x `toy_fn()` in 'toy_plan.R' has no tibble() columns left after excluding "strategy" and "period".
      i `toy_fn()` was probably refactored away from a `tibble(...)`/`tibble::tibble(...)` constructor (e.g. to `data.frame()`, `as_tibble()`, or a `dplyr::transmute()` pipeline) -- `.extract_tibble_column_names()` only recognises the former.
      i Update this test's extractor (or its `fn_name`/`exclude`) to match the new constructor; an empty required set would make this test's coverage check pass vacuously.

# .extract_intersect_allowlist aborts informatively when the allow-list is empty (#693 follow-up)

    Code
      .extract_intersect_allowlist(file, "toy_cols")
    Condition
      Error in `.extract_intersect_allowlist()`:
      x `toy_cols`'s `intersect(...)` allow-list in 'toy_plan.R' is empty.
      i The allow-list's first argument was probably emptied, or replaced with something that no longer lists columns explicitly.
      i An empty allow-list would make this test's coverage check pass vacuously; fix the allow-list or re-classify this case.

# .check_declared_required aborts informatively when the declared list is empty (#693 follow-up)

    Code
      .check_declared_required(character(0), "toy_units")
    Condition
      Error in `.check_declared_required()`:
      x `toy_units`'s hand-declared required-columns list is empty.
      i Check the `unit_map_cases` entry for `toy_units` in 'test-registry-unit-map-coverage.R'.
      i An empty required set would make this test's coverage check pass vacuously, per .claude/rules/fail-loud-not-null.md.

