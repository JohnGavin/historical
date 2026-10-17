# Seed the research log with the seven parked strategy ideas (P1..P7) from
# knowledge/wiki/parked-strategy-ideas.md (Refs #962).
#
# These are backlog ideas, NOT tests and NOT pre-registrations: they are
# written UNSEALED by hd_strategy_idea_append(), priority "low", status
# "proposed". Nothing on the wiki page has been tested.
#
# Idempotent: an idea whose name already exists in the ledger is skipped.
# The research log is append-only, so a skipped idea is never edited.
#
# Run (repo root):
#   nix develop . --command Rscript scripts/seed_parked_strategy_ideas.R
#
# Optional first argument: a base_dir override (used by the tests/dry runs);
# default is the tracked inst/extdata/research_log/.

pkgload::load_all(here::here("packages", "historicaldata"), quiet = TRUE)

args <- commandArgs(trailingOnly = TRUE)
base_dir <- if (length(args) >= 1L) args[[1]] else NULL

ALGOADVANTAGE <- "https://algoadvantage.substack.com/p/the-questions-that-change-everything"
TRADEQUANTIX  <- "https://www.tradequantixnewsletter.com/"

# claim wording follows the wiki page; no mechanism is invented for any idea.
ideas <- tibble::tribble(
  ~name,                         ~economic_claim,                                                                                       ~asset_class,             ~source,
  "p1_spy_tlt_month_end",        "SPY/TLT month-end rebalance trade (named in AlgoAdvantage #057 show notes; mechanism not yet stated)", "equity/bond",          ALGOADVANTAGE,
  "p2_bond_end_of_month",        "Bond end-of-month effect (AlgoAdvantage #057 show notes mention an 18-month drawdown)",               "bond",                   ALGOADVANTAGE,
  "p3_equity_stat_arb_pairs",    "Equity statistical arbitrage from a pairs universe (AlgoAdvantage #057 show notes)",                  "equity",                 ALGOADVANTAGE,
  "p4_long_vol_into_earnings",   "Long volatility into earnings (AlgoAdvantage #057 show notes)",                                       "equity options",         ALGOADVANTAGE,
  "p5_otm_put_hedge",            "Cheap out-of-the-money puts as a hedge (AlgoAdvantage #057 show notes)",                              "equity options",         ALGOADVANTAGE,
  "p6_pullback_in_momentum",     "Pullback entry inside a momentum trade (TradeQuantiX Part 2, USA pullback momentum)",                 "equity",                 TRADEQUANTIX,
  "p7_momentum_low_vol_sleeve",  "Momentum plus low-volatility ranking sleeve (TradeQuantiX Parts 1 and 2)",                            "equity",                 TRADEQUANTIX
)

existing <- suppressMessages(hd_strategy_ledger(base_dir = base_dir))
existing_names <- existing$name

written <- character()
skipped <- character()
for (i in seq_len(nrow(ideas))) {
  nm <- ideas$name[[i]]
  if (nm %in% existing_names) {
    skipped <- c(skipped, nm)
    next
  }
  hd_strategy_idea_append(
    name           = nm,
    economic_claim = ideas$economic_claim[[i]],
    source         = ideas$source[[i]],
    priority       = "low",
    asset_class    = ideas$asset_class[[i]],
    issue          = 962,
    status         = "proposed",
    base_dir       = base_dir
  )
  written <- c(written, nm)
}

cat(sprintf("seed_parked_strategy_ideas: written=%d skipped=%d\n",
            length(written), length(skipped)))
if (length(written) > 0L) cat("  written:", paste(written, collapse = ", "), "\n")
if (length(skipped) > 0L) cat("  skipped (already in ledger):", paste(skipped, collapse = ", "), "\n")
