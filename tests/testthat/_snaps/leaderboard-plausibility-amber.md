# enforce = TRUE aborts on an unacknowledged amber flag and names it

    Code
      check_leaderboard_plausibility_amber(leaderboard_with_outlier, empty_ack,
        enforce = TRUE)
    Message
      i qa_leaderboard_plausibility_amber: 1 peer-relative amber flag(s) (#719 Layer 1):
      i  CMR -- vol = 0.05 (peer median 0.17, modified z = -8.09) [NOT acknowledged]
    Condition
      Error in `check_leaderboard_plausibility_amber()`:
      x 1 peer-relative amber outlier(s) have no written acknowledgement (#719 Layer 1, S30, HD_ENFORCE_PLAUSIBILITY_AMBER=1):
      i  CMR / vol -- value = 0.05, peer median = 0.17, modified z = -8.09
      i Add a row to LEADERBOARD_PLAUSIBILITY_ACKNOWLEDGED (R/plan_qa_gates.R) naming strategy, metric, and a written reason the outlier is genuine -- or fix the underlying data if it is not. Per fail-loud-not-null.md, the absence of a reason is what fails, not the outlier value itself.

