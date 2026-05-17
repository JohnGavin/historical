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

# Shared vignette constants — single source of truth
VIG_MIN_MARKET_CAP <- 250e6   # GBP 250M minimum for LSE ETF filters
VIG_MAX_YIELD_PCT  <- 0.20    # 20% cap — yields above this are likely synthetic

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
      # Inject shared constants (inlined at target-construction; crew-worker safe)
      MIN_MARKET_CAP <- VIG_MIN_MARKET_CAP
      MAX_YIELD_PCT  <- VIG_MAX_YIELD_PCT
      eval(parse(text = CODEREF))
    }, list(
      CODEREF            = as.symbol(code_name),
      VIG_MIN_MARKET_CAP = VIG_MIN_MARKET_CAP,
      VIG_MAX_YIELD_PCT  = VIG_MAX_YIELD_PCT
    )))
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

# Vignette parameters — change these and tar_make() to update all plots
MIN_MARKET_CAP <- 250e6  # GBP 250M minimum for LSE ETF filters
MAX_YIELD_PCT  <- 0.20   # 20% cap — yields above this are likely synthetic
'),

    # ── Equity: Top Market Cap Moving Averages ──────────────────
    vig_pair("vig_eq_aapl", '

# Dynamically pick the largest equity by market cap
top_ticker <- hd_top_by("equity_daily", "market_cap", 1)$ticker
aapl <- hd_ohlcv(top_ticker, from = "2023-01-01") |>
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
       title = paste(top_ticker, "daily close with 50d and 200d moving averages")) +
  hd_theme()
