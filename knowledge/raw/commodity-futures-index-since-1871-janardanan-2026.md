# RAW: "An Index of Commodity Futures Returns Since 1871" (Janardanan, Qiao, Rouwenhorst 2026)

> Provenance (append-only raw source — do not edit)
> - Source URL: https://papers.ssrn.com/sol3/papers.cfm?abstract_id=6276738 (SSRN abstract 6276738)
> - Via: https://quantpedia.com/an-index-of-commodity-futures-returns-since-1871/?a=6080
> - Authors: Rajkumar Janardanan (SummerHaven Investment Management), Xiao Qiao (City University of Hong Kong), K. Geert Rouwenhorst (Yale School of Management)
> - Date: January 2026 (chapter; underlying database = Janardanan et al. 2025)
> - Retrieved: 2026-05-25 by Claude Code session (branch feat/cc-20260525-094735)
> - Method: manual PDF save (SSRN Cloudflare-blocked); text via `pdftotext -layout` (poppler-utils)
> - Related issues: #280, #273, #138, #98
> - NOTE: equations/subscripts render imperfectly via pdftotext; consult the source PDF for exact formulae.

---

              An Index of Commodity Futures Returns Since 1871*


                                      Rajkumar Janardanan
                                SummerHaven Investment Management

                                               Xiao Qiao
                                      City University of Hong Kong

                                         K. Geert Rouwenhorst
                                       Yale School of Management



                                               January 2026



                                           Abstract
This paper documents the returns to a broadly diversified index of commodity futures over more
than 150 years of U.S. market history, that accounts for survivorship bias. We find that commodity
futures have earned an average annual risk premium of 5.4% over the risk-free rate and a premium
over US inflation of more than 6% per annum. Commodity futures have outperformed equities in
roughly 43% of years and in two out of every five decades, suggesting distinct return drivers and
meaningful diversification benefits. Futures returns have exceeded spot price returns on an
interest-adjusted basis, consistent with the presence of a risk premium beyond spot price
appreciation.




* We have benefited from comments and suggestions from Roger Ibbotson, David Reiffen, and Larry Siegel.
1. Introduction

Commodity futures have long played a pivotal role in the global economy, facilitating price
discovery and risk management across sectors ranging from agriculture to energy and industrial
production. Despite their economic significance, the classification of commodity futures as a
distinct asset class remains a subject of debate. To qualify as an asset class, Sharpe (1992) and
the CFA Institute emphasize shared risk-return characteristics and common responses to
economic forces as key criteria.1

While commodity futures share common attributes, such as providing price insurance and
exposure to inflation-sensitive assets, their classification as a distinct asset class therefore hinges
on whether they exhibit consistent risk and return characteristics over time. This question is
fundamentally empirical, requiring a long-term analysis of historical performance across a
variety of economic regimes.

This chapter documents the returns to a broadly diversified index of commodity futures, covering
more than 150 years of economic, financial, and institutional development. The analysis is based
on a uniquely constructed dataset that draws from exchange yearbooks when available and relies
extensively on newspaper archives to fill gaps in coverage. By including both active and obsolete
contracts, the resulting index reflects the evolving structure of futures markets and captures the
performance of a broad array of commodities, many of which are no longer traded today.2

This chapter is organized as follows. We begin by defining the return earned by an investor in
commodity futures and discuss how this differs from the return on holding physical
commodities. We then discuss the data and the construction of our commodity futures index.
Next, we examine the time-series behavior of the commodity futures index and compare its
performance to that of a diversified index of U.S. equities. This comparison highlights the
distinct return dynamics and volatility profiles of futures-based investments relative to other
asset classes. We also compare our collateralized commodity index to the cumulative inflation
rate to understand real returns over time.


1
  According to Sharpe (1992) an asset class is “a collection of assets that have similar attributes and provide
comparable risk and return characteristics over time.” The definition given by the CFA Institute emphasizes “similar
risk and return profiles as well as similar responses to common economic forces.”
2
  For a detailed description of the database, see Janardanan et al. (2025).


                                                         1
The main findings are that over the past 155 years:

    1. Commodity futures have earned a risk premium over the risk-free rate of 5.5%
    2. Commodity futures have outperformed U.S. stocks in two out of every five years.
    3. The return to commodity futures has exceeded an index of U.S. inflation by more than
        6% per annum.

