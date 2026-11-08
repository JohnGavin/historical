# Plan: Point-in-Time S&P 500 membership universe (#816)
#
# Issue refs: #816 (this), #278 (OLMAR P4), #150 (survivorship bias), #862 (OSAP).
#
# SOURCE. fja05680/sp500 "Historical Components & Changes (Updated)" -- free,
# MIT-licensed, one row per index-change date, 1996-01-02 to the latest
# upstream update. Downloaded by scripts/fetch_sp500_membership.R to
# ~/.cache/historical/sp500_membership/ (override: SP500_MEMBERSHIP_DIR);
# the raw file is kept LOCAL (manifest committed, data not).
#
# WHAT THIS IS NOT. Membership with dates only. The source has NO delisting
# reason, NO delisting price and NO returns:
#   delisting_date   = the date the ticker LEFT THE INDEX. It is NOT a
#                      delisting: an acquisition, a bankruptcy and a demotion
#                      all look the same. NA while still a member.
#   delisting_reason = NA always (unavailable from this source).
#   delisting_price  = NA always (unavailable from this source).
# A loser-leg backtest still needs delisting prices (CRSP / Norgate), which
# remain unavailable free. What this adds is the membership list and the
# measured survivorship gap (stk_universe_pit_coverage).
#
# Cache convention (same as OSAP): the cached file enters the pipeline as a
# `format = "file"` target, so its content hash is tracked, and a machine
# WITHOUT the cache fails loudly with the fetch command in the message (no
# silent fallback, no network call inside a target).
#
# Schema of stk_universe_pit (one row per snapshot date x member ticker):
#   ticker            character -- ticker symbol as listed on the snapshot date
#   date              Date      -- snapshot (index-change) date; a member stays
#                                  a member until the next snapshot date
#   in_universe_pit   logical   -- TRUE (rows exist only for members)
#   index_name        character -- "SP500"
#   delisting_date    Date|NA   -- index-exit date (see above)
#   delisting_reason  chr|NA    -- always NA
#   delisting_price   dbl|NA    -- always NA
#
# Targets (all new in #816):
#   stk_universe_pit_file      cached CSV path, format = "file"
#   stk_universe_pit           the schema above
#   stk_universe_pit_spans     per-ticker first/last date in equity_daily
#                              (cue = always, like stk_top_tickers: remote read)
#   stk_universe_pit_presence  known-delisted presence check; ABORTS if any
#                              row is not PASS (a check that can go red)
#   stk_universe_pit_coverage  per snapshot: share of PIT members that have
#                              price data in equity_daily (the survivorship gap)
#
# Targets added in #1041 (exit prices; the 706 index leavers, 242 of them on or
# after Alpaca's 2016-01-04 history start):
#   stk_exit_bars_file   cached Alpaca bars parquet, format = "file"
#   stk_exit_bars        the bars (symbol, date, open..vwap)
#   stk_exit_assets_file cached Alpaca asset list (active + inactive), format = "file"
#   stk_exit_assets      the asset list (symbol, name, status; detects ticker changes)
#   stk_exit_prices      one row per index exit: exit_type (demotion,
#                        ticker_change, failure_candidate, takeover, ...), last
#                        trade, exit_price_lower / exit_price_upper
#                        (hd_alpaca_exit_rule())
#   stk_exit_prices_controls  positive control: named real cases (SIVB, NBL, FI,
#                        ...) must get their known exit_type; ABORTS otherwise
#   stk_exit_coverage    by exit year: exits, with bars, one count per exit_type
# These are BOUNDS, not delisting returns: a failure candidate's lower bound is
# 0 and its upper bound the last exchange close.
#
# Intended consumption (plan_olmar.R Phase 4): per-date filtering inside the
# backtest via hd_sp500_members_asof(), NOT a static ticker list.
#
# Ticker-only key caveat (#865): a symbol can be reused by another company, so
# coverage is an UPPER bound on the share genuinely supplied.

plan_universe_pit <- function() {
  list(

    targets::tar_target(
      stk_universe_pit_file,
      hd_sp500_membership_path(),
      format = "file"
    ),

    targets::tar_target(stk_universe_pit, {
      hd_sp500_pit_universe(hd_sp500_membership(stk_universe_pit_file))
    }),

    targets::tar_target(stk_universe_pit_spans, {
      duckplyr_path <- Sys.glob("/nix/store/*-r-duckplyr-*/library")
      duckplyr_path <- duckplyr_path[file.exists(file.path(duckplyr_path, "duckplyr"))]
      if (length(duckplyr_path) > 0) .libPaths(c(.libPaths(), duckplyr_path[[1]]))

      hd_sp500_equity_spans()
    }, cue = targets::tar_cue(mode = "always")),

    targets::tar_target(stk_universe_pit_presence, {
      chk <- hd_sp500_presence_check(
        stk_universe_pit[, c("date", "ticker")],
        stk_universe_pit_spans$ticker
      )
      bad <- chk[chk$status != "PASS", , drop = FALSE]
      if (nrow(bad) > 0L) {
        cli::cli_abort(c(
          "x" = "Known-delisted presence check failed for {nrow(bad)} name{?s}: {.val {bad$ticker}}.",
          "i" = "Statuses: {.val {bad$status}}.",
          "i" = "FAIL_NOT_MEMBER: the membership source does not list the name on the fixture date.",
          "i" = "FAIL_IN_PRICE_UNIVERSE: equity_daily now carries the name; the survivorship baseline moved."
        ))
      }
      chk
    }),

    targets::tar_target(stk_universe_pit_coverage, {
      hd_sp500_coverage(
        stk_universe_pit[, c("date", "ticker")],
        stk_universe_pit_spans
      )
    }),

    # ---- #1041: exit prices for names that left the index -------------------
    # Alpaca daily bars (sip feed, from 2016-01-04) for tickers that left the
    # PIT index on/after 2016-01-04, cached by scripts/fetch_alpaca_exit_bars.R.
    # A machine without the cache fails stk_exit_bars_file loudly, naming that
    # script (hd_alpaca_exit_bars_path() aborts; never an empty result).

    targets::tar_target(
      stk_exit_bars_file,
      hd_alpaca_exit_bars_path(),
      format = "file"
    ),

    targets::tar_target(stk_exit_bars, {
      tibble::as_tibble(arrow::read_parquet(stk_exit_bars_file))
    }),

    targets::tar_target(
      stk_exit_assets_file,
      hd_alpaca_exit_assets_path(),
      format = "file"
    ),

    targets::tar_target(stk_exit_assets, {
      tibble::as_tibble(arrow::read_parquet(stk_exit_assets_file))
    }),

    # All index exits (706 as of 2026-11-08, including 464 before the Alpaca
    # history starts: those come back has_bars = FALSE). The rule and its
    # constants live in hd_alpaca_exit_rule(); a known failed name is forced to
    # exit_type = "failure_candidate". A ticker_change row has no price: join
    # it to new_ticker.
    targets::tar_target(stk_exit_prices, {
      hd_alpaca_exit_prices(
        stk_exit_bars,
        hd_sp500_exits(stk_universe_pit[, c("date", "ticker")]),
        stk_exit_assets,
        known_failed = hd_sp500_known_delisted()$ticker
      )
    }),

    # Positive control (can go red): 14 real leavers whose fate is known must
    # get that exit_type; aborts on any mismatch, or if fewer than 10 are present.
    targets::tar_target(stk_exit_prices_controls, {
      hd_alpaca_exit_controls(stk_exit_prices)
    }),

    targets::tar_target(stk_exit_coverage, {
      hd_alpaca_exit_coverage(stk_exit_prices)
    })

  )
}
