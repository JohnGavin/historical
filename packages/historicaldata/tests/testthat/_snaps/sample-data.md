# macro sample has >= 15 series including SP500

    Code
      sort(series)
    Output
       [1] "CPIAUCSL"   "DCOILWTICO" "DFF"        "DGS10"      "DGS2"      
       [6] "DGS30"      "DTWEXBGS"   "FEDFUNDS"   "GDP"        "PCEPI"     
      [11] "SP500"      "T10Y2Y"     "T10Y3M"     "UNRATE"     "VIXCLS"    
      [16] "VXVCLS"    

# equity sample ticker universe is stable (snapshot)

    Code
      sort(unique(eq$ticker))
    Output
       [1] "AAPL"  "ABBV"  "ABT"   "ACN"   "ADBE"  "AMD"   "AMZN"  "BA"    "BMY"  
      [10] "BRKB"  "CAT"   "COST"  "CSCO"  "CVX"   "DHR"   "DIS"   "GE"    "GOOGL"
      [19] "GS"    "HD"    "HON"   "IBM"   "INTC"  "JNJ"   "JPM"   "KO"    "LIN"  
      [28] "LOW"   "MA"    "MCD"   "META"  "MMM"   "MRK"   "MSFT"  "NEE"   "NKE"  
      [37] "NVDA"  "ORCL"  "PEP"   "PFE"   "PG"    "PM"    "RTX"   "SBUX"  "T"    
      [46] "TMO"   "TSLA"  "TXN"   "UNH"   "UPS"   "V"     "VZ"    "WFC"   "WMT"  
      [55] "XOM"  

# sample fixture schemas are stable (snapshot)

    Code
      schemas
    Output
      $equity_daily
       [1] "adjusted"    "asset_class" "close"       "date"        "high"       
       [6] "low"         "open"        "source"      "ticker"      "updated_at" 
      [11] "volume"     
      
      $crypto_daily
       [1] "asset_class" "close"       "date"        "high"        "low"        
       [6] "open"        "source"      "ticker"      "updated_at"  "volume"     
      
      $macro_daily
      [1] "date"      "series_id" "source"    "value"    
      
      $factors
      [1] "dataset"     "date"        "factor_name" "frequency"   "source"     
      [6] "updated_at"  "value"      
      
      $metadata
       [1] "asset_class"         "beta_3yr"            "category"           
       [4] "country"             "currency"            "dataset"            
       [7] "end_date"            "exchange"            "expense_ratio"      
      [10] "fifty_two_week_high" "fifty_two_week_low"  "full_exchange"      
      [13] "fund_family"         "industry"            "instrument_type"    
      [16] "long_name"           "market_cap"          "missing_pct"        
      [19] "nav_price"           "quote_type"          "sector"             
      [22] "short_name"          "source"              "start_date"         
      [25] "three_yr_return"     "ticker"              "total_obs"          
      [28] "volume_avg"          "yield_pct"           "yield_type"         
      [31] "ytd_return"         
      

