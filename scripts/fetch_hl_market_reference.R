#!/usr/bin/env Rscript
# Hyperliquid market reference table: long name, category, definition, source (#1084)
#
# WHAT THIS IS
#   One row per perpetual market on every Hyperliquid exchange (the API's
#   `allPerpMetas`), joined to what the exchange itself publishes about the
#   market. Only trade.xyz (dex "xyz") publishes such a page today, its
#   specification index:
#     https://docs.trade.xyz/perpetuals/specifications-and-schedules/specification-index
#   read in its Markdown form (the same URL plus ".md"). Every other exchange
#   has NO parser yet, so its long_name / category / definition / source_url are
#   NA. Nothing is typed in by hand, not even as a constant: a market the source
#   does not describe stays NA. These are PERPETUAL FUTURES, not the securities
#   they reference.
#
# Why a new table and not data/dist/metadata.parquet: metadata.parquet is keyed
# by ticker and rewritten whole by scripts/fetch_metadata.py (yfinance); it holds
# no Hyperliquid rows and has no (exchange, market) key. A second writer would
# race that script, and the same long name would live in two places.
#
# Output (under --out-dir, default data/dist; gitignored, never committed):
#   perp_markets.parquet  upsert on (dex, coin)
#     dex, coin           exchange ("" = core) and market, as in every other table
#     long_name           the security / index name read from the description
#                         (see hl_spec_long_name); NA unless the page gives one
#     category           stock | etf | fx | commodity | index, DERIVED from the
#                         description wording by the rules in HL_SPEC_CATEGORY_RULES
#                         (the page has no category column); NA when no rule fits
#     definition          the page's full description text, HTML entities decoded
#     source_url          the page the row came from (that page has no per-row
#                         anchor)
#     source_fetched_at   when that page was fetched (UTC); NA = no source row
#     is_delisted         from the API (`isDelisted`, absent = FALSE)
#     max_leverage        from the API (`maxLeverage`); the page's own copy is
#                         not stored (one home per value)
#   A market that drops off the page keeps its last known source columns (and the
#   older source_fetched_at shows how stale they are): delisted markets leave the
#   page, and their names must not vanish with them.
# The raw Markdown is kept append-only under --raw-dir (default
# data/raw/hyperliquid/<UTC date>/spec_trade_xyz_specification-index.md); a parse
# can be reproduced from that copy with --spec-file=PATH (source_fetched_at is then
# the file's modification time).
#
# Usage: Rscript scripts/fetch_hl_market_reference.R [--out-dir=data/dist]
#          [--raw-dir=data/raw/hyperliquid] [--spec-file=PATH]
#
# Exit status: 0 ok | 2 usage | 3 INDETERMINATE (the API reply failed, or the page
#   could not be fetched or is malformed). On a page failure the API columns
#   (is_delisted, max_leverage) are still written and the source columns carried
#   forward; the exit status is still 3, never 0. A market on the API but not on
#   the page is NOT an error (NA, counted); a page row that is not on the API is
#   reported.

suppressPackageStartupMessages({
  library(dplyr)
  library(arrow)
  library(cli)
  library(httr2)
})

.ref_find_fetcher <- function() {
  from_file <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  cands <- character()
  if (length(from_file) > 0L) {
    cands <- c(cands, file.path(dirname(normalizePath(sub("^--file=", "", from_file[1]),
                                                       mustWork = FALSE)),
                                "fetch_hyperliquid.R"))
  }
  cands <- c(cands, file.path("scripts", "fetch_hyperliquid.R"))
  if (requireNamespace("here", quietly = TRUE)) {
    cands <- c(cands, here::here("scripts", "fetch_hyperliquid.R"))
  }
  hit <- cands[file.exists(cands)]
  if (length(hit) == 0L) {
    cli::cli_abort(c("x" = "Cannot locate {.file scripts/fetch_hyperliquid.R}",
                     "i" = "tried: {.file {cands}}"))
  }
  hit[1]
}
source(.ref_find_fetcher())

