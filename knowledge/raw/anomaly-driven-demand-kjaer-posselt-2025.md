# RAW: "Anomaly-Driven Demand" (Kjær & Posselt) — primary paper behind #279

> Provenance (append-only raw source — do not edit)
> - Source URL: https://www.conftool.org/cavalcade-asia-pacific-2025/index.php/Posselt-Anomaly-driven_demand-212.pdf (Cavalcade Asia-Pacific 2025)
> - Authors: Mads Markvart Kjær & Anders Merrild Posselt (Aarhus University; Danish Finance Institute)
> - Version: November 11, 2025
> - Cited by: Swedroe blog 2026-05-22 (see swedroe-anomaly-driven-demand-2026-05-22.md)
> - Retrieved: 2026-05-25 by Claude Code session (branch feat/cc-20260525-094735); fetched directly (not Cloudflare-blocked)
> - Method: text via `pdftotext -layout` (poppler-utils)
> - Related issues: #279, #160, #271
> - NOTE: full 1755-line extraction; tables/equations render imperfectly — consult source PDF for exact figures.

---

                     Anomaly-driven demand∗



                   Mads Markvart Kjær†              Anders Merrild Posselt‡




  ∗
      We thank Magnus Dahlquist, Clifton Green, Stig Vinther Møller, Michaela Pagel, Cameron Peng,
Christopher Polk, and conference and seminar participants at Frontiers of Factor Investing 2024, SGF
2025, and Aarhus University for many constructive comments and suggestions. The authors were par-
tially funded by a grant from the Danish Council for Independent Research (DFF - 0133-00151B).
    †
      Department of Economics and Business Economics, Aarhus University, Fuglesangs Allé 4, DK-8210
Aarhus V, Denmark, and the Danish Finance Institute (DFI). Email: mads.markvart@econ.au.dk.
    ‡
      Department of Economics and Business Economics, Aarhus University, Fuglesangs Allé 4, DK-8210
Aarhus V, Denmark, and the Danish Finance Institute (DFI). Email: amp@econ.au.dk.
                    Anomaly-driven demand


                                         Abstract

     We examine the impact of rebalancing by anomaly investors on stock prices. To
     do this, we introduce a simple proxy for anomaly-driven demand. Our proxy cap-
     tures demand and supply arising from updates in the information set of anomaly
     investors. Empirically, we find that stock returns are increasing in our proxy with
     the effect primarily occurring at the beginning of the month. This points to a
     significant rebalancing effect by anomaly investors. Our findings suggest that by
     merely targeting the risk premia associated with different anomalies, anomaly in-
     vestors impact stock prices.




Keywords: Anomalies, Investor rebalancing, Factor investing
JEL Classification: G11, G12
This version: November 11, 2025
1. Introduction

The financial literature has documented hundreds of different cross-sectional relations
between firm characteristics and stock returns. The hurdle for these "anomalies" to be-
come well-published is typically high t-statistics and alphas, which, in terms of invest-
ment performance, translate into high Sharpe ratios and low market correlation—both
highly desirable attributes for fund managers. Consequently, the research on anomalies
has impacted the investment industry substantially, and a vast array of mutual funds,
hedge funds, and ETFs now engage in factor investing, collectively overseeing trillions
of dollars under management (Wigglesworth, 2018, Ang, 2019, Morningstar, 2022). This
widespread adoption has created what we refer to as an anomaly-driven demand for
stocks; demand for specific stocks arising from investors targeting stock anomalies. In
this paper, we investigate whether anomaly-driven demand has a pricing impact on stocks.
   Broadly speaking, anomaly-driven demand operates thorugh two distinct channels.
The first channel arises when anomaly investors allocate new capital in accordance with
the targeted anomalies. This mechanism has already been shown to affect prices (Huang,
Song, and Xiang, 2019, Ben-David, Li, Rossi, and Song, 2022, Li, 2022). The second
channel stems from updates to investors’ information sets—or, in anomaly-terminology,
characteristic updates. When firm characteristics are updated, anomaly investors must
rebalance their portfolios to maintain exposure to the targeted anomaly. In this paper,
we focus on the second channel.
   To set the stage, consider a value investor. When a value stock transitions into a
growth stock, the investor must sell that stock to maintain exposure to the value factor.
We build on this intuition to construct a proxy for anomaly-driven demand based on
characteristic updates. Our contribution is to show that changes in anomaly investors’
information sets, also, generate a significant impact on stock prices.



                                            1
   Anomalies are usually defined in the literature as self-financing strategies that are
long high-characteristic stocks and short low-characteristic stocks (assuming that the
risk premium is increasing in the characteristic). For almost all anomalies, the asso-
ciated characteristic is not static, and neither are the portfolio constituents. As the
anomaly characteristics update, stocks will move in and out of the long and short legs.
An anomaly investor who targets the self-financing strategy must then buy the stocks
entering the long leg and exiting the short leg, while selling those exiting the long leg and
entering the short leg. In other words, anomaly investors’ demand and supply should
vary systematically with characteristic updates. Extending this reasoning to the broader
cross-section of anomalies, we note that all anomalies draw from the same stock universe.
This allows us to aggregate supply and demand across anomalies. Based on this intuition,
we construct a proxy for anomaly-driven demand by measuring, for each stock, changes
in the number of long-leg relative to short-leg inclusions across anomalies. An increase
in our proxy implies that the stock has entered more long legs than short legs, and/or
exited more short legs than long legs. In other words, our proxy captures the number of
anomaly-driven buy and sell signals for a given stock, and anomaly investors’ aggregate
net demand should increase in our proxy. Adding the premise that anomaly investors
roughly will rebalance simultaneously (when they update characteristics), their trading
behavior induces predictable price pressures, which should lead to cross sectional return
predictability.
   We find empirical support for this mechanism. Using the dataset of Chen and Zim-
mermann (2022), we construct our proxy based on 209 distinct anomalies and show that
monthly excess stock returns increase monotonically with anomaly-driven demand, yield-
ing a statistically and economically significant return differential between high- and low-
anomaly-driven-demand stocks. These results are consistent with price pressure arising
from the rebalancing activity of anomaly investors.


                                             2
       We proceed by verifying and validating that the return differential between high- and
low-anomaly-driven-demand stocks indeed captures rebalancing of anomaly investors.
We do this in several steps. First, we show that the return differential is not spanned
by the underlying anomalies (or risk factors). By construction, stocks with high (low)
anomaly-driven demand are constituents in many long (short) legs. Consequently, the
return differential between high- and low-anomaly-driven-demand stocks loads on multi-
ple anomaly factors. This poses a key challenge for identifying the effect of rebalancing:
seperating the price impact of trading from compensation for bearing risk. For example,
the next-period return of a stock that has just entered the long leg of the value factor also
embeds the value risk premium. To mitigate this concern, we first construct our proxy for
anomaly-driven demand using only anomalies that have already been published. Because
anomaly risk premia tend decline significantly post-publication (McLean and Pontiff,
2016), our estimates of the rebalancing effect should be less affected by these.1 Second,
we control explicitly for anomaly exposure by employing the Fama and French (2015)
five factor model, the Carhart (1997) momentum factor, and the principal components
from our cross-section of anomalies. Finally, we implement an implicit control by using
the return differential between stocks with a high versus low number of long relative to
short-leg inclusions. We condition that the stocks have zero or few changes in the relative
number of long-leg inclusions since the previous period. For example, a stock that has just
moved into the long or short leg of many anomalies is not included. Hence, in absolute
terms, these are stocks with low anomaly-driven demand, based on our proxy, but high
exposure to the anomaly risk premia. We find that none of these controls can explain
the return differential between high- and low-anomaly-driven-demand stocks, suggesting
that our results are not driven by anomaly exposure.
   1
     Both McLean and Pontiff (2016) and Linnainmaa and Roberts (2018) find that anomaly returns de-
cline post-publication either due to mispricing (McLean and Pontiff, 2016) or data-snooping (Linnainmaa
and Roberts, 2018).



                                                  3
   If our proxy truly captures the rebalancing activity of anomaly investors, it should
also predict changes in investor positioning, not only returns. We therefore examine
the relationship between anomaly-driven demand and subsequent changes in investor
positioning, as measured by changes in short interest and in the breadth of mutual fund
ownership (Chen, Hong, and Stein, 2002). Stocks with high anomaly-driven demand have
either entered many long legs or exited many short legs, whereas stocks with low anomaly-
driven demand have exited many long legs or entered many short legs. Consequently,
changes in short interest should decrease with anomaly-driven demand. In addition,
many mutual funds targeting anomalies tend to specialize in only a subset of them.
If anomaly investors focus on different subsets of anomalies, then a rise in anomaly-
driven demand should be associated with a broader set of investors buying the stock.
Hence, changes in the breadth of mutual fund ownership should increase with anomaly-
driven demand. Consistent, with this reasoning we find that anomaly-driven demand
predicts cross-sectional variation in both measures of investor positioning: changes in
short interest are decreasing in anomaly-driven demand, while changes in mutual fund
ownership breadth are increasing. In sum, our anomaly-driven-demand proxy predicts not
only cross-sectional variation in returns but also systematic shifts in investors’ positions.
   Next, we scrutinize the return differential between high- and low-anomaly-driven-
demand stocks over the course of the month. When constructing the anomalies, re-
searchers typically assume that investors can update characteristics and rebalance si-
multaneously at end-of-month closing prices. In practice, however, investors must first
process and update information on stock characteristics before rebalancing their portfo-
lios. Thus, if anomaly investors update their information sets at the end of the month,
trading should occur at the beginning of the following month (Ariel, 1987, Ogden, 1990,
Etula, Rinne, Suominen, and Vaittinen, 2020). Consequently, if our results reflect a re-
balancing effect, the return differential should be concentrated at the beginning of the


                                             4
month, when anomaly investors update information and adjust their holdings. Consistent
with this prediction, we find that the return differential between high- and low-anomaly-
driven-demand stocks is significant only at the beginning of the month. We examine the
timing further by decomposing returns into intraday (open-to-close) and overnight (close-
to-open) components. Lou, Polk, and Skouras (2019) show that institutional investors
trade mainly during market hours, while Shum, Hejazi, Haryanto, and Rodier (2016) and
Ivanov and Lenkey (2018) document similar behavior for ETFs and Li (2022) for mutual
funds. Therefore, if anomaly-driven demand captures institutional rebalancing, the effect
should occur intraday rather than overnight. Indeed, we find that the beginning-of-month
return differential is entirely generated intraday.
   To better undertand the source of the documented price effects, we examine which
