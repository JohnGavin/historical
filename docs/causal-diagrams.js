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

// Edge hover tooltips and click links — keyed by the exact label text from the diagram source.
// Unlabeled-edge interactivity is a stretch goal deferred per #140 — see TODO below.
//
// Audit of ALL labeled edges across all 5 diagrams:
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
// Total labeled edges covered by edgeMetadata: 2 unique label texts ("r=-0.17 VIOLATED", "r=-0.17")
// appearing in 3 diagram instances.
var edgeMetadata = {
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
  }

  // TODO (#140 stretch goal): unlabeled edges keyed by "SRC->DST" node IDs.
  // Mermaid v11 renders unlabeled edges as <path class="flowchart-link"> elements
  // with no text anchor. Matching them requires either path-order enumeration
  // (fragile — depends on Mermaid layout) or inserting transparent midpoint markers
  // (adds ~40+ lines of path-parsing JS). Deferred to a follow-up issue.
};

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
// Only labeled edges are covered — see edgeMetadata TODO for the unlabeled stretch goal.
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
    try {
      await mermaid.render('mmd-render-' + mountId, dagDefs[mountId]).then(function(result) {
        pre.innerHTML = result.svg;
        pre.removeAttribute('data-processed');
        // Inject tooltips into SVG nodes
        addTooltipsToSvg(pre.querySelector('svg'));
        // Inject edge interactivity (tooltips + click links on labeled edges)
        addEdgeInteractivity(pre.querySelector('svg'));
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
