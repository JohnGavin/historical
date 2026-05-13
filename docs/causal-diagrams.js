// Causal DAG diagrams for falsification dashboard
// Loaded via <script src="causal-diagrams.js"> in include-in-header

import mermaid from "https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs";
mermaid.initialize({startOnLoad:false, securityLevel:"loose", theme:"dark",
  themeVariables:{background:"#000",primaryColor:"#999",lineColor:"#C00",primaryTextColor:"#000"}});

// Hover tooltips for diagram nodes — native SVG <title> element
var nodeTooltips = {
  // Factors
  "HML": "High Minus Low (Value Factor) — long cheap stocks, short expensive. Source: hd_factors('FF5')",
  "SMB": "Small Minus Big (Size Factor) — long small caps, short large caps. Source: hd_factors('FF5')",
  "Mom": "Momentum Factor — long recent winners, short recent losers. Source: hd_factors('FF5')",
  "RMW": "Robust Minus Weak (Profitability Factor) — long profitable, short unprofitable. Source: hd_factors('FF5')",
  "Mkt_RF": "Market Risk Premium — equity market return minus risk-free rate. Source: hd_factors('FF5')",
  "Factors": "Fama-French factors from Ken French Data Library. Source: hd_factors()",
  // Macro
  "VIX": "CBOE Volatility Index — implied volatility of S&P 500 options. High VIX = fear. Source: hd_macro('VIXCLS')",
  "VTS": "VIX Term Structure — ratio of VIX to 3-month VIX futures. Inverted = elevated fear. Source: plan_vix_macro_overlay.R",
  "VVIX": "Volatility of VIX — measures uncertainty about future volatility. Source: plan_vix_macro_overlay.R",
  "Fed": "Federal Funds Rate — short-term interest rate set by the Fed. Source: hd_macro('FEDFUNDS')",
  "Infl": "Inflation — year-over-year change in consumer prices. Source: hd_macro('CPIAUCSL')",
  "Macro": "Macro signals: VIX, rates, inflation. Source: plan_regime.R",
  // Regimes
  "VolR": "Volatility Regime — benign/cautious/hostile based on VIX percentiles. Source: plan_risk_state.R",
  "RateR": "Rate Regime — rising/stable/falling based on Fed funds trajectory. Source: plan_regime.R",
  // Strategies
  "DRIF": "Daily Return Info Factor — elastic net on full distribution of 21-day factor returns. Source: plan_drif.R",
  "DRIF_S": "DRIF Signal — predicted next-month return for each FF factor. Source: plan_drif.R",
  "DRIF_R": "DRIF Strategy Return — actual return from holding predicted best factor. Source: plan_drif.R",
  "FMAX": "Factor MAX — rotate to factor with highest max daily return last month. Source: plan_factormax.R",
  "FMAX_S": "FacMAX Signal — which factor had highest MAX signal. Source: plan_factormax.R",
  "FMAX_R": "FacMAX Return — return from holding MAX-selected factor. Source: plan_factormax.R",
  "LTR": "Long-Term Reversal — cross-sectional momentum on factors. Source: plan_ltr_momentum.R",
  "LTR_S": "LTR Signal — momentum rank across factors. Source: plan_ltr_momentum.R",
  "LTR_R": "LTR Return — return from momentum-selected factor. Source: plan_ltr_momentum.R",
  "RSC": "Risk State Conditioned — reduce equity exposure in hostile vol regimes. Source: plan_risk_state.R",
  "RSC_S": "RSC Signal — current vol regime state (benign/cautious/hostile). Source: plan_risk_state.R",
  "VIXO": "VIX Overlay — reduce equity when VIX elevated. Source: plan_vix_macro_overlay.R",
  "VIX_S": "VIX Overlay Signal — binary risk-on/risk-off. Source: plan_vix_macro_overlay.R",
  // Portfolio
  "PORT": "Portfolio Return — combined return from all strategies. Source: plan_multi_strategy.R",
  "MKT_R": "Market Return — buy-and-hold equity benchmark. Source: plan_backtest.R",
  "MDD": "Maximum Drawdown — largest peak-to-trough decline. Lower is better.",
  "SR": "Sharpe Ratio — risk-adjusted return (excess return / volatility). Higher is better.",
  "RISK": "Risk Metrics — Sharpe ratio, maximum drawdown, volatility.",
  // Structural
  "Crowd": "Factor Crowding — when too many investors hold the same position, returns decay. Source: plan_strategy_decay.R",
  "Decay": "Premium Decay — factor premiums weaken after discovery and crowding. Source: plan_strategy_decay.R",
  "Cost": "Rebalance Cost — trading costs from monthly rebalancing. Source: plan_alpha_decay.R",
  "Structural": "Structural headwinds: crowding, decay, transaction costs. Source: plan_strategy_decay.R",
  "Market": "Market — equity market exposure underlying all strategies."
};