anomalies contribute most strongly to anomaly-driven price pressure. We compute our
proxy seperatley for anomalies belonging to the different economic categories defined by
Chen and Zimmermann (2022). Valuation-related signals emerge as an important driver
of the price effect of anomaly-driven demand, but the overall price pressure appears to
arise primarily from the joint influence of investors who simultaneously consider many
anomaly characteristics.
   As a final exercise, we revisit our main analysis by splitting anomalies according to
the t-statistics reported in their original studies. Specifically, we calculate our proxy sep-
arately for groups of anomalies with low, medium, and high t-statistics. Relative to our
baseline results, the subsequent return differential between high- and low-anomaly-driven-
demand stocks is substantially larger when considering only the anomalies with high t-
statistics. This pattern implies that the price pressure associated with anomaly-driven
demand is concentrated among well-documented, statistically strong anomalies—those
most likely to attract investor attention and trading activity.




                                              5
Related literature: The studies by Calluzzo, Moneta, and Topaloglu (2019), Gerakos,
Linnainmaa, and Morse (2021), Broman and Moneta (2023), Gao and Wang (2023),
Peng and Wang (2023), Huang et al. (2019), Ben-David et al. (2022), and Li (2022), all
affirm that institutional investors trade to exploit stock market anomalies. Huang et al.
(2019), Ben-David et al. (2022), and Li (2022) all find that mutual fund flows impact the
returns on several anomalies confirming that the anomaly focus by institutions impacts
stock prices. In contrast, we focus on the price impact arising from updates in the
anomaly investors’ information set. Our paper complements the literature by proposing
a strategy for identifying the stocks most likely to be bought or sold by anomaly investors
while concurrently demonstrating a significant price impact arising from this rebalancing.
Stocks with high anomaly investor demand and supply are also constituents in the long
or short legs of anomalies. Consequently, an important implication of our findings is
that ex-post risk premia estimates are likely to be considerably inflated by the anomaly
investors’ rebalancing, particularly when the researcher relies on samples that encompass
post-publication periods.
   Particularly pertinent to our work is the study by Peng and Wang (2023), who, in-
vestigate the same research question using a very different methodology. Focusing on the
value/growth and momentum anomalies they identify "mismatched" stocks from mutual
funds holdings data. For example, a mismatched value-stock is a stock with a high book-
to-market ratio, currently held by funds with low loadings on the value factor. They find
a significant return differential between the "well-matched" and mismatched stocks, indi-
cating a selling pressure in mismatched stocks. Our results echo this finding. Compared
with Peng and Wang (2023), who estimates price pressures from mutual fund holdings
data, our approach is quite simple as we rely only on characteristics data. Even though
this gives some imprecision in the sense, that we do not observe anomaly investors’ ac-
tual positioning, this offers several advantages. First, our method captures that anomaly


                                            6
investors may rely on several signals to target a certain anomaly risk premium. For ex-
ample, the Vanguard Value ETF identifies value stocks using five different signals, rather
than just book-to-market ratios.2 Second, we can generalize the demand across more
anomalies than just value and momentum, which should give a wider picture of aggre-
gated demand for anomalies. Third, we have a much higher frequency of the data, which
is available in real-time. Fourth, our approach generalizes across more investors than just
mutual funds, since we identify the stocks most likely traded by any anomaly investor.
This means that our proxy should also capture demand and supply arising from smart
beta ETFs and hedge funds which are known to target multi-factor strategies. In essence,
our findings align with Peng and Wang (2023), namely that anomaly investor rebalancing
creates price pressure on the underlying stocks. As such, our study should be seen as a
complementary study.
      More broadly our study also fits within the extensive literature that explores the
pricing impacts of mechanical investment rules, such as the influence of indexing (e.g.
Shleifer, 1986, Barberis, Shleifer, and Wurgler, 2005, Greenwood, 2005, Chang, Hong,
and Liskovich, 2015), ETFs (e.g. Shum et al., 2016, Ben-David, Franzoni, and Moussawi,
2018, Ivanov and Lenkey, 2018), reinvestment of dividends (Hartzmark and Solomon,
2025), and institutional flows (e.g. Coval and Stafford, 2007, Greenwood and Thesmar,
2011, Lou, 2012, Vayanos and Woolley, 2013, Anton and Polk, 2014, Huang et al., 2019,
Ben-David et al., 2022, Li, 2022, Lou and Polk, 2022). We document the existence of
pricing impacts in stocks due to mechanical rebalancing of anomaly investors.
      There has been much recent debate in the literature about whether many of the
published anomalies do in fact exist or are simply false discoveries as a result of p-
hacking (Harvey, Liu, and Zhu, 2016, Harvey, 2017, Harvey and Liu, 2019, 2020, Chen
and Zimmermann, 2020, Jensen, Kelly, and Pedersen, 2023). We completely refrain from
  2
      see https://www.etf.com/VTV



                                            7
this discussion. The sole purpose of our paper is to explore any pricing impacts that
arise due to the demand and supply of investors who target anomalies. For our research
question, the existence of anomalies is irrelevant. Only their perceived existence matters.
       The rest of the paper is organized as follows: Section 2 presents our proxy of anomaly-
driven demand and data, Section 3 the main empirical analysis, Section 4 some further
results, while Section 5 concludes.


2. Data and variable construction

This section introduces our proxy for anomaly-driven demand through an intuitive ex-
ample of a value investor and explains its construction. We also describe the data sources
used for anomaly characteristics and stock returns.


2.1. A proxy for anomaly-driven demand

To introduce our proxy for anomaly-driven demand, consider the perspective of a value
investor who targets the value premium using the book-to-market ratio (BM) as a signal.
The value factor is constructed by sorting stocks into portfolios based on BM, and the
corresponding factor return is generated by a strategy that is long the stocks with high
BM values and short the stocks with low BM values. An example of the long and short
portfolios is illustrated in Panel (a) of Figure 1.


                                       Figure 1 about here


       The value investor’s portfolio therefore consists of a short position in the bottom
quintile portfolio (Growth) and a long position in the top quintile portfolio (Value).3
Iterating one period forward, the investor updates the trading signal, BM, and stocks are
   3
     Fama and French (1993) use a bivariate sort; however, we consider a univariate sort here for simplicity
of illustration.



                                                     8
reallocated across quintile portfolios, as illustrated in Panel (b). To maintain exposure
after the characteristic update, the value investor must rebalance her portfolio by (1)
buying new value stocks (“T,” “G,” and “O”) and former growth stocks (“X,” “Z,” and
“B”), and (2) selling new growth stocks (“U,” “N,” and “I”) and former value stocks (“U,”
“Q,” and “J”). The key insight is that by observing how stocks are reshuffled between
portfolios, we can infer which stocks value investors are buying and selling. Extrapolating
this logic to the full cross-section of observable characteristics allows us to aggregate the
implied supply and demand of anomaly investors across all anomalies.
   Based on this intuition, we construct a simple proxy for anomaly-driven demand in
three steps. First, for each anomaly characteristic, we sort the cross-section of stocks into
five (or two) portfolios. Assuming that expected returns are increasing in the characteris-
tic value, we define the short leg, as the portfolio containing stocks with low characteristic
values, and the long leg as the portfolio containing stocks with high characteristic values.
We denote the short-leg portfolio as P short , and the long-leg portfolio as P long .
   In the second step, following Engelberg, McLean, and Pontiff (2018), we count the
number of times stock j is a constituent of either P short or P long across all anomaly
characteristics and calculate the net difference:

                                         Nt
                                         X
                              NETj,t =         1j∈P long − 1j∈Pi,t
                                                               short ,                    (1)
                                                     i,t
                                         i=1

where Nt is the number anomalies at time t and 1 is the indicator function. We focus
on anomalies that have already been published, implying that Nt is time-varying. An
increase in NET implies either that stock j has entered more long legs than short legs
and/or exited more short legs than long legs. In other words, an increase in NET predicts
that anomaly investors have a positive aggregate net demand for the stock.
   We use this reasoning in the last step and define our proxy for anomaly-driven demand,



                                                 9
ADD, as changes in NETj,t :


                                  ADDj,t = NETj,t − NETj,t−1 .                                  (2)


      Since ADD is based only on anomaly characteristics, it is both measurable in real-time
and also captures demand from multi-factor investors.


2.2. Stock data

We consider data from the Center for Research in Security Prices (CRSP) monthly secu-
rity file. We follow the literature and only include US common stocks (shrcd=10 or 11)
trading on NYSE, AMEX, and NASDAQ (exchcd=1, 2, or 3).


2.3. Stock anomalies and portfolio constituents

We obtain data on anomaly characteristics from Chen and Zimmermann (2022) includ-
ing publication year, in-sample return, portfolio update frequency and t-statistics from
each individual anomaly study.4 The dataset contains characteristics for 209 different
anomalies signed such that a high (low) characteristic value is a buy (sell) signal. We
focus on the post-publication period of the anomalies for two reasons: first, to ensure that
anomaly investors are aware of the anomaly, and second, to mitigate the effect of the real-
ized anomaly risk premium as McLean and Pontiff (2016) find that the realized anomaly
risk premia decline significantly after publication due to reduced mispricing. This re-
striction means that our sample starts in January 1990, to ensure a sufficient number
of anomalies, and ends in December 2023. Panel (a) of Figure 2 shows the number of
published anomalies in our dataset over time.


                                     Figure 2 about here
  4
      We thank the authors for making the data available at https://www.openassetpricing.com/



                                                  10
      In 1990 there were 11 published anomalies, increasing to 209 by 2016. Initially, and
towards the end of the sample period, the number of anomalies remains relatively sta-
ble. However, there is a steep increase from 2006 to 2010, consistent with the findings
of Harvey et al. (2016). Panel (b) shows the distribution of anomalies across the eco-
nomic categories defined by Chen and Zimmermann (2022). The Other and Valuation
categories stand out in size, containing 12% and 8% of all anomalies, respectively, while
the remaining categories are relatively smaller.
      To construct ADD, we perform 209 different portfolio sorts. For practical implemen-
tation, we consider quintile portfolios based on breakpoints calculated using NYSE stocks
only (see Hou, Xue, and Zhang, 2020). The portfolios are rebalanced monthly or when-
ever the characteristic is updated. Section 4.3 shows that the results are similar when
characteristics are updated according to the original studies.5 Additionally, Section 4.4
demonstrates that the results are robust when using a different number of portfolios in
the sorting process. For binary characteristics, we classify all stocks into a buy or a sell
portfolio based on the characteristic.6
      The average share of new constituents in long and short legs is 0.39,7 though this
