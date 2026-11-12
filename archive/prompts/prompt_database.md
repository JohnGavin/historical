Objective: Build a historical database of clean data for backtesting purposes.
+ research, plan and leverage existing R packages for all sources
+ python ok, if it offers material advantages


+ Datasets to be used by lots of projects related to trad finance and crypto/defi
+ Wrap output into one or more R datapackages 
	+ per database
	+ but make it available to python too. 
		+ e.g. duckdb and/or parquet/arrow format.

# Target asset classes
+ Equity stocks
+ Equity indices and sectors/subindices
+ Crypto currencies 
	+ e.g. major coins on solana ecosystem, such as SOL, USDC, USDT
	+ e.g. non-solana coins with greater liquidity, like BTC and ETH.


# build your own database relative to one off download
+ compared to one off download (see references below)
	+ reproducible
	+ updatable
	+ avoids dataset staleness
		+ i.e. one off download with period updates to append latest data


# Equity sources
+ e.g. yfinance (Yahoo Finance API)
+ e.g. Alpha Vantage (free tier)
+ leverage existing R packages

## Example

+ bulk download all NASDAQ OHLCV daily/hourly
+ clean CSV output
+ scalable to 1000+ stocks
+ as long a history as possible


# Data cleaning
+ different options for handling missing data.
	+ e.g. imputation, last observarion carried forward (locf), interpolation, smoothing via rolling window etc.
+ cross reference multiple sources for verification
	+ e.g. closing prices from two or more sources within tolerance
	+ e.g. download static database and build our dataset manually so that we compare sources to verify both


# One off static datasets 
## for stocks, indices, sectors
+ NASDAQ stocks + index
	+ https://www.kaggle.com/datasets/jacksoncrow/stock-market-dataset
	+ Covers all NASDAQ tickers
	+ Daily OHLCV per ticker
	+ Public domain (CC0)
	+ Stored per-symbol CSV

+ S&P 500 stocks + index
	+ S&P 500 historical datasets 
+ Nifty 50
	+ Nifty 50 Historical Stock Data 
		+ 25 Years with Fundamentals
	+ https://www.kaggle.com/datasets/kalyan197/nifty50-stocks1999-2026-daily-ohlcv-and-fundamentals

+ US Stock Market Dataset 
	+ https://www.kaggle.com/datasets/asadullahcreative/us-stock-market-historical-ohlcv-dataset
	+ ~184k rows
	+ 120 major US stocks
	+ Clean OHLCV 
	+ sectors
	+ No missing values
	+ cross-sectional work

+ index datasets (DataLab)
	+ https://www.datacamp.com/datalab/datasets/dataset-r-stock-exchange
	+ Daily index-level data 
		+ (not individual stocks)
	+ Long history (multi-decade)
	+ Sector-specific datasets (energy, banks, etc.)


## for crypto/defi
+ AWS Open Data
+ Hugging Face datasets
+ search both for 
	+ crypto
	+ order book data



