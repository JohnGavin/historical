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
    })

  )
}