varies significantly across anomalies. At the extremes, the share ranges from as low as
0.01 for the sin stock anomaly (Hong and Kacperczyk, 2009) to as high as 0.97 for changes
in analyst recommendations (Jegadeesh, Kim, Krische, and Lee, 2004). For more classic
anomalies, the replacement share is 0.09 for Value (by the book-to-market ratio) and 0.37
for Momentum (as defined by Jegadeesh and Titman, 1993). Overall, a large proportion
of the anomaly constituents are new stocks, which investors must buy and sell to maintain
exposure to the targeted anomaly.
  5
     Rebalancing frequencies are obtained from Chen and Zimmermann (2022).
  6
     Ignoring the short portfolio for binary variables generates the same conclusions.
   7
     To take into account that many of the characteristics are not updated on a monthly basis, the
replacement share is calculated using the original update frequency of the anomalies.




                                               11
3. Results

This section presents our main results. Stocks with high ADD earn higher returns than
those with low ADD, yielding a statistically and economically significant return differen-
tial. To validate that this differential reflects a rebalancing effect, we show that it cannot
be explained by anomaly exposure, that ADD predicts changes in investor positions, and
that the return differential is generated in the days immediately following characteristic
updates. We further demonstrate that the observed price pressure does not arise from
any single anomaly in isolation, and that the price impact of anomaly-driven demand is
concentrated among the statistically strongest anomalies. Overall, our findings indicate
a significant pricing effect driven by the rebalancing activity of anomaly investors.


3.1. Anomaly-driven demand and stock returns

We posit that our proxy, ADD, predicts the rebalancing of anomaly investors following
updates in stock characteristics. In turn, if anomaly investor rebalancing has a price
impact, stock returns should be predictable by ADD at the portfolio level. We test this
through portfolio sorting. The top panel of Table 1, the first row, reports our main
results: the average excess returns of portfolios sorted into quintiles based on ADD from
Equation (2). The ’Low’ portfolio contains the stocks with the lowest ADD, and the
’High’ portfolio contains the stocks with the highest ADD. The portfolios are value-
weighted and rebalanced monthly. Both breakpoints are included in the portfolios (see
Bali, Engle, and Murray, 2016), implying a potential overlap between portfolios due to
the discrete nature of the characteristics. The High and Low portfolios are, however,
completely non-overlapping.8
   8
    Redefining the portfolio boundaries such that a portfolio only included a single breakpoint generates
similar results but this approach does not guarantee that at least 20% of the NYSE stocks are allocated
to each portfolio. Hence, our approach is conservative.




                                                   12
                                  Table 1 about here


   Excess stock returns are monotonically increasing across ADD-sorted portfolios from
6.62% for the Low portfolio to 10.65% for the High portfolio, annualized. The return
differential between the High and the Low portfolio (High-Low) is 4.03 percentage points
with a t-statistic of 4.03. This is consistent with a significant pricing pressure from the
rebalancing of anomaly investors.
   The standard deviation is U -shaped across the ADD-sorted portfolios with the Low
portfolio having the largest standard deviation followed by the High portfolio. For the
return differential between the High and the Low portfolio, the standard deviation is very
low, suggesting a rather persistent effect. Sharpe ratios are monotonically increasing in
ADD, and a strategy that buys the High portfolio and sells the Low portfolio has a
Sharpe ratio of 0.61. Most strikingly, opposite to the individual ADD-sorted portfolios,
the High-Low return differential has a small positive skewness.
   To examine how the ADD-portfolios load on different stock characteristics, the mid
panel in Table 1 presents the value-weighted average characteristic for the constituents
in each portfolio. The table shows results for a broad set of characteristics: market beta
(BETA), log market capitalization (SIZE), book-to-market (BM), the cumulative return
over the 12 months prior to portfolio formation minus the latest month (MOM), the
Amihud (2002) illiquidity measure (ILLIQ), and the coskewness measure (COSKEW)
of Harvey and Siddique (2000). Across the different stock charactertics, no discernible
patterns are evident. The value-weighted averages of the characteristics are virtually
identical across all quintile portfolios. This implies that differences in returns across the
ADD-sorted portfolios cannot be explained by differences in these characteristics. We
show later that the return differential between the High and the Low portfolio is not
spanned by the most common risk factors or the different anomalies.
   Next, we examine changes in long- and short-leg inclusions separately. The bottom

                                             13
panel of Table 1 presents average excess returns for portfolios sorted on ADD’s two com-
ponents individually. Excess returns are monotonically increasing in changes in long-leg
inclusions and roughly monotonically decreasing in short-leg inclusions. Hence, the more
long-legs a stock enters (leaves), the higher (lower) returns. Similarly, the more short-
legs a stock enters (leaves), the lower (higher) returns. The High-Low return differentials
are of similar size when looking at long-leg driven demand and short-leg-driven demand.
None of the individually components, delivers superior portfolios compared to combining
the two, suggesting that the two signals complement each other.
   Finally, to illustrate the consistency of the effect, Figure 3 shows the cumulative return
differential between the High and the Low portfolios from sorting on ADD, changes in
long-leg inclusions, and changes in short-leg inclusions.


                                 Figure 3 about here


   The return differentials are consistent over time. Disregarding the period 1999-2000,
the cumulative returns are steadily increasing over time with little variation, explaining
the high t-statistics relative to the annualized returns. The spikes in the series for changes
in long-leg- and short-leg inclusions occur during a run-up to the peak of the dot-com
bubble in the spring of 2000.


3.1.1. Controlling for factor exposure

We have demonstrated that there is a significant difference in average returns between
stocks with a high ADD score and stocks with a low ADD score. Now, we investigate
whether this difference can simply be explained by exposure to anomalies. An increase
in ADD for any stock can occur through two channels: either by exiting a short-leg or
by entering a long-leg. In the latter case, we expect the stock to have high exposure to
the specific anomaly. For instance, a stock that enters the long leg of the value factor


                                             14
should have higher expected returns, due to the positive risk premium associated with
value. Consequently, our main results in Table 1 may be entirely driven by exposure to
the different anomalies.
       To address this, we adjust the High-Low return differential (based on the ADD-sort)
for anomaly exposure using various control variables. Ideally, we would control for the
returns of each of the 209 anomalies. However, this is not feasible due to the time
differences in publication across anomalies. Instead, we employ the Fama and French
(2015) factors (FF5), the Carhart (1997) momentum factor (MOM), and the first three
principal components from the cross-section of anomaly returns.9
       Additionally, we implement a more implicit control for anomaly exposure by conduct-
ing a five-by-five conditional bivariate sort. First, we sort on NET (see Equation (1)),
followed by sorting on the absolute ADD value. Stocks with high NET are constituents
in many long-legs relative to short-legs and, therefore, have large exposure to different
anomalies. However, NET also captures stocks that have just moved into the long or
short-leg, which are the stocks where we expect a price impact induced by anomaly
investors. Hence, to isolate the associated anomaly risk premia from anomaly-driven de-
mand, we add the second sort. We construct our control variable as the “high NET low
absolute ADD” portfolio minus the “low NET low absolute ADD” portfolio (NET⊥ADD ).
This return differential has a high anomaly exposure, but no expected anomaly-driven
demand, thereby capturing the associated risk premium, adjusted for anomaly-driven de-
mand. Tabel 2 presents the results from regressing the return differential between high-
and low-ADD stocks (cf. Table 1) on the control variables.


                                     Table 2 about here


       The return differential between high- and low-ADD stocks cannot be explained by
   9
    The first three principal components explain 72% of the total variation. The results are identical
using five and 10 principal components.


                                                 15
the controls; all intercepts are highly significant and align in magnitude with the return
differential reported earlier. The loading on the market factor is almost zero and insignif-
icant for all specifications, the FF5 and MOM factors loadings are all insignificant at
the 5% level (except the MOM factor when including all control factors) with the CMA
(investment) factor has the highest loading. For the principal components, the first and
the third are significant when including all control factors. The loadings on NET⊥ADD
are positive but only significant when included as the only control variable and when
including the FF5 model as controls. Overall, these results suggest that the return dif-
ferential between high- and low anomaly-driven demand stocks is not driven by exposure
to anomalies.


3.2. Anomaly-driven demand and position data

To establish anomaly-driven demand (ADD) as a credible proxy for the rebalancing ac-
tivity of anomaly investors, we examine whether it aligns with observed position data.
Specifically, we analyze changes in short interest and changes in the breadth of own-
ership—measured as the change in the number of mutual funds with long positions,
following Chen et al. (2002).
   First, the top panel of Table 3 reports the average change in short interest, scaled by
the number of shares outstanding, for the five portfolios sorted by ADD and by changes in
long- and short-leg inclusions separately. Because end-of-month short interest data from
Compustat are available only from January 2007 onward, the analysis in this subsection
covers the period from January 2007 to December 2023.


                                 Table 3 about here


   We hypothesize that stocks entering the highest number of new short legs are those
most likely to be shorted by anomaly investors. Hence, changes in short interest should be


                                            16
predictable from, and decreasing in, ADD. The results are consistent with this prediction:
changes in short interest decline nearly monotonically from the Low to the High portfolio.
For stocks with low ADD, short interest increases in the following month, whereas for
stocks with high ADD, short interest decreases. Although the changes in short interest
are statistically insignificant at the individual portfolio level—partly due to the limited
sample period—the difference between the High and Low portfolios is significant. De-
composing long- and short-leg inclusions yields a similar pattern. Stocks with the most
new long-leg inclusions decrease the most in short interest, while those with the most
new short-leg inclusions show a slight increase over the next month. The difference is
small and not visible at the reported two-decimal precision.
   Next, the bottom panel of Table 3 reports the average change in quarterly breadth
of ownership, sorted by the quarterly aggregated ADD. The breadth of ownership is
constructed from mutual fund holdings data and is included in the Chen and Zimmermann
(2022) dataset. Because ADD is measured monthly, we aggregate it to the quarterly
frequency to match the ownership data. For example, ADD aggregated over January and
February 2020 is used to predict quarterly changes in ownership breadth from December
31, 2019, to March 31, 2020. This approach does not capture intraquarterly variation in
ownership breadth, which constitutes a bias against our results.
   If mutual funds target one or several anomalies, and if ADD truly captures their
demand and supply, we would expect more funds to buy stocks with high ADD scores
relative to those with low ADD scores. The results align with this expectation. Changes
in the breadth of mutual fund ownership increase with ADD, with a significant differ-
ence between high- and low-ADD stocks (t-statistic = 2.38). Hence, ADD predicts which
stocks are added as new holdings to mutual fund portfolios. A high ADD score reflects
that a stock has entered many long legs and/or exited many short legs. Because short
selling is not feasible for most mutual funds, only long-leg changes should be informative


                                            17
