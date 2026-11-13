# Plan: strategy verdict (Keep / Watch / Failed) -- one home for strategy status.
#
# strategy_register_file  data/strategy_register.csv (human-judgement fields only)
# strategy_register       the parsed register
# strategy_verdict        verdict + reason per strategy, derived from the
#                         leaderboard and falsification targets
# qa_strategy_register    S51 gate: every strategy has a register row, no row
#                         names an unknown strategy, every Failed strategy has a
#                         reason (PASS / FAIL / INDETERMINATE, never collapsed)
#
# Logic lives in R/strategy_verdict.R (sourced by docs/_targets.R).

plan_strategy_verdict <- function() {
  list(
    targets::tar_target(
      strategy_register_file,
      here::here("data", "strategy_register.csv"),
      format = "file"
    ),
    targets::tar_target(
      strategy_register,
      read_strategy_register(strategy_register_file)
    ),
    targets::tar_target(
      strategy_verdict,
      compute_strategy_verdict(leaderboard, strategy_names, fals_summary,
                               strategy_register)
    ),
    targets::tar_target(qa_strategy_register, {
      verdict_tbl <- check_strategy_register(
        build_strategy_register_table(strategy_verdict, strategy_register)
      )
      s <- attr(verdict_tbl, "summary")
      cli::cli_inform(c("v" = paste0(
        "qa_strategy_register: S51 passed -- ", s[["pass"]], " pass / ",
        s[["fail"]], " fail / ", s[["indeterminate"]], " indeterminate; ",
        s[["examined"]], " strateg", ifelse(s[["examined"]] == 1L, "y", "ies"),
        " examined"
      )))
      verdict_tbl
    }, cue = targets::tar_cue(mode = "always"))
  )
}