Finally, we highlight the distinction between futures and spot returns through a decomposition of
futures excess returns into spot returns and the roll yield.

In Section 2, we define the excess return and collateralized return to commodity futures. Readers
who are familiar with these concepts can skip to Section 3 without loss of continuity.



2. Definition of Collateralized Commodity Futures Returns

When evaluating the investment performance of commodities, it is important to draw a
distinction between investing in commodity futures versus the underlying physical commodities.
A futures contract is a standardized agreement to buy or sell some physical good or financial
asset (the “underlying”) at a pre-specified time in the future. The futures price itself is not the
cost of entering into a futures contract, but rather an agreed-upon reference from which gains and
losses are tallied.

At the initiation of a futures contract, no cash changes hands between the buyer and the seller, as
the futures price is set such that the value of the contract is zero at origination. As the futures
price changes, futures buyers and sellers may be required to post collateral to alleviate
counterparty risk, but the collateral remains theirs, can be placed in interest-bearing securities
(commonly Treasury bills), and is therefore not a “cost” to the investor.

In contrast to futures, a spot transaction to buy or sell physical commodities does require a
transfer of cash to open the position. A spot transaction is therefore a fully funded investment
similar to buying or selling stocks without a margin loan.

The return dynamics differ too. An investor in physical markets benefits from an increase in the
(spot) price of the commodity but incurs the cost of “carrying” the commodity. The cost of carry
includes storage fees, insurance costs, and loss associated with spoilage. In an efficient market,


                                                   2
the futures prices will embed market expectations about future spot price movements, so a long
futures investor will benefit from unexpected spot price increases but expected spot price
changes are not a source of returns for a futures investor. We will discuss the difference between
futures returns and spot returns in more detail in Section 6.

Let 𝐹!" denote the futures price at time 𝑡 of a contract that matures at time 𝑇. The futures excess
return is then calculated as follows:

                                                       "
                                           &,"       𝐹!$%
                                         𝐸𝑅!,!$% =        −1        [1]
                                                      𝐹!"

  &,"
𝐸𝑅!,!$% is an excess return because no cash changes hands when a futures position is initiated. To
facilitate a comparison of a futures excess return to funded investments such as stocks or
physical commodities, we assume that the “funding” for the futures position is invested in a risk-
free investment. This is also how in practice “fully collateralized” commodity indices are
constructed – as a holding of T-Bills supporting a position in futures.

The total return of a fully collateralized futures position is given by:

                                         &,"       &,"
                                       𝑇𝑅!,!$% = 𝐸𝑅!,!$% + 𝑟!         [2]

where 𝑟! is the one-period risk-free rate. Because the collateral is invested in the risk-free asset,
the risk of the collateralized futures position is identical to that of the excess return. Therefore,
the excess return on the collateralized futures position has the interpretation of the commodity
futures risk premium (over the riskless asset).

A common economic explanation for the presence of a risk premium in commodity futures is to
compensate the long side of the contract for absorbing the excess demand for short hedging of
price risk in the underlying physical markets. First hypothesized by Keynes (1930), there is a
long academic literature on what is commonly known as the Theory of Normal Backwardation.3



3. Data and Index Construction



3
    See reviews by Gray and Rutledge (1971) and Rouwenhorst and Tang (2012).


                                                        3
3.1 Data Sources

Despite the long history of commodity futures trading, few comprehensive databases of
historical price records exist. One of the most popular commercial datasets, offered by
Commodity Research Bureau (now Barchart), goes back to 1959. Dow Jones published a
commodity index in 1933, but it was primarily used to track spot prices (Bhardwaj, Janardanan,
and Rouwenhorst 2021). Two recent efforts to collect historical data (Levine et al. 2018; Geczy
and Samanov 2019) cover very few contracts prior to 1950.

The data used in this chapter draws from a hand-collected dataset of 230 contracts going back to
1871 when futures trading commenced in the United States. This comprehensive dataset
combines prices from prominent newspapers with exchange handbooks. A unique and important
aspect of the database is the extensive coverage of contracts that have ceased trading over time.
Janardanan et al. (2025) show that poor investor performance is negatively correlated with
contract survival. Hence, it is important to include non-surviving contracts when evaluating the
investment performance of commodity futures.