for ownership breadth. This is indeed what we observe: when decomposing ADD into
long- and short-leg components, a clear pattern emerges only for the former. Changes
in the breadth of ownership rise with new long-leg inclusions, with a significant differ-
ence between high- and low-ADD stocks (t-statistic = 3.09). In other words, the more
new long legs a stock becomes a constituent of, the more new funds add that stock to
their portfolios. Changes in short-leg inclusions appear uninformative, as there is little
difference between stocks with many new short-leg inclusions and those with few.
   In sum, our proxy for anomaly-driven demand predicts not only cross-sectional vari-
ation in returns but also changes in investor positioning. This consistency supports the
interpretation that ADD captures the demand and supply dynamics of anomaly investors,
thereby validating our proxy as a measure of rebalancing activity.


3.3. Intramonthly return pattern

Thus far, we have shown that after characteristics updates, stocks with the most new
long-leg inclusions (or fewest new short-leg inclusions) have higher returns over the sub-
sequent month compared to stocks with the most new short-leg inclusions (or fewest new
long-leg inclusions). If these results are driven by anomaly investor rebalancing, we would
expect stock returns to react shortly after these characteristics updates enter the anomaly
investors’ information set. Studies on ’turn of the month’ effects (e.g. Ariel, 1987, Ogden,
1990, Etula et al., 2020) suggest that investors typically rebalance portfolios at the begin-
ning of the month. This implies that the return differential between high- and low-ADD
stocks should be generated during the first days of the month following these updates.
Figure 4 shows the average daily return differential between high- and low-ADD stocks
from the first trading day to the end of the month after the characteristics updates.

                         Figure 4 and Table 4 about here

   The figure shows a clear clustering of positive returns during the first five to six trad-

                                             18
ing days following the characteristics update, while the pattern becomes mixed for the
remainder of the month. To formally assess the difference, Panel A of Table 4 presents
the results for the ADD-sorted portfolios over the first five trading days after the charac-
teristics update and for the rest of the month. Consistent with a rebalancing effect the
return differential between high- and low-ADD stocks is concentrated primarily within
the first five trading days. During this period, the average return is monotonically increas-
ing across ADD portfolios with an average return differential of 0.19% and a t-statistic
of 4.10. In contrast, there is no clear pattern in the average portfolio returns for the
remainder of the month, and the return differential is insignificant.
   As a last exercise, we split the returns during the first week of each month into intraday
and overnight returns, following Lou et al. (2019). Lou et al. (2019) find that mutual
funds primarily trade during market open hours, while Shum et al. (2016) and Ivanov
and Lenkey (2018) show similar trading behavior for ETFs. If these investor types drive
the demand for anomalies, we hypothesize that the return differential between high- and
low-ADD stocks should be more concentrated intraday, rather than overnight.
   Panel B of Table 4 presents the average ADD-sorted portfolio returns split into in-
traday and overnight. Note, that the opening prices are only available from mid-1992
meaning the results are based on a slightly different sample. The High-Low return differ-
ential is entirely generated intraday for which the average return of ADD-sorted portfolios
is monotonically increasing. While the overnight return differential between the High and
the Low portfolio is both statistically and economically zero, the return differential in-
traday returns is 0.19% per month over the first five trading days, with a t-statistic of
5.28.
   In sum, the return differential between stocks with high and stocks with low anomaly-
driven demand is concentrated in the intraday period at the beginning of the month. This
finding is consistent with a significant rebalancing effect occurring as anomaly investors


                                             19
update their information set.


3.4. Which anomalies have the highest price impact?

Next, we explore for which anomalies anomaly-driven demand induces the highest price
impact. We do this by computing ADD separately for anomalies belonging to different
economic categories. That is, rather than counting across all 209 anomalies (cf. Equa-
tion (1)), we count only across the anomalies within each economic category. Panel (a)
in Figure 5 shows, for each category, the average High-Low return differential together
with 95% confidence intervals.

                                    Figure 5 about here

      Only the categories Valuation, Other, and Option Risk are individually significant,
with average return differentials of 0.26, 0.27, and 0.25 percent, respectively. Panel
(b) then shows the change in the High-Low return differential when leaving out each
economic category, relative to our main results (first row of Table 1). Excluding the
Valuation anomalies reduces the average High-Low return differential by 0.14 percentage
points, while excluding the Other category lowers it by 0.09 percentage points. Option
Risk—like the remaining categories—is no longer statistically significant.
      In sum, these results suggest that the price impact of anomaly-driven demand does not
stem from trading on a single characteristic in isolation, but rather from the joint influence
of investors who simultaneously consider many signals. However, the Valuation-signals
seems to be a particularly important driver. This finding is intuitve: the value premium is
one of the most established and our prior belief is that many anomaly investors explicitley
target the value premium. As a result, synchronized trading around value signals can
generate concentrated demand and contribute meaningfully to the overall price impact we
observe. Supporting this interpretation, the ETF screener provided by VettaFi10 shows
 10
      https://etfdb.com/screener/


                                             20
that, out of 1,533 equity ETFs, 441 are classified as value- or growth-style funds (as of
this writing), underscoring the broad investor focus on valuation-based factors.
   It appears puzzling that the Other category also seems to play an important role in
driving price impact. However, this category includes a mix of well-known but conceptu-
ally distinct characteristics—such as seasonality patterns (Heston and Sadka, 2008) and
betting-against-beta (Frazzini and Pedersen, 2014)—that do not share a common eco-
nomic theme. Many of these signals are only weakly correlated with one another, so the
significance of the Other category likely reflects the aggregation of trading across many
heterogeneous strategies rather than a unified factor exposure. In this sense, the Other
category provides further evidence that price pressure from anomaly-driven demand arises
from the collective activity of investors trading on multiple, partly independent signals,
consistent with our interpretation that the overall effect is generated by the joint behavior
of multi-signal investors rather than by any single anomaly.
   Overall, this analysis also suggests that interacting different categories is important
for understanding the price effect of anomaly-driven demand.


3.5. Price impact of anomaly-driven demand and anomaly t-statistics

In constructing our ADD proxy, all anomalies are weighted equally. However, McLean and
Pontiff (2016) show that the post-publication decline in anomaly returns is stronger for
anomalies with higher t-statistics, in the original paper, suggesting that high-performing
anomalies attract greater investor attention and subsequent arbitrage capital. Motivated
by this finding, we spliot the cross-section of anomalies into groups based on their re-
ported t-statistics from the original studies. This modification allows us to test whether
investor attention—and thus the price impact of anomaly-driven demand—depends on
the strength of the statistical evidence reported at publication.
   Specifically, in each month we compute ADD separately for three groups of anomalies


                                             21
defined by the 30th and 70th percentiles of the reported t-statistics. Within each group,
we again sort stocks into quintile portfolios based on ADD. Early in the sample period,
the number of published anomalies is relatively small, so the long leg consists of stocks
with positive anomaly-driven demand, while the short leg consists of stocks with anomaly-
driven supply. Table 5 reports the average excess returns for the five portfolios and the
corresponding High–Low differentials across the three t-statistic groups.


                                  Table 5 about here


   The results of the top panel, show that the price effect of anomaly-driven demand is
primarily a phenomenon among high-t-statistic anomalies. The High–Low return differ-
ential is statistically significant only within the high-t group, while it is both economically
and statistically close to zero for the low- and medium-t groups. Relative to our main
result (first row of Table 1), the magnitude of the High–Low differential increases by
roughly 103 basis points.
   The middle and bottom panels of Table 5 report the results from sorting stocks into
quintile portfolios based on changes in long- and short-leg inclusions, respectively. Again,
we find much stronger effects within the high-t-statistic group. Interestingly, an asym-
metric pattern now emerges between the long and short legs: the absolute High–Low
return is considerably larger for long-leg changes than for short-leg changes (4.15 per-
cent versus 1.88 percent). This implies that changes in long-leg inclusions have a greater
impact on future stock returns than changes in short-leg inclusions.
   A plausible explanation for this asymmetry is that many investors—such as mu-
tual funds and other long-only institutions—face restrictions on short selling. As a re-
sult, a substantial subset of anomaly investors may primarily trade on the long side of
an anomaly, which could contribute to the stronger price effects observed for long-leg
changes.


                                              22
   The asymmetry between long- and short-leg inclusions was not apparent in our main
specification in Table 1, likely because those results included more noise due to the aggre-
gation across all anomalies, regardless of their statistical strength. Grouping anomalies by
their reportedt-statistics reduces this noise and provides a clearer view of the underlying
relationship between anomaly-driven demand and subsequent returns.
   Overall, these results indicate that the price impact of anomaly-driven demand is con-
centrated among well-documented, statistically strong anomalies and is primarily trans-
mitted through changes in long-leg inclusions. This pattern is consistent with the view
that investor attention and trading constraints jointly shape how anoamaly-demand af-
fects stock prices.


4. Further results

In this section, we present supplementary findings that refine and corroborate the previous
results.


4.1. Anomaly driven demand, size, and liqudity

First, we investigate whether the return differential between high- and low-ADD stocks
is concentrated among small, illiquid stocks or if it also persists among large, liquid
stocks. To do this, we conduct a bivariate conditional sort, based on either the illiquidity
measure of Amihud (2002) or size in addition to ADD. We begin by sorting the stocks
into quintile portfolios ranked by illiquidity or market capitalization, respectively. Within
each of these quintile portfolios, we then form a second set of quintile portfolios ranked by
ADD. This creates a set of portfolios with similar past illiquidity or size characteristics but
with spreads in anomaly-driven demand. Table 6 shows the average size- and illiquidity-
conditional return differential between high- and low-ADD stocks. The different panels
display the results of a 5-by-5 conditional sort, with breakpoints still based on NYSE-

                                              23
listed stocks. The portfolios are value-weighted, rebalanced at the end of each month,
and are still based only on post-publication anomalies.


                                 Table 6 about here


   The table reveals a striking pattern: the average return differentials display a skewed
U-shaped across both size and liquidity. This means that the return differential between
high- and low-ADD stocks is economically largest among small, illiquid stocks, but it is
also highly significant among the largest and most liquid stocks. In contrast, the results
are weakest in the mid-quintile portfolios. Hence, the anomaly investor rebalancing effect
appears to exist in both small, illiquid stocks and large, liquid stocks.


4.2. Alternative investment universe

