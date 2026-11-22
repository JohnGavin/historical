testthat::local_edition(3)
source(here::here("scripts", "fetch_hl_market_reference.R"))

# scripts/fetch_hl_market_reference.R (#1084). NO network: the post function and
# the page fetch are injected, httr2 is mocked. The page fixture is a trimmed copy
# of the real trade.xyz specification index (Markdown; an HTML table): ten of its
# 113 rows, picked to cover an index with an HTML entity (xyz:SP500), commodities
# whose display name differs from the coin (xyz:CL shows as WTIOIL), an FX pair, a
# stock, an ETF, an ADS, a share priced in another currency and a name containing
# "&#38;" (Hims &#38; Hers).

.fxdir <- here::here("tests", "testthat", "fixtures", "hyperliquid")
.spec_path <- file.path(.fxdir, "trade_xyz_specification_index.md")
.spec_md <- paste(readLines(.spec_path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
.apm <- jsonlite::read_json(file.path(.fxdir, "allperpmetas.json"), simplifyVector = FALSE)
.spec <- hl_parse_spec_index(.spec_md)
.row <- function(coin) .spec[.spec$coin == coin, ]
.t_spec <- as.POSIXct("2026-11-22 10:00:00", tz = "UTC")
.apm_post <- function(body) {
  stopifnot(identical(body$type, "allPerpMetas"))
  .apm
}
.spec_fn <- function() list(text = .spec_md, fetched_at = .t_spec)

test_that("the fixture page parses to one row per market with the documented columns", {
  expect_equal(names(.spec), c("dex", "coin", "long_name", "category", "definition",
                               "source_url"))
  expect_equal(.spec$coin, paste0("xyz:", c("SP500", "CL", "GOLD", "JPY", "TSLA", "SOXL",
                                            "TSM", "SKHX", "HIMS", "NIFTY")))
  expect_true(all(.spec$dex == "xyz"))
  expect_equal(unique(.spec$source_url), HL_SPEC_PAGE_URL)
  expect_false(anyNA(.spec$definition))
})

test_that("long names come from the description, exactly as the page words them", {
  expect_equal(.row("xyz:SOXL")$long_name,
               "Direxion Daily Semiconductor Bull 3X Shares (NYSE Arca: SOXL)")
  expect_equal(.row("xyz:TSLA")$long_name, "Tesla, Inc. common stock (Nasdaq: TSLA)")
  expect_equal(.row("xyz:TSM")$long_name,
               "Taiwan Semiconductor Manufacturing Company Limited ADS (NYSE: TSM)")
  expect_equal(.row("xyz:SKHX")$long_name, "SK hynix Inc. common share (KRX: 000660)")
  # HTML entity decoded inside a name
  expect_equal(.row("xyz:HIMS")$long_name,
               "Hims & Hers Health, Inc. Class A common stock (NYSE: HIMS)")
  # no security name in the text: NA, never invented (the definition is still kept)
  for (cn in c("xyz:SP500", "xyz:CL", "xyz:GOLD", "xyz:JPY", "xyz:NIFTY")) {
    expect_true(is.na(.row(cn)$long_name), info = cn)
    expect_false(is.na(.row(cn)$definition), info = cn)
  }
})

test_that("category is derived from the description wording; NA when no rule fits", {
  cat <- stats::setNames(.spec$category, .spec$coin)
  expect_equal(cat[["xyz:SOXL"]], "etf")
  expect_equal(cat[["xyz:TSLA"]], "stock")
  expect_equal(cat[["xyz:TSM"]], "stock")
  expect_equal(cat[["xyz:SKHX"]], "stock")
  expect_equal(cat[["xyz:HIMS"]], "stock")
  expect_equal(cat[["xyz:JPY"]], "fx")
  expect_equal(cat[["xyz:CL"]], "commodity")
  expect_equal(cat[["xyz:GOLD"]], "commodity")
  expect_equal(cat[["xyz:SP500"]], "index")
  expect_equal(cat[["xyz:NIFTY"]], "index")
  expect_true(is.na(hl_spec_category("ZZZ is something no rule describes")))
  expect_true(is.na(hl_spec_category(NA_character_)))
  expect_true(is.na(hl_spec_long_name(NA_character_)))
})

test_that("definitions are plain text: entities decoded, tags and extra space gone", {
  d <- .row("xyz:SP500")$definition
  expect_match(d, "S&P 500 Index", fixed = TRUE)
  expect_match(d, "trade[XYZ]", fixed = TRUE)          # &#91; XYZ &#93;
  expect_false(grepl("&#|<|>", d))
  expect_false(grepl("  ", d, fixed = TRUE))
  expect_equal(hl_html_decode("a &#38; b &#x20;c &amp;#38; &lt;"), "a & b  c &#38; <")
  expect_equal(hl_html_text("x<br />y  <b>z</b>\n w"), "x y z w")
  expect_error(hl_html_decode("bad &#0;"), class = "hl_spec_malformed")
})

test_that("a malformed page ERRORS; it never returns zero rows (falsifiable)", {
  expect_error(hl_parse_spec_index(""), class = "hl_spec_malformed")
  expect_error(hl_parse_spec_index(NA_character_), class = "hl_spec_malformed")
  expect_error(hl_parse_spec_index("<html><body>Not found</body></html>"),
               class = "hl_spec_malformed")
  # a header without a Description column
  no_desc <- sub("<th>Description</th>", "<th>Notes</th>", .spec_md, fixed = TRUE)
  expect_error(hl_parse_spec_index(no_desc), "Description", class = "hl_spec_malformed")
  # a valid header but no market rows (the page layout changed)
  no_rows <- gsub("(?s)<tr data-market-coin=.*?</tr>", "", .spec_md, perl = TRUE)
  expect_error(hl_parse_spec_index(no_rows), "no market rows", class = "hl_spec_malformed")
  # a row with a cell missing
  one_td <- sub("(?s)(data-market-coin=\"xyz:TSLA\".*?)<td>0\\.5</td>", "\\1", .spec_md,
                perl = TRUE)
  expect_error(hl_parse_spec_index(one_td), "cells", class = "hl_spec_malformed")
  # a coin of another exchange, and a coin listed twice
  expect_error(hl_parse_spec_index(.spec_md, dex = "flx"), "not a market of exchange",
               class = "hl_spec_malformed")
  dup <- sub("</tbody>", paste0(regmatches(.spec_md, regexpr(
    "(?s)    <tr data-market-coin=\"xyz:TSLA\">.*?</tr>", .spec_md, perl = TRUE)),
    "\n</tbody>"), .spec_md, fixed = TRUE)
  expect_error(hl_parse_spec_index(dup), "twice", class = "hl_spec_malformed")
  # Green: the untouched page is fine
  expect_equal(nrow(hl_parse_spec_index(.spec_md)), 10L)
})

test_that("allPerpMetas -> dex, coin, is_delisted, max_leverage; no wallet fields", {
  u <- hl_parse_perp_ref_universe(.apm)
  expect_equal(names(u), c("dex", "coin", "is_delisted", "max_leverage"))
  expect_equal(u$dex, c("", "", "", "xyz", "xyz", "flx"))
  expect_equal(u$is_delisted, c(FALSE, TRUE, FALSE, FALSE, FALSE, TRUE))
  expect_equal(u$max_leverage[u$coin == "BTC"], 40)
  expect_type(u$max_leverage, "double")
  expect_error(hl_parse_perp_ref_universe(list()), class = "hl_empty_markets")
  expect_error(hl_parse_perp_ref_universe(list(list(universe = list()))),
               class = "hl_empty_markets")
  bad <- .apm; bad[[1]]$universe[[1]]$maxLeverage <- "lots"
  expect_error(hl_parse_perp_ref_universe(bad), "Non-numeric")
})

test_that("the join keys on (dex, coin); unmatched markets are NA, page extras reported", {
  api <- hl_parse_perp_ref_universe(.apm)
  j <- hl_join_market_reference(api, .spec, .t_spec)
  t <- j$table
  expect_equal(names(t), c("dex", "coin", "long_name", "category", "definition",
                           "source_url", "source_fetched_at", "is_delisted",
                           "max_leverage"))
  expect_equal(nrow(t), nrow(api))
  tsla <- t[t$coin == "xyz:TSLA", ]
  expect_equal(tsla$long_name, "Tesla, Inc. common stock (Nasdaq: TSLA)")
  expect_equal(tsla$source_fetched_at, .t_spec)
  # the SAME symbol on another exchange does not inherit trade.xyz's name
  flx <- t[t$dex == "flx" & t$coin == "flx:TSLA", ]
  expect_true(all(is.na(flx[c("long_name", "category", "definition", "source_url",
                              "source_fetched_at")])))
  expect_true(flx$is_delisted)
  # on the API but not on the page: NA
  expect_true(is.na(t$definition[t$coin == "xyz:XYZ100"]))
  expect_true(is.na(t$definition[t$coin == "BTC"]))
  # on the page but not on the API: reported, not dropped silently
  expect_equal(sort(j$spec_not_on_api), sort(setdiff(.spec$coin, c("xyz:TSLA", "xyz:XYZ100"))))
  # no page read at all: every source column NA
  none <- hl_join_market_reference(api, NULL, NA)$table
  expect_true(all(is.na(none$definition)) && all(is.na(none$source_fetched_at)))
})

test_that("a market that leaves the page keeps its last known source columns", {
  api <- hl_parse_perp_ref_universe(.apm)
  old <- hl_join_market_reference(api, .spec, .t_spec)$table
  gone <- hl_join_market_reference(api, .spec[.spec$coin != "xyz:TSLA", ],
                                   .t_spec + 86400)$table
  expect_true(is.na(gone$long_name[gone$coin == "xyz:TSLA"]))      # before carry-forward
  kept <- hl_carry_forward_source(gone, old)
  expect_equal(kept$long_name[kept$coin == "xyz:TSLA"], "Tesla, Inc. common stock (Nasdaq: TSLA)")
  expect_equal(kept$source_fetched_at[kept$coin == "xyz:TSLA"], .t_spec)   # shows the age
  # a market with no earlier source stays NA
  expect_true(is.na(kept$long_name[kept$coin == "BTC"]))
  expect_equal(hl_carry_forward_source(gone, NULL), gone)
})

test_that("a run writes perp_markets.parquet, upserted on (dex, coin), status 0", {
  out <- withr::local_tempdir()
  r <- suppressMessages(hl_market_reference_run(.apm_post, .spec_fn, out))
  expect_equal(r$status, 0L)
  x <- arrow::read_parquet(file.path(out, "perp_markets.parquet"))
  expect_equal(nrow(x), 6L)
  expect_equal(r$n_named, 1L)                       # only xyz:TSLA is on both sides
  expect_equal(r$n_described, 1L)
  expect_equal(sum(x$is_delisted), 2L)
  expect_setequal(r$by_dex$dex, c("", "xyz", "flx"))
  suppressMessages(hl_market_reference_run(.apm_post, .spec_fn, out))
  expect_equal(nrow(arrow::read_parquet(file.path(out, "perp_markets.parquet"))), 6L)
  # the long name lives in ONE place: no other table of the run holds it
  expect_equal(list.files(out), "perp_markets.parquet")
})

test_that("a failed or malformed page is 3 (never 0) but the API columns are still written", {
  out <- withr::local_tempdir()
  down <- function() hl_unavailable("HTTP 503")
  r <- suppressMessages(hl_market_reference_run(.apm_post, down, out))
  expect_equal(r$status, 3L)
  expect_match(r$reason, "specification page", fixed = TRUE)
  x <- arrow::read_parquet(file.path(out, "perp_markets.parquet"))
  expect_equal(sum(x$is_delisted), 2L)
  expect_true(all(is.na(x$definition)))
  # malformed page: same
  junk <- function() list(text = "<html>moved</html>", fetched_at = .t_spec)
  expect_equal(suppressMessages(hl_market_reference_run(.apm_post, junk, withr::local_tempdir()))$status, 3L)
  # an earlier good run is not erased by a later bad page
  out2 <- withr::local_tempdir()
  suppressMessages(hl_market_reference_run(.apm_post, .spec_fn, out2))
  suppressMessages(hl_market_reference_run(.apm_post, down, out2))
  x2 <- arrow::read_parquet(file.path(out2, "perp_markets.parquet"))
  expect_equal(x2$long_name[x2$coin == "xyz:TSLA"], "Tesla, Inc. common stock (Nasdaq: TSLA)")
  # API down: 3 and nothing written
  out3 <- withr::local_tempdir()
  nope <- function(body) hl_unavailable("connection refused")
  expect_equal(suppressMessages(hl_market_reference_run(nope, .spec_fn, out3))$status, 3L)
  expect_false(file.exists(file.path(out3, "perp_markets.parquet")))
})

test_that("the real page fetch keeps the exact bytes append-only and fails loudly", {
  raw <- withr::local_tempdir()
  ok <- function(req) httr2::response(status_code = 200L, body = charToRaw(.spec_md),
                                      headers = list(`Content-Type` = "text/markdown"))
  got <- httr2::with_mocked_responses(ok, hl_fetch_spec_page(raw_dir = raw))
  expect_equal(got$text, .spec_md)
  expect_true(file.exists(got$path))
  expect_match(basename(got$path), "^spec_trade_xyz_specification-index\\.md$")
  expect_identical(readBin(got$path, "raw", file.size(got$path)), charToRaw(.spec_md))
  got2 <- httr2::with_mocked_responses(ok, hl_fetch_spec_page(raw_dir = raw))
  expect_false(identical(got$path, got2$path))       # never overwritten
  expect_length(list.files(raw, recursive = TRUE), 2L)
  # Red: HTTP errors and an empty body are errors, not a blank page
  notfound <- function(req) httr2::response(status_code = 404L)
  expect_error(httr2::with_mocked_responses(notfound, hl_fetch_spec_page(raw_dir = raw)),
               class = "hl_source_unavailable")
  empty <- function(req) httr2::response(status_code = 200L, body = charToRaw("  \n"))
  expect_error(httr2::with_mocked_responses(empty, hl_fetch_spec_page(raw_dir = raw)),
               class = "hl_source_unavailable")
})

test_that("a saved copy reproduces the parse; a missing file is an error", {
  s <- hl_read_spec_file(.spec_path)
  expect_equal(nrow(hl_parse_spec_index(s$text)), 10L)
  expect_s3_class(s$fetched_at, "POSIXct")
  expect_error(hl_read_spec_file(file.path(tempdir(), "no-such-spec.md")), class = "hl_bad_arg")
})

test_that("main: usage errors are 2; a saved page and an injected API give 0", {
  out <- withr::local_tempdir()
  expect_equal(suppressMessages(.fetch_hl_market_reference_main("--bogus=1")), 2L)
  expect_equal(suppressMessages(.fetch_hl_market_reference_main("--out-dir=")), 2L)
  args <- c(paste0("--out-dir=", out), paste0("--raw-dir=", file.path(out, "raw")),
            paste0("--spec-file=", .spec_path))
  expect_equal(suppressMessages(.fetch_hl_market_reference_main(args, post_fn = .apm_post)), 0L)
  expect_true(file.exists(file.path(out, "perp_markets.parquet")))
  bad <- c(args[1:2], paste0("--spec-file=", file.path(out, "missing.md")))
  expect_equal(suppressMessages(.fetch_hl_market_reference_main(bad, post_fn = .apm_post)), 3L)
})
