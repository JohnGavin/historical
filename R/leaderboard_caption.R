# Leaderboard "Rankings" table caption, as bullets (presentation only).
#
# The caption used to be one wall of prose. Owner: "be punchy, almost always
# use bullet points, be concise and use embedded links to the details or popup
# on hover with embedded links." This builder returns:
#   $short   a <ul> of at most 3 one-line bullets, always visible
#   $details a <ul> with one bullet per column or concept: bold term (the
#            hover target of a popover holding the long explanation), a
#            blurb of <= 15 words, and links.
# The long prose was RELOCATED into the popover bodies, not deleted. Every
# number is computed from `full` (or the arguments) -- no hand-typed copies.
#
# Popover bodies are built inline with htmltools (not from
# data/column_glossary.yaml) because they carry per-build numbers and the
# glossary has no placeholder mechanism. They go through hd_popover_span()
# (R/column_popover.R), so attributes are escaped by .hd_esc_attr().
#
# docs/leaderboard.qmd calls this and hands the result to hd_caption().

.lc_a <- function(label, url) {
  htmltools::tags$a(href = url, target = "_blank", rel = "noopener noreferrer", label)
}

.lc_issue <- function(n, gh_repo_url) {
  .lc_a(paste0("#", n), sprintf("%s/issues/%s", gh_repo_url, n))
}

.lc_html <- function(...) as.character(htmltools::tagList(...))

# A <p> built by string concatenation, NOT by htmltools child rendering:
# htmltools pretty-prints each child on its own indented line, which would put
# newlines and runs of spaces around every inline number inside the popover.
# Text is escaped here; tags (code, a) are rendered whole; numbers are as-is.
.lc_p <- function(...) {
  parts <- vapply(list(...), function(x) {
    if (inherits(x, c("shiny.tag", "shiny.tag.list", "html"))) {
      paste(as.character(x), collapse = "")
    } else {
      htmltools::htmlEscape(paste(as.character(x), collapse = ""), attribute = FALSE)
    }
  }, character(1))
  htmltools::tags$p(htmltools::HTML(paste(parts, collapse = "")))
}

.lc_plural_y <- function(n) if (n == 1L) "y" else "ies"

# One bullet: popover-wrapped bold term, ": ", short blurb, then links.
.lc_li <- function(term, blurb, pop_body, ..., pop_title = term) {
  links <- list(...)
  pop <- hd_popover_span(label = term, title = pop_title, content_html = pop_body)
  htmltools::tags$li(
    htmltools::tags$strong(htmltools::HTML(pop)), ": ", blurb,
    if (length(links) > 0L) {
      htmltools::tagList(" ", lapply(seq_along(links), function(i) {
        htmltools::tagList(if (i > 1L) " · ", links[[i]])
      }))
    }
  )
}