So far, we have constructed anomalies using a portfolio sort, as illustrated in Section
2. An alternative approach proposed in the literature is rank-based, where investors are
assumed to hold all assets, with portfolio weights increasing in the anomaly characteristic
(e.g., Asness, Moskowitz, and Pedersen, 2013). However, this approach is expensive to
apply in practice both in terms of transaction costs and attention, making it infeasible
to real-world investors (Novy-Marx and Velikov, 2022). Furthermore, the portfolio sort
approach aligns with the habitat view, i.e., many investors choose only to trade a subset
of available securities. In our context this corresponds to anomaly investors focusing
only on the extreme characteristic portfolios making the rank-based approach a noisier
proxy for anomaly-driven demand. To explore this further, we modify ADD using a
rank-based approach. Specifically, we follow Asness et al. (2013) and calculate stock i’s
                                                                                  median
portfolio weight in anomaly, j, with cross-sectional rank ri,t,j and median rank rt,j    as
the following:




                                             24
                                              median
                                      ri,t,j −rt,j                              median
                                                            median if ri,t,j > rt,j
                             
                              P
                                                  ri,t,j −rt,j
                              { i,t,j t,j       }
                                         median
                             
                             
                                k|r  >r
                             
                  wi,t,j =                                                                             (3)
                             
                                                       median |
                             
                                            |ri,t,j −rt,j                                    median
                                                                                 if ri,t,j < rt,j
                             
                             
                              P                                        median
                                                              ri,t,j −rt,j
                                  {   k|ri,t,j <r median   }
                             
                                                 t,j


These weights ensures that the weights of the long leg sum to 1 and the short weights sum
to -1, and the portfolio is, thereby, self-financed. We esitmate demand by suming weights
acorss published anomalies, and take first difference. We then form quantile portfolios
based on changes in the sum of ranks. For simplicity, we only consider continuous char-
acteristics. Table 7 shows the average monthly returns. The “Low” portfolio contains
the stocks with the lowest change in the sum of ranks from the previous month, while
the "High" portfolio includes stocks with the largest change in the sum of ranks.


                                         Table 7 about here


   The return di!erential between high- and low- anomaly-driven demand stocks is only
just significant using a rank-based approach and we no longer observe a consistent mono-
tonic increase in returns from the Low to the High portfolio. Consequently, in comparison
to our primary findings as presented in Tabel 7, the application of rank-based weights
yields weaker results.


4.3. Updating portfolios according to original papers

Previously, we considered monthly rebalancing (or whenever the characteristic is up-
dated) for all anomalies. However, many of the original anomaly studies employ different
rebalancing frequencies. For example, Jegadeesh and Titman (1993) used quarterly re-
balancing for the momentum anomaly, even though the signal can be updated monthly.
Now, we examine whether our results are sensitive to the rebalancing frequency by up-
dating the anomaly portfolios according to the rebalancing frequency proposed in the


                                                               25
original paper. Table 9 presents the result from sorting on ADD based on the original
rebalancing frequencies.


                                  Table 9 about here


   The results are similar to those in Table 1, though weaker. Specifically, for the main
ADD specification which incorporates both long-leg and short-leg changes, the average
return differential between the Low and the High portfolio decreases by 162 basis points,
with its t-statistic decreasing by 1.57.


4.4. Different number of portfolios

As highlighted by Walter, Weber, and Weiss (2022), the number of portfolios used in a
portfolio sort can have a substantial impact on the results. Our main analysis applies
portfolio sorting in two stages: first, to construct ADD (the ADD sort), and second,
to test for the pricing implications of anomaly-driven demand (the testing sort). All
previous results are based on quintile portfolios in both stages. Here, we examine the
sensitivity of our main result (see Table 1) to variations in the number of portfolios used
in both stages. Table 8 reports the average return differential between the High and the
Low portfolios. Along the columns, we vary the number of portfolios in the ADD sort,
while along the rows, we vary the number of portfolios in the testing sort. We consider
three, five, or ten portfolios.


                                  Table 8 about here


   The results in Table 1 are generally robust to changes in the number of portfolios
in both sorts. The return differentials remain highly significant, both economically and
statistically except in the case of using 10 portfolios in both sorts. In general, the results
are weaker when applying 10 portfolios in the ADD sort.


                                             26
5. Conclusion

We introduce a proxy for anomaly-driven demand, by tracking changes in the net num-
ber of long- and short-leg inclusions across anomalies for each stock. Empirically, we
demonstrate that monthly stock returns are increasing in anomaly-driven demand with a
significant return differential between high- and low-anomaly-driven demand stocks. This
return differential cannot be explained by anomaly exposure and is concentrated at the
beginning of the month following a characteristics update. Furthermore, our proxy for
anomly-driven demand also predicts changes in position data. In summary, our findings
provide evidence of a significant rebalancing effect by anomaly investors, suggesting that
by merely targeting the risk premia associated with different anomalies, these investors
drive stock prices.




                                           27
References

Amihud, Y. (2002). Illiquidity and stock returns: cross-section and time-series effects.
  Journal of Financial Markets 5 (1), 31–56.

Ang, A. (2019).     Factor capacity by the numbers.        Available at:   https://www.
  institutionalinvestor.com/article/2bsw74wxh0ow9ixem2akg/innovation/
  factor-capacity-by-the-numbers (Last Accessed: November 10, 2025).

Anton, M. and C. Polk (2014). Connected stocks. Journal of Finance 69 (3), 1099–1127.

Ariel, R. A. (1987). A monthly effect in stock returns. Journal of Financial Eco-
  nomics 18 (1), 161–174.

Asness, C. S., T. J. Moskowitz, and L. H. Pedersen (2013). Value and momentum every-
  where. Journal of Finance 68 (3), 929–985.

Bali, T. G., R. F. Engle, and S. Murray (2016). Empirical asset pricing: The cross section
  of stock returns. John Wiley & Sons.

Barberis, N., A. Shleifer, and J. Wurgler (2005). Comovement. Journal of Financial
  Economics 75 (2), 283–317.

Ben-David, I., F. Franzoni, and R. Moussawi (2018). Do etfs increase volatility? Journal
  of Finance 73 (6), 2471–2535.

Ben-David, I., J. Li, A. Rossi, and Y. Song (2022). Ratings-driven demand and systematic
  price fluctuations. Review of Financial Studies 35 (6), 2790–2838.

Broman, M. S. and F. Moneta (2023). On the anomaly tilts of factor funds. Working
  paper.



                                           28
Calluzzo, P., F. Moneta, and S. Topaloglu (2019). When anomalies are publicized broadly,
  do institutions trade accordingly? Management Science 65 (10), 4555–4574.

Carhart, M. M. (1997). On persistence in mutual fund performance. Journal of Fi-
  nance 52 (1), 57–82.

Chang, Y.-C., H. Hong, and I. Liskovich (2015). Regression discontinuity and the price
  effects of stock market indexing. Review of Financial Studies 28 (1), 212–246.

Chen, A. Y. and T. Zimmermann (2020). Publication bias and the cross-section of stock
  returns. Review of Asset Pricing Studies 10 (2), 249–289.

Chen, A. Y. and T. Zimmermann (2022). Open source cross-sectional asset pricing.
  Critical Finance Review 27 (2), 207–264.

Chen, J., H. Hong, and J. C. Stein (2002). Breadth of ownership and stock returns.
  Journal of Financial Economics 66 (2), 171–205.

Coval, J. and E. Stafford (2007). Asset fire sales (and purchases) in equity markets.
  Journal of Financial Economics 86 (2), 479–512.

Engelberg, J., R. D. McLean, and J. Pontiff (2018). Anomalies and news. Journal of
  Finance 73 (5), 1971–2001.

Etula, E., K. Rinne, M. Suominen, and L. Vaittinen (2020). Dash for cash: Monthly
  market impact of institutional liquidity needs. Review of Financial Studies 33 (1),
  75–111.

Fama, E. F. and K. R. French (1993). Common risk factors in the returns on stocks and
  bonds. Journal of financial economics 33 (1), 3–56.

Fama, E. F. and K. R. French (2015). A five-factor asset pricing model. Journal of
  Financial Economics 116 (1), 1–22.

                                             29
Frazzini, A. and L. H. Pedersen (2014). Betting against beta. Journal of financial
  economics 111 (1), 1–25.

Gao, X. and Y. Wang (2023). Mining the short side: Institutional investors and stock
  market anomalies. Journal of Financial and Quantitative Analysis 58 (1), 392–418.

Gerakos, J., J. T. Linnainmaa, and A. Morse (2021). Asset managers: Institutional
  performance and factor exposures. Journal of Finance 76 (4), 2035–2075.

Greenwood, R. (2005). Short-and long-term demand curves for stocks: theory and evi-
  dence on the dynamics of arbitrage. Journal of Financial Economics 75 (3), 607–649.

Greenwood, R. and D. Thesmar (2011). Stock price fragility. Journal of Financial
  Economics 102 (3), 471–490.

Hartzmark, S. M. and D. H. Solomon (2025). Market-wide predictable price pressure.
  American Economic Review 115 (9), 3171–3213.

Harvey, C. R. (2017). Presidential address: The scientific outlook in financial economics.
  Journal of Finance 72 (4), 1399–1440.

Harvey, C. R. and Y. Liu (2019). A census of the factor zoo. Working paper.

Harvey, C. R. and Y. Liu (2020). False (and missed) discoveries in financial economics.
  Journal of Finance 75 (5), 2503–2553.

Harvey, C. R., Y. Liu, and H. Zhu (2016). . . . and the cross-section of expected returns.
  Review of Financial Studies 29 (1), 5–68.

Harvey, C. R. and A. Siddique (2000). Conditional skewness in asset pricing tests. Journal
  of Finance 55 (3), 1263–1295.




                                           30
Heston, S. L. and R. Sadka (2008). Seasonality in the cross-section of stock returns.
  Journal of Financial Economics 87 (2), 418–445.

Hong, H. and M. Kacperczyk (2009). The price of sin: The effects of social norms on
  markets. Journal of Financial Economics 93 (1), 15–36.

Hou, K., C. Xue, and L. Zhang (2020). Replicating anomalies. Review of Financial
  Studies 33 (5), 2019–2133.

Huang, S., Y. Song, and H. Xiang (2019). Noise trading and asset pricing factors. Working
  paper.

Ivanov, I. T. and S. L. Lenkey (2018). Do leveraged etfs really amplify late-day returns
  and volatility? Journal of Financial Markets 41, 36–56.

Jegadeesh, N., J. Kim, S. D. Krische, and C. M. Lee (2004). Analyzing the analysts:
  When do recommendations add value? Journal of Finance 59 (3), 1083–1124.

