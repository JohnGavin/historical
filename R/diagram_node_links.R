# diagram_node_links.R — single source of truth for Mermaid node → file:line mappings
#
# Every clickable node in vignette Mermaid diagrams MUST appear here.
# Line numbers point to the tar_target() or function() definition that the node
# represents. Resolve lines with Grep on the repo, not by hand.
#
# Usage:
#   source("R/diagram_node_links.R")
#   df  <- diagram_node_links()
#   url <- gh_url("DRIF")   # "https://github.com/JohnGavin/historical/blob/main/R/plan_drif.R#L12"
#
# Maintenance: when a definition line changes, update the ~line value here ONLY.

#' Node → file + line mapping for all Mermaid diagram click targets
#'
#' @return A tibble with columns: node (character), file (repo-relative path,
#'   character), line (integer). NA_integer_ means "file is correct but exact
#'   line is unknown — add anchor when resolved".
#' @export
diagram_node_links <- function() {
  tibble::tribble(
    ~node,        ~file,                                          ~line,

    # ── Fama-French factors (query function in historicaldata) ────────────────
    # All factor data flows through hd_factors() defined at this line.
    "HML",        "packages/historicaldata/R/query.R",           193L,
    "SMB",        "packages/historicaldata/R/query.R",           193L,
    "Mom",        "packages/historicaldata/R/query.R",           193L,
    "RMW",        "packages/historicaldata/R/query.R",           193L,
    "Mkt_RF",     "packages/historicaldata/R/query.R",           193L,

    # ── Macro / VIX inputs ────────────────────────────────────────────────────
    # VIX, VTS, VVIX, Fed, Infl feed into rsc_params (risk-state plan)
    "VIX",        "R/plan_risk_state.R",                          23L,
    "VTS",        "R/plan_risk_state.R",                          23L,
    "VVIX",       "R/plan_risk_state.R",                          23L,
    "Fed",        "R/plan_risk_state.R",                          23L,
    "Infl",       "R/plan_risk_state.R",                          23L,

    # ── Regime states ─────────────────────────────────────────────────────────
    # Vol regime: rsc_regime inside plan_risk_state (line 131 = tar_target(rsc_regime))
    # Rate regime: regime_classification inside plan_regime (line 96)
    # VolR / RateR: Mermaid node IDs used in click directives
    # Vol_regime / Rate_regime: token aliases used in causal-implication label text
    #   (plan_causal_graph.R emits labels like "VIX_level ⊥ DRIF_return | Vol_regime").
    #   The link_node() function in falsification.qmd matches on these longer names.
    #   Without these aliases the implication table rows lose their hyperlinks.
    "VolR",       "R/plan_risk_state.R",                         131L,
    "RateR",      "R/plan_regime.R",                              96L,
    "Vol_regime", "R/plan_risk_state.R",                         131L,
    "Rate_regime","R/plan_regime.R",                              96L,

    # ── Strategy Signals / Returns (DRIF) ────────────────────────────────────
    "DRIF",       "R/plan_drif.R",                                12L,
    "DRIF_S",     "R/plan_drif.R",                                12L,
    "DRIF_R",     "R/plan_drif.R",                                12L,

    # ── Strategy Signals / Returns (Factor MAX) ───────────────────────────────
    "FMAX",       "R/plan_factormax.R",                           12L,
    "FMAX_S",     "R/plan_factormax.R",                           12L,
    "FMAX_R",     "R/plan_factormax.R",                           12L,

    # ── Strategy Signals / Returns (LTR) ─────────────────────────────────────
    "LTR",        "R/plan_ltr_momentum.R",                        17L,
    "LTR_S",      "R/plan_ltr_momentum.R",                        17L,
    "LTR_R",      "R/plan_ltr_momentum.R",                        17L,

    # ── VIX macro overlay (RSC overlay and VIX overlay nodes) ─────────────────
    # RSC_S feeds into the RSC overlay; VIXO / VIX_S feed into VIX overlay.
    # Both originate from vmo_params (line 11) in plan_vix_macro_overlay.
    "RSC",        "R/plan_risk_state.R",                          23L,
    "RSC_S",      "R/plan_risk_state.R",                          23L,
    "VIXO",       "R/plan_vix_macro_overlay.R",                   11L,
    "VIX_S",      "R/plan_vix_macro_overlay.R",                   11L,
    "VIX_level",  "R/plan_vix_macro_overlay.R",                   11L,
    "VIX_overlay","R/plan_vix_macro_overlay.R",                   48L,

    # ── Portfolio outcomes ─────────────────────────────────────────────────────
    # PORT/SR/MDD/RISK: multi-strategy portfolio plan (ms_params = line 10)
    # MKT_R: market benchmark return, computed in plan_backtest (bt_returns = line 47)
    "PORT",       "R/plan_multi_strategy.R",                      10L,
    "MKT_R",      "R/plan_backtest.R",                            47L,
    "SR",         "R/plan_multi_strategy.R",                      10L,
    "MDD",        "R/plan_multi_strategy.R",                      10L,
    "RISK",       "R/plan_multi_strategy.R",                      10L,

    # ── Structural factors (decay / crowding) ────────────────────────────────
    # Cost: transaction/rebalance cost in alpha decay plan (decay_params = line 20)
    "Structural", "R/plan_strategy_decay.R",                      13L,
    "Crowd",      "R/plan_strategy_decay.R",                      13L,
    "Decay",      "R/plan_strategy_decay.R",                      13L,
    "Cost",       "R/plan_alpha_decay.R",                         20L,

    # ── Diagram 1 overview aggregate nodes ───────────────────────────────────
    # "Factors", "Macro", "Market" are aggregate grouping nodes; point to the
    # most representative target in each plan.
    "Factors",    "R/plan_drif.R",                                12L,
    "Macro",      "R/plan_risk_state.R",                          23L,
    "Market",     "R/plan_drif.R",                                12L
  )
}

