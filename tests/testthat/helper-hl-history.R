# Shared builders for the weekly-history tests (#1088): tiny parquet tables with the
# registry's key columns. Sourced here (not only in the test files) so that every test
# file sees the same functions.
source(here::here("scripts", "hl_history_guard.R"))

# A small table with the registry's key columns, `days` x BTC/ETH. The date column has the
# type the real table has (Date, POSIXct, epoch ms, ISO string).
.mk_table <- function(t, days = c("2026-01-01", "2026-01-02")) {
  if (t == "perp_dexs") return(data.frame(dex = c("", "xyz"), full_name = c(NA, "XYZ")))
  if (t == "perp_markets") return(data.frame(dex = "", coin = c("BTC", "ETH")))
  spec <- hl_hist_spec(t)
  g <- expand.grid(day = days, coin = c("BTC", "ETH"), stringsAsFactors = FALSE)
  out <- data.frame(dex = "", coin = g$coin, stringsAsFactors = FALSE)
  at <- as.POSIXct(paste(g$day, "00:00:00"), tz = "UTC")
  out[[spec$when]] <- switch(spec$when,
    date = as.Date(g$day), time = at, time_ms = as.numeric(at) * 1000,
    fetched_at = paste0(g$day, "T00:00:00Z"))
  out$v <- seq_len(nrow(out))
  out
}
.put <- function(df, dir, t) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  arrow::write_parquet(df, file.path(dir, paste0(t, ".parquet")))
}
.required <- function() HL_HIST_TABLES$table[HL_HIST_TABLES$required]
# A full set of required tables in `dir`.
.put_all <- function(dir, days = c("2026-01-01", "2026-01-02"), tables = .required()) {
  for (t in tables) .put(.mk_table(t, days), dir, t)
  invisible(dir)
}

