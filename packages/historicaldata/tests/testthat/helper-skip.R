# Test helpers separating CI-portable unit tests from network/integration tests.
#
# Issue #288: duckdb's `httpfs` extension cannot autoload on an offline CI
# runner, so integration tests that read remote `hf://` parquet (and other
# live-data tests) must be skipped on CI. These are integration tests, not
# offline-safe unit tests. testthat auto-loads `helper-*.R` before tests.
#
# Issue #580: `skip_if_offline()` only proves the machine can reach *some*
# host — it says nothing about whether the `hf://` parquet endpoint is
# actually serving valid data. When the endpoint rate-limits, truncates, or
# returns an error page, the machine is still "online", the three original
# guards all pass, and the test runs straight into duckdb dying mid-query
# with a cryptic `TProtocolException: Invalid data` instead of a clean skip.
# That instability was corrupting scripts/verify.sh's package-suite baseline
# (a green run could not be told apart from a lucky one).
#
# The fix: after the three cheap guards, attempt one minimal real read
# against the smallest hf:// dataset and skip() -- never fail -- if it does
# not return valid data. The probe result is memoised per test session (this
# guard is called 7+ times across the suite) so only the first call pays the
# network cost.

# NULL = not yet probed this session. Populated by `.probe_remote_data()`.
.remote_probe_cache <- new.env(parent = emptyenv())
.remote_probe_cache$result <- NULL

#' Probe the hf:// remote data source with one cheap, real read.
#'
#' Reads a single row from `equity_daily.parquet` -- the same
#' `read_parquet_duckdb()` path used by `hd_tickers()` / `hd_lazy()`, just
#' capped to `LIMIT 1` via `head(1)` before `collect()` so nothing beyond one
#' row crosses the wire. Memoised in `.remote_probe_cache` for the rest of
#' the test session so the 7+ call sites in this suite hit the network once.
#'
#' @return `TRUE` on a valid read, or the caught error/condition object.
#' @noRd
.probe_remote_data <- function() {
  if (!is.null(.remote_probe_cache$result)) {
    return(.remote_probe_cache$result)
  }

  # Errors only — deliberately NOT warnings. Catching warnings here would make
  # any benign warning during the read (deprecation notices, duckdb chatter)
  # skip the entire remote-data suite, silently trading 7 tests for a clean
  # run. That is the #574 failure mode with extra steps. The failure this
  # guard exists to absorb — TProtocolException on invalid parquet — is an
  # error, so error-only is both sufficient and the conservative choice:
  # it can only ever skip when a read genuinely could not complete.
  probe <- tryCatch(
    {
      url <- historicaldata:::hd_base_url("equity_daily.parquet")
      row <- duckplyr::read_parquet_duckdb(url) |>
        head(1) |>
        dplyr::collect()
      if (!is.data.frame(row) || nrow(row) < 1) {
        stop("probe returned zero rows")
      }
      TRUE
    },
    error = function(e) e
  )

  .remote_probe_cache$result <- probe
  probe
}

#' Skip a test that requires live remote data access.
#'
#' Skips on CRAN, on CI (where duckdb httpfs cannot autoload offline), when
#' offline, and -- after those three cheap checks -- when a real probe read
#' against the `hf://` endpoint does not return valid data (#580). Use in
#' place of the `skip_on_cran(); skip_if_offline()` pair for any test that
#' hits the network (hf:// parquet, FRED, Ken French, etc.).
#'
#' The probe skip message always names the underlying error so a rising
#' SKIP count is diagnosable, not just visible (see scripts/verify.sh, which
#' surfaces skip reasons when the package suite's count exceeds its normal
#' baseline of 5).
skip_if_no_remote_data <- function() {
  testthat::skip_on_cran()
  testthat::skip_on_ci()
  testthat::skip_if_offline()

  probe <- .probe_remote_data()
  if (!isTRUE(probe)) {
    testthat::skip(paste0(
      "hf:// remote data source did not return valid data (probe: ",
      conditionMessage(probe), ") -- machine is online but the endpoint ",
      "is rate-limited, truncated, or erroring. Not a code regression; ",
      "see issue #580."
    ))
  }
}