Jegadeesh, N. and S. Titman (1993). Returns to buying winners and selling losers:
  Implications for stock market efficiency. Journal of Finance 48 (1), 65–91.

Jensen, T. I., B. Kelly, and L. H. Pedersen (2023). Is there a replication crisis in finance?
  Journal of Finance 78 (5), 2465–2518.

Li, J. (2022). What drives the size and value factors? Review of Asset Pricing Stud-
  ies 12 (4), 845–885.

Linnainmaa, J. T. and M. R. Roberts (2018). The history of the cross-section of stock
  returns. Review of Financial Studies 31 (7), 2606–2649.

Lou, D. (2012). A flow-based explanation for return predictability. Review of Financial
  Studies 25 (12), 3457–3489.


                                             31
Lou, D. and C. Polk (2022). Comomentum: Inferring arbitrage activity from return
  correlations. Review of Financial Studies 35 (7), 3272–3302.

Lou, D., C. Polk, and S. Skouras (2019). A tug of war: Overnight versus intraday expected
  returns. Journal of Financial Economics 134 (1), 192–213.

McLean, R. D. and J. Pontiff (2016). Does academic research destroy stock return pre-
  dictability? Journal of Finance 71 (1), 5–32.

Morningstar (2022).      A global guide to strategic-beta exhcange-traded products.
  Morningstar.        Available at:    https://assets.contentstack.io/v3/assets/
  blt4eb669caa7dc65b2/bltcb6949c5d872310b/62a12c0f43918857196ebe3b/
  Global_Strategic_Beta_ETP_Landscape_Report.pdf (Last Accessed:                 Novem-
  ber 10, 2025).

Newey, W. K. and K. D. West (1994). Automatic lag selection in covariance matrix
  estimation. Review of Economic Studies 61 (4), 631–653.

Novy-Marx, R. and M. Velikov (2022). Betting against betting against beta. Journal of
  Financial Economics 143 (1), 80–106.

Ogden, J. P. (1990). Turn-of-month evaluations of liquid profits and stock returns: A
  common explanation for the monthly and january effects. Journal of Finance 45 (4),
  1259–1272.

Peng, C. and C. Wang (2023). Factor demand and factor returns. Working paper.

Shleifer, A. (1986). Do demand curves for stocks slope down? Journal of Finance 41 (3),
  579–590.

Shum, P., W. Hejazi, E. Haryanto, and A. Rodier (2016). Intraday share price volatility
  and leveraged etf rebalancing. Review of Finance 20 (6), 2379–2409.

                                           32
Vayanos, D. and P. Woolley (2013). An institutional theory of momentum and reversal.
  Review of Financial Studies 26 (5), 1087–1145.

Walter, D., R. Weber, and P. Weiss (2022). Non-standard errors in portfolio sorts.
  Working paper.

Wigglesworth, R. (2018, 18 Sep).          Can factor investing kill off the hedge
  fund.   Financial Times (July 22).    Available at: https://www.ft.com/content/
  2b3e2eaa-6fe6-11e8-92d3-6c13e5c92914 (Last Accessed: November 10, 2025).




                                          33
                    Table 1: Quantile portfolios of stocks sorted by ADD
The top panel of this table reports average monthly annualized returns and further descriptive statistics
for portfolios formed by sorting on anomaly-driven demand. The “Low” ("High") portfolio contains the
stocks with the lowest (highest) anomaly-driven demand. The column “High-Low” reports the difference
in average monthly returns between the High and Low portfolios. The middle panel reports the value-
weighted average of several characteristics for the constituents in the portfolios sorted on anomaly-driven
demand. The characteristics are: market beta (BETA), log market capitalization (SIZE), book-to-market
(BM), the cumulative returns over the 11 months prior to portfolio formation (MOM), the Amihud (2002)
illiquidity measure (ILLIQ), and the COSKEWNESS (COSKEW) of Harvey and Siddique (2000). The
bottom panel reports the average monthly annualized returns for portfolios sorted on changes in long-leg
inclusions and changes in short-leg inclusions separately. Our sample period is January 1990 to December
2023 and t-statistics calculated using Newey and West (1994) standard errors with six lags are provided
in brackets.

                     Low             2              3              4             High        High-Low
                                     Panel A: Portfolio descriptives
 Mean                6.62           7.28           9.14          10.19          10.65           4.03
                    [2.45]         [2.65]         [3.38]         [3.91]         [3.80]         [4.03]
 Std.dev.           16.34          15.76          15.63          15.40          15.80           6.57
 Sharpe ratio        0.41           0.46           0.58           0.66           0.67           0.61
 Skewness           -0.58          -0.62          -0.55          -0.47          -0.39           0.10
 Kurtosis            4.12           4.14           4.34           3.83           3.91          10.47
 Turnover            1.50           1.39           1.35           1.36           1.45
                                    Panel B: Portfolio characteristics
 BETA                 0.76           0.73           0.72           0.73           0.76           0.00
                    [44.56]        [44.49]        [42.96]        [42.30]        [45.22]         [0.03]
 SIZE                16.92          16.93          16.94          16.93          16.92           0.00
                   [149.15]       [146.98]       [143.66]       [145.82]       [148.04]        [-0.10]
 BM                  -1.62          -1.62          -1.63          -1.61          -1.61           0.01
                   [-34.49]       [-36.54]       [-35.00]       [-36.53]       [-34.50]         [0.56]
 MOM                  0.20           0.20           0.20           0.20           0.20           0.01
                     [9.02]         [9.13]         [9.34]         [9.43]         [9.45]         [1.15]
 ILL                  0.00           0.00           0.00           0.00           0.00           0.00
                     [6.37]         [5.89]         [5.44]         [5.92]         [6.38]         [1.19]
 COSKEW               0.28           0.28           0.28           0.28           0.28           0.00
                     [8.65]         [8.60]         [8.64]         [8.75]         [8.54]         [0.13]
                              Panel C: long- and short-leg driven demand
 Long                 7.38          7.65           8.49           9.25           9.87            2.49
                     [2.83]        [2.73]         [3.11]         [3.43]         [3.54]          [2.53]
 Short                9.54          9.35           9.57           8.51           7.07           -2.46
                    [ 3.41]        [3.51]         [3.67]         [3.17]         [2.55]         [-2.22]




                                                    34
                            Table 2: Controlling for factor exposure
This table reports the risk-adjusted annualized returns (Intercept) on the High-Low portfolio from sorting
on ADD (top row of Table 1), and loadings on several control variables. The control variables are: Fama
and French (2015) factors, the Carhart (1997), the first three principal components from our cross-
section of anomaly factors, and the return-differential between the “high NET low absolute ADD” and
“low NET low absolute ADD” portfolio (NET⊥ADD ). Our sample period is January 1990 to December
2023 and t-statistics calculated using Newey and West (1994) standard errors with six lags are provided
in brackets.

                  (1)          (2)          (3)           (4)         (5)          (6)           (7)
  Intercept       4.41         3.58         3.88          3.73         3.50        3.76          3.99
                 [4.31]       [2.70]       [3.58]        [3.45]       [2.63]      [3.42]        [3.17]
   MKT           -0.04        -0.02                                   -0.01                      0.05
                [-2.24]      [-0.57]                                 [-0.39]                    [1.10]
    SMB                        0.04                                    0.02                      0.01
                              [0.82]                                  [0.36]                    [0.21]
    HML                       -0.05                                   -0.08                     -0.11
                             [-0.82]                                 [-1.36]                   [-1.46]
   RMW                         0.02                                    0.01                     -0.04
                              [0.39]                                  [0.15]                   [-0.49]
   CMA                         0.15                                    0.13                      0.05
                              [1.68]                                  [1.49]                    [0.52]
   MOM                         0.03                                    0.02                     -0.13
                              [0.66]                                  [0.48]                   [-2.24]
    PC1                                    -0.01                                   -0.01        -0.02
                                          [-1.92]                                 [-1.69]      [-2.07]
    PC2                                    -0.00                                   -0.00        -0.01
                                          [-0.43]                                 [-0.65]      [-0.87]
    PC3                                     0.02                                    0.02         0.03
                                           [1.73]                                  [1.44]       [2.27]
 NET⊥ADD                                                  0.06        0.06          0.03         0.04
                                                         [1.96]      [2.49]        [1.06]       [1.55]
     R2          1.05         3.57         5.18          2.21         4.67         5.43         8.34




                                                    35
                       Table 3: Anomaly-driven demand and position data
This table reports average monthly changes in short interest (top panel) and average quarterly changes
in breadth of mutual fund ownership (bottom panel) for portfolios formed by sorting on anomaly-driven
demand (top row), changes in the number of long-leg inclusions (middle row), and changes in short-leg
inclusions (bottom row). The “Low” portfolio contains the stocks with the lowest anomaly-driven demand
(top row), the lowest number of changes in long-leg inclusions (middle row), or the lowest number of
changes in short-leg inclusions (bottom row). Similarly, the “High” portfolio contains the stocks with the
highest anomaly-driven demand (top row), the highest number of changes in long-leg inclusions (middle
row), or the highest number of changes in short-leg inclusions (bottom row). The column “High-Low”
reports the difference in average short interest between the High and Low portfolios. Our sample period
is January 2007 to December 2023 and t-statistics calculated using Newey and West (1994) standard
errors with six lags are provided in brackets.

              Low               2               3               4             High          High-Low
                               Panel A: Changes in short-interest
 ADD           0.03           -0.02            0.01           -0.03           -0.11           -0.14
              [0.36]         [-0.18]          [0.07]         [-0.45]         [-1.34]         [-2.27]
 Long          0.04           -0.04           -0.04           -0.05           -0.11           -0.15
              [0.55]         [-0.46]         [-0.38]         [-0.62]         [-1.33]         [-2.86]
 Short        -0.08           -0.03            0.01            0.01            0.01            0.09
             [-0.94]         [-0.41]          [0.12]          [0.16]          [0.12]          [1.06]
                           Panel B: Changes in breadth of ownership
 ADD          0.10            0.12             0.14            0.15            0.14            0.05
             [2.04]          [3.41]           [3.13]          [3.46]          [3.39]          [2.38]
 Long         0.09            0.12             0.14            0.15            0.17            0.08
             [2.06]          [2.93]           [3.01]          [3.21]          [3.60]          [3.09]
 Short        0.11            0.13             0.14            0.14            0.14            0.03
             [2.20]          [3.03]           [2.97]          [3.01]          [3.17]          [0.79]




                                                       36
                                  Table 4: Intramonthly returns