We complement our futures data with other datasets used in subsequent analysis and comparison.
For the risk-free rate we use the 3-month Treasury Bill: Secondary Market Rate from Federal
Reserve Economic Data (FRED) from 1934 to 2025, the Ibbotson Associates 30-Day Treasury
Bill Total Returns from 1926 to 1934, and values obtained from Siegel (1992) prior to 1926. We
use the all-cap composite portfolio from Ibbotson Equity IndicesTM to represent the performance
of the aggregate U.S. stock market, kindly provided by Roger Ibbotson and described elsewhere
in this volume. As the Ibbotson IndicesTM start in 1926, we use the market-capitalization
weighted portfolio of all stocks from the Cowles Foundation from 1871 through 1925.

Finally, inflation data are obtained from the Federal Reserve Bank of St. Louis. From 1913 to
2025, we use the monthly series Consumer Price Index for All Urban Consumers: All Items in
U.S. City Average, not seasonally adjusted (CPIAUCNS). From 1871 to 1912, inflation figures
are calculated from Robert Shiller’s CPI data used in his book Irrational Exuberance (Shiller
2000).

3.2 Index Construction




                                                4
The construction of an index of commodity futures returns requires a number of choices
regarding the tenor (time to maturity) of the contract and the roll schedule.

   (i)     Contract maturity: at the end of month t, the index tracks for each commodity the
           nearest-to-maturity contract that does not mature in month t+1. This ensures that the
           index is invested in what is typically the “front” contract, which is typically the most
           liquid portion of the futures curve.
   (ii)    Commodity weighting: especially in the early days of futures trading, similar
           commodities are traded on multiple exchanges. For example, wheat was traded in
           Buffalo as well as Chicago, and Chicago offered multiple Turkey contracts. For the
           purpose of index calculation, “similar” contracts on the same underlying commodities
           on the same exchange are treated (averaged) as one, but commodities that trade on
           different exchanges are always treated as separate commodities.
   (iii)   Commodities receive equal index weights and the index is rebalanced monthly.

                                                                       &,"
In a given month the index total return is defined as follows, where 𝑇𝑅',!,!$% is the total return of
commodity 𝑖 and 𝑁! is the number of commodities in month 𝑡.

                                            *!
                                                    &,"
                                 ()
                                                  𝑇𝑅',!,!$%
                               𝑇𝑅!,!$% =1                          [3]
                                                    𝑁!
                                            '+%




4. Index Returns

4.1 Annual Returns

Figure 1 is a pictorial representation of annual total returns for the collateralized equally-
weighted (EW) commodity futures index. A time series of annual total returns can be constructed
from the data labels in the four panels. The advantage of having a bar plot along with specific
values combines the ease of visual inspection of return sizes and dynamics with the precision of
exact figures for each calendar year.

In its early history, toward the end of the 19th century, the index performed poorly due to a string
of negative returns, despite experiencing one of the largest single-year returns in its 150-year


                                                   5
history (54.2% in 1879). This period was marked by large increases in cultivated farmland and
technological improvements (such as railways and tractors) in a largely deflationary environment
that saw a steady decrease in consumer prices.

A remarkable string of positive annual total returns followed this period, from 1897 to 1919. The
period between World War I and World War II was marked by large total returns of either sign,
indicating heightened uncertainty in the resources markets. A more tranquil phase followed World
War II, with many years exhibiting returns with relatively small magnitudes, mostly positive,
between 1950 and 1970.

The 1970s were again a turbulent decade, with several events putting inflationary pressure on
commodity prices such as the energy crisis of 1973 and the “Great Grain Robbery” in 1972, which
saw the Soviet Union purchase massive amounts of grain from the United States at subsidized
prices, subsequently causing global prices to soar. A period of mostly positive returns spans 1987
to 2010, although consecutive positive years are interrupted by a few negative ones such as 2008.
No clear pattern emerges from the most recent 15 years of history.

To provide a sense of the breadth of the index and the ebb and flow of commodity contracts over
time, Figure 1 tracks the number of index constituents in each year at the bottom of each panel.
During the first decade, the index comprised fewer than 20 commodities, reflecting the gradual
expansion of commodity futures markets in the U.S. By the turn of the 20th century, the index
covered about 30 distinct commodity futures, growing to 50 by the early 21st century. The two
World Wars were periods of index contraction due to trading suspensions and market closures.



