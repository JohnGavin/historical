// Causal DAG diagrams for falsification dashboard
// Loaded via <script src="causal-diagrams.js"> in include-in-header

import mermaid from "https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs";
mermaid.initialize({startOnLoad:false, securityLevel:"loose", theme:"dark",
  themeVariables:{background:"#000",primaryColor:"#999",lineColor:"#C00",primaryTextColor:"#000"}});

var dagDefs = {
  "dag-overview-mount": "graph LR\n  Factors[\"FF Factors\"] --> DRIF[\"DRIF\"]\n  Factors --> FMAX[\"Factor MAX\"]\n  Factors --> LTR[\"LTR\"]\n  Macro[\"Macro Signals\"] --> VolR[\"Vol Regime\"]\n  Macro --> RateR[\"Rate Regime\"]\n  VolR --> RSC[\"RSC Overlay\"]\n  VolR --> VIXO[\"VIX Overlay\"]\n  RateR --> LTR\n  Market[\"Market\"] --> DRIF\n  Market --> FMAX\n  Market --> LTR\n  DRIF --> PORT[\"Portfolio Return\"]\n  FMAX --> PORT\n  LTR --> PORT\n  RSC --> PORT\n  VIXO --> PORT\n  PORT --> RISK[\"Sharpe, Max DD\"]\n  Structural[\"Crowding + Decay\"] --> DRIF\n  Structural --> FMAX\n  Macro -.->|\"r=-0.17\"| Factors\n  linkStyle default stroke:#CC0000,stroke-width:2px\n  linkStyle 19 stroke:#ffff00,stroke-width:3px,stroke-dasharray:5",
  "dag-full-mount": "graph TD\n  subgraph Factors[\"Fama-French Factors\"]\n    HML[\"HML Value\"]\n    SMB[\"SMB Size\"]\n    Mom[\"Mom Momentum\"]\n    RMW[\"RMW Profitability\"]\n    Mkt_RF[\"Mkt-RF Market\"]\n  end\n  subgraph Macro[\"Macro Signals\"]\n    VIX[\"VIX Level\"]\n    VTS[\"VIX Term Structure\"]\n    VVIX[\"VVIX\"]\n    Fed[\"Fed Rate\"]\n    Infl[\"Inflation\"]\n  end\n  subgraph Regime[\"Regime States\"]\n    VolR[\"Vol Regime\"]\n    RateR[\"Rate Regime\"]\n  end\n  subgraph Signals[\"Strategy Signals\"]\n    DRIF_S[\"DRIF Signal\"]\n    FMAX_S[\"FacMAX Signal\"]\n    LTR_S[\"LTR Signal\"]\n    RSC_S[\"RSC Signal\"]\n    VIX_S[\"VIX Overlay\"]\n  end\n  subgraph Returns[\"Strategy Returns\"]\n    DRIF_R[\"DRIF Return\"]\n    FMAX_R[\"FacMAX Return\"]\n    LTR_R[\"LTR Return\"]\n    MKT_R[\"Market Return\"]\n  end\n  subgraph Portfolio[\"Portfolio Outcomes\"]\n    PORT[\"Portfolio Return\"]\n    MDD[\"Max Drawdown\"]\n    SR[\"Sharpe Ratio\"]\n  end\n  subgraph Structural[\"Structural\"]\n    Crowd[\"Factor Crowding\"]\n    Decay[\"Premium Decay\"]\n    Cost[\"Rebalance Cost\"]\n  end\n  HML --> DRIF_S\n  SMB --> DRIF_S\n  Mom --> DRIF_S\n  RMW --> DRIF_S\n  HML --> FMAX_S\n  SMB --> FMAX_S\n  Mom --> FMAX_S\n  Mom --> LTR_S\n  SMB --> LTR_S\n  VIX --> VolR\n  VTS --> VolR\n  VVIX --> VolR\n  Fed --> RateR\n  Infl --> RateR\n  VolR --> RSC_S\n  VolR --> VIX_S\n  RateR --> LTR_S\n  DRIF_S --> DRIF_R\n  FMAX_S --> FMAX_R\n  LTR_S --> LTR_R\n  RSC_S --> MKT_R\n  VIX_S --> MKT_R\n  Mkt_RF --> MKT_R\n  Mkt_RF --> DRIF_R\n  Mkt_RF --> FMAX_R\n  Mkt_RF --> LTR_R\n  Crowd --> Decay\n  Decay --> FMAX_R\n  Decay --> DRIF_R\n  DRIF_R --> PORT\n  FMAX_R --> PORT\n  LTR_R --> PORT\n  Cost --> PORT\n  PORT --> SR\n  PORT --> MDD\n  VolR --> MDD\n  VIX -.->|\"r=-0.17 VIOLATED\"| HML\n  linkStyle default stroke:#CC0000,stroke-width:2px",
  "dag-drif-mount": "graph TD\n  HML[\"HML Value\"] --> DRIF_S[\"DRIF Signal\"]\n  SMB[\"SMB Size\"] --> DRIF_S\n  Mom[\"Mom Momentum\"] --> DRIF_S\n  RMW[\"RMW Profitability\"] --> DRIF_S\n  DRIF_S --> DRIF_R[\"DRIF Return\"]\n  Mkt_RF[\"Market Mkt-RF\"] --> DRIF_R\n  VIX[\"VIX Level\"] -.->|\"r=-0.17\"| HML\n  Decay[\"Premium Decay\"] --> DRIF_R\n  DRIF_R --> PORT[\"Portfolio Return\"]\n  linkStyle default stroke:#CC0000,stroke-width:2px\n  linkStyle 6 stroke:#ffff00,stroke-width:3px,stroke-dasharray:5",
  "dag-fmax-mount": "graph TD\n  HML[\"HML Value\"] --> FMAX_S[\"FacMAX Signal\"]\n  SMB[\"SMB Size\"] --> FMAX_S\n  Mom[\"Mom Momentum\"] --> FMAX_S\n  FMAX_S --> FMAX_R[\"FacMAX Return\"]\n  Mkt_RF[\"Market Mkt-RF\"] --> FMAX_R\n  Decay[\"Premium Decay\"] --> FMAX_R\n  FMAX_R --> PORT[\"Portfolio Return\"]\n  linkStyle default stroke:#CC0000,stroke-width:2px",
  "dag-ltr-mount": "graph TD\n  Mom[\"Mom Momentum\"] --> LTR_S[\"LTR Signal\"]\n  SMB[\"SMB Size\"] --> LTR_S\n  RateR[\"Rate Regime\"] --> LTR_S\n  LTR_S --> LTR_R[\"LTR Return\"]\n  Mkt_RF[\"Market Mkt-RF\"] --> LTR_R\n  LTR_R --> PORT[\"Portfolio Return\"]\n  linkStyle default stroke:#CC0000,stroke-width:2px"
};

async function renderDiagrams() {
  for (var mountId in dagDefs) {
    var mount = document.getElementById(mountId);
    if (!mount || mount.querySelector('svg')) continue;
    var pre = document.createElement('pre');
    pre.className = 'mermaid';
    pre.textContent = dagDefs[mountId];
    pre.style.minHeight = mountId.includes('full') ? '600px' : '400px';
    mount.appendChild(pre);
  }
  var unrendered = document.querySelectorAll('pre.mermaid:not([data-processed])');
  if (unrendered.length > 0) {
    try { await mermaid.run({nodes: Array.from(unrendered)}); } catch(e) { console.log('mermaid:', e); }
  }
}

document.addEventListener('DOMContentLoaded', function() { setTimeout(renderDiagrams, 800); });
document.addEventListener('shown.bs.tab', function() { setTimeout(renderDiagrams, 300); });