This table reports average returns on portfolios formed by sorting on anomaly-driven demand (top row),
changes in the number of long-leg inclusions (middle row), and changes in short-leg inclusions (bottom
row). The “Low” portfolio contains the stocks with the lowest anomaly-driven demand, while the “High”
portfolio contains the stocks with the highest anomaly-driven demand. The column “High-Low” reports
the difference in average monthly returns between the High and Low portfolios. Panel A show the returns
over the first five trading days in each month, and the remainder of the month. Panel B Splits the returns
over the first five trading days into intraday- (open-to-close) and overnight (close-to-open) returns. Our
sample period is January 1990 to December 2023, for Panel B the starting point is a little later due to
the availability of opening prices. t-statistics calculated using Newey and West (1994) standard errors
with six lags are provided in brackets.

                              Low           2             3            4          High       High-Low
                                                   Panel A: Intramonth returns
 First five trading days      0.22         0.28          0.33         0.38         0.41         0.19
                             [1.67]       [2.14]        [2.55]       [2.93]       [3.13]       [4.10]
 Rest of the month            0.35         0.34          0.45         0.48         0.49         0.13
                             [2.22]       [2.16]        [2.96]       [3.17]       [2.92]       [1.68]
                                  Panel B: First five trading days returns across day and night
 Intraday                     0.08         0.14          0.20         0.25         0.27          0.19
                             [0.74]       [1.36]        [2.00]       [2.54]       [2.64]        [5.28]
 Overnight                    0.60         0.48          0.51         0.58         0.57         -0.04
                             [4.82]       [4.07]        [4.18]       [4.79]       [4.36]       [-0.74]




                                                   37
                  Table 5: Quantile portfolios across anomaly t-statistics
This table reports average monthly annualized returns on portfolios formed by sorting on anomaly-
driven demand (top panel), changes in the number of long-leg inclusions (middle panel), and changes
in short-leg inclusions (bottom panel) across groups based on the anomaly’s t-stastics. We first split
the set of published anomalies into three depending on their reported t-statistic and afterward anomaly-
driven demand estimated within each group. The “Low” portfolio contains the stocks with the lowest
anomaly-driven demand (top row), the lowest number of changes in long-leg inclusions (middle row),
or the lowest number of changes in short-leg inclusions (bottom row). Similarly, the “High” portfolio
contains the stocks with the highest anomaly-driven demand (top row), the highest number of changes in
long-leg inclusions (middle row), or the highest number of changes in short-leg inclusions (bottom row).
The column “High-Low” reports the difference in average monthly returns between the High and Low
portfolios. For these results, our proxy, ADD, has been constructed by scaling the indicator function in
Equation (1) with the t-statistic of the original paper. Our sample period is January 1990 to December
2023 and t-statistics calculated using Newey and West (1994) standard errors with six lags are provided
in brackets.

                      Low             2             3                   4      High        High-Low
                                                            ADD
 Low t-stat           9.03           8.29          8.76                8.58     9.08          0.05
                     [3.31]         [3.22]        [3.34]              [3.28]   [3.31]        [0.05]
 Medium t-stat        9.03           8.43          8.64                8.60     8.26         -0.76
                     [3.23]         [3.33]        [3.35]              [3.25]   [2.92]       [-0.77]
 High t-stat          6.47           7.82          8.72                9.50    11.53          5.06
                     [2.32]         [2.83]        [3.22]              [3.60]   [4.29]        [4.14]
                                                           Long-leg
 Low t-stat           8.44           8.55          8.55                8.32     8.69          0.25
                     [3.10]         [3.24]        [3.27]              [3.17]   [3.19]        [0.33]
 Medium t-stat        8.69           8.92          9.19                8.46     8.13         -0.56
                     [3.33]         [3.47]        [3.50]              [3.19]   [2.96]       [-0.68]
 High t-stat          7.05           7.76          8.42                9.84    11.20          4.16
                     [2.50]         [2.77]        [3.09]              [3.78]   [4.37]        [4.09]
                                                        Short-leg
 Low t-stat           8.62           9.04          8.95                8.95     8.47         -0.15
                     [3.12]         [3.49]        [3.46]              [3.44]   [3.08]       [-0.18]
 Medium t-stat        8.98           8.84          8.87                8.71     7.90         -1.09
                     [3.27]         [3.47]        [3.51]              [3.41]   [2.77]       [-1.38]
 High t-stat          9.78           8.98          8.65                8.34     7.90         -1.88
                     [3.76]         [3.45]        [3.28]              [3.15]   [2.85]       [-2.07]




                                                  38
                 Table 6: Anomaly-driven demand across size and liquidity
This table reports the average monthly return annualized differential between the “Low” and “High”
from a bivariate sort. We first sort stocks into quintile portfolios based on the market cap (top panel) or
the illiquidity measure of Amihud (2002) (bottom panel). Then within each quintile, stocks are sorted
into quintile portfolios based on changes in the number of long-leg inclusions (first column), changes in
the number of short-leg inclusions (middle column), or anomaly-driven demand (last column) and we
report the return differential between the “High” and “Low” portfolios. For example, the combination
Micro/ADD means that for the smallest stocks, the return differential between the portfolio containing
stocks with high anomaly-driven demand and the portfolio containing the stocks with low anomaly-driven
demand is 5.71%. Our sample period is January 1990 to December 2023 and t-statistics calculated using
Newey and West (1994) standard errors with six lags are provided in brackets.

                            Long                        Short                           ADD
                                               Panel A: Market cap/Size
 Micro                       4.83                         -2.17                          7.44
                            [4.80]                       [-1.25]                        [6.22]
 2                           3.35                         -2.70                          5.04
                            [2.93]                       [-2.32]                        [4.72]
 3                           1.43                         -2.05                          2.12
                            [1.19]                       [-1.83]                        [1.82]
 4                           3.34                         -0.98                          2.82
                            [3.76]                       [-0.87]                        [2.46]
 Mega                        3.05                         -2.63                          3.05
                            [2.62]                       [-1.99]                        [2.39]
                                                   Panel B: Illiquidity
 Most liquid                 3.69                         -3.17                          3.00
                            [3.03]                       [-2.29]                        [2.46]
 2                           3.08                         -1.00                          2.00
                            [2.69]                       [-0.88]                        [1.47]
 3                           1.34                         -2.82                          3.22
                            [1.24]                       [-2.39]                        [2.70]
 4                           2.78                         -2.56                          4.03
                            [2.34]                       [-2.08]                        [2.65]
 Most illiquid               6.62                         -4.74                          8.31
                            [5.53]                       [-3.38]                        [5.37]




                                                    39
                                Table 7: Rank based weighting
This table reports average monthly annualized returns on portfolios formed by sorting on changes in
the sum of ranks across anomalies. Specifically, each stock is ranked based on its beginning-of-month
characteristic and we sum the ranks over the different anomaly-characteristics. The “Low” portfolio
contains the stocks with the lowest change in the sum of ranks in the previous month. Similarly, the
“High” portfolio contains the stocks with the largest change in the sum of ranks in the previous month.
The column “High-Low” reports the difference in average monthly returns between the High and Low
portfolios. Our sample period is January 1990 to December 2023 and t-statistics calculated using Newey
and West (1994) standard errors with six lags are provided in brackets.

                       Low            2             3             4           High        High-Low
 Long and short        8.19          7.70          8.42          8.48         11.25          3.06
                      [2.78]        [2.83]        [3.24]        [3.24]        [3.80]        [2.13]
 Long                  8.42          7.95          7.81          8.87         10.95          2.53
                      [3.05]        [2.73]        [2.95]        [3.36]        [3.81]        [1.97]
 Short                 7.31          8.13          8.79         10.10          9.36          2.05
                      [2.42]        [3.12]        [3.43]        [3.78]        [3.25]        [1.58]




                                                  40
                Table 8: Robustness: number of portfolios in portfolio sorts.
This table reports the average monthly annualized return differential between the portfolios with low
and high anomaly-driven demand, using different numbers of portfolios for 1) Constructing our ADD
proxy (columns) and 2) Sorting stocks based on their ADD (rows). For example 10 in the column and
3 in the rows means that for each anomaly characteristic stocks are sorted into decile portfolios for
counting for calculating ADD. Then subsequently stocks are sorted into tercile portfolios based on ADD
for estimating the arbitrageur rebalancing effect. Our sample period is January 1990 to December 2023
and t-statistics calculated using Newey and West (1994) standard errors with six lags are provided in
brackets.

                                     3                        5                        10
            3                       3.02                     3.19                     1.88
                                   [3.67]                   [3.71]                   [2.71]
            5                       2.86                     4.03                     2.84
                                   [2.77]                   [4.03]                   [3.13]
           10                       3.65                     4.24                     2.29
                                   [2.37]                   [3.09]                   [1.52]




                                                 41
                            Table 9: Robustness: rebalancing frequency
This table reports average monthly annualized returns on portfolios formed by sorting on anomaly-driven
demand (top row), changes in the number of long-leg inclusions (middle row), and changes in short-leg
inclusions (bottom row). The “Low” portfolio contains the stocks with the lowest anomaly-driven demand
(top row), the lowest number of changes in long-leg inclusions (middle row), or the lowest number of
changes in short-leg inclusions (bottom row). Similarly, the “High” portfolio contains the stocks with the
highest anomaly-driven demand (top row), the highest number of changes in long-leg inclusions (middle
row), or the highest number of changes in short-leg inclusions (bottom row). The column “High-Low”
reports the difference in average monthly returns between the High and Low portfolios. For these results,
our proxy, ADD, is constructed using the rebalancing frequency of the original papers. Our sample period
is January 1990 to December 2023 and t-statistics calculated using Newey and West (1994) standard
errors with six lags are provided in brackets.

                    Low              2              3              4            High        High-Low
    ADD             7.61           7.61           8.42           9.42          10.02            2.41
                   [2.80]         [2.89]         [3.14]         [3.49]         [3.56]          [2.46]
     Long           7.00           7.74           9.31           9.05          10.20            3.21
                   [2.66]         [2.89]         [3.56]         [3.41]         [3.61]          [3.19]
    Short           9.72           8.80           8.83           9.19           7.50           -2.23
                   [3.55]         [3.26]         [3.35]         [3.52]         [2.76]         [-2.28]




                                                   42
                                        Figure 1: BM portfolio sort
