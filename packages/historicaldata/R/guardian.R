#' Fetch Guardian Open Platform articles
#'
#' Queries the Guardian Content API for articles matching a keyword
#' in the business/money sections.
#'
#' @param query Search query string
#' @param section Guardian section ("business", "money", etc.)
#' @param from Start date (character "YYYY-MM-DD" or Date)
#' @param to End date (character or Date)
#' @param api_key API key. Default: "test" (limited to 1 call/sec, no body text)
#' @param page_size Results per page (max 200)
#' @param max_pages Maximum pages to fetch (rate limit protection). The Guardian
#'   API rate-limits at 1 req/sec for the "test" key, so `max_pages = 50` takes
#'   approximately 50 seconds per call. Default is 10 (≈ 10 seconds).
#' @return Tibble with columns: date, headline, section, wordcount, url
#' @family data-access
#' @export
#' @examplesIf interactive()
#' hd_guardian("recession", from = "2024-01-01")
hd_guardian <- function(query, section = "business",
                        from = "2020-01-01", to = NULL,
                        api_key = Sys.getenv("GUARDIAN_API_KEY", "test"),
                        page_size = 200L, max_pages = 10L) {
  if (!requireNamespace("httr2", quietly = TRUE)) {
    cli::cli_abort("Package {.pkg httr2} required for Guardian data.")
  }
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    cli::cli_abort("Package {.pkg jsonlite} required for parsing Guardian API responses.")
  }

  if (max_pages > 10L) {
    sleep_per_page <- if (api_key == "test") 1 else 0.1
    cli::cli_inform(c(
      "i" = "Fetching up to {max_pages} pages at {sleep_per_page} sec/req",
      " " = "Expected wait: ~{max_pages * sleep_per_page} seconds."
    ))
  }

  all_results <- list()
  page <- 1L

  repeat {
    req <- httr2::request("https://content.guardianapis.com/search") |>
      httr2::req_url_query(
        q = query,
        section = section,
        `from-date` = as.character(from),
        `page-size` = page_size,
        page = page,
        `api-key` = api_key,
        `show-fields` = "headline,wordcount"
      )

    if (!is.null(to)) {
      req <- req |> httr2::req_url_query(`to-date` = as.character(to))
    }

    resp <- req |>
      httr2::req_error(is_error = function(r) FALSE) |>
      httr2::req_perform()

    if (httr2::resp_status(resp) != 200L) {
      cli::cli_warn("Guardian API returned status {httr2::resp_status(resp)}")
      break
    }

    data <- jsonlite::fromJSON(httr2::resp_body_string(resp))
    results <- data$response$results
    if (is.null(results) || length(results) == 0L) break
    # jsonlite may return a data.frame or a list depending on response structure.
    # Guard against both so nrow() works safely.
    n_results <- if (is.data.frame(results)) nrow(results) else length(results)
    if (n_results == 0L) break

    # Defensive headline extraction: results$fields may be a data.frame or a
    # list-of-lists (or missing entirely) depending on the API response shape.
    extract_field <- function(results, field) {
      vapply(seq_len(n_results), function(i) {
        r <- if (is.data.frame(results)) results[i, , drop = FALSE] else results[[i]]
        flds <- if (is.data.frame(results)) r$fields else r[["fields"]]
        if (is.null(flds)) return(NA_character_)
        val <- if (is.data.frame(flds)) flds[[field]] else flds[[field]]
        if (is.null(val) || length(val) == 0L) NA_character_ else as.character(val[[1L]])
      }, character(1L))
    }

    null_chr <- function(x) if (is.null(x) || length(x) == 0L) NA_character_ else as.character(x[[1L]])
    webPublicationDate <- if (is.data.frame(results)) results$webPublicationDate else
      vapply(results, function(r) null_chr(r$webPublicationDate), character(1L))
    sectionName <- if (is.data.frame(results)) results$sectionName else
      vapply(results, function(r) null_chr(r$sectionName), character(1L))
    webUrl <- if (is.data.frame(results)) results$webUrl else
      vapply(results, function(r) null_chr(r$webUrl), character(1L))

    all_results[[page]] <- tibble::tibble(
      date      = as.Date(webPublicationDate),
      headline  = extract_field(results, "headline"),
      section   = sectionName,
      wordcount = {
        wc_raw <- extract_field(results, "wordcount")
        # NA values from missing fields produce coercion NAs intentionally;
        # non-numeric strings are unexpected so we track them.
        wc_int <- as.integer(wc_raw)
        n_coerce_fail <- sum(!is.na(wc_raw) & is.na(wc_int))
        if (n_coerce_fail > 0L) {
          cli::cli_warn("{n_coerce_fail} wordcount value(s) could not be parsed as integer.")
        }
        wc_int
      },
      url       = webUrl
    )

    if (page >= data$response$pages || page >= max_pages) break
    page <- page + 1L
    Sys.sleep(if (api_key == "test") 1 else 0.1)
  }

  dplyr::bind_rows(all_results)
}

#' Count Guardian articles by month for a keyword
#'
#' Fetches monthly article counts from the Guardian for a given keyword.
#' Useful for building news sentiment time series.
#'
#' @param query Search query
#' @param section Guardian section
#' @param from Start date
#' @param to End date
#' @param api_key API key
#' @param max_pages Maximum pages to fetch. The Guardian API rate-limits at
#'   1 req/sec for the "test" key, so `max_pages = 50` takes ~50 seconds.
#'   Default is 5 (≈ 5 seconds, 1000 articles max — sufficient for most queries).
#' @return Tibble with columns: year_month, keyword, n_articles
#' @family data-access
#' @export
hd_guardian_monthly <- function(query, section = "business",
                                from = "2020-01-01", to = NULL,
                                api_key = Sys.getenv("GUARDIAN_API_KEY", "test"),
                                max_pages = 5L) {
  articles <- hd_guardian(
    query = query, section = section,
    from = from, to = to, api_key = api_key,
    page_size = 200L, max_pages = max_pages
  )

  if (nrow(articles) == 0L) {
    return(tibble::tibble(
      year_month = character(), keyword = character(), n_articles = integer()
    ))
  }

  articles |>
    dplyr::mutate(year_month = format(date, "%Y-%m")) |>
    dplyr::count(year_month, name = "n_articles") |>
    dplyr::mutate(keyword = query) |>
    dplyr::select(year_month, keyword, n_articles) |>
    dplyr::arrange(year_month)
}