// Edge hover tooltips and click links.
//
// Audit of ALL edges across all 5 diagrams:
//
//   dag-overview-mount:
//     Labeled:   Macro -.->|"r=-0.17"| Factors
//     Unlabeled: Factors-->DRIF, Factors-->FMAX, Factors-->LTR,
//                Macro-->VolR, Macro-->RateR, VolR-->RSC, VolR-->VIXO,
//                RateR-->LTR, Market-->DRIF, Market-->FMAX, Market-->LTR,
//                DRIF-->PORT, FMAX-->PORT, LTR-->PORT, RSC-->PORT, VIXO-->PORT,
//                PORT-->RISK, Structural-->DRIF, Structural-->FMAX
//
//   dag-full-mount:
//     Labeled:   VIX -.->|"r=-0.17 VIOLATED"| HML
//     Unlabeled: HML-->DRIF_S, SMB-->DRIF_S, Mom-->DRIF_S, RMW-->DRIF_S,
//                HML-->FMAX_S, SMB-->FMAX_S, Mom-->FMAX_S, Mom-->LTR_S, SMB-->LTR_S,
//                VIX-->VolR, VTS-->VolR, VVIX-->VolR, Fed-->RateR, Infl-->RateR,
//                VolR-->RSC_S, VolR-->VIX_S, RateR-->LTR_S,
//                DRIF_S-->DRIF_R, FMAX_S-->FMAX_R, LTR_S-->LTR_R,
//                RSC_S-->MKT_R, VIX_S-->MKT_R, Mkt_RF-->MKT_R,
//                Mkt_RF-->DRIF_R, Mkt_RF-->FMAX_R, Mkt_RF-->LTR_R,
//                Crowd-->Decay, Decay-->FMAX_R, Decay-->DRIF_R,
//                DRIF_R-->PORT, FMAX_R-->PORT, LTR_R-->PORT, Cost-->PORT,
//                PORT-->SR, PORT-->MDD, VolR-->MDD
//
//   dag-drif-mount:
//     Labeled:   VIX -.->|"r=-0.17"| HML
//     Unlabeled: HML-->DRIF_S, SMB-->DRIF_S, Mom-->DRIF_S, RMW-->DRIF_S,
//                DRIF_S-->DRIF_R, Mkt_RF-->DRIF_R, Decay-->DRIF_R, DRIF_R-->PORT
//
//   dag-fmax-mount:
//     Labeled:   (none)
//     Unlabeled: HML-->FMAX_S, SMB-->FMAX_S, Mom-->FMAX_S,
//                FMAX_S-->FMAX_R, Mkt_RF-->FMAX_R, Decay-->FMAX_R, FMAX_R-->PORT
//
//   dag-ltr-mount:
//     Labeled:   (none)
//     Unlabeled: Mom-->LTR_S, SMB-->LTR_S, RateR-->LTR_S,
//                LTR_S-->LTR_R, Mkt_RF-->LTR_R, LTR_R-->PORT
//
// Total edges covered: 2 labeled + 47 unlabeled across 5 diagrams.
// Shared edges (same logical edge, multiple diagrams) use one entry.
var edgeMetadata = {
  // ── LABELED EDGES ──────────────────────────────────────────────────────────

  // ── dag-full-mount: VIX -.->|"r=-0.17 VIOLATED"| HML ─────────────────────
  // This is the key falsification test: VIX and HML should be d-separated in
  // the structural causal model, but partial correlation is r = -0.17.
  // Tested in plan_causal_graph.R::partial_cor() (line ~259) and the pre/post
  // 2010 split test cg_test_split (line ~352). Stronger pre-2010, weaker post.
  "r=-0.17 VIOLATED": {
    tooltip: "Partial r = -0.17 (p < 0.05). VIX and HML should be conditionally independent given Mkt-RF — this edge violates that assumption. Tested in plan_causal_graph.R (partial_cor, cg_test_split). Pre-2010 r ≈ -0.26, 2010+ r ≈ -0.14.",
    href: "https://github.com/JohnGavin/historical/blob/main/R/plan_causal_graph.R"
  },

  // ── dag-overview-mount / dag-drif-mount: Macro/VIX -.->|"r=-0.17"| Factors/HML ───
  // Same statistical finding but shown in overview/DRIF detail diagrams with
  // shorter label text. Same test function: plan_causal_graph.R partial_cor().
  "r=-0.17": {
    tooltip: "Partial r = -0.17. VIX co-moves with HML sell-offs in crisis months — a violation of the assumed d-separation in the causal graph. Source: plan_causal_graph.R partial_cor() and cg_test_split tar_target.",
    href: "https://github.com/JohnGavin/historical/blob/main/R/plan_causal_graph.R"
  },

  // ── UNLABELED EDGES: Factor inputs to strategy signals ────────────────────

  // HML -> DRIF_S (dag-full-mount, dag-drif-mount)
  // plan_drif.R: drif_daily fetches HML from hd_factors('FF5'), then drif_features
  // computes 21-day rolling returns per factor. drif_signal applies elastic net.
  "HML->DRIF_S": {
    tooltip: "HML daily returns are one of the 5 factor inputs (HML, SMB, RMW, CMA, Mom) to the DRIF elastic net. Source: plan_drif.R tar_target(drif_daily) and tar_target(drif_signal).",
    href: "https://github.com/JohnGavin/historical/blob/main/R/plan_drif.R"
  },

  // SMB -> DRIF_S (dag-full-mount, dag-drif-mount)
  "SMB->DRIF_S": {
    tooltip: "SMB daily returns are one of the 5 factor inputs to the DRIF elastic net signal. Source: plan_drif.R tar_target(drif_daily) and tar_target(drif_signal).",
    href: "https://github.com/JohnGavin/historical/blob/main/R/plan_drif.R"
  },

  // Mom -> DRIF_S (dag-full-mount, dag-drif-mount)
  "Mom->DRIF_S": {
    tooltip: "Momentum daily returns are one of the 5 factor inputs to the DRIF elastic net signal. Source: plan_drif.R tar_target(drif_daily) and tar_target(drif_signal).",
    href: "https://github.com/JohnGavin/historical/blob/main/R/plan_drif.R"
  },

  // RMW -> DRIF_S (dag-full-mount, dag-drif-mount)
  "RMW->DRIF_S": {
    tooltip: "RMW (profitability) daily returns are one of the 5 factor inputs to the DRIF elastic net signal. Source: plan_drif.R tar_target(drif_daily) and tar_target(drif_signal).",
    href: "https://github.com/JohnGavin/historical/blob/main/R/plan_drif.R"
  },

  // HML -> FMAX_S (dag-full-mount, dag-fmax-mount)
  // plan_factormax.R: fm_signal computes MAX (highest single-day return in month)
  // for each factor in c("HML","SMB","RMW","CMA","Mom"). HML is included.
  "HML->FMAX_S": {
    tooltip: "HML is one of the factors ranked by MAX signal (highest single-day return in prior month). Source: plan_factormax.R tar_target(fm_signal).",
    href: "https://github.com/JohnGavin/historical/blob/main/R/plan_factormax.R"
  },

  // SMB -> FMAX_S (dag-full-mount, dag-fmax-mount)
  "SMB->FMAX_S": {
    tooltip: "SMB is one of the factors ranked by MAX signal (highest single-day return in prior month). Source: plan_factormax.R tar_target(fm_signal).",
    href: "https://github.com/JohnGavin/historical/blob/main/R/plan_factormax.R"
  },

  // Mom -> FMAX_S (dag-full-mount, dag-fmax-mount)
  "Mom->FMAX_S": {
    tooltip: "Momentum is one of the factors ranked by MAX signal. Source: plan_factormax.R tar_target(fm_signal).",
    href: "https://github.com/JohnGavin/historical/blob/main/R/plan_factormax.R"
  },

  // Mom -> LTR_S (dag-full-mount, dag-ltr-mount)
  // plan_causal_graph.R defines Mom -> LTR_signal in the structural DAG (line ~31).
  // plan_ltr_momentum.R uses momentum-based features: lookback-window mom features.
  "Mom->LTR_S": {
    tooltip: "Momentum factor return is one of the cross-section inputs to the LTR signal momentum ranking. Source: plan_causal_graph.R (structural edge line ~31); plan_ltr_momentum.R tar_target(ltr_features).",
    href: "https://github.com/JohnGavin/historical/blob/main/R/plan_ltr_momentum.R"
  },

  // SMB -> LTR_S (dag-full-mount, dag-ltr-mount)
  "SMB->LTR_S": {
    tooltip: "SMB factor return is one of the cross-section inputs to the LTR signal momentum ranking. Source: plan_causal_graph.R (structural edge line ~32); plan_ltr_momentum.R tar_target(ltr_features).",
    href: "https://github.com/JohnGavin/historical/blob/main/R/plan_ltr_momentum.R"
  },

  // ── UNLABELED EDGES: Macro -> Regime ──────────────────────────────────────

  // VIX -> VolR (dag-full-mount)
  // plan_risk_state.R: rsc_data fetches VIX (VIXCLS) and VVIX. rsc_regime
  // classifies benign/cautious/hostile using VVIX percentile threshold.
  "VIX->VolR": {
    tooltip: "VIX level (VIXCLS = 30-day implied vol) is fetched in rsc_data and used alongside VTS and VVIX to classify the vol regime (benign/cautious/hostile). Source: plan_risk_state.R tar_target(rsc_data) and tar_target(rsc_regime).",
    href: "https://github.com/JohnGavin/historical/blob/main/R/plan_risk_state.R"
  },

  // VTS -> VolR (dag-full-mount)
  // plan_risk_state.R: VIX3M/VIX1M slope used in rsc_signals (slope_ratio, slope_change).
  "VTS->VolR": {
    tooltip: "VIX term structure (VIX3M/VIX1M ratio) — slope change and level — are signals 2 and 3 in the vol regime classifier. Source: plan_risk_state.R tar_target(rsc_signals) and tar_target(rsc_regime).",
    href: "https://github.com/JohnGavin/historical/blob/main/R/plan_risk_state.R"
  },

  // VVIX -> VolR (dag-full-mount)
  // plan_risk_state.R: VVIX percentile is signal 1 (earliest warning) in rsc_regime.
  "VVIX->VolR": {
    tooltip: "VVIX (vol-of-vol, earliest warning signal) percentile against rsc_thresholds determines hostile/cautious/benign classification. Source: plan_risk_state.R tar_target(rsc_regime) line ~136-165.",
    href: "https://github.com/JohnGavin/historical/blob/main/R/plan_risk_state.R"
  },

  // Fed -> RateR (dag-full-mount)
  // plan_causal_graph.R: Fed_rate -> Rate_regime structural edge (line ~39).
  // Rate_regime proxy: Fed_rate > median(Fed_rate) (plan_causal_graph.R line ~220-223).
  "Fed->RateR": {
    tooltip: "Federal funds rate (FEDFUNDS) feeds into Rate_regime classification. Rate_regime = 1 when Fed_rate > historical median. Source: plan_causal_graph.R tar_target(cg_data) line ~220-223.",
    href: "https://github.com/JohnGavin/historical/blob/main/R/plan_causal_graph.R"
  },

  // Infl -> RateR (dag-full-mount)
  // Structural-only: inflation is a driver of rate regime in the causal model
  // (central bank raises rates when inflation is elevated). Not directly implemented
  // in a single tar_target — the Rate_regime in plan_causal_graph.R uses Fed_rate only,
  // but inflation is theoretically the upstream cause of rate moves.
  "Infl->RateR": {
    tooltip: "Inflation (CPI) is the upstream structural cause of rate regime shifts — central banks raise rates in response to high inflation. Structural edge in plan_causal_graph.R; Rate_regime proxy uses Fed_rate (plan_causal_graph.R line ~220-223).",
    href: "https://github.com/JohnGavin/historical/blob/main/R/plan_causal_graph.R"
  },

  // ── UNLABELED EDGES: Regime -> Signal ─────────────────────────────────────

  // VolR -> RSC_S (dag-full-mount)
  // plan_risk_state.R: rsc_regime produces the vol regime. rsc_portfolio uses regime
  // to scale exposure (benign=100%, cautious=50%, hostile=10%).
  "VolR->RSC_S": {
    tooltip: "Vol regime (benign/cautious/hostile) from rsc_regime directly determines RSC exposure scaling: 100%/50%/10%. Source: plan_risk_state.R tar_target(rsc_regime) and tar_target(rsc_portfolio).",
    href: "https://github.com/JohnGavin/historical/blob/main/R/plan_risk_state.R"
  },

  // VolR -> VIX_S (dag-full-mount)
  // plan_vix_macro_overlay.R: vmo_results applies a binary risk-on/risk-off overlay
  // using VIX threshold (exit at VIX > vix_high, re-enter at VIX < vix_reentry).
  "VolR->VIX_S": {
    tooltip: "Vol regime state feeds into the VIX overlay binary signal: exit equity when VIX > threshold, re-enter when VIX < re-entry level. Source: plan_vix_macro_overlay.R tar_target(vmo_results).",
    href: "https://github.com/JohnGavin/historical/blob/main/R/plan_vix_macro_overlay.R"
  },

  // RateR -> LTR_S (dag-full-mount, dag-ltr-mount)
  // plan_causal_graph.R: Rate_regime -> LTR_signal structural edge (line ~44-45).
  // Rate regime is a conditioning variable in the d-separation test for LTR.
  "RateR->LTR_S": {
    tooltip: "Rate regime conditions LTR signal generation — rising rates affect factor momentum dynamics. Structural edge in plan_causal_graph.R (line ~44-45); tested in d-separation analysis.",
    href: "https://github.com/JohnGavin/historical/blob/main/R/plan_causal_graph.R"
  },

  // ── UNLABELED EDGES: Signal -> Return ─────────────────────────────────────

  // DRIF_S -> DRIF_R (dag-full-mount, dag-drif-mount)
  // plan_drif.R: drif_portfolio uses drif_signal (predicted factor returns) to select
  // top-N factors, then holds them — converting signal to actual return.
  "DRIF_S->DRIF_R": {
    tooltip: "DRIF signal (predicted factor return from elastic net) drives portfolio construction: long top-predicted factors each month. Source: plan_drif.R tar_target(drif_portfolio).",
    href: "https://github.com/JohnGavin/historical/blob/main/R/plan_drif.R"
  },

  // FMAX_S -> FMAX_R (dag-full-mount, dag-fmax-mount)
  // plan_factormax.R: fm_portfolio selects top-N factors by fm_signal (MAX rank).
  "FMAX_S->FMAX_R": {
    tooltip: "FacMAX signal (factor ranked by highest single-day return last month) selects which factors to hold. Source: plan_factormax.R tar_target(fm_portfolio).",
    href: "https://github.com/JohnGavin/historical/blob/main/R/plan_factormax.R"
  },

  // LTR_S -> LTR_R (dag-full-mount, dag-ltr-mount)
  // plan_ltr_momentum.R: ltr_portfolio translates ltr_features (signal) into returns.
  "LTR_S->LTR_R": {
    tooltip: "LTR signal (LambdaMART momentum rank) drives long/short equity portfolio construction, producing monthly strategy returns. Source: plan_ltr_momentum.R tar_target(ltr_portfolio).",
    href: "https://github.com/JohnGavin/historical/blob/main/R/plan_ltr_momentum.R"
  },

  // ── UNLABELED EDGES: Overlay signals -> Market return ─────────────────────

  // RSC_S -> MKT_R (dag-full-mount)
  // plan_risk_state.R: rsc_portfolio scales Mkt-RF by the regime exposure factor.
  "RSC_S->MKT_R": {
    tooltip: "RSC signal (exposure weight: benign=100%, cautious=50%, hostile=10%) scales the market return. Source: plan_risk_state.R tar_target(rsc_portfolio) line ~179.",
    href: "https://github.com/JohnGavin/historical/blob/main/R/plan_risk_state.R"
  },

  // VIX_S -> MKT_R (dag-full-mount)
  // plan_vix_macro_overlay.R: vmo_results applies VIX overlay, scaling out of equity
  // when VIX is elevated.
  "VIX_S->MKT_R": {
    tooltip: "VIX overlay signal (binary in/out) scales market exposure — exit when VIX > threshold, reducing effective market return. Source: plan_vix_macro_overlay.R tar_target(vmo_results).",
    href: "https://github.com/JohnGavin/historical/blob/main/R/plan_vix_macro_overlay.R"
  },

  // Mkt_RF -> MKT_R (dag-full-mount)
  // plan_backtest.R: bt_returns computes benchmark_return from SPY prices.
  // Mkt-RF is the raw factor; MKT_R is the buy-and-hold benchmark return.
  "Mkt_RF->MKT_R": {
    tooltip: "Market risk premium (Mkt-RF) is the raw input for the buy-and-hold benchmark return. Source: plan_backtest.R tar_target(bt_returns) — benchmark_return from SPY.",
    href: "https://github.com/JohnGavin/historical/blob/main/R/plan_backtest.R"
  },

  // ── UNLABELED EDGES: Mkt_RF as passive return component ───────────────────

  // Mkt_RF -> DRIF_R (dag-full-mount, dag-drif-mount)
  // plan_drif.R: drif_portfolio benchmarks against Mkt-RF. The strategy return
  // includes the market component since factor returns embed Mkt-RF.
  "Mkt_RF->DRIF_R": {
    tooltip: "Mkt-RF is the benchmark return for DRIF: all factor returns include market exposure. Source: plan_drif.R tar_target(drif_portfolio) — benchmark_factor = 'Mkt_RF'.",
    href: "https://github.com/JohnGavin/historical/blob/main/R/plan_drif.R"
  },

  // Mkt_RF -> FMAX_R (dag-full-mount, dag-fmax-mount)
  "Mkt_RF->FMAX_R": {
    tooltip: "Mkt-RF is the benchmark for FacMAX: all factor returns embed market exposure. Source: plan_factormax.R tar_target(fm_monthly) and tar_target(fm_portfolio).",
    href: "https://github.com/JohnGavin/historical/blob/main/R/plan_factormax.R"
  },

  // Mkt_RF -> LTR_R (dag-full-mount, dag-ltr-mount)
  // plan_causal_graph.R: Mkt_RF -> LTR_return structural edge (line ~55).
  "Mkt_RF->LTR_R": {
    tooltip: "Mkt-RF is a structural driver of LTR return — the d-separation test checks DRIF_return ⊥ LTR_return | Mkt_RF. Source: plan_causal_graph.R structural edge line ~55.",
    href: "https://github.com/JohnGavin/historical/blob/main/R/plan_causal_graph.R"
  },

  // ── UNLABELED EDGES: Structural nodes ─────────────────────────────────────

  // Crowd -> Decay (dag-full-mount)
  // plan_strategy_decay.R: decay_analysis measures strategy Sharpe decay over time.
  // Crowding (many investors holding same position) causes premium decay.
  "Crowd->Decay": {
    tooltip: "Factor crowding accelerates premium decay — as more investors pile in, the return is front-run and compressed. Source: plan_strategy_decay.R tar_target(decay_analysis) and tar_target(decay_scores).",
    href: "https://github.com/JohnGavin/historical/blob/main/R/plan_strategy_decay.R"
  },

  // Decay -> DRIF_R (dag-full-mount, dag-drif-mount)
  // plan_strategy_decay.R: decay_scores checks if DRIF Sharpe has decayed >50%
  // in the second half vs first half of its history.
  "Decay->DRIF_R": {
    tooltip: "Premium decay reduces DRIF returns in later periods: decay_scores checks if DRIF Sharpe decayed >50% (early vs late half). Source: plan_strategy_decay.R tar_target(decay_scores).",
    href: "https://github.com/JohnGavin/historical/blob/main/R/plan_strategy_decay.R"
  },

  // Decay -> FMAX_R (dag-full-mount, dag-fmax-mount)
  "Decay->FMAX_R": {
    tooltip: "Premium decay reduces FacMAX returns in later periods: decay_scores checks if FacMAX Sharpe decayed >50% (early vs late half). Source: plan_strategy_decay.R tar_target(decay_scores).",
    href: "https://github.com/JohnGavin/historical/blob/main/R/plan_strategy_decay.R"
  },

  // ── UNLABELED EDGES: Returns -> Portfolio ─────────────────────────────────

  // DRIF_R -> PORT (dag-full-mount, dag-drif-mount)
  // plan_multi_strategy.R: ms_portfolio weights DRIF at 50%.
  "DRIF_R->PORT": {
    tooltip: "DRIF return is combined into the portfolio at 50% weight (ms_params$weights['drif'] = 0.50). Source: plan_multi_strategy.R tar_target(ms_portfolio).",
    href: "https://github.com/JohnGavin/historical/blob/main/R/plan_multi_strategy.R"
  },

  // FMAX_R -> PORT (dag-full-mount, dag-fmax-mount)
  // plan_multi_strategy.R: ms_portfolio weights FacMAX at 15% (downweighted for decay).
  "FMAX_R->PORT": {
    tooltip: "FacMAX return is combined at 15% weight (downweighted for decay). Source: plan_multi_strategy.R tar_target(ms_portfolio) — ms_params$weights['fac_max'] = 0.15.",
    href: "https://github.com/JohnGavin/historical/blob/main/R/plan_multi_strategy.R"
  },

  // LTR_R -> PORT (dag-full-mount, dag-ltr-mount)
  // plan_multi_strategy.R: ms_portfolio weights LTR at 35%.
  "LTR_R->PORT": {
    tooltip: "LTR return is combined at 35% weight (negative correlation to DRIF provides diversification). Source: plan_multi_strategy.R tar_target(ms_portfolio) — ms_params$weights['ltr'] = 0.35.",
    href: "https://github.com/JohnGavin/historical/blob/main/R/plan_multi_strategy.R"
  },

  // Cost -> PORT (dag-full-mount)
  // plan_multi_strategy.R: ms_portfolio deducts ms_params$cost_per_rebalance each month.
  "Cost->PORT": {
    tooltip: "Monthly rebalancing cost (20bps round-trip) is subtracted from portfolio return. Source: plan_multi_strategy.R tar_target(ms_portfolio) — cost_per_rebalance = 0.002.",
    href: "https://github.com/JohnGavin/historical/blob/main/R/plan_multi_strategy.R"
  },

  // ── UNLABELED EDGES: Portfolio -> Risk Metrics ────────────────────────────

  // PORT -> SR (dag-full-mount)
  // plan_multi_strategy.R: ms_metrics computes Sharpe from ms_portfolio returns.
  "PORT->SR": {
    tooltip: "Sharpe ratio computed from portfolio return series: mean(ret)/sd(ret)*sqrt(12). Source: plan_multi_strategy.R tar_target(ms_metrics).",
    href: "https://github.com/JohnGavin/historical/blob/main/R/plan_multi_strategy.R"
  },

  // PORT -> MDD (dag-full-mount)
  // plan_multi_strategy.R: ms_metrics computes max drawdown from cumulative return.
  "PORT->MDD": {
    tooltip: "Maximum drawdown computed from cumulative portfolio return in ms_metrics. Source: plan_multi_strategy.R tar_target(ms_metrics).",
    href: "https://github.com/JohnGavin/historical/blob/main/R/plan_multi_strategy.R"
  },

  // VolR -> MDD (dag-full-mount)
  // Structural: hostile vol regimes produce clustered drawdowns.
  // plan_risk_state.R: rsc_regime classification correlates with drawdown periods.
  "VolR->MDD": {
    tooltip: "Hostile vol regimes directly produce portfolio drawdowns — regime clustering concentrates losses. Structural edge; evidenced by rsc_portfolio exposure scaling. Source: plan_risk_state.R tar_target(rsc_regime).",
    href: "https://github.com/JohnGavin/historical/blob/main/R/plan_risk_state.R"
  },

  // ── UNLABELED EDGES: dag-overview-mount ───────────────────────────────────

  // Factors -> DRIF (overview)
  // plan_drif.R: drif_daily fetches FF5+Mom factor data via hd_factors().
  "Factors->DRIF": {
    tooltip: "Fama-French factors (HML, SMB, RMW, CMA, Mom) are the inputs to DRIF. Source: plan_drif.R tar_target(drif_daily).",
    href: "https://github.com/JohnGavin/historical/blob/main/R/plan_drif.R"
  },

  // Factors -> FMAX (overview)
  "Factors->FMAX": {
    tooltip: "Fama-French factors (HML, SMB, RMW, CMA, Mom) are the inputs to Factor MAX. Source: plan_factormax.R tar_target(fm_daily).",
    href: "https://github.com/JohnGavin/historical/blob/main/R/plan_factormax.R"
  },

  // Factors -> LTR (overview)
  "Factors->LTR": {
    tooltip: "Fama-French factor returns (Mom, SMB) are among the cross-section ranking inputs to LTR. Source: plan_ltr_momentum.R tar_target(ltr_features).",
    href: "https://github.com/JohnGavin/historical/blob/main/R/plan_ltr_momentum.R"
  },

  // Macro -> VolR (overview)
  "Macro->VolR": {
    tooltip: "Macro signals (VIX level, VIX term structure, VVIX) drive the vol regime classifier. Source: plan_risk_state.R tar_target(rsc_data) and tar_target(rsc_regime).",
    href: "https://github.com/JohnGavin/historical/blob/main/R/plan_risk_state.R"
  },

  // Macro -> RateR (overview)
  "Macro->RateR": {
    tooltip: "Macro signals (Fed funds rate, inflation) determine rate regime classification. Source: plan_causal_graph.R tar_target(cg_data) line ~220-223.",
    href: "https://github.com/JohnGavin/historical/blob/main/R/plan_causal_graph.R"
  },

  // VolR -> RSC (overview)
  "VolR->RSC": {
    tooltip: "Vol regime state drives RSC overlay exposure: benign=100%, cautious=50%, hostile=10%. Source: plan_risk_state.R tar_target(rsc_portfolio).",
    href: "https://github.com/JohnGavin/historical/blob/main/R/plan_risk_state.R"
  },

  // VolR -> VIXO (overview)
  "VolR->VIXO": {
    tooltip: "Vol regime (elevated VIX) triggers the VIX overlay: exit equity when VIX > threshold. Source: plan_vix_macro_overlay.R tar_target(vmo_results).",
    href: "https://github.com/JohnGavin/historical/blob/main/R/plan_vix_macro_overlay.R"
  },

  // RateR -> LTR (overview) — same as RateR->LTR_S in full diagram
  "RateR->LTR": {
    tooltip: "Rate regime conditions LTR signal generation — rising rates affect factor momentum dynamics. Source: plan_causal_graph.R structural edge (line ~44-45).",
    href: "https://github.com/JohnGavin/historical/blob/main/R/plan_causal_graph.R"
  },

  // Market -> DRIF (overview)
  // plan_drif.R: drif_params sets benchmark_factor = "Mkt_RF". The market return
  // provides the passive baseline and is embedded in factor returns.
  "Market->DRIF": {
    tooltip: "Market return (Mkt-RF) is the benchmark factor for DRIF; all factor returns embed market exposure. Source: plan_drif.R tar_target(drif_params) — benchmark_factor = 'Mkt_RF'.",
    href: "https://github.com/JohnGavin/historical/blob/main/R/plan_drif.R"
  },

  // Market -> FMAX (overview)
  "Market->FMAX": {
    tooltip: "Market return (Mkt-RF) is the benchmark for FacMAX. Source: plan_factormax.R tar_target(fm_params) — benchmark_factor = 'Mkt_RF'.",
    href: "https://github.com/JohnGavin/historical/blob/main/R/plan_factormax.R"
  },

  // Market -> LTR (overview)
  "Market->LTR": {
    tooltip: "Market return (Mkt-RF) is a structural driver of LTR return — equity benchmark. Source: plan_causal_graph.R structural edge Mkt_RF -> LTR_return (line ~55).",
    href: "https://github.com/JohnGavin/historical/blob/main/R/plan_causal_graph.R"
  },

  // DRIF -> PORT (overview) — maps to DRIF_R -> PORT in full diagram
  "DRIF->PORT": {
    tooltip: "DRIF strategy return is combined into the portfolio at 50% weight. Source: plan_multi_strategy.R tar_target(ms_portfolio).",
    href: "https://github.com/JohnGavin/historical/blob/main/R/plan_multi_strategy.R"
  },

  // FMAX -> PORT (overview)
  "FMAX->PORT": {
    tooltip: "FacMAX strategy return is combined at 15% weight (downweighted for decay). Source: plan_multi_strategy.R tar_target(ms_portfolio).",
    href: "https://github.com/JohnGavin/historical/blob/main/R/plan_multi_strategy.R"
  },

  // LTR -> PORT (overview)
  "LTR->PORT": {
    tooltip: "LTR strategy return is combined at 35% weight. Source: plan_multi_strategy.R tar_target(ms_portfolio).",
    href: "https://github.com/JohnGavin/historical/blob/main/R/plan_multi_strategy.R"
  },

  // RSC -> PORT (overview)
  // plan_risk_state.R: rsc_portfolio produces regime-scaled market return.
  // This feeds into the overall portfolio as a defensive overlay component.
  "RSC->PORT": {
    tooltip: "RSC (regime-scaled market return) is a defensive overlay component in the portfolio — reduces market exposure during hostile regimes. Source: plan_risk_state.R tar_target(rsc_portfolio).",
    href: "https://github.com/JohnGavin/historical/blob/main/R/plan_risk_state.R"
  },

  // VIXO -> PORT (overview)
  "VIXO->PORT": {
    tooltip: "VIX overlay return feeds into the portfolio as a timing component (exit equity when VIX elevated). Source: plan_vix_macro_overlay.R tar_target(vmo_results).",
    href: "https://github.com/JohnGavin/historical/blob/main/R/plan_vix_macro_overlay.R"
  },

  // PORT -> RISK (overview)
  "PORT->RISK": {
    tooltip: "Portfolio return series is the input for all risk metrics: Sharpe ratio, max drawdown, volatility. Source: plan_multi_strategy.R tar_target(ms_metrics).",
    href: "https://github.com/JohnGavin/historical/blob/main/R/plan_multi_strategy.R"
  },

  // Structural -> DRIF (overview)
  "Structural->DRIF": {
    tooltip: "Structural headwinds (crowding, premium decay, transaction costs) reduce DRIF returns over time. Source: plan_strategy_decay.R tar_target(decay_scores).",
    href: "https://github.com/JohnGavin/historical/blob/main/R/plan_strategy_decay.R"
  },

  // Structural -> FMAX (overview)
  "Structural->FMAX": {
    tooltip: "Structural headwinds (crowding, premium decay, transaction costs) reduce FacMAX returns. Source: plan_strategy_decay.R tar_target(decay_scores).",
    href: "https://github.com/JohnGavin/historical/blob/main/R/plan_strategy_decay.R"
  }
};

