# Covariance-estimator configuration (issue #498).
# Single source of truth for which estimator the portfolio-construction
# pipeline uses. Routed through historicaldata::hd_cov_estimate().
#
# Default is "sample": bit-identical to stats::cov() (use = "complete.obs"),
# so deployed numbers are unchanged by the Phase 2 routing. Phase 3 will flip
# this to "ledoit_wolf" ONLY after the out-of-sample diagnostic (#498) shows
# regularisation improves min-variance OOS Sharpe / conditioning.
COV_METHOD    <- "sample"        # one of: sample, ledoit_wolf, rmt_denoise, threshold
COV_LW_TARGET <- "const_cor"     # Ledoit-Wolf target; only used when COV_METHOD == "ledoit_wolf"
