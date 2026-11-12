# Strategy verdict -- ONE home for "is this strategy Keep / Watch / Failed?"
#
# Before this file a strategy's standing had no single home: failures were
# listed by three different filters (falsification.qmd `ff_alpha_tstat < 2.0`,
# hand-typed evidence.qmd cards, the research log), so a strategy could be
# "refuted" in one place and ranked in another. The verdict is now DERIVED from
# metrics already in the pipeline (leaderboard, fals_summary) by
# compute_strategy_verdict(), under the thresholds in STRATEGY_VERDICT_RULE.
# Only human-judgement fields (family, reason, decided_on, issue, ...) are typed,
# in data/strategy_register.csv (see data/strategy_register.md); the register
# holds NO metric values.
#
# Rule (all thresholds below, no literal copies elsewhere):
#   Failed  = the leaderboard flags the series as not tradeable (hindsight);
#             OR the falsification verdict is a no-alpha verdict;
#             OR (net CAGR < 0 AND DSR p > 0.5).
#   Keep    = net CAGR > 0 AND DSR p < 0.05 AND detection powered.
#   Watch   = everything else, with verdict_reason naming each unmet or
#             unknown Keep criterion. NA inputs never fall silently into
#             Watch: the reason says which input was missing.

STRATEGY_VERDICT_LEVELS <- c("Keep", "Watch", "Failed")

STRATEGY_VERDICT_RULE <- list(
  # Keep: all three must hold.
  keep_net_cagr_above = 0,
  keep_dsr_p_below = 0.05,
  # Failed (return-based): both must hold.
  fail_net_cagr_below = 0,
  fail_dsr_p_above = 0.5,
  # Failed (hindsight): leaderboard `borrow_status` value that means the series
  # has no weight vector to trade (derived in R/plan_cost_convention.R).
  not_tradeable_borrow_status = "not_tradeable",
  # Falsification verdict (Fama-French 5 + Momentum alpha), one home for the
  # scorecard in R/plan_falsification_vignette.R too.
  fals_genuine_alpha_t_above = 2.0,
  fals_genuine_r2_below = 0.15,
  fals_borderline_alpha_t_above = 1.96,
  fals_levels = c("Genuine alpha", "Borderline", "No alpha (beta)"),
  fals_no_alpha_verdicts = "No alpha (beta)"
)

#' Falsification verdict from FF5+Mom alpha t-statistic and R-squared
#'
#' @param alpha_t Numeric vector, `ff_alpha_tstat`.
#' @param r_squared Numeric vector, `ff_r_squared`.
#' @param rule Threshold list, default [STRATEGY_VERDICT_RULE].
#' @return Character vector, one of `rule$fals_levels`, `NA` when an input is NA.
#' @noRd
falsification_verdict <- function(alpha_t, r_squared, rule = STRATEGY_VERDICT_RULE) {
  lv <- rule$fals_levels
  genuine <- alpha_t > rule$fals_genuine_alpha_t_above &
    r_squared < rule$fals_genuine_r2_below
  border <- alpha_t > rule$fals_borderline_alpha_t_above
  # An NA input is not a no-alpha verdict: it stays NA (not assessed).
  ifelse(is.na(alpha_t) | is.na(r_squared), NA_character_,
         ifelse(genuine, lv[1], ifelse(border, lv[2], lv[3])))
}

#' Read the strategy register (human-judgement fields only)
#'
#' @param path Path to data/strategy_register.csv.
#' @return Tibble of character columns; empty cells are `NA`.
#' @noRd
read_strategy_register <- function(path) {
  if (!is.character(path) || length(path) != 1L || !file.exists(path)) {
    cli::cli_abort(c(
      "x" = "Strategy register file not found.",
      "i" = "Expected data/strategy_register.csv; got {.val {path}}."
    ))
  }
  reg <- utils::read.csv(path, colClasses = "character", na.strings = "",
                         stringsAsFactors = FALSE, strip.white = TRUE)
  need <- STRATEGY_REGISTER_COLS
  miss <- setdiff(need, names(reg))
  if (length(miss) > 0L) {
    cli::cli_abort(c(
      "x" = "Strategy register is missing column(s): {.field {miss}}.",
      "i" = "Required columns: {.field {need}}."
    ))
  }
  tibble::as_tibble(reg[, need, drop = FALSE])
}

STRATEGY_REGISTER_COLS <- c(
  "strategy_id", "family", "reason", "decided_on", "issue",
  "hypothesis_uuid", "revisit_if", "notes"
)