// ── Edge popup CSS ────────────────────────────────────────────────────────────
// Injected once into <head>. Uses --bs-* CSS vars so popup picks up Bootstrap
// dark/light theming automatically. pointer-events:auto on popup lets users
// hover into it to click the link.
(function injectEdgePopupStyles() {
  if (document.getElementById('edge-popup-styles')) return;
  var style = document.createElement('style');
  style.id = 'edge-popup-styles';
  style.textContent = [
    '.edge-popup {',
    '  position: fixed;',
    '  visibility: hidden;',
    '  background: var(--bs-body-bg, #1a1a1a);',
    '  color: var(--bs-body-color, #f0f0f0);',
    '  border: 1px solid var(--bs-border-color, #444);',
    '  border-radius: 4px;',
    '  padding: 8px 12px;',
    '  max-width: 320px;',
    '  font-size: 0.85rem;',
    '  line-height: 1.4;',
    '  z-index: 1000;',
    '  pointer-events: auto;',
    '  box-shadow: 0 4px 12px rgba(0,0,0,0.3);',
    '}',
    '.edge-popup p { margin: 0 0 6px 0; }',
    '.edge-popup a {',
    '  color: var(--bs-link-color, #7ab8ff);',
    '  text-decoration: underline dotted;',
    '}'
  ].join('\n');
  document.head.appendChild(style);
}());

