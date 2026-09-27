# drif_multiverse_caption is a non-empty string

    Code
      cat(caption)
    Output
      Of 3 specifications tested (varying elastic-net alpha, CV folds, feature set, and lambda rule), the current DRIF spec (S01: alpha=0.5, k=5, chrono, lambda.min) ranks 2 by OOS Sharpe (0.82). Sharpe range across specs: 0.74 to 0.91. Source: plan_drif_v2.R; paper: Cakici et al. 2024 (SSRN 6005614).

# compute_drif_selection_jaccard aborts with fewer than 2 months

    Code
      compute_drif_selection_jaccard(list(`2020-01` = c("c1")))
    Condition
      Error in `compute_drif_selection_jaccard()`:
      x compute_drif_selection_jaccard() needs at least 2 months of selected features to form a consecutive pair.
      i Got 1.

# summarise_drif_selection_stability aborts on a malformed input tibble

    Code
      summarise_drif_selection_stability(tibble::tibble(wrong_col = 1))
    Condition
      Error in `summarise_drif_selection_stability()`:
      x summarise_drif_selection_stability(): jaccard_tbl is missing required column(s): ym_from, ym_to, jaccard.
      i Expected the tibble returned by compute_drif_selection_jaccard().

# compute_drif_selected_features aborts when every month is skipped

    Code
      compute_drif_selected_features(features, params)
    Condition
      Error in `compute_drif_selected_features()`:
      x compute_drif_selected_features(): no trade month produced a fitted model.
      i Every one of the 1 trade month(s) was skipped by the same min-training-rows / min-test-rows guard drif_signal itself uses -- check drif_features / drif_params (#910 item 2).

