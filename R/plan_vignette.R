# Vignette targets: code-as-target pattern
#
# Each example has TWO targets:
#   code_vig_* — R code as character string, parse-validated
#   vig_*      — result of eval(parse(text=code))
#
# The code targets contain library(historicaldata) so users can copy-paste.
# The output targets use pkgload::load_all() to actually execute.

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
      eval(parse(text = CODEREF))
    }, list(CODEREF = as.symbol(code_name))))
  )
}

plan_vignette <- function() {
  plot_theme <- '
theme_set(theme_minimal(base_size = 12) + theme(
  plot.background = element_rect(fill = "gray70", colour = NA),
  panel.background = element_rect(fill = "gray70", colour = NA),
  text = element_text(colour = "grey20"),
  axis.text = element_text(colour = "grey30"),
  panel.grid.minor = element_blank(),
  panel.grid.major = element_line(colour = "grey60"),
  legend.position = "bottom"
))'

  c(
    # ── Equity: AAPL Moving Averages ──────────────────────────────
    vig_pair("vig_eq_aapl", paste0('
library(historicaldata)
library(dplyr)
library(ggplot2)
library(scales)
', plot_theme, '

aapl <- hd_ohlcv("AAPL", from = "2023-01-01") |>
  arrange(date) |>
  mutate(
    cs = cumsum(close),
    ma_50  = if_else(row_number() >= 50, (cs - lag(cs, 50)) / 50, NA_real_),
    ma_200 = if_else(row_number() >= 200, (cs - lag(cs, 200)) / 200, NA_real_)
  ) |>
  select(-cs)

ggplot(aapl, aes(date)) +
  geom_line(aes(y = close), colour = "grey20", linewidth = 0.4) +
  geom_line(aes(y = ma_50), colour = "#3498db", linewidth = 0.5, linetype = "dashed") +
  geom_line(aes(y = ma_200), colour = "#e74c3c", linewidth = 0.5, linetype = "dashed") +
  scale_y_continuous(labels = dollar) +
  labs(
    x = NULL, y = "Close (USD)",
    title = "AAPL daily close with 50-day and 200-day moving averages"
  )
')),

    # ── Equity: FAANG Returns ─────────────────────────────────────
    vig_pair("vig_eq_faang", paste0('
library(historicaldata)
library(dplyr)
library(ggplot2)
library(scales)
', plot_theme, '

faang <- bind_rows(lapply(
  c("AAPL", "AMZN", "GOOGL", "META", "NFLX"),
  \\(t) hd_ohlcv(t, from = "2024-01-01")
)) |>
  group_by(ticker) |>
  mutate(cum_ret = adjusted / first(adjusted) - 1) |>
  ungroup()

best <- faang |> filter(date == max(date)) |> slice_max(cum_ret, n = 1)

ggplot(faang, aes(date, cum_ret, colour = ticker)) +
  geom_line(linewidth = 0.5) +
  geom_hline(yintercept = 0, colour = "grey50", linetype = "dashed") +
  scale_y_continuous(labels = percent) +
  labs(
    x = NULL, y = "Cumulative return", colour = NULL,
    title = "FAANG cumulative returns rebased to 2024-01-01"
  )
')),

    # ── Equity: Realised Volatility ───────────────────────────────
    vig_pair("vig_eq_vol", paste0('
library(historicaldata)
library(dplyr)
library(ggplot2)
library(scales)
', plot_theme, '

vol <- bind_rows(lapply(
  c("AAPL", "NVDA", "TSLA", "SPY"),
  \\(t) hd_ohlcv(t, from = "2023-06-01")
)) |>
  group_by(ticker) |>
  arrange(date) |>
  mutate(
    log_ret = log(adjusted / lag(adjusted)),
    cum_sq = cumsum(if_else(is.na(log_ret), 0, log_ret^2)),
    vol_21d = sqrt(pmax((cum_sq - lag(cum_sq, 21, default = 0)) / 21, 0)) * sqrt(252)
  ) |>
  filter(!is.na(vol_21d), date >= as.Date("2024-01-01")) |>
  ungroup()

max_vol <- vol |> filter(date == max(date)) |> slice_max(vol_21d, n = 1)
min_vol <- vol |> filter(date == max(date)) |> slice_min(vol_21d, n = 1)

ggplot(vol, aes(date, vol_21d, colour = ticker)) +
  geom_line(linewidth = 0.4) +
  scale_y_continuous(labels = percent) +
  labs(
    x = NULL, y = "21d annualised volatility", colour = NULL,
    title = "Realised volatility: AAPL, NVDA, TSLA vs SPY benchmark"
  )
')),

    # ── Equity: Coverage ──────────────────────────────────────────
    vig_pair("vig_eq_coverage", '
library(historicaldata)
library(dplyr)

tickers <- hd_tickers("equity_daily")
coverage <- bind_rows(lapply(tickers, \\(t) {
  d <- hd_ohlcv(t, from = "1900-01-01")
  tibble(Ticker = t, `Trading Days` = nrow(d),
         From = as.character(min(d$date)),
         To = as.character(max(d$date)))
})) |> arrange(desc(`Trading Days`))

coverage
'),

    # ── Crypto: Major Coins ───────────────────────────────────────
    vig_pair("vig_cr_major", paste0('
library(historicaldata)
library(dplyr)
library(ggplot2)
library(scales)
', plot_theme, '

major <- bind_rows(lapply(
  c("BTC", "ETH", "SOL", "BNB"),
  \\(t) hd_ohlcv(t, from = "2022-01-01")
))

ggplot(major, aes(date, close, colour = ticker)) +
  geom_line(linewidth = 0.4) +
  scale_y_log10(labels = dollar) +
  labs(
    x = NULL, y = "Close USD (log scale)", colour = NULL,
    title = "BTC, ETH, SOL, BNB daily close prices"
  )
')),

    # ── Crypto: Stablecoin Peg ────────────────────────────────────
    vig_pair("vig_cr_stable", paste0('
library(historicaldata)
library(dplyr)
library(ggplot2)
', plot_theme, '

stable <- bind_rows(
  hd_ohlcv("USDC", from = "2022-01-01"),
  hd_ohlcv("USDT", from = "2022-01-01")
)

max_depeg <- stable |> mutate(depeg = abs(close - 1.0)) |> slice_max(depeg, n = 1)

ggplot(stable, aes(date, close, colour = ticker)) +
  geom_line(linewidth = 0.4) +
  geom_hline(yintercept = 1.0, linetype = "dashed", colour = "grey50") +
  scale_y_continuous(limits = c(0.97, 1.03)) +
  labs(
    x = NULL, y = "USD price", colour = NULL,
    title = "Stablecoin peg: USDC and USDT deviation from $1.00"
  )
')),

    # ── Crypto: Correlation ───────────────────────────────────────
    vig_pair("vig_cr_corr", paste0('
library(historicaldata)
library(dplyr)
library(tidyr)
library(ggplot2)
', plot_theme, '

tokens <- c("BTC", "ETH", "SOL", "BNB", "ADA", "XRP")
wide <- bind_rows(lapply(tokens, \\(t) hd_ohlcv(t, from = "2023-01-01"))) |>
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

max_pair <- cor_long |> filter(row != col) |> slice_max(cor, n = 1)
min_pair <- cor_long |> filter(row != col) |> slice_min(cor, n = 1)

ggplot(cor_long, aes(row, col, fill = cor)) +
  geom_tile() +
  geom_text(aes(label = round(cor, 2)), colour = "grey20", size = 3.5) +
  scale_fill_gradient2(low = "#3498db", mid = "grey80", high = "#e74c3c",
                       midpoint = 0.5, limits = c(0, 1)) +
  labs(
    x = NULL, y = NULL, fill = "Corr",
    title = "Crypto log-return correlation matrix (2023+)"
  ) +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))
')),

    # ── Crypto: Coverage ──────────────────────────────────────────
    vig_pair("vig_cr_coverage", '
library(historicaldata)
library(dplyr)

tickers <- hd_tickers("crypto_daily")
bind_rows(lapply(tickers, \\(t) {
  d <- hd_ohlcv(t, from = "2010-01-01")
  tibble(Token = t, Days = nrow(d),
         From = as.character(min(d$date)),
         To = as.character(max(d$date)))
})) |> arrange(desc(Days))
'),

    # ── Macro: Interest Rates ─────────────────────────────────────
    vig_pair("vig_ma_rates", paste0('
library(historicaldata)
library(dplyr)
library(ggplot2)
', plot_theme, '

rates <- bind_rows(lapply(
  c("DGS2", "DGS10", "DGS30", "DFF"),
  \\(s) hd_macro(s, from = "2020-01-01")
)) |> filter(!is.na(value))

latest <- rates |> group_by(series_id) |> filter(date == max(date)) |> ungroup()
spread <- diff(range(latest$value[latest$series_id %in% c("DGS2", "DGS10")]))

ggplot(rates, aes(date, value, colour = series_id)) +
  geom_line(linewidth = 0.4) +
  labs(
    x = NULL, y = "Yield (%)", colour = NULL,
    title = "US Treasury yields and Fed Funds rate (2020+)"
  )
')),

    # ── Macro: Yield Curve ────────────────────────────────────────
    vig_pair("vig_ma_yc", paste0('
library(historicaldata)
library(dplyr)
library(ggplot2)
', plot_theme, '

yc <- hd_macro("T10Y2Y", from = "2018-01-01") |> filter(!is.na(value))
inv <- yc |> filter(value < 0)
inv_start <- min(inv$date)
inv_end <- max(inv$date)
inv_days <- as.integer(difftime(inv_end, inv_start, units = "days"))

ggplot(yc, aes(date, value)) +
  geom_line(linewidth = 0.4, colour = "#e74c3c") +
  geom_hline(yintercept = 0, linetype = "dashed", colour = "grey50") +
  annotate("rect", xmin = inv_start, xmax = inv_end,
           ymin = -Inf, ymax = 0, fill = "#e74c3c", alpha = 0.15) +
  labs(
    x = NULL, y = "10Y - 2Y spread (%)",
    title = "Yield curve: 10Y-2Y Treasury spread with inversion shading"
  )
')),

    # ── Macro: Credit Spreads ─────────────────────────────────────
    vig_pair("vig_ma_spreads", paste0('
library(historicaldata)
library(dplyr)
library(ggplot2)
', plot_theme, '

spreads <- bind_rows(
  hd_macro("BAMLH0A0HYM2", from = "2020-01-01"),
  hd_macro("BAMLC0A4CBBB", from = "2020-01-01")
) |>
  filter(!is.na(value)) |>
  mutate(series_id = recode(series_id,
    BAMLH0A0HYM2 = "HY Spread", BAMLC0A4CBBB = "BBB Spread"))

latest <- spreads |> group_by(series_id) |> filter(date == max(date)) |> ungroup()

ggplot(spreads, aes(date, value, colour = series_id)) +
  geom_line(linewidth = 0.4) +
  labs(
    x = NULL, y = "OAS (percentage points)", colour = NULL,
    title = "ICE BofA credit spreads: High Yield vs BBB (2020+)"
  )
')),

    # ── Macro: Coverage ───────────────────────────────────────────
    vig_pair("vig_ma_coverage", '
library(historicaldata)
library(dplyr)

series <- hd_macro_series()
bind_rows(lapply(series, \\(s) {
  d <- hd_macro(s)
  tibble(Series = s, Obs = nrow(d),
         From = as.character(min(d$date)),
         To = as.character(max(d$date)))
})) |> arrange(Series)
'),

    # ── Factors: FF3 Daily ────────────────────────────────────────
    vig_pair("vig_fa_ff3", paste0('
library(historicaldata)
library(dplyr)
library(ggplot2)
', plot_theme, '

ff3 <- hd_factors("FF3", "daily", from = "2020-01-01")
mktrf <- ff3 |> filter(factor_name == "Mkt-RF")

ggplot(ff3, aes(date, value, colour = factor_name)) +
  geom_line(alpha = 0.6, linewidth = 0.3) +
  geom_hline(yintercept = 0, colour = "grey50", linewidth = 0.2) +
  facet_wrap(~factor_name, ncol = 1, scales = "free_y") +
  labs(
    x = NULL, y = "Return (%)",
    title = "Fama-French 3 factors: daily returns (2020+)"
  ) +
  theme(legend.position = "none")
')),

    # ── Factors: FF5 Cumulative ───────────────────────────────────
    vig_pair("vig_fa_ff5", paste0('
library(historicaldata)
library(dplyr)
library(ggplot2)
library(scales)
', plot_theme, '

ff5 <- hd_factors("FF5", "daily", from = "2000-01-01") |>
  filter(factor_name != "RF") |>
  group_by(factor_name) |>
  arrange(date) |>
  mutate(cum_ret = cumprod(1 + value / 100) - 1) |>
  ungroup()

latest <- ff5 |> group_by(factor_name) |> filter(date == max(date)) |> ungroup()
best <- latest |> slice_max(cum_ret, n = 1)
worst <- latest |> slice_min(cum_ret, n = 1)

ggplot(ff5, aes(date, cum_ret, colour = factor_name)) +
  geom_line(linewidth = 0.5) +
  geom_hline(yintercept = 0, colour = "grey50", linetype = "dashed") +
  scale_y_continuous(labels = percent) +
  labs(
    x = NULL, y = "Cumulative return", colour = NULL,
    title = "FF5 cumulative factor returns (2000-2026)"
  )
')),

    # ── Factors: Momentum ─────────────────────────────────────────
    vig_pair("vig_fa_mom", paste0('
library(historicaldata)
library(dplyr)
library(ggplot2)
library(scales)
', plot_theme, '

mom <- hd_factors("Mom", "daily", from = "2000-01-01") |>
  arrange(date) |>
  mutate(cum_ret = cumprod(1 + value / 100) - 1)

peak <- mom |> slice_max(cum_ret, n = 1)
trough <- mom |> slice_min(cum_ret, n = 1)

ggplot(mom, aes(date, cum_ret)) +
  geom_line(linewidth = 0.5, colour = "#2ecc71") +
  geom_hline(yintercept = 0, colour = "grey50", linetype = "dashed") +
  scale_y_continuous(labels = percent) +
  labs(
    x = NULL, y = "Cumulative return",
    title = "Momentum factor cumulative return (2000-2026)"
  )
')),

    # ── Factors: Coverage ─────────────────────────────────────────
    vig_pair("vig_fa_coverage", '
library(historicaldata)

con <- hd_connect()
on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
ds <- hd_datasets()[["factors"]]
DBI::dbGetQuery(con, sprintf(
  "SELECT dataset AS Dataset, frequency AS Freq, factor_name AS Factor,
          COUNT(*) AS Obs, MIN(date) AS \'From\', MAX(date) AS \'To\'
   FROM read_parquet(\'%s\')
   GROUP BY dataset, frequency, factor_name
   ORDER BY dataset, frequency, factor_name", ds$url
)) |> dplyr::as_tibble()
')
  )
}