// ── Single shared popup div ───────────────────────────────────────────────────
var sharedPopup = null;
var hideTimeout = null;

function getOrCreatePopup() {
  if (!sharedPopup) {
    sharedPopup = document.createElement('div');
    sharedPopup.className = 'edge-popup';
    document.body.appendChild(sharedPopup);
    // Keep popup visible when user hovers into it (to click the link)
    sharedPopup.addEventListener('mouseenter', function() {
      if (hideTimeout) { clearTimeout(hideTimeout); hideTimeout = null; }
    });
    sharedPopup.addEventListener('mouseleave', function() {
      hideEdgePopup();
    });
  }
  return sharedPopup;
}

function showEdgePopup(evt, meta, midX, midY) {
  var popup = getOrCreatePopup();
  var html = '<p>' + meta.tooltip + '</p>';
  if (meta.href) {
    html += '<a href="' + meta.href + '" target="_blank" rel="noopener noreferrer">View source &rarr;</a>';
  }
  popup.innerHTML = html;

  // Use midpoint of SVG edge path when available; fall back to cursor position
  var x, y;
  if (midX !== null && midY !== null) {
    x = midX;
    y = midY;
  } else {
    x = evt.clientX + 12;
    y = evt.clientY + 8;
  }

  // Clamp to viewport so popup does not overflow off-screen
  var vw = window.innerWidth;
  var vh = window.innerHeight;
  var pw = 320; // max-width from CSS
  var ph = 120; // rough estimate
  x = Math.min(x, vw - pw - 16);
  y = Math.min(y, vh - ph - 16);
  x = Math.max(x, 8);
  y = Math.max(y, 8);

  popup.style.left = x + 'px';
  popup.style.top  = y + 'px';
  popup.style.visibility = 'visible';
}

