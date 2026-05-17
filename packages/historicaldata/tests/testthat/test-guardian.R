# Tests for hd_guardian() and hd_guardian_monthly()
# Covers: F3 (rate-limit docs, max_pages default) and F4 (malformed fields)

test_that("hd_guardian returns tibble from well-formed response", {
  skip_if_not_installed("httr2")
  skip_if_not_installed("jsonlite")

  body_json <- jsonlite::toJSON(list(
    response = list(
      status = "ok",
      pages  = 1L,
      results = data.frame(
        webPublicationDate = "2024-06-01T10:00:00Z",
        sectionName        = "Business",
        webUrl             = "https://www.theguardian.com/business/2024/jun/01/test",
        fields = I(list(list(headline = "Test headline", wordcount = "123"))),
        stringsAsFactors   = FALSE
      )
    )
  ), auto_unbox = TRUE)

  fake <- function(req) {
    httr2::response(
      status_code = 200L,
      headers     = list(`Content-Type` = "application/json"),
      body        = charToRaw(body_json)
    )
  }

  result <- httr2::with_mocked_responses(fake, {
    hd_guardian("test", from = "2024-01-01", max_pages = 1L)
  })

  expect_s3_class(result, "tbl_df")
  expect_true("headline" %in% names(result))
  expect_true("wordcount" %in% names(result))
  expect_true("date" %in% names(result))
})

test_that("hd_guardian survives malformed fields (F4: missing fields entirely)", {
  skip_if_not_installed("httr2")
  skip_if_not_installed("jsonlite")

  # A row where 'fields' key is absent — simulates partial API response
  body_json <- jsonlite::toJSON(list(
    response = list(
      status = "ok",
      pages  = 1L,
      results = list(
        list(
          webPublicationDate = "2024-06-01T10:00:00Z",
          sectionName        = "Business",
          webUrl             = "https://www.theguardian.com/business/test",
          fields             = list(headline = "Present headline", wordcount = "42")
        ),
        list(
          # fields key absent entirely
          webPublicationDate = "2024-06-02T10:00:00Z",
          sectionName        = "Business",
          webUrl             = "https://www.theguardian.com/business/test2"
        )
      )
    )
  ), auto_unbox = TRUE)

  fake <- function(req) {
    httr2::response(
      status_code = 200L,
      headers     = list(`Content-Type` = "application/json"),
      body        = charToRaw(body_json)
    )
  }

  # Must not error — missing fields become NA
  result <- httr2::with_mocked_responses(fake, {
    hd_guardian("test", from = "2024-01-01", max_pages = 1L)
  })

  expect_s3_class(result, "tbl_df")
  expect_equal(nrow(result), 2L)
  # Second row has no fields: headline and wordcount should be NA
  expect_true(is.na(result$headline[[2L]]))
  expect_true(is.na(result$wordcount[[2L]]))
})

test_that("hd_guardian handles empty results without error", {
  skip_if_not_installed("httr2")
  skip_if_not_installed("jsonlite")

  body_json <- jsonlite::toJSON(list(
    response = list(
      status  = "ok",
      pages   = 0L,
      results = list()
    )
  ), auto_unbox = TRUE)

  fake <- function(req) {
    httr2::response(
      status_code = 200L,
      headers     = list(`Content-Type` = "application/json"),
      body        = charToRaw(body_json)
    )
  }

  result <- httr2::with_mocked_responses(fake, {
    hd_guardian("nothing", from = "2024-01-01", max_pages = 1L)
  })

  expect_s3_class(result, "tbl_df")
  expect_equal(nrow(result), 0L)
})

test_that("hd_guardian_monthly has max_pages parameter and defaults to 5", {
  # Verify the function signature changed (F3: was hardcoded to 50)
  expect_equal(formals(hd_guardian_monthly)$max_pages, 5L)
})

test_that("hd_guardian returns NULL-headline as NA not error (F4 defensive extraction)", {
  skip_if_not_installed("httr2")
  skip_if_not_installed("jsonlite")

  body_json <- jsonlite::toJSON(list(
    response = list(
      status = "ok",
      pages  = 1L,
      results = list(
        list(
          webPublicationDate = "2024-06-01T10:00:00Z",
          sectionName        = "Business",
          webUrl             = "https://www.theguardian.com/test",
          fields             = list(wordcount = "99")  # headline key absent
        )
      )
    )
  ), auto_unbox = TRUE)

  fake <- function(req) {
    httr2::response(
      status_code = 200L,
      headers     = list(`Content-Type` = "application/json"),
      body        = charToRaw(body_json)
    )
  }

  result <- httr2::with_mocked_responses(fake, {
    hd_guardian("test", from = "2024-01-01", max_pages = 1L)
  })

  expect_s3_class(result, "tbl_df")
  expect_equal(nrow(result), 1L)
  expect_true(is.na(result$headline[[1L]]))
  expect_equal(result$wordcount[[1L]], 99L)
})