HL_SPEC_DEX <- "xyz"
HL_SPEC_PAGE_URL <- "https://docs.trade.xyz/perpetuals/specifications-and-schedules/specification-index"
HL_SPEC_MD_URL <- paste0(HL_SPEC_PAGE_URL, ".md")
HL_SPEC_RAW_STEM <- "spec_trade_xyz_specification-index"
HL_MARKETS_FILE <- "perp_markets.parquet"
HL_MARKETS_KEYS <- c("dex", "coin")
HL_SPEC_TIMEOUT_S <- 30
# Columns the page supplies; carried forward when a market leaves the page.
HL_SPEC_SOURCE_COLS <- c("long_name", "category", "definition", "source_url",
                         "source_fetched_at")

# Category rules: the FIRST matching rule wins; no match = NA. The page has no
# category column, so this is derived from the wording of the description. ETF
# before stock (an ETF description also says "1 share of"), stock before index.
HL_SPEC_CATEGORY_RULES <- c(
  etf       = "\\b(ETF|ETN)\\b|\\bThe (actively managed )?fund\\b",
  stock     = "^\\S+ references (1|one) .*\\b(share|shares|ADS|stock)\\b",
  fx        = "spot exchange rate",
  commodity = "references the USD (spot )?price of 1 ",
  index     = "\\b[Ii]ndex\\b"
)

hl_spec_malformed <- function(why) {
  cli::cli_abort(c("x" = "The specification page is not in the expected form",
                   "i" = why),
                 class = "hl_spec_malformed")
}

# ── Pure parsers (no network) ───────────────────────────────────────

# Decode numeric (&#38; &#x20;) and the common named HTML entities. &amp; is
# decoded LAST so "&amp;#38;" is not decoded twice.
hl_html_decode <- function(x) {
  for (i in seq_along(x)) {
    s <- x[i]
    if (is.na(s)) next
    ents <- unique(unlist(regmatches(s, gregexpr("&#[xX]?[0-9A-Fa-f]+;", s))))
    for (e in ents) {
      code <- if (grepl("^&#[xX]", e)) {
        strtoi(sub("^&#[xX]([0-9A-Fa-f]+);$", "\\1", e), 16L)
      } else {
        strtoi(sub("^&#([0-9]+);$", "\\1", e), 10L)
      }
      if (is.na(code) || code < 1L) hl_spec_malformed(sprintf("bad HTML entity %s", e))
      s <- gsub(e, intToUtf8(code), s, fixed = TRUE)
    }
    for (pair in list(c("&lt;", "<"), c("&gt;", ">"), c("&quot;", "\""),
                      c("&apos;", "'"), c("&nbsp;", " "), c("&amp;", "&"))) {
      s <- gsub(pair[1], pair[2], s, fixed = TRUE)
    }
    x[i] <- s
  }
  x
}

# HTML fragment -> plain text: <br> becomes a space, other tags are dropped,
# entities decoded, whitespace squeezed.
hl_html_text <- function(x) {
  x <- gsub("<br\\s*/?>", " ", x, perl = TRUE)
  x <- gsub("<[^>]*>", "", x, perl = TRUE)
  x <- hl_html_decode(x)
  trimws(gsub("[[:space:]]+", " ", x))
}

# Security-style descriptions only: "<NAME> references 1 share of the <LONG NAME>
# (<EXCHANGE>: <SYMBOL>), quoted in USD ...". The long name is the text after the
# quantity phrase up to and including the first "(EXCHANGE: SYMBOL)" group, the
# form the issue shows ("Direxion Daily Semiconductor Bull 3X Shares (NYSE Arca:
# SOXL)"). Anything that does not fit (indices, commodities, FX) is NA: the
# description is still stored whole in `definition`.
hl_spec_long_name <- function(description) {
  re <- paste0("^\\S+ references (?:1|one) ",
               "(?:(?:[A-Za-z]+ ){0,2}(?:[A-Z]-)?share of )?(?:the )?",
               "(.+?\\([^():]+: [^()]+\\))")
  m <- regexec(re, description, perl = TRUE)
  hit <- regmatches(description, m)
  vapply(hit, function(h) if (length(h) == 2L) h[2] else NA_character_, character(1))
}

hl_spec_category <- function(description) {
  vapply(description, function(d) {
    if (is.na(d)) return(NA_character_)
    for (nm in names(HL_SPEC_CATEGORY_RULES)) {
      if (grepl(HL_SPEC_CATEGORY_RULES[[nm]], d, perl = TRUE)) return(nm)
    }
    NA_character_
  }, character(1), USE.NAMES = FALSE)
}

