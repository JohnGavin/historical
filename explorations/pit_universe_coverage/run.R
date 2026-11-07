#!/usr/bin/env Rscript
# explorations/pit_universe_coverage/run.R -- the survivorship gap, measured (#816)
#
# QUESTION. For each point-in-time S&P 500 snapshot, what share of the index
# members have price data in equity_daily on or near that date? The missing
# share is the survivorship gap: members equity_daily cannot supply (delisted,
# acquired, renamed, never ingested).
#
# INPUTS. The cached membership file (scripts/fetch_sp500_membership.R) and the
# remote equity_daily parquet via the package (hd_lazy). Nothing is typed in.
#
# CAVEAT. share_covered is an UPPER bound on true coverage: a recycled ticker
# (a different company reusing the symbol, #865) and an interior gap inside a
# ticker's [first, last] span both count as covered. The survivorship gap
# (1 - share_covered) is therefore a LOWER bound.
#
# EXIT STATUS. Aborts (non-zero) if any known-failed-name presence check row is
# not PASS, after writing the CSVs and printing the table.
#
# OUTPUTS (derived statistics only; the raw membership file is never committed):
#   coverage_by_snapshot.csv  one row per snapshot date
#   coverage_by_year.csv      per calendar year: min / median / max share
#   presence_check.csv        known failed names: PIT member? in equity_daily?
#
# Usage (from the repo root):
#   nix develop . --command Rscript explorations/pit_universe_coverage/run.R

suppressPackageStartupMessages({
  pkgload::load_all(here::here("packages", "historicaldata"), quiet = TRUE)
  library(dplyr)
})

out_dir <- here::here("explorations", "pit_universe_coverage")

mem <- hd_sp500_membership()

spans <- hd_sp500_equity_spans()
cli::cli_inform("equity_daily: {nrow(spans)} distinct tickers.")

cov <- hd_sp500_coverage(mem, spans)

by_year <- cov |>
  mutate(year = as.integer(format(date, "%Y"))) |>
  group_by(year) |>
  summarise(
    n_snapshots  = n(),
    min_share    = min(share_covered),
    median_share = median(share_covered),
    max_share    = max(share_covered),
    .groups = "drop"
  )

chk <- hd_sp500_presence_check(mem, spans$ticker)

utils::write.csv(cov, file.path(out_dir, "coverage_by_snapshot.csv"), row.names = FALSE)
utils::write.csv(by_year, file.path(out_dir, "coverage_by_year.csv"), row.names = FALSE)
utils::write.csv(chk, file.path(out_dir, "presence_check.csv"), row.names = FALSE)

cat(sprintf("\nprice window: %s to %s; scored %d of %d snapshots\n",
            min(spans$first_date), max(spans$last_date), nrow(cov),
            length(unique(mem$date))))
cat("\n-- presence check --\n")
print(as.data.frame(chk), row.names = FALSE)
cat("\n-- coverage, selected snapshots --\n")
pick <- cov[cov$date %in% as.Date(c(min(cov$date), max(cov$date))) |
              cov$date == cov$date[which.min(abs(cov$date - as.Date("2008-01-02")))] |
              cov$date == cov$date[which.min(abs(cov$date - as.Date("2010-01-04")))] |
              cov$date == cov$date[which.min(abs(cov$date - as.Date("2000-01-03")))], ]
print(as.data.frame(pick), row.names = FALSE)
cat(sprintf("\nall snapshots: min %.3f, median %.3f, max %.3f (n = %d)\n",
            min(cov$share_covered), median(cov$share_covered),
            max(cov$share_covered), nrow(cov)))

bad <- chk[chk$status != "PASS", , drop = FALSE]
if (nrow(bad) > 0L) {
  cli::cli_abort(c(
    "x" = "Presence check failed for {nrow(bad)} name{?s}: {.val {bad$ticker}}.",
    "i" = "Statuses: {.val {bad$status}}."
  ))
}
