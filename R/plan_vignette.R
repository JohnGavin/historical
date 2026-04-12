# Vignette targets: code-as-target pattern
#
# Each example has TWO targets:
#   code_vig_* — R code as character string, parse-validated
#   vig_*      — result of eval(parse(text=code))
#
# Theme and palette come from the historicaldata package:
#   hd_theme()   — black bg, white text, high-contrast
#   hd_palette() — 10 high-contrast colours for black bg
# These are exported functions, not duplicated code.

# Helper: create a code+output target pair
vig_pair <- function(name, code) {
  code_name <- paste0("code_", name)
  list(
    targets::tar_target_raw(code_name, substitute({
      code_text <- CODE
      parse(text = code_text)
      code_text
    }, list(CODE = code))),
    targets::tar_target_raw(name, substitute({
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      library(dplyr)
      library(ggplot2)
      library(scales)
      library(tidyr)
      library(purrr)
      eval(parse(text = CODEREF))
    }, list(CODEREF = as.symbol(code_name))))
  )
}

plan_vignette <- function() {
  c(
    # ── Setup ─────────────────────────────────────────────────────
    vig_pair("vig_setup", '
library(historicaldata)
library(dplyr)
library(ggplot2)
library(scales)
library(purrr)

# hd_theme() and hd_palette() are provided by the historicaldata package.
# hd_theme() gives black bg, white text/gridlines, high-contrast.
# hd_palette(n) returns n high-contrast hex colours for dark backgrounds.

"Setup complete. Use + hd_theme() on any ggplot. Colours: hd_palette(n)."
'),

    # ── Equity: AAPL Moving Averages ──────────────────────────────
    vig_pair("vig_eq_aapl", '

aapl <- hd_ohlcv("AAPL", from = "2023-01-01") |>
  arrange(date) |>
  mutate(
    cs = cumsum(close),
    ma_50  = if_else(row_number() >= 50, (cs - lag(cs, 50)) / 50, NA_real_),
    ma_200 = if_else(row_number() >= 200, (cs - lag(cs, 200)) / 200, NA_real_)
  ) |>
  select(-cs)

ggplot(aapl, aes(date)) +
  geom_line(aes(y = close), colour = "white", linewidth = 0.4) +
  geom_line(aes(y = ma_50), colour = "#00BFFF", linewidth = 0.5, linetype = "dashed") +
  geom_line(aes(y = ma_200), colour = "#FF6347", linewidth = 0.5, linetype = "dashed") +
  scale_y_continuous(labels = dollar) +
  labs(x = NULL, y = "Close (USD)",
       title = "AAPL daily close with 50d and 200d moving averages") +
  hd_theme()
'),

    # ── Equity: FAANG Returns ─────────────────────────────────────
    vig_pair("vig_eq_faang", '

faang <- c("AAPL", "AMZN", "GOOGL", "META", "NFLX") |>
  map(\\(t) hd_ohlcv(t, from = "2024-01-01")) |>
  list_rbind() |>
  group_by(ticker) |>
  mutate(cum_ret = adjusted / first(adjusted) - 1) |>
  ungroup()

ggplot(faang, aes(date, cum_ret, colour = ticker)) +
  geom_line(linewidth = 0.5) +
  geom_hline(yintercept = 0, colour = "grey50", linetype = "dashed") +
  scale_y_continuous(labels = percent) +
  scale_colour_manual(values = c("#00BFFF", "#FF6347", "#32CD32", "#FFD700", "#FF69B4")) +
  labs(x = NULL, y = "Cumulative return", colour = NULL,
       title = "FAANG cumulative returns rebased to 2024-01-01") +
  hd_theme()
'),

    # ── Equity: Realised Volatility ───────────────────────────────
    vig_pair("vig_eq_vol", '

vol <- c("AAPL", "NVDA", "TSLA", "SPY") |>
  map(\\(t) hd_ohlcv(t, from = "2023-06-01")) |>
  list_rbind() |>
  group_by(ticker) |>
  arrange(date) |>
  mutate(
    log_ret = log(adjusted / lag(adjusted)),
    cum_sq = cumsum(if_else(is.na(log_ret), 0, log_ret^2)),
    vol_21d = sqrt(pmax((cum_sq - lag(cum_sq, 21, default = 0)) / 21, 0)) * sqrt(252)
  ) |>
  filter(!is.na(vol_21d), date >= as.Date("2024-01-01")) |>
  ungroup()

ggplot(vol, aes(date, vol_21d, colour = ticker)) +
  geom_line(linewidth = 0.5) +
  scale_y_continuous(labels = percent) +
  scale_colour_manual(values = c("#00BFFF", "#FF6347", "#32CD32", "#FFD700")) +
  labs(x = NULL, y = "21d annualised volatility", colour = NULL,
       title = "Realised volatility: AAPL, NVDA, TSLA vs SPY") +
  hd_theme()
'),

    # ── Equity: Coverage (single query, not per-ticker) ───────────
    vig_pair("vig_eq_coverage", '
con <- hd_connect()
on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
ds <- hd_datasets()[["equity_daily"]]
sql <- paste0("SELECT ticker, COUNT(*) as days, MIN(date)::VARCHAR as first_dt, MAX(date)::VARCHAR as last_dt FROM read_parquet(\'", ds$url, "\') GROUP BY ticker ORDER BY days DESC")
DBI::dbGetQuery(con, sql) |> as_tibble() |>
  rename(Ticker = ticker, Days = days, From = first_dt, To = last_dt)
'),

    # ── Crypto: Major Coins ───────────────────────────────────────
    vig_pair("vig_cr_major", '

major <- c("BTC", "ETH", "SOL", "BNB") |>
  map(\\(t) hd_ohlcv(t, from = "2022-01-01")) |>
  list_rbind()

ggplot(major, aes(date, close, colour = ticker)) +
  geom_line(linewidth = 0.5) +
  scale_y_log10(labels = dollar) +
  scale_colour_manual(values = c("#00BFFF", "#FF6347", "#32CD32", "#FFD700")) +
  labs(x = NULL, y = "Close USD (log scale)", colour = NULL,
       title = "BTC, ETH, SOL, BNB daily close") +
  hd_theme()
'),

    # ── Crypto: Stablecoin Peg ────────────────────────────────────
    vig_pair("vig_cr_stable", '

stable <- c("USDC", "USDT") |>
  map(\\(t) hd_ohlcv(t, from = "2022-01-01")) |>
  list_rbind()

ggplot(stable, aes(date, close, colour = ticker)) +
  geom_line(linewidth = 0.5) +
  geom_hline(yintercept = 1.0, linetype = "dashed", colour = "grey50") +
  scale_y_continuous(limits = c(0.97, 1.03)) +
  scale_colour_manual(values = c("#00BFFF", "#FF6347")) +
  labs(x = NULL, y = "USD price", colour = NULL,
       title = "Stablecoin peg: USDC and USDT vs $1.00") +
  hd_theme()
'),

    # ── Crypto: Correlation ───────────────────────────────────────
    vig_pair("vig_cr_corr", '

wide <- c("BTC", "ETH", "SOL", "BNB", "ADA", "XRP") |>
  map(\\(t) hd_ohlcv(t, from = "2023-01-01")) |>
  list_rbind() |>
  group_by(ticker) |> arrange(date) |>
  mutate(ret = log(close / lag(close))) |>
  filter(!is.na(ret)) |> ungroup() |>
  select(date, ticker, ret) |>
  pivot_wider(names_from = ticker, values_from = ret) |>
  filter(if_all(everything(), ~ !is.na(.)))

cor_mat <- cor(wide |> select(-date))
cor_long <- cor_mat |> as.data.frame() |>
  mutate(row = rownames(cor_mat)) |>
  pivot_longer(-row, names_to = "col", values_to = "cor")

ggplot(cor_long, aes(row, col, fill = cor)) +
  geom_tile(colour = "grey30") +
  geom_text(aes(label = round(cor, 2)), colour = "white", size = 4) +
  scale_fill_gradient2(low = "#00BFFF", mid = "grey30", high = "#FF6347",
                       midpoint = 0.5, limits = c(0, 1)) +
  labs(x = NULL, y = NULL, fill = "Corr",
       title = "Crypto log-return correlation (2023+)") +
  hd_theme() +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))
'),

    # ── Crypto: Coverage (single query) ───────────────────────────
    vig_pair("vig_cr_coverage", '
con <- hd_connect()
on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
ds <- hd_datasets()[["crypto_daily"]]
sql <- paste0("SELECT ticker, COUNT(*) as days, MIN(date)::VARCHAR as first_dt, MAX(date)::VARCHAR as last_dt FROM read_parquet(\'", ds$url, "\') GROUP BY ticker ORDER BY days DESC")
DBI::dbGetQuery(con, sql) |> as_tibble() |>
  rename(Token = ticker, Days = days, From = first_dt, To = last_dt)
'),

    # ── Macro: Interest Rates ─────────────────────────────────────
    vig_pair("vig_ma_rates", '

rates <- c("DGS2", "DGS10", "DGS30", "DFF") |>
  map(\\(s) hd_macro(s, from = "2020-01-01")) |>
  list_rbind() |>
  filter(!is.na(value))

ggplot(rates, aes(date, value, colour = series_id)) +
  geom_line(linewidth = 0.5) +
  scale_colour_manual(values = c("#00BFFF", "#FF6347", "#32CD32", "#FFD700")) +
  labs(x = NULL, y = "Yield (%)", colour = NULL,
       title = "US Treasury yields + Fed Funds rate (2020+)") +
  hd_theme()
'),

    # ── Macro: Yield Curve ────────────────────────────────────────
    vig_pair("vig_ma_yc", '

yc <- hd_macro("T10Y2Y", from = "2018-01-01") |> filter(!is.na(value))
inv <- yc |> filter(value < 0)
inv_start <- min(inv$date)
inv_end <- max(inv$date)

ggplot(yc, aes(date, value)) +
  geom_line(linewidth = 0.5, colour = "#FF6347") +
  geom_hline(yintercept = 0, linetype = "dashed", colour = "grey50") +
  annotate("rect", xmin = inv_start, xmax = inv_end,
           ymin = -Inf, ymax = 0, fill = "#FF6347", alpha = 0.2) +
  labs(x = NULL, y = "10Y - 2Y spread (%)",
       title = "Yield curve: 10Y-2Y spread with inversion") +
  hd_theme()
'),

    # ── Macro: Credit Spreads ─────────────────────────────────────
    vig_pair("vig_ma_spreads", '

spreads <- c("BAMLH0A0HYM2", "BAMLC0A4CBBB") |>
  map(\\(s) hd_macro(s, from = "2020-01-01")) |>
  list_rbind() |>
  filter(!is.na(value)) |>
  mutate(series_id = recode(series_id,
    BAMLH0A0HYM2 = "HY Spread", BAMLC0A4CBBB = "BBB Spread"))

ggplot(spreads, aes(date, value, colour = series_id)) +
  geom_line(linewidth = 0.5) +
  scale_colour_manual(values = c("#FF6347", "#00BFFF")) +
  labs(x = NULL, y = "OAS (pp)", colour = NULL,
       title = "ICE BofA credit spreads: HY vs BBB (2020+)") +
  hd_theme()
'),

    # ── Macro: Coverage (single query) ────────────────────────────
    vig_pair("vig_ma_coverage", '
con <- hd_connect()
on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
ds <- hd_datasets()[["macro_daily"]]
sql <- paste0("SELECT series_id, COUNT(*) as n, MIN(date)::VARCHAR as first_dt, MAX(date)::VARCHAR as last_dt FROM read_parquet(\'", ds$url, "\') GROUP BY series_id ORDER BY series_id")
DBI::dbGetQuery(con, sql) |> as_tibble() |>
  rename(Series = series_id, Obs = n, From = first_dt, To = last_dt)
'),

    # ── Factors: FF3 Daily ────────────────────────────────────────
    vig_pair("vig_fa_ff3", '

ff3 <- hd_factors("FF3", "daily", from = "2020-01-01")

ggplot(ff3, aes(date, value, colour = factor_name)) +
  geom_line(alpha = 0.7, linewidth = 0.4) +
  geom_hline(yintercept = 0, colour = "grey50", linewidth = 0.2) +
  facet_wrap(~factor_name, ncol = 1, scales = "free_y") +
  scale_colour_manual(values = c("#00BFFF", "#FF6347", "#32CD32", "#FFD700")) +
  labs(x = NULL, y = "Return (%)",
       title = "Fama-French 3 factors: daily (2020+)") +
  hd_theme() +
  theme(legend.position = "none")
'),

    # ── Factors: FF5 Cumulative ───────────────────────────────────
    vig_pair("vig_fa_ff5", '

ff5 <- hd_factors("FF5", "daily", from = "2000-01-01") |>
  filter(factor_name != "RF") |>
  group_by(factor_name) |>
  arrange(date) |>
  mutate(cum_ret = cumprod(1 + value / 100) - 1) |>
  ungroup()

ggplot(ff5, aes(date, cum_ret, colour = factor_name)) +
  geom_line(linewidth = 0.5) +
  geom_hline(yintercept = 0, colour = "grey50", linetype = "dashed") +
  scale_y_continuous(labels = percent) +
  scale_colour_manual(values = c("#FF6347", "#00BFFF", "#32CD32", "#FFD700", "#FF69B4")) +
  labs(x = NULL, y = "Cumulative return", colour = NULL,
       title = "FF5 cumulative factor returns (2000-2026)") +
  hd_theme()
'),

    # ── Factors: Momentum ─────────────────────────────────────────
    vig_pair("vig_fa_mom", '

mom <- hd_factors("Mom", "daily", from = "2000-01-01") |>
  arrange(date) |>
  mutate(cum_ret = cumprod(1 + value / 100) - 1)

ggplot(mom, aes(date, cum_ret)) +
  geom_line(linewidth = 0.5, colour = "#00BFFF") +
  geom_hline(yintercept = 0, colour = "grey50", linetype = "dashed") +
  scale_y_continuous(labels = percent) +
  labs(x = NULL, y = "Cumulative return",
       title = "Momentum factor cumulative return (2000-2026)") +
  hd_theme()
'),

    # ── Factors: Coverage (single query) ─────────────────────────
    vig_pair("vig_fa_coverage", '
con <- hd_connect()
on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
ds <- hd_datasets()[["factors"]]
sql <- paste0("SELECT dataset, frequency, factor_name, COUNT(*) as n, MIN(date)::VARCHAR as first_dt, MAX(date)::VARCHAR as last_dt FROM read_parquet(\'", ds$url, "\') GROUP BY dataset, frequency, factor_name ORDER BY dataset, frequency, factor_name")
DBI::dbGetQuery(con, sql) |> as_tibble() |>
  rename(Dataset = dataset, Freq = frequency, Factor = factor_name,
         Obs = n, From = first_dt, To = last_dt)
')
  )
}