5. Commodity Futures versus Equities

5.1 Cumulative performance

Figure 2 illustrates the cumulative total returns of commodities and stocks over 150 years versus
cumulative inflation, plotted on a log scale to visualize changes in average returns over time.
Three observations stand out:




                                                 6
    1. A long position in commodity futures has historically earned a positive risk premium that
        is similar in magnitude to the equity risk premium, as evidenced by the similar average
        slope of the two indexes on a logarithmic scale.
    2. Returns to commodity futures and equities have historically exceeded inflation by a wide
        margin.
    3. The commodity risk premium has historically accrued in different periods than the equity
        risk premium, as evidenced by the divergence and subsequent convergence of the two
        performance lines.

The first observation is evident from comparing the futures and equity lines in Figure 2. Those
who are skeptical about the presence of a historical risk premium would have to explain why the
two lines have tracked each other closely over a 150-year period. For others, the presence of a
historical risk premium can provide direct evidence of an important requirement for qualification
as an asset class.

As Janardanan et al. (2025) show, the index risk premium stems in large part from risk premia
embedded in the pricing of the individual index constituents. These authors show that the
majority of the 230 futures contracts that make up the index have earned a positive average
excess return over their lifetimes. In this respect commodity futures fit well with Sharpe’s (1992)
definition of an asset class as “a collection of assets that have similar attributes and provide
comparable risk and return characteristics over time.” The second observation is self-evident
from the discrepancy between the cumulative returns to commodity futures and equities, on one
hand, and cumulative inflation on the other.

5.2 Differential performance and diversification

The third observation is more clearly illustrated in Figure 3, which plots the annual difference
between the return to stocks and the return to commodity futures over the past 150 years. A
positive bar indicates a year where commodity futures outperformed equities, while a negative
bar indicates underperformance of commodities relative to equities. The solid line tracks the 10-
year trailing return difference of commodities over stocks. Two observations stand out:

    1. There is large variability in the annual return difference between commodities and stocks.




                                                  7
    2. Commodities have outperformed equities in two out of every five years historically.
         Similarly, in two out of every five historical 10-year periods, commodities outperformed
         equities.

The first finding suggests that commodity futures and equities have distinct fundamental risk
drivers. If they had significant common drivers, we would expect to observe high co-movement
of returns, and little variation in the return difference between the two indices. But we do not. In
other words, commodities as a whole have a high “tracking error” relative to equities, marked by
idiosyncratic movement in the respective asset classes. The second finding points at the potential
diversification benefits of commodity futures. A portfolio that allocates to commodities and
equities, rather than just equities, benefits from improved performance in the 40% of years that
equities underperform commodities.



6. A Decomposition of Commodity Futures Returns

In this section, we discuss how the collateralized futures return differs from the spot return. The
             ,
spot return 𝑅!,!$% is defined as follows:

                                            ,
                                                       𝑆!$%
                                           𝑅!,!$% =         −1         [4]
                                                        𝑆!

where 𝑆 is the spot price of the commodity. The standard way to describe the link between the
spot return [equation 4] and the excess futures return [equation 1] when rolling futures forward is
through the approximate expression:

                                 &,"      ,
                               𝐸𝑅!,!$% = 𝑅!,!$% + 𝑅𝑜𝑙𝑙 𝑌𝑖𝑒𝑙𝑑!,!$%                   [5]

“Rolling futures forward” refers to closing out the front contract and opening a comparable
position in the next-closest to maturity contract. The roll yield, also known as “carry,” is the
slope of the futures curve between the two contracts.4 When the futures curve slopes downward,




4
 See, for example, Bessembinder (2018) for an in-depth discussion on why the roll yield should not be interpreted
as a cash flow to a futures investor. Also see Gorton et al. (2013), Erb and Harvey (2016), Koijen et al. (2018), and
Levine et al. (2018).


                                                          8
the roll yield will be positive; this condition is called backwardation; when the futures curve
slopes upward (called contango), the roll yield will be negative.