# Specification-index Markdown (an HTML table with one <tr data-market-coin="...">
# per market) -> one row per market: dex, coin, long_name, category, definition,
# source_url. Aborts (class hl_spec_malformed) when the header lacks the
# Instrument / Description columns, when there is no market row at all (never a
# silent zero-row result), when a row has a different number of cells than the
# header, when a coin is not on `dex`, or when a coin appears twice. An empty
# description cell is NA, not an error.
hl_parse_spec_index <- function(md, dex = HL_SPEC_DEX, source_url = HL_SPEC_PAGE_URL) {
  if (!is.character(md) || length(md) != 1L || is.na(md) || !nzchar(trimws(md))) {
    hl_spec_malformed("the page text is empty")
  }
  th <- regmatches(md, gregexpr("(?s)<th[^>]*>(.*?)</th>", md, perl = TRUE))[[1]]
  header <- hl_html_text(th)
  need <- c("Instrument", "Description")
  if (!all(need %in% header)) {
    hl_spec_malformed(sprintf("table header lacks column(s): %s",
                              paste(setdiff(need, header), collapse = ", ")))
  }
  trs <- regmatches(md, gregexpr(
    "(?s)<tr\\s+data-market-coin=\"[^\"]+\"\\s*>.*?</tr>", md, perl = TRUE))[[1]]
  if (length(trs) == 0L) {
    hl_spec_malformed("no market rows (<tr data-market-coin=...>) found")
  }
  one <- function(tr) {
    coin <- sub("(?s)^<tr\\s+data-market-coin=\"([^\"]+)\".*$", "\\1", tr, perl = TRUE)
    tds <- regmatches(tr, gregexpr("(?s)<td[^>]*>(.*?)</td>", tr, perl = TRUE))[[1]]
    if (length(tds) != length(header)) {
      hl_spec_malformed(sprintf("row %s has %d cells, the header has %d",
                                coin, length(tds), length(header)))
    }
    if (!startsWith(coin, paste0(dex, ":"))) {
      hl_spec_malformed(sprintf("row %s is not a market of exchange %s", coin, dex))
    }
    txt <- hl_html_text(tds)
    def <- txt[header == "Description"]
    data.frame(dex = dex, coin = coin,
               definition = if (nzchar(def)) def else NA_character_,
               stringsAsFactors = FALSE)
  }
  out <- bind_rows(lapply(trs, one))
  if (anyDuplicated(out$coin) > 0L) {
    hl_spec_malformed(sprintf("market(s) listed twice: %s",
                              paste(unique(out$coin[duplicated(out$coin)]), collapse = ", ")))
  }
  out$long_name <- hl_spec_long_name(out$definition)
  out$category <- hl_spec_category(out$definition)
  out$source_url <- source_url
  out[c("dex", "coin", "long_name", "category", "definition", "source_url")]
}

# allPerpMetas -> dex, coin, is_delisted, max_leverage for every perp market of
# every exchange. `isDelisted` is absent on live markets (= FALSE). Wallet,
# deployer and fee fields are not read.
hl_parse_perp_ref_universe <- function(apm) {
  if (!is.list(apm) || length(apm) == 0L) {
    cli::cli_abort("allPerpMetas payload is empty or not a list", class = "hl_empty_markets")
  }
  rows <- lapply(apm, function(m) {
    u <- m$universe
    if (is.null(u) || length(u) == 0L) {
      cli::cli_abort("allPerpMetas holds an exchange with an empty universe",
                     class = "hl_empty_markets")
    }
    hl_require_fields(u, c("name", "maxLeverage"), "universe")
    data.frame(
      coin = vapply(u, function(r) as.character(r$name), character(1)),
      is_delisted = vapply(u, function(r) isTRUE(r$isDelisted), logical(1)),
      max_leverage = hl_num(lapply(u, `[[`, "maxLeverage"), "maxLeverage"),
      stringsAsFactors = FALSE
    )
  })
  df <- bind_rows(rows)
  cls <- hl_classify_coin(df$coin)
  if (!all(cls %in% c("main_perp", "builder_perp"))) {
    cli::cli_abort("allPerpMetas holds a non-perp market form", class = "hl_unknown_market_class")
  }
  if (anyDuplicated(df$coin) > 0L) {
    cli::cli_abort("allPerpMetas lists a market twice", class = "hl_duplicate_keys")
  }
  df$dex <- ifelse(cls == "builder_perp", sub(":.*$", "", df$coin), "")
  df[c("dex", "coin", "is_delisted", "max_leverage")]
}