#' Build a GitHub permalink for a diagram node
#'
#' @param node Character. Must match a row in [diagram_node_links()].
#' @param ref Character. Git ref — default "main". Pin to a SHA for stable links.
#' @param repo Character. GitHub "owner/repo" slug.
#' @return Character URL, including \code{#L<n>} anchor when the line is known.
#' @export
gh_url <- function(node,
                   ref  = "main",
                   repo = "JohnGavin/historical") {
  df  <- diagram_node_links()
  row <- df[df$node == node, ]
  if (nrow(row) == 0L) {
    cli::cli_abort(c(
      "x" = "Node {.val {node}} not found in {.fn diagram_node_links}.",
      "i" = "Add a row to {.file R/diagram_node_links.R} for this node."
    ))
  }
  if (nrow(row) > 1L) {
    cli::cli_abort(c(
      "x" = "Node {.val {node}} has {nrow(row)} duplicate entries in {.fn diagram_node_links}.",
      "i" = "Each node must appear exactly once in {.file R/diagram_node_links.R}."
    ))
  }
  base <- sprintf("https://github.com/%s/blob/%s/%s", repo, ref, row$file)
  if (!is.na(row$line)) {
    paste0(base, "#L", row$line)
  } else {
    base
  }
}

#' Emit Mermaid click directives for every node in diagram_node_links()
#'
#' Convenience helper for generating the click block when rebuilding a diagram.
#'
#' @param nodes Character vector of node IDs to emit. Default: all nodes.
#' @param ref Character. Git ref passed to \code{gh_url()}.
#' @return Character vector of Mermaid click lines (one per node).
#' @export
mermaid_click_block <- function(nodes = diagram_node_links()$node, ref = "main") {
  vapply(nodes, function(n) {
    sprintf(' click %s "%s" _blank', n, gh_url(n, ref = ref))
  }, character(1L))
}