The Theory of Storage (Kaldor, 1939; Working, 1949) can be used to decompose the roll yield
into: (1) the benefits of holding the spot commodity, called the convenience yield (y); and (2) the
cost of carrying physical inventories, which is the sum of the foregone interest (r) and direct
storage costs (u):

                          𝑅𝑜𝑙𝑙 𝑌𝑖𝑒𝑙𝑑!,!$% = 𝑦!,!$% − (𝑟! + 𝑢! )          [6]

Note that equation [5] links the futures excess return (excluding collateral) to the spot return
which is a funded investment. To facilitate a more meaningful comparison, we follow Levine et
al. (2018), and combine equations [5] and [6] to express the difference between the futures and
spot in excess return form:

                       &,"       ,
                     𝐸𝑅!,!$% − (𝑅!,!$% − 𝑟! ) = (𝑦!,!$% − 𝑢! )                 [7]

where (y – u) is referred to as the “interest-adjusted carry.”

The intuition for the difference in [7] is that the convenience yield (net of storage) is a benefit
embedded in the spot price of the physical commodity related to its use as an input in the
productive process. It is accrued to the futures investor as the futures price converges to the spot
prices at the maturity of a futures contract.

As pointed out in Section 2, Keynes’ Theory of Normal Backwardation predicts that the first
term on the left-hand side of [7] is positive. By contrast, neither Keynes nor the Theory of
Storage make a direct prediction about the overall sign of [7]. Whether the convenience yield has
historically exceeded storage costs is an empirical matter, which we explore in Figure 4.

The historical evolution of the components of equations [5] and [7] for the equally weighted
index are illustrated in the two panels of Figure 4, which show that:

   1. The futures excess return has historically lagged the spot return due to the cumulative
       effect of negative carry (roll yield) over the past 150 years.
   2. The futures excess return has historically exceeded the spot price excess return (positive
       interest-adjusted carry).



                                                  9
The first finding empirically underscores the important observation that a negative roll yield does
not preclude investors from earning a positive risk premium. The second finding implies that
when collateral returns are included, futures returns have historically exceeded spot price returns.
This is the case even before taking into account storage costs which would be necessary for
calculating the return to carrying physical inventories.



7. Summary of Asset Class Performance

We quantitatively summarize our results in Table 1, which provides average returns, volatility,
and Sharpe ratios of collateralized commodity futures, stocks, Treasury bills, and inflation over
the 1871-2025 period. The top panel shows that the equally-weighted commodity futures index
has earned a risk premium of 5.5%, with annualized volatility of 14.3%, and a Sharpe ratio of
0.38. For comparison, the stock index has a risk premium of 6.6% and a volatility of 16.2%,
which results in a Sharpe ratio of 0.41. The commodity spot index has the same volatility as the
commodity futures index, but a markedly lower Sharpe ratio (0.22). The risk-adjusted returns are
similar for commodity futures and stocks, and exceed the risk-adjusted performance of the
commodity spot index.

To examine Sharpe’s (1992) requirement that an asset class “provides comparable risk and return
characteristics over time,” we split the 155 years of the sample into three periods of similar
length (roughly 50 years each). The basic observations from the full sample statistics continue to
hold for the sub-samples: Nearly identical volatility for commodity futures and spot returns,
similar risk-adjusted returns for commodity futures and stocks, and a substantially lower risk-
adjusted return for the commodity spot index.

There does remain some sample-specific variation across different time periods. In the first sub-
period from 1871 to 1922, commodity spot returns show little appreciation, recording a near zero
geometric mean. In contrast, commodity futures in this period earn a risk premium of 5.1%,
nearly 2% higher than stocks. From 1923 to 1974, commodity futures have a lower volatility
than stocks but exhibit a higher Sharpe ratio (0.48 versus 0.38). The most recent sub-period saw
the highest return and Sharpe ratio for equities. Perhaps the most striking aspect of Table 1 is the
consistency of the 50-year commodity futures performance. Fifty-year averages of geometric



                                                 10
total returns fall in a narrow range of 7.8 to 8.7% versus 6.5 to 12.6% for stocks. Similarly, the
range of Sharpe ratios (0.31 to 0.48) is close to its full sample mean of 0.38, and shows less
variability than the Sharpe ratios for stocks (0.29 to 0.57) versus its full sample mean of 0.41.