# Leaderboard columns the verdict reads.
.SV_LB_COLS <- c("period", "strategy", "net_cagr", "dsr_pvalue_klogged",
                 "detection_underpowered", "borrow_status")

#' One verdict from already-extracted inputs (scalar)
#'
#' @return list(verdict, reason)
#' @noRd
.sv_one <- function(net_cagr, dsr_p, underpowered, borrow_status, fals, has_row, rule) {
  fmt <- function(x) format(x, scientific = FALSE, trim = TRUE)
  if (!has_row) {
    return(list(verdict = "Watch",
                reason = "no Full Period row on the leaderboard (not ranked)"))
  }
  if (!is.na(borrow_status) && borrow_status == rule$not_tradeable_borrow_status) {
    return(list(verdict = "Failed",
                reason = "series is not tradeable (hindsight: no weight vector to trade)"))
  }
  if (!is.na(fals) && fals %in% rule$fals_no_alpha_verdicts) {
    return(list(verdict = "Failed",
                reason = paste0("falsification verdict: ", fals)))
  }
  if (!is.na(net_cagr) && !is.na(dsr_p) &&
      net_cagr < rule$fail_net_cagr_below && dsr_p > rule$fail_dsr_p_above) {
    return(list(verdict = "Failed",
                reason = paste0("net CAGR < ", fmt(rule$fail_net_cagr_below),
                                " and DSR p > ", fmt(rule$fail_dsr_p_above))))
  }
  unmet <- character(0)
  if (is.na(net_cagr)) {
    unmet <- c(unmet, "net CAGR missing")
  } else if (net_cagr <= rule$keep_net_cagr_above) {
    unmet <- c(unmet, paste0("net CAGR not > ", fmt(rule$keep_net_cagr_above)))
  }
  if (is.na(dsr_p)) {
    unmet <- c(unmet, "DSR p missing")
  } else if (dsr_p >= rule$keep_dsr_p_below) {
    unmet <- c(unmet, paste0("DSR p not < ", fmt(rule$keep_dsr_p_below)))
  }
  if (is.na(underpowered)) {
    unmet <- c(unmet, "detection power not assessed")
  } else if (isTRUE(underpowered)) {
    unmet <- c(unmet, "detection underpowered")
  }
  if (length(unmet) == 0L) {
    return(list(verdict = "Keep",
                reason = paste0("net CAGR > ", fmt(rule$keep_net_cagr_above),
                                ", DSR p < ", fmt(rule$keep_dsr_p_below),
                                ", detection powered")))
  }
  list(verdict = "Watch", reason = paste(unmet, collapse = "; "))
}

