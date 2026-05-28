test_that("hd_jst_variables returns expected structure", {
  vars <- hd_jst_variables()
  expect_s3_class(vars, "tbl_df")
  expect_named(vars, c("variable", "category", "description", "coverage"))
  expect_true(nrow(vars) >= 10)
  # Key return variables must be present
  expect_true("eq_tr" %in% vars$variable)
  expect_true("bond_tr" %in% vars$variable)
  expect_true("housing_tr" %in% vars$variable)
  expect_true("crisisJST" %in% vars$variable)
})

test_that("hd_jst_variables categories are non-empty strings", {
  vars <- hd_jst_variables()
  expect_true(all(nzchar(vars$variable)))
  expect_true(all(nzchar(vars$category)))
  expect_true(all(nzchar(vars$description)))
})

test_that("jst_macrohistory entry is in hd_datasets registry", {
  ds <- hd_datasets()
  expect_true("jst_macrohistory" %in% names(ds))
  entry <- ds[["jst_macrohistory"]]
  expect_true(all(c("url", "schema", "frequency", "description") %in% names(entry)))
  expect_equal(entry$frequency, "annual")
  expect_true(grepl("macrohistory", entry$url, fixed = TRUE))
  # Schema covers required columns from issue #98
  expect_true("iso" %in% entry$schema)
  expect_true("year" %in% entry$schema)
  expect_true("eq_tr" %in% entry$schema)
  expect_true("bond_tr" %in% entry$schema)
  expect_true("housing_tr" %in% entry$schema)
})

test_that("hd_jst returns cached data when cache file exists", {
  cache_file <- file.path(hd_cache_path(), "jst_macrohistory.rds")
  skip_if(!file.exists(cache_file), "JST cache file not present — run hd_jst() once to populate")

  result <- hd_jst(cache = TRUE)
  expect_s3_class(result, "tbl_df")
  expect_true("iso" %in% names(result))
  expect_true("year" %in% names(result))
  expect_true("eq_tr" %in% names(result))
  expect_true(nrow(result) > 0)
  # 18 countries expected in Release 6
  expect_true(length(unique(result$iso)) >= 10)
  # Coverage 1870-2020
  expect_true(min(result$year) <= 1900)
  expect_true(max(result$year) >= 2000)
})

test_that("hd_jst aborts when cache missing and haven not installed", {
  # with_envvar opens the scoped env BEFORE skip_if so the skip predicate
  # evaluates against the temp cache dir, not the user's real cache dir.
  # Previously the outer skip_if fired against hd_cache_path() before
  # HD_CACHE_DIR was overridden, causing the test to silently skip even when
  # the real cache exists but the temp dir (used by the test body) does not.
  # Fix: move skip_if inside with_envvar so both see the same HD_CACHE_DIR.
  # (Issue #315)
  withr::with_envvar(c(HD_CACHE_DIR = tempdir()), {
    tmp_cache <- file.path(hd_cache_path(), "jst_macrohistory.rds")
    if (file.exists(tmp_cache)) file.remove(tmp_cache)

    skip_if(requireNamespace("haven", quietly = TRUE) &&
              requireNamespace("httr2", quietly = TRUE),
            "Both haven and httr2 available — network call would occur")

    expect_error(hd_jst(cache = FALSE), "required")
  })
})

# Regression test for issue #315: skip-guard timing with with_envvar
# Verifies that hd_cache_path() reads HD_CACHE_DIR from the scoped env set by
# with_envvar, not from the outer (user) env. This is the prerequisite for the
# skip_if inside with_envvar pattern above to work correctly.
test_that("hd_cache_path reads HD_CACHE_DIR from with_envvar scope (regression #315)", {
  sentinel <- file.path(tempdir(), "hd_skip_guard_timing_test")
  withr::with_envvar(c(HD_CACHE_DIR = sentinel), {
    observed <- hd_cache_path()
    expect_equal(observed, sentinel,
      info = "hd_cache_path() must see the HD_CACHE_DIR set by with_envvar, not the outer env")
  })
  # Outside the scope, hd_cache_path() must revert to the previous value
  outer_path <- hd_cache_path()
  expect_false(outer_path == sentinel,
    info = "hd_cache_path() must revert after with_envvar scope closes")
})