8. Conclusion

Long-term returns provide critical input to inform investors about the properties of an asset class,
especially when the underlying asset class constituents are volatile. This chapter presents a 155-
year history of commodity futures markets. Leveraging a unique hand-collected dataset, we
present annual returns and cumulative returns to an index of commodity futures, and compare its
performance to the aggregate stock market, inflation, and spot returns. Like stocks, commodity
futures have a positive risk premium. Returns to commodity futures deviate from stocks in ways
that provide periodic outperformance, likely due to different fundamental drivers of returns.
While volatile over shorter investment horizons, the index performance has shown consistent
performance over long horizons – a critical requirement for any asset class.




                                                 11
References

Bessembinder, Hendrik. 2018. The ‘roll yield’ myth. Financial Analysts Journal 74: 41-53.

Bhardwaj, Geetesh, Rajkumar Janardanan, and K. Geert Rouwenhorst. 2021. The first
commodity futures index of 1933. Journal of Commodity Markets 23, 100157.

Erb, Claude, and Campbell Harvey. 2006. The strategic and tactical value of commodity futures.
Financial Analysts Journal 62: 69-97.

Erb, Claude, and Campbell Harvey. 2016. Conquering misperceptions about commodity futures
investing. Financial Analysts Journal 72: 26-35.

Geczy, Christopher, and Mikhail Samanov. 2019. Two centuries of commodity futures premia:
Momentum, value, and basis. Working paper,
https://papers.ssrn.com/sol3/papers.cfm?abstract_id=3336406.

Gorton, Gary, and K. Geert Rouwenhorst. 2006. Facts and fantasies about commodity futures.
Financial Analysts Journal 62: 47-68.

Gorton, Gary, Fumio Hayashi, and K. Geert Rouwenhorst. 2013. The fundamentals of
commodity futures returns. Review of Finance 17: 35-105.

Gray, Roger W. and David J. S. Rutledge. 1971. The economics of commodity futures markets.
Review of Marketing and Agricultural Economics 39: 57-108.

Janardanan, Rajkumar, Xiao Qiao, and K. Geert Rouwenhorst. 2024. The flipside of financial
innovation: Why contracts fail. https://papers.ssrn.com/sol3/papers.cfm?abstract_id=4730746.

Kaldor, Nicholas. 1939. Speculation and economic stability. Review of Economic Studies 7: 1-27.

Keynes, John M., 1930. A treatise on money, London: Macmillan & Co.

Koijen, Ralph S., Tobias J. Moskowitz, Lasse Heje Pedersen, and Evert B. Vrugt. 2018. Carry.
Journal of Financial Economics 127: 197-225.

Levine, Ari, Yao Hua Ooi, and Matthew Richardson. 2018. Commodities for the long run.
Financial Analysts Journal 74: 55-68.




                                               12
Sharpe, William F. 1992. Asset allocation: Management style and performance measurement.
Journal of Portfolio Management 18: 7-19.

Shiller, Robert J. 2000. Irrational Exuberance. Princeton, NJ: Princeton University Press.

Siegel, Jeremy J. 1992. The real rate of interest from 1800-1990: A study of the U.S. and U.K.
Journal of Monetary Economics 29: 227-252.

Rouwenhorst, K. Geert and Ke Tang. 2012. Commodity investing. Annual Review of Finance
and Economics 4: 447-467.

Working, Holbrook. 1949. The theory of price of storage. American Economic Review 39: 1254-
1262.




                                               13
       Figure 1: Annual Total Returns of Equally-Weighted Commodity Futures Index

The figure provides annual total returns of the equally-weighted commodity futures index. The number of index
constituents is shown at the bottom of each panel.

                                                     Panel A




                                                     Panel B




                                                       14
Panel C




Panel D




  15
                 Figure 2: Cumulative Total Returns of Commodities and Stocks,
                                January 1871–December 2025

The figure shows cumulative total returns for the collateralized commodity futures and stock indexes, as well as
cumulative inflation.




                                                      16
                                 Figure 3: Difference in Annual Returns between Commodities and Stocks,
                                                       January 1871—December 2025

The figure presents the difference in annual returns between the equally-weighted commodity futures index and the stock index in a bar plot. The trailing 10-year
moving average of the annual differences is shown as a line.




                                                                              17
                           Figure 4: Decomposition of Futures Excess Returns

