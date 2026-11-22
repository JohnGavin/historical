# Specification Index \[Consolidated specifications for active trade\[XYZ] perpetual markets.]

<table data-v="">
  <thead>
    <tr>
      <th data-type="number">#</th>
      <th>Instrument</th>
      <th>Description</th>
      <th>Underlying</th>
      <th>Max Leverage</th>
      <th>Discovery Bound</th>
      <th data-type="number">Discovery Bound Resets</th>
      <th>Margin Mode</th>
      <th>External Session Hours</th>
      <th>Internal Session Hours</th>
      <th>Funding Rate Multiplier</th>
      <th>Mark Clamp</th>
    </tr>
  </thead>

  <tbody>
    <tr data-market-coin="xyz:SP500">
      <td>1</td>

      <td>
        S&#38;P500
      </td>

      <td>
        S&#38;P500 references the S&#38;P 500 Index, a free-float-capitalization-weighted benchmark of 500 leading publicly-traded U.S. companies, widely regarded as the best single gauge of large-cap U.S. equities. The S&#38;P 500 Index is a product of S&#38;P Dow Jones Indices LLC and has been licensed for use by trade&#91;XYZ&#93;; see https://docs.trade.xyz/legal-and-disclaimers/s-and-p-500-disclaimers.
      </td>

      <td>See <a data-mention="" href="/perpetuals/markets/equity-indices#external-price-derivation">#external-price-derivation</a></td>

      <td>
        50x
      </td>

      <td>±2%</td>
      <td>1</td>
      <td>Cross Margin</td>
      <td>From Sunday 6:00 PM ET to Friday 5:00 PM ET</td>
      <td>Daily maintenance window applies from 5PM ET to 6PM ET, Monday to Thursday. Trading also follows <a href="/perpetuals/specifications-and-schedules/holiday-closures">futures holiday closures</a>.</td>
      <td>0.5</td>
      <td>0.5%</td>
    </tr>

    <tr data-market-coin="xyz:CL">
      <td>4</td>

      <td>
        WTIOIL
      </td>

      <td>
        WTIOIL references the USD price of 1 barrel of WTI Light Sweet Crude Oil. WTI serves as a primary global benchmark for oil prices due to its high quality (low density, low sulfur).
      </td>

      <td>1 barrel of WTI Light Sweet Crude Oil.<br /><br />For current reference contract, see <a data-mention="" href="/perpetuals/specifications-and-schedules/roll-schedules">roll-schedules.md</a></td>

      <td>
        20x
      </td>

      <td>±5%</td>
      <td>2</td>
      <td>Cross Margin</td>
      <td>From Sunday 6PM ET to Friday 5PM ET</td>
      <td>Daily maintenance window applies from 5PM ET to 6PM ET, Monday to Thursday. Trading also follows <a href="/perpetuals/specifications-and-schedules/holiday-closures">futures holiday closures</a>. </td>
      <td>0.5</td>
      <td>1%</td>
    </tr>

    <tr data-market-coin="xyz:GOLD">
      <td>6</td>

      <td>
        GOLD
      </td>

      <td>
        GOLD references the USD spot price of 1 troy ounce of gold (XAU/USD).
      </td>

      <td>XAU / USD </td>

      <td>
        25x
      </td>

      <td>±4%</td>
      <td>2</td>
      <td>Cross Margin</td>
      <td>From Sunday 6PM ET to Friday 5PM ET</td>
      <td>Daily maintenance window applies from 5PM ET to 6PM ET, Monday to Thursday. Trading also follows <a href="/perpetuals/specifications-and-schedules/holiday-closures">futures holiday closures</a>. </td>
      <td>0.5</td>
      <td>0.5%</td>
    </tr>

    <tr data-market-coin="xyz:JPY">
      <td>11</td>

      <td>
        USDJPY
      </td>

      <td>
        USDJPY references the USD/JPY spot exchange rate: Japanese yen per 1 U.S. dollar. The Japanese yen is the official currency of Japan.
      </td>

      <td>USD / JPY </td>

      <td>
        50x
      </td>

      <td>±2%</td>
      <td>1</td>
      <td>Normal Isolated</td>
      <td>From Sunday 5PM ET to Friday 5PM ET</td>
      <td>Trading continues during most US holidays</td>
      <td>0.5</td>
      <td>0.5%</td>
    </tr>

    <tr data-market-coin="xyz:TSLA">
      <td>15</td>

      <td>
        TSLA
      </td>

      <td>
        TSLA references 1 share of Tesla, Inc. common stock (Nasdaq: TSLA), quoted in USD. Tesla designs electric vehicles, energy-storage systems, and related products.
      </td>

      <td>TSLA / USD </td>

      <td>
        20x
      </td>

      <td>±5%</td>
      <td>2</td>
      <td>Cross Margin</td>
      <td>24/5, from Sunday 8:05 PM ET to Friday 8:00 PM ET</td>
      <td>Friday 8:00 PM to Sunday 8:05 PM ET,  and follows <a href="/perpetuals/specifications-and-schedules/holiday-closures">equities holidays & trading hours</a>.</td>
      <td>0.5</td>
      <td>1%</td>
    </tr>

    <tr data-market-coin="xyz:SOXL">
      <td>88</td>

      <td>
        SOXL
      </td>

      <td>
        SOXL references 1 share of the Direxion Daily Semiconductor Bull 3X Shares (NYSE Arca: SOXL), quoted in USD. The fund seeks daily investment results of 300% of the daily performance of the ICE Semiconductor Index, an index of the 30 largest U.S.-listed semiconductor companies; leverage resets daily.
      </td>

      <td>SOXL / USD</td>

      <td>
        10x
      </td>

      <td>10%</td>
      <td>1</td>
      <td>Normal Isolated</td>
      <td>24/5, from Sunday 8:05 PM ET to Friday 8:00 PM ET</td>
      <td>Friday 8:00 PM to Sunday 8:05 PM ET,  and follows <a href="/perpetuals/specifications-and-schedules/holiday-closures">equities holidays & trading hours</a>.</td>
      <td>0.5</td>
      <td>1%</td>
    </tr>

    <tr data-market-coin="xyz:TSM">
      <td>35</td>

      <td>
        TSM
      </td>

      <td>
        TSM references 1 Taiwan Semiconductor Manufacturing Company Limited ADS (NYSE: TSM), representing 5 common shares (TWSE: 2330), quoted in USD. TSMC manufactures semiconductors for third-party customers.
      </td>

      <td>TSM / USD</td>

      <td>
        10x
      </td>

      <td>±10%</td>
      <td>1</td>
      <td>Normal Isolated</td>
      <td>24/5, from Sunday 8:05 PM ET to Friday 8:00 PM ET</td>
      <td>Friday 8:00 PM to Sunday 8:05 PM ET,  and follows <a href="/perpetuals/specifications-and-schedules/holiday-closures">equities holidays & trading hours</a>.</td>
      <td>0.5</td>
      <td>1%</td>
    </tr>

    <tr data-market-coin="xyz:SKHX">
      <td>36</td>

      <td>
        SKHYNIX
      </td>

      <td>
        SKHYNIX references 1 SK hynix Inc. common share (KRX: 000660). The oracle converts the KRW share price to USD at the prevailing USD/KRW FX rate. SK hynix manufactures DRAM and NAND memory semiconductors used in data centers, AI hardware, mobile devices, and computing systems.
      </td>

      <td>000660.KS / USD</td>

      <td>
        10x
      </td>

      <td>±10%</td>
      <td>1</td>
      <td>Cross Margin</td>
      <td>Refer to <a href="/perpetuals/markets/stocks/korea#external-coverage-utc9">Korea External Session</a></td>
      <td>Refer to <a href="/perpetuals/markets/stocks/korea#internal-coverage-gmt9">Korea Internal Session</a></td>
      <td>0.5</td>
      <td>1%</td>
    </tr>

    <tr data-market-coin="xyz:HIMS">
      <td>45</td>

      <td>
        HIMS
      </td>

      <td>
        HIMS references 1 share of Hims &#38; Hers Health, Inc. Class A common stock (NYSE: HIMS), quoted in USD. Hims &#38; Hers operates a consumer health and telehealth platform.
      </td>

      <td>HIMS / USD</td>

      <td>
        10x
      </td>

      <td>±10%</td>
      <td>1</td>
      <td>Normal Isolated</td>
      <td>24/5, from Sunday 8:05 PM ET to Friday 8:00 PM ET</td>
      <td>Friday 8:00 PM to Sunday 8:05 PM ET,  and follows <a href="/perpetuals/specifications-and-schedules/holiday-closures">equities holidays & trading hours</a>.</td>
      <td>0.5</td>
      <td>1%</td>
    </tr>

    <tr data-market-coin="xyz:NIFTY">
      <td>109</td>

      <td>
        NIFTY
      </td>

      <td>
        NIFTY references the native INR level of the NIFTY 50, a free-float capitalization-weighted index of 50 leading Indian equities. No FX conversion is applied; index-point P&#38;L is cash-settled in USDC.
      </td>

      <td>NIFTY / INR</td>

      <td>
        20x
      </td>

      <td>5%</td>
      <td>1</td>
      <td>Normal Isolated</td>
      <td>Refer to <a href="/perpetuals/markets/stocks/india#fo-calendar-equity-derivatives">India FO External Session</a> </td>
      <td>Refer to <a href="/perpetuals/markets/stocks/india#fo-calendar-equity-derivatives">India FO Internal Session</a></td>
      <td>0.5</td>
      <td>0.5%</td>
    </tr>
  </tbody>
</table>

Open interest is capped for all XYZ deployed perps markets, with each market having a dedicated OI cap. Once this cap is reached, new positions cannot be opened until open interest falls below the specified limit; only existing positions may be reduced or closed. These caps are subject to change and will likely be increased over time.&#x20;