#' Compute the Keep / Watch / Failed verdict for every strategy
#'
#' One row per `strategy_names$code_name`, plus one row per leaderboard
#' strategy that is not in `strategy_names` (so the QA gate can flag it).
#'
#' @param leaderboard The `leaderboard` target (all periods; only
#'   `period == "Full Period"` is read).
#' @param strategy_names The `strategy_names` target (`code_name`, `short_name`).
#' @param fals_summary The `fals_summary` target (`strategy` = code_name,
#'   `ff_alpha_tstat`, `ff_r_squared`) or `NULL`. Strategies it does not cover
#'   have no falsification verdict (`NA`), which is not a no-alpha verdict.
#' @param register Optional tibble from [read_strategy_register()]; its fields
#'   are left-joined by `strategy_id`.
#' @param rule Threshold list, default [STRATEGY_VERDICT_RULE].
#' @return Tibble: strategy_id, short_name, verdict, verdict_reason, the input
#'   metrics (net_cagr, sharpe, max_dd, dsr_pvalue_klogged,
#'   detection_underpowered, borrow_status, fals_verdict) and the register fields.
#' @noRd
compute_strategy_verdict <- function(leaderboard, strategy_names,
                                     fals_summary = NULL, register = NULL,
                                     rule = STRATEGY_VERDICT_RULE) {
  if (!is.data.frame(leaderboard) || !all(.SV_LB_COLS %in% names(leaderboard))) {
    cli::cli_abort(c(
      "x" = "compute_strategy_verdict(): leaderboard lacks required column(s).",
      "i" = "Need: {.field {.SV_LB_COLS}}."
    ))
  }
  if (!is.data.frame(strategy_names) ||
      !all(c("code_name", "short_name") %in% names(strategy_names))) {
    cli::cli_abort(c(
      "x" = "compute_strategy_verdict(): strategy_names lacks code_name/short_name."
    ))
  }
  fp <- leaderboard[leaderboard$period == "Full Period" &
                      !is.na(leaderboard$period), , drop = FALSE]
  if (anyDuplicated(fp$strategy) > 0L) {
    cli::cli_abort(c(
      "x" = "Duplicate Full Period leaderboard rows for: {.val {unique(fp$strategy[duplicated(fp$strategy)])}}.",
      "i" = "A verdict needs exactly one row per strategy."
    ))
  }
  for (col in c("sharpe", "max_dd")) {
    if (!col %in% names(fp)) fp[[col]] <- NA_real_
  }

  ids <- tibble::tibble(
    strategy_id = strategy_names$code_name,
    short_name = strategy_names$short_name
  )
  orphans <- setdiff(fp$strategy, ids$short_name)
  if (length(orphans) > 0L) {
    ids <- dplyr::bind_rows(ids, tibble::tibble(strategy_id = orphans,
                                                short_name = orphans))
  }

  m <- match(ids$short_name, fp$strategy)
  lb_col <- function(col) fp[[col]][m]
  fals_v <- rep(NA_character_, nrow(ids))
  if (!is.null(fals_summary) && nrow(fals_summary) > 0L) {
    fv <- falsification_verdict(fals_summary$ff_alpha_tstat,
                                fals_summary$ff_r_squared, rule)
    fals_v <- fv[match(ids$strategy_id, fals_summary$strategy)]
  }
  out <- dplyr::mutate(
    ids,
    net_cagr = as.numeric(lb_col("net_cagr")),
    sharpe = as.numeric(lb_col("sharpe")),
    max_dd = as.numeric(lb_col("max_dd")),
    dsr_pvalue_klogged = as.numeric(lb_col("dsr_pvalue_klogged")),
    detection_underpowered = as.logical(lb_col("detection_underpowered")),
    borrow_status = as.character(lb_col("borrow_status")),
    fals_verdict = fals_v,
    has_row = !is.na(m)
  )
  res <- lapply(seq_len(nrow(out)), function(i) {
    .sv_one(out$net_cagr[i], out$dsr_pvalue_klogged[i],
            out$detection_underpowered[i], out$borrow_status[i],
            out$fals_verdict[i], out$has_row[i], rule)
  })
  out$verdict <- vapply(res, `[[`, character(1), "verdict")
  out$verdict_reason <- vapply(res, `[[`, character(1), "reason")
  out <- dplyr::select(out, strategy_id, short_name, verdict, verdict_reason,
                       net_cagr, sharpe, max_dd, dsr_pvalue_klogged,
                       detection_underpowered, borrow_status, fals_verdict)
  if (!is.null(register)) {
    reg <- register[!duplicated(register$strategy_id), , drop = FALSE]
    out <- dplyr::left_join(out, reg, by = "strategy_id")
  }
  out
}

#' Dynamic verdict count, for captions (counts derived, never typed)
#' @param verdict Character vector of verdicts.
#' @return e.g. "Verdict: 0 Keep, 10 Watch, 8 Failed of 18."
#' @noRd
strategy_verdict_counts_text <- function(verdict) {
  n <- vapply(STRATEGY_VERDICT_LEVELS, function(l) sum(verdict == l, na.rm = TRUE),
              integer(1))
  paste0("Verdict: ", paste0(n, " ", STRATEGY_VERDICT_LEVELS, collapse = ", "),
         " of ", length(verdict), ".")
}

#' One-sentence statement of the verdict rule, built from the thresholds
#' @param rule Threshold list, default [STRATEGY_VERDICT_RULE].
#' @noRd
strategy_verdict_rule_text <- function(rule = STRATEGY_VERDICT_RULE) {
  paste0(
    "Keep = net CAGR > ", rule$keep_net_cagr_above, ", DSR p < ", rule$keep_dsr_p_below,
    " and detection powered. Failed = hindsight (not tradeable) series, a no-alpha falsification verdict, or net CAGR < ",
    rule$fail_net_cagr_below, " with DSR p > ", rule$fail_dsr_p_above, ". Otherwise Watch."
  )
}

# ---- S51: every strategy has a register row; every Failed one has a reason ----