The figure plots the cumulative commodity futures excess returns along with two decompositions. Panel A
decomposes futures ER into spot total returns and carry. Panel B decomposes futures ER into spot excess returns and
interest rate-adjusted carry.

                                      Panel A: Spot Total Returns and Carry




                                                        18
Panel B: Spot Excess Returns and Interest Rate-Adjusted Carry




                             19
                  Table 1: Summary Statistics for Commodity and Stock Indexes

This table includes summary statistics for commodity futures, commodity spot, and stock indexes, as well as for the
risk-free rate and inflation. Both total returns (TR) and excess returns (ER) are expressed as percent per annum.



!"#A%C'ECFG%%C+"I-%A.C/M1/2P4PR
                     'ST8VIA8T:C AABIA8ST:C 'ST8VIA8T:C AABIA8ST:C                          aB%"8T%T8EC    +V"S-AC
                   ;A"#C<=C>?@ ;A"#C<=C>?@ ;A"#CC=C>?@ ;A"#CC=C>?@                            >?@           ="8TB
cBIIBdT8EC
                            Mhi              MhP              RhR              MhR            /Mhk          4hkM
FG8GSAeCf#dAJ
cBIIBdT8EC+-B8C
                            lh1              RhM              khP              PhP            /Mhk          4hPP
f#dAJ

+8B:mCf#dAJ                /4h/              ihP              lhl              RhR            /lhP          4hM/

=Tem2FSAAC="8A              khR              khR               2                2              4h1             2

f#n%"8TB#                   PhP              Ph/               2                2              khR             2




!"#ABC'ECFG+FIF-..
                       /M12P4A21RC <A=4A2M1RC  /M12P4A21RC <A=4A2M1RC                       ?=B"21B12@C    AP"MBAC
                      SA"#CT8CV:; SA"#CT8CV:; SA"#C>8CV:; SA"#C>8CV:;                         V:;           8"21=
C=44=a12@C
                            GJ-              +JG              hJF              iJ-            FMJk          lJiF
Ec2cMAdCe#aAf
C=44=a12@CAB=2C
                            hJh              kJ.              FJG              lJk            FMJk          lJFF
e#aAf

A2=RmCe#aAf                 +Jl              MJh              iJ.              .JM            FFJi          lJ.-

81dmIEMAAC8"2A              iJ+              iJG               I                I              lJ.             I

e#nB"21=#                   lJ+              lJM               I                I              hJh             I




                                                         20
!"#A%C'ECFG+I-FG./
                      M12P4RAP2SC =A>RAP12SC  M12P4RAP2SC =A>RAP12SC   @>%"P2%2PAC   B4"1CAC
                     TA"#C8VC:;< TA"#C8VC:;< TA"#C?VC:;< TA"#C?VC:;<     :;<          V"P2>
'>RR>a2PAC
                         GJI         hJ.          iJG        iJF         F/J/        MJ/h
EcPc1AdCe#aAf
'>RR>a2PACBC>PC
                         .JF         iJ+          /J.        IJ.         F/J/        MJII
e#aAf

BP>SkCe#aAf             FMJ+         hJl          .Jh        lJG         +MJI        MJIh

V2dk-E1AACV"PA           +J/         +J/           -          -           MJi          -

e#m%"P2>#                +J+         +J+           -          -           +J+          -




!"#A%CDECFG+I-./.I
                      M12P4RAP2SC =A>RAP12SC  M12P4RAP2SC =A>RAP12SC   @>%"P2%2PAC   B4"1CAC
                     TA"#C8VC:;< TA"#C8VC:;< TA"#C?VC:;< TA"#C?VC:;<     :;<          V"P2>
a>RR>E2PAC
                         hiM         hi.          kil        liM         FFiM        /il+
cdPd1AeCf#EAJ
a>RR>E2PACBC>PC
                         +ik         MiG          liF        .ik         FFih        /i.M
f#EAJ

BP>SmCf#EAJ             Fli.        F.iM          hiG        +iG         FIiI        /iI+

V2em-c1AACV"PA           kil         kik           -          -           Fi/          -

f#n%"P2>#                liM         li+           -          -           Fil          -




                                             21