#' Build the Rankings caption pieces
#'
#' @param full Leaderboard data frame (one row per strategy).
#' @param gh_base GitHub repo URL (no trailing slash).
#' @param git_sha Commit SHA (or "main") used in code permalinks.
#' @param kraw,keff Raw / effective number of strategies tested (may be NA).
#' @param has_sharpe_ci Logical: is the Sharpe CI column present.
#' @param n_ci_crosses_zero Count of strategies whose Sharpe CI spans zero.
#' @return list(short = <ul>, details = <ul>) of htmltools tags.
#' @noRd
hd_leaderboard_caption <- function(full, gh_base, git_sha, kraw, keff,
                                   has_sharpe_ci, n_ci_crosses_zero) {
  N <- nrow(full)
  code_url <- function(path, anchor = "") sprintf("%s/blob/%s/%s%s", gh_base, git_sha, path, anchor)
  code_link <- function(label, path, anchor = "") {
    .lc_a(htmltools::tags$code(label), code_url(path, anchor))
  }
  issue <- function(n) .lc_issue(n, gh_base)

  # ---- counts, all computed from `full` -----------------------------------
  n_ssr_covered <- sum(!is.na(full$ssr))
  n_ssr_na      <- sum(is.na(full$ssr))
  n_net_covered <- sum(!is.na(full$net_cagr))

  n_flagged <- sum(!is.na(full$credible) & !full$credible)
  flagged   <- full$strategy[!is.na(full$credible) & !full$credible]
  n_biased  <- if ("survivorship_biased" %in% names(full)) sum(full$survivorship_biased, na.rm = TRUE) else 0L
  biased    <- if (n_biased > 0) full$strategy[!is.na(full$survivorship_biased) & full$survivorship_biased] else character(0)

  n_2x <- if ("gross_convention" %in% names(full)) sum(full$gross_convention >= 2, na.rm = TRUE) else 0L
  n_capped <- if ("is_cap" %in% names(full)) sum(full$is_cap, na.rm = TRUE) else 0L
  n_na_gross <- if ("gross_convention" %in% names(full)) sum(is.na(full$gross_convention)) else N

  n_gross_target <- sum(!is.na(full$G_capped))
  n_binds <- sum(full$backstop_binds, na.rm = TRUE)
  n_blocked_s31 <- sum(
    !is.na(full$G_capped) & full$G_capped > 1.0 &
      (is.na(full$detection_underpowered) | full$detection_underpowered),
    na.rm = TRUE
  )
  sigma_used_vals <- full$sigma_target_used[!is.na(full$sigma_target_used)]
  backstop_used_vals <- full$backstop_used[!is.na(full$backstop_used)]

  n_zero_cost <- if ("cost_per_trade_bps" %in% names(full)) sum(full$cost_per_trade_bps == 0, na.rm = TRUE) else 0L
  zero_cost_strategies <- if (n_zero_cost > 0) {
    full$strategy[!is.na(full$cost_per_trade_bps) & full$cost_per_trade_bps == 0]
  } else character(0)
  n_na_cost <- if ("cost_per_trade_bps" %in% names(full)) sum(is.na(full$cost_per_trade_bps)) else N
  cost_bps_range <- if ("cost_per_trade_bps" %in% names(full) && any(!is.na(full$cost_per_trade_bps))) {
    rng <- range(full$cost_per_trade_bps, na.rm = TRUE)
    paste0(rng[1], "–", rng[2], " bps")
  } else "not available"

  n_redundant <- if ("redundant" %in% names(full)) sum(full$redundant, na.rm = TRUE) else 0L
  n_redundant_na <- if ("redundant" %in% names(full)) sum(is.na(full$redundant)) else N
  corr_covered_n <- if ("redundant" %in% names(full)) sum(!is.na(full$redundant)) else 0L
  corr_excluded_strats <- if ("redundant" %in% names(full)) full$strategy[is.na(full$redundant)] else full$strategy

  # ---- visible part: <= 3 one-line bullets ---------------------------------
  short <- htmltools::tags$ul(
    htmltools::tags$li("Strategies ranked by Sharpe, highest first; CAGR is gross, Net CAGR is net of cost."),
    htmltools::tags$li("Gross exposure and cost differ by row, so Vol, Net CAGR and Max DD are not comparable; Sharpe is leverage-invariant."),
    htmltools::tags$li("“not computed” means never assessed, not a pass.")
  )

  # ---- details: one bullet per column / concept ----------------------------
  lb <- code_link("plan_leaderboard.R", "R/plan_leaderboard.R")
  qa <- code_link("plan_qa_gates.R", "R/plan_qa_gates.R")
  li <- list()

  li$cagr <- .lc_li(
    "CAGR / Net CAGR", "gross vs cost-adjusted compound annual growth.",
    .lc_html(
      .lc_p("CAGR = unadjusted (gross) compound annual growth rate, computed for every strategy."),
      .lc_p("Net CAGR is net of cost; it is covered for ", n_net_covered, " of ", N, " strategies.")
    ), lb)

  li$ssr <- .lc_li(
    "SSR", "Sharpe Stability Ratio; ≥2 means consistent.",
    .lc_html(
      .lc_p("SSR = Sharpe Stability Ratio (HAC t-stat of rolling 36-month Sharpes; ≥2 = consistent)."),
      .lc_p("Computed for a fixed subset of strategies (", n_ssr_covered, " of ", N,
                        "); the remaining ", n_ssr_na,
                        " show “not computed” — never assessed, not a computed absence of stability.")
    ), lb)

  li$top5 <- .lc_li(
    "Top5% Share", "fraction of total return from the best 5% of months.",
    .lc_html(
      .lc_p("Top5% Share = fraction of total return from best 5% of months."),
      .lc_p("Like SSR it is computed for a fixed subset of strategies (", n_ssr_covered, " of ", N,
                        "); the remaining ", n_ssr_na,
                        " show “not computed” — never assessed, not a computed absence of stability.")
    ), lb)

  li$credible <- .lc_li(
    "Credible", "plausible CAGR (<20%) and cum P&L (<50x); NO means assessed and failed.",
    .lc_html(
      .lc_p("Credible = plausible CAGR (<20%) and cum P&L (<50x): “NO” marks a strategy that was ",
                        "assessed and failed that check, “not computed” marks a strategy for which ",
                        "cost-adjusted metrics were never assessed at all (not the same as failing the check).")
    ), qa)

  li$cvar <- .lc_li(
    "CVaR 95%", paste0("same “not computed” scope as Net CAGR (", n_net_covered, " of ", N, ")."),
    .lc_html(
      .lc_p("The Net CAGR, Credible and CVaR 95% columns share this exact same “not computed” scope (",
                        n_net_covered, " of ", N, " strategies covered) — all three come from the same cost_rows join ",
                        "and are jointly present or jointly absent per row (QA gate S23, R/plan_qa_gates.R).")
    ), qa)

  flag_parts <- list(
    if (n_flagged > 0) .lc_p(
      "WARNING: ", paste(flagged, collapse = ", "),
      " flagged as non-credible (>20% CAGR or >50x cum P&L — likely unrealistic)."),
    if (n_biased > 0) .lc_p(
      "Survivorship-biased (", htmltools::tags$code("survivorship_biased = TRUE"), "): ",
      paste(biased, collapse = ", "), " — draw on ", htmltools::tags$code("stk_universe"),
      " (see issue #150).")
  )
  flag_parts <- Filter(Negate(is.null), flag_parts)
  if (length(flag_parts) == 0L) {
    flag_parts <- list(.lc_p("No strategy is currently flagged as non-credible or survivorship-biased."))
  }
  li$flags <- .lc_li(
    "Flags", paste0(n_flagged, " non-credible, ", n_biased, " survivorship-biased."),
    .lc_html(flag_parts), issue(150))

  li$gross_now <- .lc_li(
    "Gross (now)", "own-construction exposure; * marks a ceiling, not a realised average.",
    .lc_html(
      .lc_p(
        "Gross exposure (", htmltools::tags$code("sum(abs(w))"), ", computed by ",
        code_link("hd_exposure_metrics()", "packages/historicaldata/R/exposure.R", "#L67"),
        " and recorded per strategy in ",
        code_link("strategy_gross_convention", "R/plan_exposure.R", "#L27"),
        ") is not uniform across this table: ", n_2x,
        " strategies are built dollar-neutral long-short at 2.0x gross while others run long-only at 1.0x, ",
        "so Vol, Net CAGR, and Max DD are not directly comparable across rows even when Sharpe is similar ",
        "(Sharpe is leverage-invariant under proportional scaling; the other three columns are not)."),
      .lc_p(
        "A trailing * on the Gross (now) column (", n_capped,
        " strategies) marks a construction ceiling the strategy can reach but does not realise every period ",
        "(e.g. Managed Futures targets volatility and only hits its 3.0x cap in low-vol regimes) — ",
        "treat those as upper bounds, not realised averages."),
      if (n_na_gross > 0) .lc_p(
        n_na_gross, " strategy row(s) show — for Gross (now): either the return is assembled from a ",
        "pre-computed factor series with no explicit weight vector to measure, or the row is a ",
        "meta-portfolio blend of other rows.")
    ),
    code_link("strategy_gross_convention", "R/plan_exposure.R", "#L27"), issue(626))

  if (n_gross_target > 0) {
    li$gross_target <- .lc_li(
      "Gross (target)", "leverage the vol-normalised allocator would assign; backstop provisional.",
      .lc_html(
        .lc_p(
          "Gross (target) (", code_link("compute_allocator_gross()", "R/plan_leverage.R"), ", ", issue(626),
          ") is the leverage the vol-normalised allocator would assign this build: sigma_target = ",
          sprintf("%.4f", sigma_used_vals[1]),
          " divided by each strategy's own vol-per-unit-gross, capped at a PROVISIONAL gross-exposure ",
          "backstop of ", sprintf("%.1f", backstop_used_vals[1]),
          "x (issue #626 decision D1 — this LEVEL is not yet finalized; override with HD_LEVERAGE_GROSS_BACKSTOP). ",
          "The backstop binds for ", n_binds, " strateg", .lc_plural_y(n_binds), " (", n_gross_target,
          " strategies have a measurable target)."),
        .lc_p(
          if (n_blocked_s31 > 0) {
            paste0(
              n_blocked_s31, " strategy row(s) show a BLOCKED badge — QA gate S31 (R/plan_qa_gates.R) forbids ",
              "actually granting more than 1.0x gross to a detection-underpowered or unverified strategy ",
              "(detection-power-required.md); the figure displayed is the allocator's raw, unblocked output, ",
              "shown for transparency only.")
          } else "No strategy is currently blocked by the detection-power gate (S31).")
      ),
      code_link("compute_allocator_gross()", "R/plan_leverage.R"), issue(626))
  }

  li$cost <- .lc_li(
    "Cost (bps)", paste0("strategy's own cost assumption, ", cost_bps_range, "; * marks a verified zero."),
    .lc_html(
      .lc_p(
        "Per-strategy transaction-cost assumptions (recorded in ",
        code_link("strategy_cost_convention", "R/plan_cost_convention.R", "#L44"),
        ") are not uniform across this table, in both magnitude (", cost_bps_range,
        ") and unit: most rows charge a per-trade bps figure on realised turnover, but Value (HML) and ",
        "Managed Futures charge a flat per-calendar-month bps figure regardless of turnover, and ",
        "TOM/Risk State charge only on discrete switch days — see cost_convention in the registry ",
        "for each row's exact timing."),
      if (n_zero_cost > 0) .lc_p(
        "A trailing * on the Cost (bps) column (", paste(zero_cost_strategies, collapse = ", "),
        ") marks a verified zero — no transaction-cost deduction exists in that strategy's code, ",
        "not a plausible default; it is not net-of-cost comparable to the cost-charging rows above and below it."),
      if (n_na_cost > 0) .lc_p(
        n_na_cost, " strategy row(s) show — for Cost (bps): a meta-portfolio blend inherits its ",
        "constituents' already-net returns with no separate cost applied at the blend level."),
      .lc_p(
        "This Cost (bps) column is the strategy's own internal assumption baked into its returns before ",
        "they reach this table; for the ", n_net_covered,
        " strategies with a Net CAGR value above, it is additional to — not the same as — ",
        "the flat cost applied there.")
    ),
    code_link("strategy_cost_convention", "R/plan_cost_convention.R", "#L44"), issue(624))

  corr_link <- code_link("plan_strategy_correlation.R", "R/plan_strategy_correlation.R", "#L31")
  li$redundant <- .lc_li(
    "Redundant", paste0("YES when highly correlated with a higher-Sharpe strategy (", n_redundant, " of ", N, ")."),
    .lc_html(
      .lc_p(
        "Redundant = \"YES\" when a strategy's Full-Period monthly-return correlation with another, ",
        "higher-Sharpe strategy exceeds the threshold fixed in ", corr_link,
        " (", n_redundant, " of ", N, " strategies currently flagged); “not computed” (",
        n_redundant_na, " strateg", .lc_plural_y(n_redundant_na), ") marks a strategy outside the ",
        corr_covered_n, "-strategy correlation universe that plan_strategy_correlation.R currently covers",
        if (length(corr_excluded_strats) > 0L) {
          paste0(" (excluded: ", paste(corr_excluded_strats, collapse = ", "), ")")
        } else "",
        " — that is unassessed, not assessed-and-passed.")
    ), corr_link, issue(496))

  li$incremental <- .lc_li(
    "Incremental Sharpe", "change in equal-weight-portfolio Sharpe from including this strategy.",
    .lc_html(
      .lc_p(
        "Incremental Sharpe = the change in equal-weight-portfolio Sharpe from including this strategy vs ",
        "excluding it — positive means it adds diversification value, negative means the portfolio is ",
        "better off without it; it shares the same “not computed” scope as Redundant (both come from ",
        "the same join). Both feed the new-strategy value gate (#496).")
    ), corr_link, issue(496))

  li$detection <- .lc_li(
    "Detection", "3-state verdict: can this sample distinguish its Sharpe from zero?",
    .lc_html(
      .lc_p(
        "Detection = 3-state verdict from ", htmltools::tags$code("hd_detection_power()"), " (",
        htmltools::tags$code("detection-power-required"), " rule): whether this row's own sample has ",
        "enough data to distinguish its Sharpe from zero at alpha=0.05 one-sided, 80% power. A strategy ",
        "that passes the single test but fails once corrected for testing ", kraw, " strategies (K_eff = ",
        keff, ") is marked distinctly (◆ “fails MT-correction”), not rendered identically ",
        "to one that clears both bars — see #726.")
    ), issue(726))

  li$rigour <- .lc_li(
    "Rigour", "coverage of deflated Sharpe, DSR p-value and K_eff.",
    .lc_html(
      .lc_p(
        "Rigour = coverage of deflated Sharpe / DSR p-value / K_eff (hover for the three numeric values); ",
        "○ excluded marks a documented exclusion from ", htmltools::tags$code("DEFLATED_SHARPE_EXEMPTIONS"),
        " (R/plan_qa_gates.R), not a gap — see #728.")
    ), qa, issue(728))

  if (isTRUE(has_sharpe_ci)) {
    li$sharpe_ci <- .lc_li(
      "Sharpe CI", paste0("⚠ marks ", n_ci_crosses_zero, " of ", N, " whose 90% CI spans zero."),
      .lc_html(
        .lc_p(
          "Sharpe is shown as point [90% block-bootstrap CI lo, hi] (1000 draws, 3-month blocks — ",
          "R/plan_bootstrap_ci.R); ⚠ marks the ", n_ci_crosses_zero, " of ", N,
          " strateg", .lc_plural_y(n_ci_crosses_zero),
          " whose CI spans zero — a positive point estimate there is not evidence the true ",
          "Sharpe differs from zero (see Robustness > Bootstrap CI below for CAGR/Max DD CIs too).")
      ), code_link("plan_bootstrap_ci.R", "R/plan_bootstrap_ci.R"), issue(585))
  }

  list(short = short, details = htmltools::tags$ul(unname(li)))
}