#' S51: one verdict per strategy id in the union of the verdict and the register
#'
#' PASS: id in both, and (not Failed or `reason` non-empty). FAIL: a strategy
#' with no register row; a register row naming an unknown strategy; a duplicated
#' register id; a Failed strategy whose register `reason` is empty/NA.
#' INDETERMINATE: either input missing, empty, or without its required columns.
#'
#' @param verdict_tbl Output of [compute_strategy_verdict()] (needs
#'   `strategy_id`, `verdict`).
#' @param register Output of [read_strategy_register()].
#' @return Tibble: strategy_id, verdict, detail.
#' @noRd
build_strategy_register_table <- function(verdict_tbl, register) {
  row1 <- function(id, verdict, detail) {
    tibble::tibble(strategy_id = id, verdict = verdict, detail = detail)
  }
  ok_v <- is.data.frame(verdict_tbl) && nrow(verdict_tbl) > 0L &&
    all(c("strategy_id", "verdict") %in% names(verdict_tbl))
  ok_r <- is.data.frame(register) && nrow(register) > 0L &&
    all(c("strategy_id", "reason") %in% names(register))
  if (!ok_v || !ok_r) {
    return(row1(NA_character_, "INDETERMINATE",
                "verdict table or register is NULL, empty, or lacks required columns"))
  }
  ids <- unique(c(verdict_tbl$strategy_id, register$strategy_id))
  ids <- ids[!is.na(ids)]
  in_v <- ids %in% verdict_tbl$strategy_id
  in_r <- ids %in% register$strategy_id
  v <- verdict_tbl$verdict[match(ids, verdict_tbl$strategy_id)]
  reason <- register$reason[match(ids, register$strategy_id)]
  empty_reason <- is.na(reason) | !nzchar(trimws(reason))
  bad_failed <- in_v & in_r & !is.na(v) & v == "Failed" & empty_reason
  verdict <- ifelse(in_v & in_r & !bad_failed, "PASS", "FAIL")
  detail <- ifelse(
    !in_r, "strategy has no register row",
    ifelse(!in_v, "register row names an unknown strategy",
           ifelse(bad_failed, "Failed strategy has an empty register reason",
                  "registered")))
  out <- tibble::tibble(strategy_id = ids, verdict = verdict, detail = detail)
  dup <- unique(register$strategy_id[duplicated(register$strategy_id)])
  extra <- list()
  if (length(dup) > 0L) {
    extra[[1L]] <- row1(dup, "FAIL", "register id appears more than once")
  }
  if (anyNA(register$strategy_id)) {
    extra[[length(extra) + 1L]] <- row1(NA_character_, "FAIL", "register row with an empty strategy_id")
  }
  dplyr::bind_rows(c(list(out), extra))
}

#' S51: abort on any FAIL or INDETERMINATE; PASS returns the table
#'
#' FAIL aborts with class `qa_s51_fail`; INDETERMINATE with
#' `qa_s51_indeterminate`; PASS returns `verdict_tbl` with a `summary` attribute.
#' @param verdict_tbl Output of [build_strategy_register_table()].
#' @noRd
check_strategy_register <- function(verdict_tbl) {
  v <- verdict_tbl$verdict
  n_pass <- sum(v == "PASS"); n_fail <- sum(v == "FAIL")
  n_ind <- sum(v == "INDETERMINATE")
  examined <- n_pass + n_fail
  summary <- vapply(c(pass = n_pass, fail = n_fail, indeterminate = n_ind,
                      examined = examined), as.integer, integer(1))
  head_line <- sprintf("%d pass, %d fail, %d indeterminate; %d strateg%s examined",
                       n_pass, n_fail, n_ind, examined,
                       ifelse(examined == 1L, "y", "ies"))
  bad <- verdict_tbl[v %in% c("FAIL", "INDETERMINATE"), , drop = FALSE]
  bad_msgs <- gsub("}", "}}", gsub("{", "{{", sprintf(
    "  %s: %s", ifelse(is.na(bad$strategy_id), "(none)", bad$strategy_id),
    bad$detail), fixed = TRUE), fixed = TRUE)
  if (n_fail > 0L) {
    cli::cli_abort(c(
      "x" = paste0("qa_strategy_register (S51) FAILED: ", head_line, "."),
      stats::setNames(bad_msgs, rep("i", length(bad_msgs))),
      "i" = "Add/fix the row in data/strategy_register.csv (a Failed strategy needs a reason)."
    ), class = "qa_s51_fail")
  }
  if (examined == 0L || n_ind > 0L) {
    cli::cli_abort(c(
      "x" = paste0("qa_strategy_register (S51) is INDETERMINATE: ", head_line, "."),
      stats::setNames(bad_msgs, rep("i", length(bad_msgs))),
      "i" = "The register could not be compared; this is NOT a pass (checks-must-distinguish-unknown)."
    ), class = "qa_s51_indeterminate")
  }
  structure(verdict_tbl, summary = summary)
}
