test_that("plan_drif cumprod survives scattered NA in returns", {
  df <- tibble::tibble(
    ym = c("2024-01", "2024-02", "2024-03"),
    portfolio_ret = c(0.05, NA_real_, 0.03),
    benchmark_ret = c(0.02, 0.01, NA_real_),
    rf_ret        = c(0, 0, 0),
    last_date     = as.Date(c("2024-01-31", "2024-02-29", "2024-03-31"))
  )
  result <- df |>
    dplyr::mutate(
      date       = last_date,
      port_cum   = cumprod(1 + dplyr::coalesce(portfolio_ret, 0)),
      bench_cum  = cumprod(1 + dplyr::coalesce(benchmark_ret, 0))
    )
  expect_false(any(is.na(result$port_cum)))
  expect_false(any(is.na(result$bench_cum)))
  # February row's port_cum == January's (NA → 0 → no change)
  expect_equal(result$port_cum[2], result$port_cum[1], tolerance = 1e-10)
})