'),

    # ── Equity: FAANG Returns ─────────────────────────────────────
    vig_pair("vig_eq_faang", '

# Batch query: all FAANG tickers in one DuckDB request
faang <- hd_ohlcv(hd_group("FAANG"), from = "2024-01-01") |>
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

# Top 3 most volatile equities + SPY benchmark — single batch query
vol_tickers <- c(hd_most_volatile("equity_daily", 3)$ticker, "SPY")
vol <- hd_ohlcv(vol_tickers, from = "2023-06-01") |>
  group_by(ticker) |>
  arrange(date) |>
  mutate(
    log_ret = log(adjusted / lag(adjusted)),
    cum_sq = cumsum(if_else(is.na(log_ret), 0, log_ret^2)),
    vol_21d = sqrt(pmax((cum_sq - lag(cum_sq, 21, default = NA_real_)) / 21, 0)) * sqrt(252)
  ) |>
  filter(!is.na(vol_21d), date >= as.Date("2024-01-01")) |>
  ungroup()

ggplot(vol, aes(date, vol_21d, colour = ticker)) +
  geom_line(linewidth = 0.5) +
  scale_y_continuous(labels = percent) +
  scale_colour_manual(values = hd_palette(length(vol_tickers))) +
  labs(x = NULL, y = "21d annualised volatility", colour = NULL,
       title = paste("Realised volatility:", paste(vol_tickers, collapse = ", "))) +
  hd_theme()
'),

    # ── Equity: Coverage (duckplyr, zero SQL) ───────────────────
    vig_pair("vig_eq_coverage", '
ds <- hd_datasets()[["equity_daily"]]
duckplyr::read_parquet_duckdb(ds$url) |>
  summarise(Days = n(), From = min(date), To = max(date), .by = ticker) |>
  arrange(desc(Days)) |>
  collect() |>
  mutate(From = as.character(From), To = as.character(To)) |>
  rename(Ticker = ticker)
'),

    # ── Crypto: Major Coins ───────────────────────────────────────
    vig_pair("vig_cr_major", '

# Batch query: Major Crypto group in one request
major <- hd_ohlcv(hd_group("Major Crypto"), from = "2022-01-01")

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

# Batch query: Stablecoins in one request
stable <- hd_ohlcv(hd_group("Stablecoins"), from = "2022-01-01")

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

# Top 6 crypto by average volume — single batch query
corr_tickers <- hd_top_by("crypto_daily", "volume_avg", 6)$ticker
wide <- hd_ohlcv(corr_tickers, from = "2023-01-01") |>
  group_by(ticker) |> arrange(date) |>
  mutate(ret = log(close / lag(close))) |>
  filter(!is.na(ret)) |> ungroup() |>
  select(date, ticker, ret) |>
  pivot_wider(names_from = ticker, values_from = ret)

cor_mat <- cor(wide |> select(-date), use = "pairwise.complete.obs")
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

    # ── Crypto: Coverage (duckplyr, zero SQL) ───────────────────
    vig_pair("vig_cr_coverage", '
ds <- hd_datasets()[["crypto_daily"]]
duckplyr::read_parquet_duckdb(ds$url) |>
  summarise(Days = n(), From = min(date), To = max(date), .by = ticker) |>
  arrange(desc(Days)) |>
  collect() |>
  mutate(From = as.character(From), To = as.character(To)) |>
  rename(Token = ticker)
'),

    # ── Macro: Interest Rates ─────────────────────────────────────
    vig_pair("vig_ma_rates", '

# Batch query: 4 macro series in one DuckDB request
rates <- hd_macro(c("DGS2", "DGS10", "DGS30", "DFF"), from = "2020-01-01") |>
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
p <- ggplot(yc, aes(date, value)) +
  geom_line(linewidth = 0.5, colour = "#FF6347") +
  geom_hline(yintercept = 0, linetype = "dashed", colour = "grey50") +
  labs(x = NULL, y = "10Y - 2Y spread (%)",
       title = "Yield curve: 10Y-2Y spread with inversion") +
  hd_theme()

if (nrow(inv) > 0) {
  inv_start <- min(inv$date)
  inv_end <- max(inv$date)
  p <- p + annotate("rect", xmin = inv_start, xmax = inv_end,
                    ymin = -Inf, ymax = 0, fill = "#FF6347", alpha = 0.2)
}

p
'),

    # ── Macro: Credit Spreads ─────────────────────────────────────
    vig_pair("vig_ma_spreads", '

# Batch query: 2 credit spread series in one request
spreads <- hd_macro(c("BAMLH0A0HYM2", "BAMLC0A4CBBB"), from = "2020-01-01") |>
  filter(!is.na(value)) |>
  mutate(series_id = case_match(series_id,
    "BAMLH0A0HYM2" ~ "HY Spread",
    "BAMLC0A4CBBB" ~ "BBB Spread",
    .default = series_id))

ggplot(spreads, aes(date, value, colour = series_id)) +
  geom_line(linewidth = 0.5) +
  scale_colour_manual(values = c("#FF6347", "#00BFFF")) +
  labs(x = NULL, y = "OAS (pp)", colour = NULL,
       title = "ICE BofA credit spreads: HY vs BBB (2020+)") +
  hd_theme()
'),

    # ── Macro: Coverage (duckplyr, zero SQL) ────────────────────
    vig_pair("vig_ma_coverage", '
# Join data stats with FRED metadata (frequency, units, title)
ds <- hd_datasets()[["macro_daily"]]
stats <- duckplyr::read_parquet_duckdb(ds$url) |>
  summarise(Obs = n(), From = min(date), To = max(date), .by = series_id) |>
  arrange(series_id) |>
  collect() |>
  mutate(From = as.character(From), To = as.character(To))
meta <- hd_fred_meta()
stats |>
  left_join(meta, by = "series_id") |>
  select(Series = series_id, Title = title, Freq = frequency,
         Units = units, Obs, From, To)
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

    # ── Factors: Coverage (duckplyr, zero SQL) ──────────────────
    vig_pair("vig_fa_coverage", '
ds <- hd_datasets()[["factors"]]
duckplyr::read_parquet_duckdb(ds$url) |>
  summarise(Obs = n(), From = min(date), To = max(date), .by = c(dataset, frequency, factor_name)) |>
  arrange(dataset, frequency, factor_name) |>
  collect() |>
  mutate(From = as.character(From), To = as.character(To)) |>
  rename(Dataset = dataset, Freq = frequency, Factor = factor_name)
'),

    # ══ LSE ETFs ═════════════════════════════════════════════════

    # ── LSE: Most Liquid ──────────────────────────────────────────
    vig_pair("vig_lse_liquid", '
# Top 5 LSE ETFs by volume, filtered by market cap > MIN_MARKET_CAP
liquid <- hd_search(".*[.]L$") |>
  filter(!is.na(volume_avg), !is.na(market_cap), market_cap > MIN_MARKET_CAP) |>
  slice_max(volume_avg, n = 5)

liquid_data <- hd_ohlcv(liquid$ticker, from = "2022-01-01")

ggplot(liquid_data, aes(date, close, colour = ticker)) +
  geom_line(linewidth = 0.5) +
  scale_y_log10(labels = dollar) +
  scale_colour_manual(values = hd_palette(5)) +
  labs(x = NULL, y = "Close (log scale)", colour = NULL,
       title = paste("Top 5 LSE ETFs by volume (market cap > GBP 250M):",
                     paste(liquid$ticker, collapse = ", "))) +
  hd_theme()
'),

    # ── LSE: FTSE 100 vs Global ───────────────────────────────────
    vig_pair("vig_lse_ftse_vs_global", '
# Compare curated FTSE 100 ETF group vs Global Equity ETF group
ftse_tickers <- hd_group("FTSE 100 ETFs")
global_tickers <- hd_group("Global Equity ETFs (LSE)")

combined <- bind_rows(
  hd_ohlcv(ftse_tickers, from = "2022-01-01") |> mutate(group = "FTSE 100"),
  hd_ohlcv(global_tickers, from = "2022-01-01") |> mutate(group = "Global")
) |>
  group_by(ticker) |>
  mutate(cum_ret = close / first(close) - 1) |>
  ungroup()

ggplot(combined, aes(date, cum_ret, colour = ticker, linetype = group)) +
  geom_line(linewidth = 0.5) +
  geom_hline(yintercept = 0, colour = "grey50", linetype = "dashed") +
  scale_y_continuous(labels = percent) +
  scale_colour_manual(values = hd_palette(length(c(ftse_tickers, global_tickers)))) +
  labs(x = NULL, y = "Cumulative return", colour = NULL, linetype = NULL,
       title = "FTSE 100 ETFs vs Global Equity ETFs (LSE)") +
  hd_theme()
'),

    # ── LSE: GBP vs USD denominated ───────────────────────────────
    vig_pair("vig_lse_currency", '
# Top 3 GBP and top 3 USD LSE ETFs by market cap (> GBP 250M)
lse_meta <- hd_search(".*[.]L$") |>
  filter(!is.na(market_cap), market_cap > MIN_MARKET_CAP)
gbp <- lse_meta |> filter(currency %in% c("GBP", "GBp")) |>
  slice_max(market_cap, n = 3)
usd <- lse_meta |> filter(currency == "USD") |>
  slice_max(market_cap, n = 3)

combined <- bind_rows(
  hd_ohlcv(gbp$ticker, from = "2023-01-01") |> mutate(ccy = "GBP"),
  hd_ohlcv(usd$ticker, from = "2023-01-01") |> mutate(ccy = "USD")
) |>
  group_by(ticker) |>
  mutate(cum_ret = close / first(close) - 1) |>
  ungroup()

ggplot(combined, aes(date, cum_ret, colour = ticker)) +
  geom_line(linewidth = 0.5) +
  facet_wrap(~ccy, ncol = 1, scales = "free_y") +
  scale_y_continuous(labels = percent) +
  scale_colour_manual(values = hd_palette(n_distinct(combined$ticker))) +
  labs(x = NULL, y = "Cumulative return", colour = NULL,
       title = paste("Top 3 by market cap (>GBP 250M). GBP:",
                     paste(gbp$ticker, collapse = ", "),
                     "| USD:", paste(usd$ticker, collapse = ", "))) +
  hd_theme()
'),

    # ── LSE: Fund Families ────────────────────────────────────────
    vig_pair("vig_lse_families", '
# Distribution of LSE ETFs by fund family (market cap > GBP 250M)
lse_meta <- hd_search(".*[.]L$") |>
  filter(!is.na(fund_family), !is.na(market_cap), market_cap > MIN_MARKET_CAP)

family_counts <- lse_meta |>
  count(fund_family, sort = TRUE) |>
  slice_head(n = 15)

ggplot(family_counts, aes(reorder(fund_family, n), n)) +
  geom_col(fill = "#00BFFF") +
  coord_flip() +
  labs(x = NULL, y = "Number of ETFs",
       title = paste(nrow(lse_meta), "LSE ETFs by fund family (market cap > GBP 250M, top 15)")) +
  hd_theme()
'),

    # ── LSE: Highest Yield ────────────────────────────────────────
    vig_pair("vig_lse_yield", '
# Top 10 LSE ETFs by yield (market cap > GBP 250M, yield < 20%)
high_yield <- hd_search(".*[.]L$") |>
  filter(!is.na(yield_pct), yield_pct > 0, yield_pct <= MAX_YIELD_PCT,
         !is.na(market_cap), market_cap > MIN_MARKET_CAP) |>
  slice_max(yield_pct, n = 10) |>
  mutate(yield_label = paste0(round(yield_pct * 100, 1), "%"))

ggplot(high_yield, aes(reorder(ticker, yield_pct), yield_pct * 100)) +
  geom_col(fill = "#32CD32") +
  geom_text(aes(label = yield_label), hjust = -0.1, colour = "white", size = 3.5) +
  coord_flip() +
  labs(x = NULL, y = "Dividend yield (%)",
       title = "Top 10 LSE ETFs by yield (market cap > GBP 250M, yield < 20%)") +
  hd_theme()
'),

    # ── LSE: Coverage ─────────────────────────────────────────────
    vig_pair("vig_lse_coverage", '
# Full metadata table for all LSE ETFs
hd_search(".*[.]L$") |>
  select(ticker, long_name, currency, fund_family, volume_avg,
         yield_pct, beta_3yr, start_date, end_date, total_obs) |>
  arrange(desc(volume_avg))
'),

    # ══ METADATA TABLES (companion to each plot) ═════════════════

    vig_pair("vig_meta_eq_aapl", '
top_ticker <- hd_top_by("equity_daily", "market_cap", 1)$ticker
hd_ticker_meta(top_ticker)
'),
    vig_pair("vig_meta_eq_faang", '
hd_ticker_meta(hd_group("FAANG"))
'),
    vig_pair("vig_meta_eq_vol", '
vol_tickers <- c(hd_most_volatile("equity_daily", 3)$ticker, "SPY")
hd_ticker_meta(vol_tickers)
'),
    vig_pair("vig_meta_cr_major", '
hd_ticker_meta(hd_group("Major Crypto"))
'),
    vig_pair("vig_meta_cr_stable", '
hd_ticker_meta(hd_group("Stablecoins"))
'),
    vig_pair("vig_meta_cr_corr", '
corr_tickers <- hd_top_by("crypto_daily", "volume_avg", 6)$ticker
hd_ticker_meta(corr_tickers)
'),
    vig_pair("vig_meta_lse_liquid", '
hd_ticker_meta(
  hd_search(".*[.]L$") |>
    filter(!is.na(volume_avg)) |>
    slice_max(volume_avg, n = 5) |>
    pull(ticker)
)
'),
    vig_pair("vig_meta_lse_currency", '
lse <- hd_search(".*[.]L$")
gbp_t <- lse |> filter(currency %in% c("GBP", "GBp")) |> slice_max(volume_avg, n = 3) |> pull(ticker)
usd_t <- lse |> filter(currency == "USD") |> slice_max(volume_avg, n = 3) |> pull(ticker)
hd_ticker_meta(c(gbp_t, usd_t))
'),
    vig_pair("vig_meta_lse_yield", '
hd_ticker_meta(
  hd_search(".*[.]L$") |>
    filter(!is.na(yield_pct), yield_pct > 0) |>
    slice_max(yield_pct, n = 10) |>
    pull(ticker)
)
'),
    vig_pair("vig_meta_lse_ftse_global", '
hd_ticker_meta(c(hd_group("FTSE 100 ETFs"), hd_group("Global Equity ETFs (LSE)")))
')
  )
}