# API universe LEFT JOIN page rows on (dex, coin): a market the page does not
# describe gets NA source columns; a page row that is not on the API is returned
# in `spec_not_on_api` (reported, not dropped silently). `spec = NULL` means no
# page was read: every source column is NA.
hl_join_market_reference <- function(api, spec = NULL, source_fetched_at = NA) {
  src_at <- as.POSIXct(source_fetched_at, tz = "UTC")
  if (is.null(spec)) {
    spec <- data.frame(dex = character(), coin = character(), long_name = character(),
                       category = character(), definition = character(),
                       source_url = character(), stringsAsFactors = FALSE)
  }
  tbl <- api |>
    left_join(spec, by = c("dex", "coin")) |>
    mutate(source_fetched_at = if_else(is.na(definition) & is.na(long_name) &
                                         is.na(source_url),
                                       as.POSIXct(NA, tz = "UTC"), src_at)) |>
    select(dex, coin, long_name, category, definition, source_url,
           source_fetched_at, is_delisted, max_leverage)
  list(table = as.data.frame(tbl),
       spec_not_on_api = setdiff(spec$coin, api$coin))
}

# A market with no source row this run keeps the source columns of its previous
# row (when that had a source), so a market that leaves the page does not lose
# its name. `old` = the previous table or NULL.
hl_carry_forward_source <- function(new, old) {
  if (is.null(old) || nrow(old) == 0L) return(new)
  key <- function(d) paste(d$dex, d$coin, sep = "\r")
  i <- which(is.na(new$source_fetched_at))
  j <- match(key(new)[i], key(old))
  has <- !is.na(j) & !is.na(old$source_fetched_at[j])
  for (col in HL_SPEC_SOURCE_COLS) {
    new[[col]][i[has]] <- old[[col]][j[has]]
  }
  new
}

# ── Network ─────────────────────────────────────────────────────────

# Fetch the Markdown page; keep the exact bytes under raw_dir (append-only).
# Returns list(text, fetched_at, path). HTTP errors and empty bodies abort as
# hl_source_unavailable.
hl_fetch_spec_page <- function(url = HL_SPEC_MD_URL, raw_dir = "data/raw/hyperliquid",
                               timeout = HL_SPEC_TIMEOUT_S) {
  resp <- tryCatch(
    httr2::request(url) |>
      httr2::req_timeout(timeout) |>
      httr2::req_retry(max_tries = 3,
                       is_transient = function(r) httr2::resp_status(r) %in%
                         c(500L, 502L, 503L, 504L),
                       backoff = ~ 2^.x) |>
      httr2::req_error(is_error = function(r) FALSE) |>
      httr2::req_perform(),
    error = function(e) hl_unavailable(conditionMessage(e))
  )
  status <- httr2::resp_status(resp)
  if (status >= 400L) hl_unavailable(sprintf("HTTP %d from %s", status, url))
  text <- httr2::resp_body_string(resp)
  fetched_at <- Sys.time()
  if (!nzchar(trimws(text))) hl_unavailable("the page body is empty")
  path <- hl_save_raw(NULL, text, raw_dir, now = fetched_at,
                      stem = HL_SPEC_RAW_STEM, ext = "md")
  list(text = text, fetched_at = fetched_at, path = path)
}

# A saved copy instead of the network (reproducing a parse). The fetch time is
# the file's modification time.
hl_read_spec_file <- function(path) {
  if (!file.exists(path)) {
    cli::cli_abort(c("x" = "Spec file not found", "i" = "{.file {path}}"),
                   class = "hl_bad_arg")
  }
  list(text = paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n"),
       fetched_at = file.mtime(path), path = path)
}