This figure illustrates the construction of a value factor using portfolio sorts. At each rebalancing date,
stocks are sorted into quintile portfolios based on their book-to-market ratio (BM). The bottom quintile
contains the 20% of stocks with the lowest BM values (Growth), while the top quintile contains the 20%
of stocks with the highest BM values (Value), as shown in Panel (a). At the subsequent rebalancing,
as BM ratios are updated, stocks are reallocated across quintile portfolios, as shown in Panel (b). For
example, stocks “U,” “Q,” and “J” are no longer in the Value portfolio, while stocks “T,” “G,” and “O”
enter the Value portfolio. Similarly, stocks “X,” “Z,” and “B” leave the Growth portfolio, while “U,”
“N,” and “I” move into it.



    Growth            Portfolio 2            Portfolio 3       Portfolio 4            Value
    X, Z, B, ...         U, N, I, ...          Y, H, J, ...      T, G, O, ...        U, Q, J,...




                                  (a) Quintile portfolios pre-BM update




    Growth            Portfolio 2            Portfolio 3       Portfolio 4            Value
     U, N, I, ...        X, Z, B, ...          Y, H, J, ...      U, Q, J, ...        T, G, O,...




                                 (b) Quintile portfolios post-BM update




                                                        43
                                                                                         Share of total anomalies in data




                                                                                  0.02
                                                                                          0.04
                                                                                                   0.06
                                                                                                            0.08
                                                                                                                            0.12
                                                                                                                                   0.14
                                               as




                                                                              0
                                                                                                                     0.1
                                                                                                                                                                               19




                                                                                                                                                                                          50




                                                                                                                                                                                      0
                                                                                                                                                                                               100
                                                                                                                                                                                                     150
                                                                                                                                                                                                           200
                                                                                                                                                                                                                 250
                                                   se                                                                                                                            90
                                          co           tc a R
                                             m
                                               po ca om ccr &D                                                                                                                 19
                                                   si sh po ua                                                                                                                   92
                                                      te f si ls
                                                          ac low tio
                                                             c           n                                                                                                     19
                                                     e     d o ri                                                                                                                94
                                                ea ar efaunt sk
                                                     rn nin ul ing
                                                  e in gs t r                                                                                                                  19
                                                ex arn gs f ev isk                                                                                                               96
                                                    te ing or en
                                                       rn s ec t
                                                          al gr as                                                                                                             19
                                                  in         fi o t                                                                                                              98
                                                     fo in nan wth
                                                         rm fo c
                                                            ed p ing                                                                                                           20
                                                                    r                                                                                                            00
                                              in in inv tra oxy
                                                 ve v e di
                                                      st es stm ng                                                                                                             20
                                                         m tm e
                                                           en e n                                                                                                                02
                                                              t g nt t
                                                                  r a                                                                                                          20
                                                               le owt lt                                                                                                         04
                                               lo
                                                  ng          le ad l h
                                                        te l ver ag                                                                                                            20
                                                          rm iq ag                                                                                                               06




44
                                                                   u e
                                                          m rev idit                                                                                                           20
                                                             om e y
                                                                      r                                                                                                          08
                                                            op en sal
                                                                tio tum
                                                  pa               nr                                                                                                          20
                                                       yo ow o isk                                                                                                               10
                                                          ut ne the
                                                             i r r                                                                                                             20
                                                           p nd sh                                                                                                               12
                                                 re pro rof ica ip
                                                    co fit ita to
                                                         m ab bil r                                                                                                            20
                                           sh              m ili ity
                                                             en ty                                                                                                               14
                                              or                        a
                                                 t s sa dat lt
                                                                       io                                                                                                      20




                                                                                                                                          (a) Number of anomalies in dataset




     (b) Anomalies by economic category
                                                     al le                                                                                                                       16
                                                        e s rn
                                                           co gr is
                                                              ns ow k                                                                                                          20
                                                             va trai th                                                                                                          18
                                                                 lu nt
                                                              vo atios                                                                                                         20
                                                                  la n                                                                                                           20
                                                                vo tilit
                                                                   lu y
                                                                       m                                                                                                       20
                                                                                                                                                                                                                                                                                                                              Figure 2: Number published of anomalies over time




                                                                          e                                                                                                      22
                                                                                                                                                                                                                       December 2023, and anomaly characteristics are obtained from Chen and Zimmermann (2022).
                                                                                                                                                                                                                       distribution of anomalies across economic categories (Panel b). Our sample period is January 1990 to
                                                                                                                                                                                                                       This figure shows the number of anomaly characteristics over time in our dataset (Panel a) and the
       Figure 3: Cumulative return differential between High and Low portfolios.
This figure shows the cumulative annualized return differential betwen the Low and High portfolios from
sorting on ADD (blue), changes in the number long-leg inclusions (orange), and changes in the number
of short-leg inclusions (green). Our sample period is January 1990 to December 2023.




                                                  45
                                                  Figure 4: ADD-sorted portfolios over the month
This figure shows the intra-monthly daily return differential between low- and high ADD stocks. Our
sample period is January 1990 to December 2023.


                                          0.12


                                            0.1


                                          0.08


                                          0.06
              Mean daily excess returns




                                          0.04


                                          0.02


                                             0


                                          -0.02


                                          -0.04


                                          -0.06


                                          -0.08
                                                   1   2   3   4   5   6   7   8   9   10 11 12 13 14 15 16 17 18 19 20




                                                                                       46
                                                                                                                                                                                                                                                                                                        2023.
                                                                                             Difference in mean monthly excess returns
                                                                                                                                                                                                                                                              Mean monthly excess returns




                                                                              -0.25
                                                                                                 -0.15
                                                                                                                -0.05




                                                                                      -0.2
                                                                                                         -0.1
                                                                                                                               0.05
                                                                                                                                               0.15
                                               as




                                                                                                                        0
                                                                                                                                         0.1
                                                                                                                                                                                                                                                -0.6
                                                                                                                                                                                                                                                       -0.4
                                                                                                                                                                                                                                                                 -0.2
                                                                                                                                                                                                                 as




                                                                                                                                                                                                                                                                          0
                                                                                                                                                                                                                                                                                    0.2
                                                                                                                                                                                                                                                                                            0.4
                                                                                                                                                                                                                                                                                                  0.6
                                                   se                                                                                                                                                               se
                                          co           tc a R                                                                                                                                               co
                                             m                                                                                                                                                                m
                                                                                                                                                                                                                        tc a R
                                               po ca om ccr &D                                                                                                                                                  po ca om ccr &D
                                                   si sh po ua                                                                                                                                                      si sh po ua
                                                      te f si ls                                                                                                                                                       te f si ls
                                                          ac low tio
                                                             c           n                                                                                                                                                 ac low tio
                                                                                                                                                                                                                              c            n
                                                     e     d o ri                                                                                                                                                           d o ri
                                                ea ar efaunt sk                                                                                                                                                  ea ear efaunt sk
                                                     rn nin ul ing                                                                                                                                                         n
                                                                                                                                                                                                                      rn i u ng         i
                                                  e in gs t r                                                                                                                                                      e in ngs lt r
                                                ex arn gs f ev isk                                                                                                                                               ex arn gs f ev isk
                                                    te ing or en                                                                                                                                                     te ing or en
                                                       rn s ec t                                                                                                                                                        rn s ec t
                                                          al gr as                                                                                                                                                         al gr as
                                                  in         fi o t                                                                                                                                                in         fi o t
                                                     fo in nan wth                                                                                                                                                    fo in nan wth
                                                         rm fo c                                                                                                                                                          rm fo c
                                                            ed p ing
                                                                    r                                                                                                                                                        ed p ing
                                                                                                                                                                                                                                      r
                                              in in inv tra oxy                                                                                                                                                in in inv tra oxy
                                                 ve v e di                                                                                                                                                        ve v e di
                                                      st es stm ng                                                                                                                                                     st es stm ng
                                                         m tm e                                                                                                                                                           m tm e
                                                           en e n                                                                                                                                                           en e n
                                                              t g nt t                                                                                                                                                         t g nt t
                                                                  r a                                                                                                                                                              r a
                                                               le owt lt
                                               lo                                                                                                                                                               lo
                                                                                                                                                                                                                                le owt lt
                                                  ng          le ad l h                                                                                                                                            ng          le ad l h
                                                        te l ver ag                                                                                                                                                      te l ver ag
                                                          rm iq ag




47
                                                                   u e                                                                                                                                                     rm iq ag
                                                          m rev idit                                                                                                                                                                u e
                                                             om e y                                                                                                                                                        m rev idit
                                                                      r                                                                                                                                                       om e y
                                                                                                                                                                                                                                        r
                                                            op en sal                                                                                                                                                              e
                                                                                                                                                                                                                             op n sal
                                                                tio tum                                                                                                                                                          tio tum
                                                  pa               nr
                                                                                                                                                                                                                   pa               n  r
                                                       yo ow o isk                                                                                                                                                      yo ow o isk
                                                          ut ne the                                                                                                                                                        ut ne the
                                                             i r r                                                                                                                                                            in rs r
                                                           p nd sh                                                                                                                                                          p d h
                                                 re pro rof ica ip                                                                                                                                                re pro rof ica ip
                                                    co fit ita to                                                                                                                                                    co fit ita to
                                                         m ab bil r                                                                                                                                                       m ab bil r
                                           sh              m ili ity                                                                                                                                                        m ili ity
                                                             en ty                                                                                                                                          sh
                                              or                        a                                                                                                                                                     en ty
                                                                                                                                                                                                                                          a




     (b) Change in overall price impact
                                                 t s sa dat lt                                                                                                                                                 or
                                                     al le             io                                                                                                                                         t s sa dat lt
                                                                                                                                                                                                                      al le              io
                                                        e s rn                                                                                                                                                           e s rn
                                                           co gr is                                                                                                                                                         co gr is
                                                              ns ow k                                                                                                                                                          ns ow k
                                                             va trai th                                                                                                                                                       va trai th
                                                                 lu nt                                                                                                                                                            lu nt
                                                              vo atios                                                                                                                                                         vo atios
                                                                  la n




                                                                                                                                                      (a) Price impact for individual economic categories
                                                                vo tilit                                                                                                                                                           la n
                                                                   lu y                                                                                                                                                          vo tilit
                                                                       m                                                                                                                                                             lu y
                                                                          e                                                                                                                                                              m
                                                                                                                                                                                                                                            e
                                                                                                                                                                                                                                                                                                                                                                                                               Figure 5: Anomaly-driven demand across economic categories

                                                                                                                                                                                                                                                                                                        The plot shows the average daily return differential Our sample period is January 1990 to December
                                                                                                                                                                                                                                                                                                        This figure shows the intra-monthly annualized return differential between low- and high ADD stocks.