function hideEdgePopup() {
  if (sharedPopup) {
    sharedPopup.style.visibility = 'hidden';
  }
}

function scheduleHide() {
  if (hideTimeout) clearTimeout(hideTimeout);
  hideTimeout = setTimeout(function() {
    hideTimeout = null;
    hideEdgePopup();
  }, 200);
}

// ── Midpoint extraction from Mermaid data-points ─────────────────────────────
// data-points is a base64-encoded JSON array of {x,y} waypoints in SVG-space.
// Returns {x,y} in CLIENT coordinates (accounting for SVG's bounding rect).
function midpointFromDataPoints(b64, svgEl) {
  if (!b64) return null;
  try {
    var json = atob(b64);
    var pts = JSON.parse(json);
    if (!pts || pts.length === 0) return null;
    var mid;
    if (pts.length === 1) {
      mid = pts[0];
    } else {
      var m = Math.floor(pts.length / 2);
      // Average two middle waypoints for even-length arrays
      if (pts.length % 2 === 0) {
        mid = { x: (pts[m-1].x + pts[m].x) / 2, y: (pts[m-1].y + pts[m].y) / 2 };
      } else {
        mid = pts[m];
      }
    }
    // Convert SVG coordinates to client (viewport) coordinates
    if (svgEl && svgEl.getScreenCTM) {
      var ctm = svgEl.getScreenCTM();
      if (ctm) {
        return {
          x: ctm.a * mid.x + ctm.c * mid.y + ctm.e,
          y: ctm.b * mid.x + ctm.d * mid.y + ctm.f
        };
      }
    }
    // Fallback: offset by SVG bounding rect
    if (svgEl) {
      var rect = svgEl.getBoundingClientRect();
      return { x: rect.left + mid.x, y: rect.top + mid.y };
    }
    return null;
  } catch(e) {
    return null;
  }
}