# ── Orchestration ───────────────────────────────────────────────────
# `post_fn(body)` and `spec_fn()` are injectable. Returns list(status, reason,
# n_markets, by_dex, n_named, n_described, spec_not_on_api).
hl_market_reference_run <- function(post_fn, spec_fn, out_dir = "data/dist") {
  indeterminate <- function(why, ...) {
    cli::cli_alert_danger("INDETERMINATE: {why}")
    list(status = 3L, reason = why, ...)
  }
  api <- tryCatch(hl_parse_perp_ref_universe(post_fn(list(type = "allPerpMetas"))),
                  error = function(e) e)
  if (inherits(api, "error")) {
    return(indeterminate(paste("allPerpMetas:", conditionMessage(api)), n_markets = 0L))
  }
  spec <- tryCatch({
    s <- spec_fn()
    list(rows = hl_parse_spec_index(s$text), fetched_at = s$fetched_at)
  }, error = function(e) e)
  spec_ok <- !inherits(spec, "error")
  joined <- hl_join_market_reference(api, if (spec_ok) spec$rows else NULL,
                                     if (spec_ok) spec$fetched_at else NA)
  path <- file.path(out_dir, HL_MARKETS_FILE)
  old <- if (file.exists(path)) arrow::read_parquet(path) else NULL
  tbl <- hl_carry_forward_source(joined$table, old)
  hl_upsert(tbl, path, HL_MARKETS_KEYS)

  by_dex <- tbl |>
    group_by(dex) |>
    summarise(n_markets = dplyr::n(), n_described = sum(!is.na(definition)),
              n_long_name = sum(!is.na(long_name)),
              n_delisted = sum(is_delisted), .groups = "drop") |>
    as.data.frame()
  if (length(joined$spec_not_on_api) > 0L) {
    cli::cli_alert_warning("{length(joined$spec_not_on_api)} page market{?s} not on the API: {.val {joined$spec_not_on_api}}")
  }
  res <- list(status = 0L, reason = "", n_markets = nrow(tbl), by_dex = by_dex,
              n_named = sum(!is.na(tbl$long_name)),
              n_described = sum(!is.na(tbl$definition)),
              spec_not_on_api = joined$spec_not_on_api)
  if (!spec_ok) {
    return(c(indeterminate(paste("specification page:", conditionMessage(spec))),
             res[setdiff(names(res), c("status", "reason"))]))
  }
  cli::cli_alert_success("{nrow(tbl)} market{?s}, {res$n_described} with a definition, {res$n_named} with a long name")
  res
}

.fetch_hl_market_reference_main <- function(args = commandArgs(trailingOnly = TRUE),
                                            post_fn = NULL, spec_fn = NULL) {
  known <- c("out-dir", "raw-dir", "spec-file")
  bad <- args[!grepl(paste0("^--(", paste(known, collapse = "|"), ")=.+$"), args)]
  if (length(bad) > 0L) {
    message("usage: fetch_hl_market_reference.R [--out-dir=D] [--raw-dir=D] [--spec-file=PATH]\n",
            "unknown or malformed argument(s): ", paste(bad, collapse = " "))
    return(2L)
  }
  opt <- function(name, default) {
    hit <- grep(paste0("^--", name, "="), args, value = TRUE)
    if (length(hit) == 0L) default else sub(paste0("^--", name, "="), "", hit[1])
  }
  raw_dir <- opt("raw-dir", "data/raw/hyperliquid")
  if (is.null(post_fn)) post_fn <- hl_make_post(raw_dir)
  if (is.null(spec_fn)) {
    sf <- opt("spec-file", NA_character_)
    spec_fn <- if (is.na(sf)) function() hl_fetch_spec_page(raw_dir = raw_dir) else
      function() hl_read_spec_file(sf)
  }
  res <- tryCatch(
    hl_market_reference_run(post_fn, spec_fn, out_dir = opt("out-dir", "data/dist")),
    error = function(e) {
      message("INDETERMINATE: ", conditionMessage(e))
      list(status = 3L)
    })
  if (!is.null(res$by_dex)) {
    message(paste(utils::capture.output(print(res$by_dex, row.names = FALSE)), collapse = "\n"))
  }
  res$status
}

if (sys.nframe() == 0L) {
  quit(save = "no", status = .fetch_hl_market_reference_main())
}
