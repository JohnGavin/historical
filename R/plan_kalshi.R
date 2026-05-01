# Plan: Kalshi FOMC Implied Rate Probabilities (#47)
#
# Fetches live Kalshi prediction-market prices for Fed rate decisions.
# Kalshi KXFED series: one market per rate threshold per FOMC meeting.
# last_price (dollars, 0.01-0.99) = implied probability.
#
# Produces:
#   kalshi_params          — configuration list
#   kalshi_markets         — tidy tibble of current market prices
#   kalshi_implied_rates   — probability-weighted implied Fed Funds rate
#   kalshi_summary         — summary statistics
#   kalshi_caption         — dynamic prose caption

plan_kalshi <- function() {
  list(

    # ── Parameters ────────────────────────────────────────────────
    targets::tar_target(kalshi_params, {
      list(
        series_ticker = "KXFED",
        api_base      = "https://api.elections.kalshi.com/trade-api/v2",
        parquet_path  = here::here("data/raw/kalshi_fomc.parquet"),
        page_limit    = 200L
      )
    }),

    # ── Fetch current FOMC market data ────────────────────────────
    targets::tar_target(kalshi_markets, {
      library(dplyr)

      # Helper: safe scalar extraction
      safe_num <- function(x) {
        if (is.null(x) || length(x) == 0) return(NA_real_)
        v <- suppressWarnings(as.numeric(x[[1]]))
        if (is.na(v)) NA_real_ else v
      }
      safe_int <- function(x) {
        if (is.null(x) || length(x) == 0) return(NA_integer_)
        v <- suppressWarnings(as.integer(x[[1]]))
        if (is.na(v)) NA_integer_ else v
      }
      safe_chr <- function(x) {
        if (is.null(x) || length(x) == 0) NA_character_ else as.character(x[[1]])
      }
      safe_time <- function(x) {
        if (is.null(x) || length(x) == 0 || is.na(x)) return(as.POSIXct(NA))
        tryCatch(as.POSIXct(x, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
                 error = function(e) as.POSIXct(NA))
      }

      # Paginated fetch
      all_markets <- list()
      cursor      <- NULL

      repeat {
        url <- sprintf("%s/markets?series_ticker=%s&limit=%d",
                       kalshi_params$api_base,
                       kalshi_params$series_ticker,
                       kalshi_params$page_limit)
        if (!is.null(cursor) && nchar(cursor) > 0) {
          url <- paste0(url, "&cursor=",
                        utils::URLencode(cursor, reserved = TRUE))
        }

        resp <- tryCatch(
          jsonlite::fromJSON(url, simplifyDataFrame = FALSE),
          error = function(e) {
            cli::cli_warn("Kalshi API request failed: {e$message}")
            NULL
          }
        )
        if (is.null(resp)) break

        markets <- resp$markets
        if (is.null(markets) || length(markets) == 0) break
        all_markets <- c(all_markets, markets)

        cursor_next <- resp$cursor
        if (is.null(cursor_next) || length(cursor_next) == 0 ||
            nchar(cursor_next) == 0) break
        if (!is.null(cursor) && identical(cursor_next, cursor)) break
        cursor <- cursor_next
        Sys.sleep(1)
      }

      if (length(all_markets) == 0) {
        cli::cli_warn("No Kalshi KXFED markets returned from API")
        return(tibble(
          event_ticker  = character(),
          market_ticker = character(),
          outcome_label = character(),
          probability   = numeric(),
          yes_bid       = numeric(),
          yes_ask       = numeric(),
          volume        = integer(),
          open_interest = integer(),
          close_time    = as.POSIXct(character()),
          status        = character(),
          fetched_at    = as.POSIXct(character())
        ))
      }

      # Parse each market
      rows <- lapply(all_markets, function(m) {
        # last_price_dollars is $0-$1 (probability); fall back to last_price
        last_price_raw <- m$last_price_dollars %||% m$last_price
        tibble(
          event_ticker  = safe_chr(m$event_ticker),
          market_ticker = safe_chr(m$ticker),
          outcome_label = safe_chr(m$subtitle %||% m$title),
          probability   = safe_num(last_price_raw),
          yes_bid       = safe_num(m$yes_bid),
          yes_ask       = safe_num(m$yes_ask),
          volume        = safe_int(m$volume),
          open_interest = safe_int(m$open_interest),
          close_time    = safe_time(m$close_time),
          status        = safe_chr(m$status)
        )
      })

      bind_rows(rows) |>
        mutate(fetched_at = Sys.time()) |>
        arrange(event_ticker, outcome_label)
    },
    cue = targets::tar_cue(mode = "always")),  # always refresh: live data

    # ── Implied Fed Funds rate per FOMC meeting ───────────────────
    targets::tar_target(kalshi_implied_rates, {
      library(dplyr)

      if (nrow(kalshi_markets) == 0) {
        cli::cli_warn("kalshi_markets is empty — cannot compute implied rates")
        return(tibble(
          event_ticker  = character(),
          meeting_date  = as.Date(character()),
          implied_rate  = numeric(),
          prob_cut      = numeric(),
          prob_hold     = numeric(),
          prob_hike     = numeric(),
          n_outcomes    = integer()
        ))
      }

      # Extract numeric rate from outcome_label (e.g. "4.25% or above" -> 4.25)
      # Typical formats: "X.XX% or above", "X.XX% to Y.YY%", "X.XX% or below"
      parse_rate_from_label <- function(label) {
        if (is.na(label)) return(NA_real_)
        # Extract first decimal number from label
        m <- regmatches(label, regexpr("[0-9]+\\.[0-9]+", label))
        if (length(m) == 0 || nchar(m) == 0) return(NA_real_)
        as.numeric(m)
      }

      # Extract meeting date from event_ticker (e.g., "KXFED-25JUN25" -> "2025-06-25")
      parse_meeting_date <- function(ticker) {
        if (is.na(ticker)) return(as.Date(NA))
        # Kalshi FOMC tickers: KXFED-YYMM (e.g., KXFED-26JUN, KXFED-27JAN)
        # or KXFED-YYMMMDD (e.g., KXFED-26JUN25)
        # Extract the suffix after "KXFED-"
        suffix <- sub("^KXFED-", "", ticker)
        if (nchar(suffix) == 0) return(as.Date(NA))

        # Format: YYMM (5 chars) e.g., "26JUN" → 2026-06-01
        m1 <- regmatches(suffix, regexpr("^[0-9]{2}[A-Z]{3}$", suffix))
        if (length(m1) > 0 && nchar(m1) > 0) {
          d <- tryCatch(as.Date(paste0("01", m1), format = "%d%y%b"),
                        error = function(e) as.Date(NA))
          if (!is.na(d)) return(d)
        }

        # Format: YYMMDD (7 chars) e.g., "26JUN25" → 2026-06-25
        m2 <- regmatches(suffix, regexpr("^[0-9]{2}[A-Z]{3}[0-9]{2}$", suffix))
        if (length(m2) > 0 && nchar(m2) > 0) {
          d <- tryCatch(as.Date(m2, format = "%y%b%d"),
                        error = function(e) as.Date(NA))
          if (!is.na(d)) return(d)
        }

        as.Date(NA)
      }

      # Current effective federal funds rate (midpoint of target range)
      # Used to classify cut/hold/hike — approximated from KXFED range context
      markets_with_rate <- kalshi_markets |>
        filter(!is.na(probability), probability > 0) |>
        mutate(
          rate_pct     = vapply(outcome_label, parse_rate_from_label, numeric(1)),
          meeting_date = as.Date(vapply(event_ticker, function(x) {
            as.numeric(parse_meeting_date(x))
          }, numeric(1)), origin = "1970-01-01")
        )

      if (all(is.na(markets_with_rate$rate_pct))) {
        cli::cli_warn("Could not parse rate values from outcome_labels — returning raw probabilities only")
        return(
          markets_with_rate |>
            group_by(event_ticker, meeting_date) |>
            summarise(
              implied_rate  = NA_real_,
              prob_cut      = NA_real_,
              prob_hold     = NA_real_,
              prob_hike     = NA_real_,
              n_outcomes    = dplyr::n(),
              .groups = "drop"
            )
        )
      }

      # Probability-weighted implied rate per FOMC event
      # Normalise probabilities within each event so they sum to 1
      implied <- markets_with_rate |>
        filter(!is.na(rate_pct)) |>
        group_by(event_ticker, meeting_date) |>
        mutate(
          prob_total    = sum(probability, na.rm = TRUE),
          prob_norm     = if_else(prob_total > 0, probability / prob_total, 0)
        ) |>
        summarise(
          implied_rate  = sum(rate_pct * prob_norm, na.rm = TRUE),
          n_outcomes    = dplyr::n(),
          .groups       = "drop"
        )

      # Current rate: use the rate with highest probability across all events
      # (rough proxy; best estimate from "hold" markets)
      current_rate_est <- markets_with_rate |>
        slice_max(probability, n = 1, with_ties = FALSE) |>
        pull(rate_pct)
      if (length(current_rate_est) == 0 || is.na(current_rate_est)) {
        current_rate_est <- 4.25  # fallback: approximate mid-2025 FFR
      }

      # Cut/hold/hike probabilities
      # "cut"  = implied_rate < current_rate_est - 0.10
      # "hike" = implied_rate > current_rate_est + 0.10
      # "hold" = otherwise
      CUT_THRESHOLD  <- 0.10  # >10bp below current = cut
      HIKE_THRESHOLD <- 0.10  # >10bp above current = hike

      implied |>
        left_join(
          markets_with_rate |>
            filter(!is.na(rate_pct)) |>
            group_by(event_ticker, meeting_date) |>
            mutate(
              prob_total = sum(probability, na.rm = TRUE),
              prob_norm  = if_else(prob_total > 0, probability / prob_total, 0),
              is_cut     = rate_pct < current_rate_est - CUT_THRESHOLD,
              is_hike    = rate_pct > current_rate_est + HIKE_THRESHOLD,
              is_hold    = !is_cut & !is_hike
            ) |>
            summarise(
              prob_cut  = sum(prob_norm[is_cut],  na.rm = TRUE),
              prob_hold = sum(prob_norm[is_hold], na.rm = TRUE),
              prob_hike = sum(prob_norm[is_hike], na.rm = TRUE),
              .groups   = "drop"
            ),
          by = c("event_ticker", "meeting_date")
        ) |>
        mutate(
          across(c(implied_rate, prob_cut, prob_hold, prob_hike), round, digits = 4)
        ) |>
        arrange(meeting_date)
    }),

    # ── Summary statistics ─────────────────────────────────────────
    targets::tar_target(kalshi_summary, {
      library(dplyr)

      if (nrow(kalshi_markets) == 0 || nrow(kalshi_implied_rates) == 0) {
        return(list(
          n_markets        = 0L,
          n_meetings       = 0L,
          next_meeting     = as.Date(NA),
          next_implied_rate = NA_real_,
          next_prob_cut    = NA_real_,
          next_prob_hold   = NA_real_,
          next_prob_hike   = NA_real_,
          fetched_at       = Sys.time()
        ))
      }

      next_event <- kalshi_implied_rates |>
        filter(!is.na(meeting_date), meeting_date >= Sys.Date()) |>
        slice_min(meeting_date, n = 1, with_ties = FALSE)

      list(
        n_markets         = nrow(kalshi_markets),
        n_meetings        = n_distinct(kalshi_implied_rates$event_ticker),
        next_meeting      = if (nrow(next_event) > 0) next_event$meeting_date    else as.Date(NA),
        next_implied_rate = if (nrow(next_event) > 0) next_event$implied_rate    else NA_real_,
        next_prob_cut     = if (nrow(next_event) > 0) next_event$prob_cut        else NA_real_,
        next_prob_hold    = if (nrow(next_event) > 0) next_event$prob_hold       else NA_real_,
        next_prob_hike    = if (nrow(next_event) > 0) next_event$prob_hike       else NA_real_,
        fetched_at        = if (nrow(kalshi_markets) > 0)
                              max(kalshi_markets$fetched_at, na.rm = TRUE)
                            else Sys.time()
      )
    }),

    # ── Dynamic prose caption ──────────────────────────────────────
    targets::tar_target(kalshi_caption, {
      s <- kalshi_summary

      if (s$n_markets == 0) {
        return("Kalshi FOMC market data unavailable — API returned no results.")
      }

      meeting_str <- if (!is.na(s$next_meeting)) {
        format(s$next_meeting, "%d %b %Y")
      } else {
        "next meeting"
      }

      rate_str <- if (!is.na(s$next_implied_rate)) {
        paste0(round(s$next_implied_rate, 2), "%")
      } else {
        "unknown"
      }

      dominant_outcome <- if (!is.na(s$next_prob_cut) &&
                              !is.na(s$next_prob_hold) &&
                              !is.na(s$next_prob_hike)) {
        probs <- c(cut = s$next_prob_cut,
                   hold = s$next_prob_hold,
                   hike = s$next_prob_hike)
        names(probs)[which.max(probs)]
      } else {
        "unknown"
      }

      dominant_pct <- if (!is.na(s$next_prob_cut)) {
        probs <- c(cut = s$next_prob_cut,
                   hold = s$next_prob_hold,
                   hike = s$next_prob_hike)
        paste0(round(max(probs) * 100, 1), "%")
      } else {
        "unknown"
      }

      paste0(
        "Kalshi KXFED prediction-market implied Fed Funds rate probabilities. ",
        s$n_markets, " markets across ", s$n_meetings, " FOMC meeting events. ",
        "For the ", meeting_str, " FOMC decision, the probability-weighted implied rate is ",
        rate_str, " with a dominant ", dominant_outcome, " outcome at ", dominant_pct, " probability. ",
        "Prices sourced from api.elections.kalshi.com/trade-api/v2 (public, no auth). ",
        "Kalshi last_price_dollars ($0-$1) treated directly as implied probability. ",
        "Data fetched: ", format(s$fetched_at, "%Y-%m-%d %H:%M UTC"), "."
      )
    })

  )
}