// ── Node ID extraction from dagDefs ──────────────────────────────────────────
// Returns a Set of all node IDs that appear as src or dst in a diagram text.
// Handles A-->B, A-->|"label"|B, A-.->B, A==>B, A & B --> C patterns,
// as well as node definitions A["label"], A(label), A{label}.
function nodeIdsFromDagDef(text) {
  var ids = new Set();
  // Match node definitions: ID["label"], ID(label), ID{label}, ID[[label]], etc.
  var defRe = /\b([A-Za-z_][A-Za-z0-9_]*)(?:\s*[\[({"'])/g;
  var m;
  while ((m = defRe.exec(text)) !== null) {
    // Skip Mermaid keywords
    var kw = ['graph', 'subgraph', 'end', 'click', 'style', 'classDef',
               'class', 'linkStyle', 'direction', 'LR', 'RL', 'TD', 'BT'];
    if (kw.indexOf(m[1]) === -1) ids.add(m[1]);
  }
  // Also match bare IDs in edge declarations: A-->B, A -.-> B, etc.
  // Pattern: word boundary + ID + optional whitespace + arrow or pipe
  var edgeRe = /\b([A-Za-z_][A-Za-z0-9_]*)\s*(?:-->|-.->|==>|--o|--x|~~~|\|)/g;
  while ((m = edgeRe.exec(text)) !== null) {
    if (['graph', 'subgraph', 'end', 'click', 'style',
         'classDef', 'class', 'linkStyle'].indexOf(m[1]) === -1) ids.add(m[1]);
  }
  // Also match right-hand side of edges: --> ID and -->|".."|ID
  var rhsRe = /(?:-->|-.->|==>)\s*(?:\|[^|]*\|\s*)?([A-Za-z_][A-Za-z0-9_]*)/g;
  while ((m = rhsRe.exec(text)) !== null) ids.add(m[1]);
  return ids;
}

// Parse a Mermaid path id like "L_Mom_LTR_S_0" into "Mom->LTR_S".
// Validates both halves against the diagram's node-ID set.
// When node IDs contain underscores (e.g. Mkt_RF), tries splits from longest
// src first so that Mkt_RF is preferred over Mkt + RF_LTR_R_0.
function parseEdgeKey(pathId, validNodeIds) {
  // Strip "L_" prefix and "_<digits>" suffix
  var m = pathId.match(/^L_(.+)_(\d+)$/);
  if (!m) return null;
  var body = m[1];
  var parts = body.split('_');
  // Try splits from longest src first (greedy src)
  for (var i = parts.length - 1; i >= 1; i--) {
    var src = parts.slice(0, i).join('_');
    var dst = parts.slice(i).join('_');
    if (validNodeIds.has(src) && validNodeIds.has(dst)) {
      return src + '->' + dst;
    }
  }
  return null;
}

// Cache for node-ID sets per mountId (computed once per diagram)
var nodeIdCache = {};

// ── addEdgePopups ─────────────────────────────────────────────────────────────
// Attaches floating popup interactivity to all unlabeled (and labeled) edges
// that have a matching edgeMetadata entry.
function addEdgePopups(svg, mountId) {
  if (!svg) return;

  // Build or retrieve node-ID set for this diagram
  if (!nodeIdCache[mountId] && dagDefs[mountId]) {
    nodeIdCache[mountId] = nodeIdsFromDagDef(dagDefs[mountId]);
  }
  var validNodes = nodeIdCache[mountId] || new Set();

  var paths = svg.querySelectorAll('path.flowchart-link[id^="L_"]');
  paths.forEach(function(path) {
    var key = parseEdgeKey(path.id, validNodes);
    if (!key) return;
    var meta = edgeMetadata[key];
    if (!meta) return;

    // Make the path stroke hoverable (default fill is none, stroke gives a thin target)
    path.style.pointerEvents = 'stroke';
    path.style.cursor = 'pointer';

    // Compute midpoint once in client coordinates
    var b64 = path.getAttribute('data-points');
    var mid = midpointFromDataPoints(b64, svg);
    var midX = mid ? mid.x : null;
    var midY = mid ? mid.y : null;

    path.addEventListener('mouseenter', function(e) {
      if (hideTimeout) { clearTimeout(hideTimeout); hideTimeout = null; }
      showEdgePopup(e, meta, midX, midY);
    });
    path.addEventListener('mouseleave', function() {
      scheduleHide();
    });
    // Click on path opens the source link (matches the link inside the popup)
    if (meta.href) {
      path.addEventListener('click', function() {
        window.open(meta.href, '_blank', 'noopener');
      });
    }
  });
}

// Inject <title> tooltips into SVG nodes after mermaid render
function addTooltipsToSvg(svg) {
  if (!svg) return;
  // Mermaid creates nodes with id like "flowchart-HML-123" or class containing node id
  // Also creates clickable groups with data-id attribute
  for (var nodeId in nodeTooltips) {
    // Try multiple selector patterns mermaid uses
    var selectors = [
      '[data-id="' + nodeId + '"]',
      '[id*="flowchart-' + nodeId + '-"]',
      '[id*="-' + nodeId + '-"]',
      '.node[id*="' + nodeId + '"]'
    ];
    for (var i = 0; i < selectors.length; i++) {
      var el = svg.querySelector(selectors[i]);
      if (el && !el.querySelector('title')) {
        var title = document.createElementNS('http://www.w3.org/2000/svg', 'title');
        title.textContent = nodeTooltips[nodeId];
        el.prepend(title);
        break;
      }
    }
  }
}

// Add hover tooltips and click links to labeled edges after mermaid render.
// Matches by the text content of the edgeLabel div, then looks up edgeMetadata.
function addEdgeInteractivity(svg) {
  if (!svg) return;

  // Mermaid v11 renders labeled edges as:
  //   <g class="edgeLabels">
  //     <g class="edgeLabel">
  //       <foreignObject>
  //         <div class="edgeLabel">
  //           <p>label text here</p>
  //         </div>
  //       </foreignObject>
  //     </g>
  //   </g>
  // securityLevel:"loose" allows foreignObject manipulation.
  var labelEls = svg.querySelectorAll(
    '.edgeLabel foreignObject div, .edgeLabel foreignObject p'
  );

  labelEls.forEach(function(el) {
    var labelText = (el.textContent || '').trim();
    if (!labelText) return;
    var meta = edgeMetadata[labelText];
    if (!meta) return;

    // Hover tooltip: title attribute on the element (browsers show it natively)
    el.setAttribute('title', meta.tooltip);
    el.style.cursor = 'help';

    // Clickable link: wrap children in <a> so the label opens the source file
    if (meta.href && !el.querySelector('a')) {
      var a = document.createElement('a');
      a.href = meta.href;
      a.target = '_blank';
      a.rel = 'noopener noreferrer';
      // color:inherit preserves Mermaid edge label colour in both dark and light mode.
      // underline dotted signals interactivity without overriding Mermaid's colour theme.
      a.style.color = 'inherit';
      a.style.textDecoration = 'underline dotted';
      // Move all children of el into the <a>
      while (el.firstChild) {
        a.appendChild(el.firstChild);
      }
      el.appendChild(a);
    }
  });
}

var dagDefs = {
  "dag-overview-mount": "graph LR\n  Factors[\"FF Factors\"] --> DRIF[\"DRIF\"]\n  Factors --> FMAX[\"Factor MAX\"]\n  Factors --> LTR[\"LTR\"]\n  Macro[\"Macro Signals\"] --> VolR[\"Vol Regime\"]\n  Macro --> RateR[\"Rate Regime\"]\n  VolR --> RSC[\"RSC Overlay\"]\n  VolR --> VIXO[\"VIX Overlay\"]\n  RateR --> LTR\n  Market[\"Market\"] --> DRIF\n  Market --> FMAX\n  Market --> LTR\n  DRIF --> PORT[\"Portfolio Return\"]\n  FMAX --> PORT\n  LTR --> PORT\n  RSC --> PORT\n  VIXO --> PORT\n  PORT --> RISK[\"Sharpe, Max DD\"]\n  Structural[\"Crowding + Decay\"] --> DRIF\n  Structural --> FMAX\n  Macro -.->|\"r=-0.17\"| Factors\n  click DRIF \"https://github.com/JohnGavin/historical/blob/main/R/plan_drif.R\" _blank\n  click FMAX \"https://github.com/JohnGavin/historical/blob/main/R/plan_factormax.R\" _blank\n  click LTR \"https://github.com/JohnGavin/historical/blob/main/R/plan_ltr_momentum.R\" _blank\n  click RSC \"https://github.com/JohnGavin/historical/blob/main/R/plan_risk_state.R\" _blank\n  click VIXO \"https://github.com/JohnGavin/historical/blob/main/R/plan_vix_macro_overlay.R\" _blank\n  click Factors \"https://github.com/JohnGavin/historical/blob/main/packages/historicaldata/R/query.R\" _blank\n  click Macro \"https://github.com/JohnGavin/historical/blob/main/R/plan_regime.R\" _blank\n  click PORT \"https://github.com/JohnGavin/historical/blob/main/R/plan_multi_strategy.R\" _blank\n  click Structural \"https://github.com/JohnGavin/historical/blob/main/R/plan_strategy_decay.R\" _blank\n  linkStyle default stroke:#CC0000,stroke-width:2px\n  linkStyle 19 stroke:#ffff00,stroke-width:3px,stroke-dasharray:5",
  "dag-full-mount": "graph LR\n  subgraph Factors[\"Fama-French Factors\"]\n    HML[\"HML Value\"]\n    SMB[\"SMB Size\"]\n    Mom[\"Mom Momentum\"]\n    RMW[\"RMW Profitability\"]\n    Mkt_RF[\"Mkt-RF Market\"]\n  end\n  subgraph Macro[\"Macro Signals\"]\n    VIX[\"VIX Level\"]\n    VTS[\"VIX Term Structure\"]\n    VVIX[\"VVIX\"]\n    Fed[\"Fed Rate\"]\n    Infl[\"Inflation\"]\n  end\n  subgraph Regime[\"Regime States\"]\n    VolR[\"Vol Regime\"]\n    RateR[\"Rate Regime\"]\n  end\n  subgraph Signals[\"Strategy Signals\"]\n    DRIF_S[\"DRIF Signal\"]\n    FMAX_S[\"FacMAX Signal\"]\n    LTR_S[\"LTR Signal\"]\n    RSC_S[\"RSC Signal\"]\n    VIX_S[\"VIX Overlay\"]\n  end\n  subgraph Returns[\"Strategy Returns\"]\n    DRIF_R[\"DRIF Return\"]\n    FMAX_R[\"FacMAX Return\"]\n    LTR_R[\"LTR Return\"]\n    MKT_R[\"Market Return\"]\n  end\n  subgraph Portfolio[\"Portfolio Outcomes\"]\n    PORT[\"Portfolio Return\"]\n    MDD[\"Max Drawdown\"]\n    SR[\"Sharpe Ratio\"]\n  end\n  subgraph Structural[\"Structural\"]\n    Crowd[\"Factor Crowding\"]\n    Decay[\"Premium Decay\"]\n    Cost[\"Rebalance Cost\"]\n  end\n  HML --> DRIF_S\n  SMB --> DRIF_S\n  Mom --> DRIF_S\n  RMW --> DRIF_S\n  HML --> FMAX_S\n  SMB --> FMAX_S\n  Mom --> FMAX_S\n  Mom --> LTR_S\n  SMB --> LTR_S\n  VIX --> VolR\n  VTS --> VolR\n  VVIX --> VolR\n  Fed --> RateR\n  Infl --> RateR\n  VolR --> RSC_S\n  VolR --> VIX_S\n  RateR --> LTR_S\n  DRIF_S --> DRIF_R\n  FMAX_S --> FMAX_R\n  LTR_S --> LTR_R\n  RSC_S --> MKT_R\n  VIX_S --> MKT_R\n  Mkt_RF --> MKT_R\n  Mkt_RF --> DRIF_R\n  Mkt_RF --> FMAX_R\n  Mkt_RF --> LTR_R\n  Crowd --> Decay\n  Decay --> FMAX_R\n  Decay --> DRIF_R\n  DRIF_R --> PORT\n  FMAX_R --> PORT\n  LTR_R --> PORT\n  Cost --> PORT\n  PORT --> SR\n  PORT --> MDD\n  VolR --> MDD\n  VIX -.->|\"r=-0.17 VIOLATED\"| HML\n  click HML \"https://github.com/JohnGavin/historical/blob/main/packages/historicaldata/R/query.R\" _blank\n  click SMB \"https://github.com/JohnGavin/historical/blob/main/packages/historicaldata/R/query.R\" _blank\n  click Mom \"https://github.com/JohnGavin/historical/blob/main/packages/historicaldata/R/query.R\" _blank\n  click RMW \"https://github.com/JohnGavin/historical/blob/main/packages/historicaldata/R/query.R\" _blank\n  click Mkt_RF \"https://github.com/JohnGavin/historical/blob/main/packages/historicaldata/R/query.R\" _blank\n  click VIX \"https://github.com/JohnGavin/historical/blob/main/R/plan_vix_macro_overlay.R\" _blank\n  click VTS \"https://github.com/JohnGavin/historical/blob/main/R/plan_vix_macro_overlay.R\" _blank\n  click VVIX \"https://github.com/JohnGavin/historical/blob/main/R/plan_vix_macro_overlay.R\" _blank\n  click Fed \"https://github.com/JohnGavin/historical/blob/main/R/plan_regime.R\" _blank\n  click Infl \"https://github.com/JohnGavin/historical/blob/main/R/plan_regime.R\" _blank\n  click VolR \"https://github.com/JohnGavin/historical/blob/main/R/plan_risk_state.R\" _blank\n  click RateR \"https://github.com/JohnGavin/historical/blob/main/R/plan_regime.R\" _blank\n  click DRIF_S \"https://github.com/JohnGavin/historical/blob/main/R/plan_drif.R\" _blank\n  click FMAX_S \"https://github.com/JohnGavin/historical/blob/main/R/plan_factormax.R\" _blank\n  click LTR_S \"https://github.com/JohnGavin/historical/blob/main/R/plan_ltr_momentum.R\" _blank\n  click RSC_S \"https://github.com/JohnGavin/historical/blob/main/R/plan_risk_state.R\" _blank\n  click VIX_S \"https://github.com/JohnGavin/historical/blob/main/R/plan_vix_macro_overlay.R\" _blank\n  click DRIF_R \"https://github.com/JohnGavin/historical/blob/main/R/plan_drif.R\" _blank\n  click FMAX_R \"https://github.com/JohnGavin/historical/blob/main/R/plan_factormax.R\" _blank\n  click LTR_R \"https://github.com/JohnGavin/historical/blob/main/R/plan_ltr_momentum.R\" _blank\n  click MKT_R \"https://github.com/JohnGavin/historical/blob/main/R/plan_backtest.R\" _blank\n  click PORT \"https://github.com/JohnGavin/historical/blob/main/R/plan_multi_strategy.R\" _blank\n  click Crowd \"https://github.com/JohnGavin/historical/blob/main/R/plan_strategy_decay.R\" _blank\n  click Decay \"https://github.com/JohnGavin/historical/blob/main/R/plan_strategy_decay.R\" _blank\n  click Cost \"https://github.com/JohnGavin/historical/blob/main/R/plan_alpha_decay.R\" _blank\n  linkStyle default stroke:#CC0000,stroke-width:2px",
  "dag-drif-mount": "graph LR\n  HML[\"HML Value\"] --> DRIF_S[\"DRIF Signal\"]\n  SMB[\"SMB Size\"] --> DRIF_S\n  Mom[\"Mom Momentum\"] --> DRIF_S\n  RMW[\"RMW Profitability\"] --> DRIF_S\n  DRIF_S --> DRIF_R[\"DRIF Return\"]\n  Mkt_RF[\"Market Mkt-RF\"] --> DRIF_R\n  VIX[\"VIX Level\"] -.->|\"r=-0.17\"| HML\n  Decay[\"Premium Decay\"] --> DRIF_R\n  DRIF_R --> PORT[\"Portfolio Return\"]\n  click HML \"https://github.com/JohnGavin/historical/blob/main/packages/historicaldata/R/query.R\" _blank\n  click SMB \"https://github.com/JohnGavin/historical/blob/main/packages/historicaldata/R/query.R\" _blank\n  click Mom \"https://github.com/JohnGavin/historical/blob/main/packages/historicaldata/R/query.R\" _blank\n  click RMW \"https://github.com/JohnGavin/historical/blob/main/packages/historicaldata/R/query.R\" _blank\n  click DRIF_S \"https://github.com/JohnGavin/historical/blob/main/R/plan_drif.R\" _blank\n  click DRIF_R \"https://github.com/JohnGavin/historical/blob/main/R/plan_drif.R\" _blank\n  click Mkt_RF \"https://github.com/JohnGavin/historical/blob/main/packages/historicaldata/R/query.R\" _blank\n  click VIX \"https://github.com/JohnGavin/historical/blob/main/R/plan_vix_macro_overlay.R\" _blank\n  click Decay \"https://github.com/JohnGavin/historical/blob/main/R/plan_strategy_decay.R\" _blank\n  click PORT \"https://github.com/JohnGavin/historical/blob/main/R/plan_multi_strategy.R\" _blank\n  linkStyle default stroke:#CC0000,stroke-width:2px\n  linkStyle 6 stroke:#ffff00,stroke-width:3px,stroke-dasharray:5",
  "dag-fmax-mount": "graph LR\n  HML[\"HML Value\"] --> FMAX_S[\"FacMAX Signal\"]\n  SMB[\"SMB Size\"] --> FMAX_S\n  Mom[\"Mom Momentum\"] --> FMAX_S\n  FMAX_S --> FMAX_R[\"FacMAX Return\"]\n  Mkt_RF[\"Market Mkt-RF\"] --> FMAX_R\n  Decay[\"Premium Decay\"] --> FMAX_R\n  FMAX_R --> PORT[\"Portfolio Return\"]\n  click HML \"https://github.com/JohnGavin/historical/blob/main/packages/historicaldata/R/query.R\" _blank\n  click SMB \"https://github.com/JohnGavin/historical/blob/main/packages/historicaldata/R/query.R\" _blank\n  click Mom \"https://github.com/JohnGavin/historical/blob/main/packages/historicaldata/R/query.R\" _blank\n  click FMAX_S \"https://github.com/JohnGavin/historical/blob/main/R/plan_factormax.R\" _blank\n  click FMAX_R \"https://github.com/JohnGavin/historical/blob/main/R/plan_factormax.R\" _blank\n  click Mkt_RF \"https://github.com/JohnGavin/historical/blob/main/packages/historicaldata/R/query.R\" _blank\n  click Decay \"https://github.com/JohnGavin/historical/blob/main/R/plan_strategy_decay.R\" _blank\n  click PORT \"https://github.com/JohnGavin/historical/blob/main/R/plan_multi_strategy.R\" _blank\n  linkStyle default stroke:#CC0000,stroke-width:2px",
  "dag-ltr-mount": "graph LR\n  Mom[\"Mom Momentum\"] --> LTR_S[\"LTR Signal\"]\n  SMB[\"SMB Size\"] --> LTR_S\n  RateR[\"Rate Regime\"] --> LTR_S\n  LTR_S --> LTR_R[\"LTR Return\"]\n  Mkt_RF[\"Market Mkt-RF\"] --> LTR_R\n  LTR_R --> PORT[\"Portfolio Return\"]\n  click Mom \"https://github.com/JohnGavin/historical/blob/main/packages/historicaldata/R/query.R\" _blank\n  click SMB \"https://github.com/JohnGavin/historical/blob/main/packages/historicaldata/R/query.R\" _blank\n  click RateR \"https://github.com/JohnGavin/historical/blob/main/R/plan_regime.R\" _blank\n  click LTR_S \"https://github.com/JohnGavin/historical/blob/main/R/plan_ltr_momentum.R\" _blank\n  click LTR_R \"https://github.com/JohnGavin/historical/blob/main/R/plan_ltr_momentum.R\" _blank\n  click Mkt_RF \"https://github.com/JohnGavin/historical/blob/main/packages/historicaldata/R/query.R\" _blank\n  click PORT \"https://github.com/JohnGavin/historical/blob/main/R/plan_multi_strategy.R\" _blank\n  linkStyle default stroke:#CC0000,stroke-width:2px"
};

// Render each diagram INDIVIDUALLY so one failure doesn't block others
async function renderDiagrams() {
  for (var mountId in dagDefs) {
    var mount = document.getElementById(mountId);
    if (!mount || mount.querySelector('svg')) continue;
    // Check if mount is visible (hidden tabs cause mermaid to fail)
    if (mount.offsetParent === null) continue;
    var pre = document.createElement('pre');
    pre.className = 'mermaid';
    pre.id = 'mmd-' + mountId;
    pre.textContent = dagDefs[mountId];
    pre.style.minHeight = mountId.includes('full') ? '600px' : '400px';
    mount.appendChild(pre);
    // Render THIS diagram alone
    var capturedMountId = mountId;
    try {
      await mermaid.render('mmd-render-' + mountId, dagDefs[mountId]).then(function(result) {
        pre.innerHTML = result.svg;
        pre.removeAttribute('data-processed');
        // Inject tooltips into SVG nodes
        addTooltipsToSvg(pre.querySelector('svg'));
        // Inject edge interactivity (tooltips + click links on labeled edges)
        addEdgeInteractivity(pre.querySelector('svg'));
        // Inject floating popup interactivity for unlabeled edges
        addEdgePopups(pre.querySelector('svg'), capturedMountId);
      });
    } catch(e) {
      console.log('mermaid error for ' + mountId + ':', e.message || e);
      pre.textContent = 'Diagram render failed: ' + (e.message || e);
      pre.style.color = '#ff4444';
    }
  }
}

document.addEventListener('DOMContentLoaded', function() { setTimeout(renderDiagrams, 800); });
document.addEventListener('shown.bs.tab', function() { setTimeout(renderDiagrams, 300); });
