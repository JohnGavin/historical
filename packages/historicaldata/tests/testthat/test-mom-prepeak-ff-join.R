test_that("month-key floor aligns month-start FF dates with month-end strategy dates", {
  ff    <- tibble::tibble(date      = as.Date(c("2026-01-01", "2026-02-01", "2026-03-01")), val = 1:3)
  strat <- tibble::tibble(exec_date = as.Date(c("2026-01-31", "2026-02-28", "2026-03-31")), ret = 11:13)

  joined <- ff |>
    dplyr::mutate(month_key = lubridate::floor_date(date, "month")) |>
    dplyr::inner_join(
      strat |> dplyr::mutate(month_key = lubridate::floor_date(exec_date, "month")),
      by = "month_key"
    )
  expect_equal(nrow(joined), 3L)
  expect_equal(joined$val, c(1L, 2L, 3L))
  expect_equal(joined$ret, c(11L, 12L, 13L))
})
