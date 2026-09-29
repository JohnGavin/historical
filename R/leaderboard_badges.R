# Short-label + hover/focus pop-up badge builders for docs/leaderboard.qmd's
# Rankings table Detection and P(SR>0) columns (#726, #851, #927).
#
# Ported from the owner-approved #927 Phase-0 prototype
# (explorations/prob_sharpe_prototype/prototype.qmd, revision 2,
# `.claude/rules/dashboard-output-first.md` Step 4) -- same short-label
# vocabulary, same pop-up mechanism (a CSS `:hover`/`:focus`/`:focus-within`
# popover, NOT the native HTML `title=` attribute -- per the accessibility
# rule's "Do not rely on the native HTML title attribute" clause), same
# "operative number" design choice. Generalised here for same-page anchors:
# this file is sourced INSIDE docs/leaderboard.qmd itself (not a standalone
# explorations/ prototype rendered in isolation), so the Biases and Caveats
# link is a bare `#biases-and-caveats` fragment, not a relative
# `../../docs/leaderboard.html#...` path.
#
# Extracted into this sourced file -- the SAME pattern docs/leaderboard.qmd
# already uses for plan_qa_gates.R's DEFLATED_SHARPE_EXEMPTIONS (its Rigour
# column's own source of truth) -- so the badge-verdict logic is
# unit-testable (testthat snapshot tests, one per state, at
# tests/testthat/test-leaderboard-badges.R) rather than living only inside a
# chunk that Quarto renders. docs/leaderboard.qmd sources this file the same
# conditional-path way it sources R/plan_qa_gates.R/R/disclosures.R/
# R/plan_partitions.R, and calls detection_badge()/psr_badge() exactly as it
# previously called its own inline detection_badge().

# ── Strategy -> its own dashboard page, ONLY where one genuinely exists ────
# Verified by grepping docs/*.qmd for each strategy's OWN heading (never
# guessed from filenames) -- e.g. "Risk State" and "Macro Defense Rotation"
# are NOT the same strategy despite both being VIX-related (a grep for
# "Risk State" in docs/macro-defense-rotation.qmd returns zero matches), so
# Risk State deliberately has NO entry here rather than a wrong link.
# Anchors confirmed against docs/stock-backtest.qmd headings (`# Stock MAX`,
# `# Stock DRIF`, `# XGBoost DRIF`, `# Factor-Level Deep Dive
# {#factor-level-deep-dive}`) and docs/avoid-worst-days.qmd /
# docs/momentum-prepeak.qmd's own page-level titles.
HD_STRATEGY_DASHBOARD_HREF <- list(
  "Avoid Worst"   = "avoid-worst-days.html",
  "Factor DRIF"   = "stock-backtest.html#factor-level-deep-dive",
  "Factor MAX"    = "stock-backtest.html#factor-level-deep-dive",
  "Stock MAX"     = "stock-backtest.html#stock-max",
  "Stock DRIF"    = "stock-backtest.html#stock-drif",
  "XGB DRIF"      = "stock-backtest.html#xgboost-drif",
  "Mom Pre-Peak"  = "momentum-prepeak.html",
  "Mom Post-Peak" = "momentum-prepeak.html",
  "Mom 12-2"      = "momentum-prepeak.html"
)

.hd_pop_issue_link <- function(n) {
  sprintf(
    "<a href='https://github.com/JohnGavin/historical/issues/%s' target='_blank' rel='noopener'>#%s</a>",
    n, n
  )
}

#' Build the drilldown-links line shown in every pop-up body
#'
#' Always links back to the Biases and Caveats section (same-page anchor,
#' `#biases-and-caveats`), then the strategy's own dashboard page where one
#' genuinely exists (`HD_STRATEGY_DASHBOARD_HREF`), then the explaining
#' GitHub issue(s).
#'
#' @param strategy Strategy display name (`leaderboard$strategy`).
#' @param issue_nums Integer vector of GitHub issue numbers to cite.
#' @return A single HTML string, `&middot;`-joined.
#' @noRd
hd_pop_links <- function(strategy, issue_nums) {
  parts <- "<a href='#biases-and-caveats'>Detection &amp; Rigour caveats &#8599;</a>"
  href <- HD_STRATEGY_DASHBOARD_HREF[[strategy]]
  if (!is.null(href)) {
    parts <- c(parts, sprintf(
      "<a href='%s' target='_blank' rel='noopener'>%s dashboard &#8599;</a>", href, strategy
    ))
  }
  parts <- c(parts, vapply(issue_nums, .hd_pop_issue_link, character(1)))
  paste(parts, collapse = " &middot; ")
}

#' The SHORT badge + hover/focus pop-up shell
#'
#' Accessibility rule: no native `title=`. `tabindex='0'` makes the wrapper
#' keyboard-focusable so `:focus`/`:focus-within` (see the `<style>` block in
#' docs/leaderboard.qmd) reveal the pop-up without a mouse, the same content
#' a mouse hover shows.
#'
#' @param family Badge family class (`det-badge` / `psr-badge`).
#' @param state State class (e.g. `detectable`, `mtfail`, `underpowered`,
#'   `napp`, `notcomputed`; or `sufficient`/`insufficient` for P(SR>0)).
#' @param short Short label HTML (icon + compact number, kept BOTH on the
#'   short span so the colour-mapping CSS keeps working unchanged).
#' @param body_html Full pop-up body HTML.
#' @param aria `aria-label` text for the wrapper.
#' @return A single HTML string.
#' @noRd
hd_pop_wrap <- function(family, state, short, body_html, aria) {
  sprintf(
    "<span class='pop-wrap %s %s' tabindex='0' aria-label='%s'><span class='pop-short'>%s</span><span class='pop-body'>%s</span></span>",
    family, state, aria, short, body_html
  )
}

.hd_fmt_yr    <- function(x) if (is.na(x)) "?" else sprintf("%.0f", x)
.hd_fmt_yr1   <- function(x) if (is.na(x)) "?" else sprintf("%.1f", x)
.hd_fmt_keff  <- function(x) if (is.na(x)) "n/a" else sprintf("%.1f", x)
.hd_fmt_pct   <- function(x) if (is.na(x)) "?" else sprintf("%.1f%%", x * 100)

HD_DET_MEANING <- paste0(
  "<span class='pop-meaning'>Detection asks: is the sample long enough to ",
  "reliably detect this Sharpe if it is real? (prospective power test, ",
  "one-sided, &alpha;=0.05)</span>"
)
HD_PSR_MEANING <- paste0(
  "<span class='pop-meaning'>P(SR&gt;0) asks: given what we observed, how ",
  "confident are we the TRUE Sharpe is positive? (retrospective confidence, ",
  "Bailey &amp; Lopez de Prado)</span>"
)

#' Years-available prose for the Detection pop-up
#'
#' `avail` (`leaderboard$years`) should always be non-NA now that
#' R/plan_leaderboard.R derives `years` centrally from
#' `months / obs_ann_factor` and QA gate S43
#' (`check_leaderboard_years_available()`, R/plan_qa_gates.R) asserts it for
#' every positive-Sharpe row -- the NA branch is kept as a defensive
#' fallback only (`fail-loud-not-null.md`), not the expected path.
#'
#' @param avail Years available (`leaderboard$years`), may be `NA`.
#' @return HTML string.
#' @noRd
hd_avail_phrase <- function(avail) {
  if (is.na(avail)) {
    "years available not recorded for this strategy in the leaderboard target (data gap -- see #726)"
  } else {
    sprintf("<b>%s yr</b> available", .hd_fmt_yr1(avail))
  }
}

#' Detection badge: short label + hover/focus pop-up (#726, #903, #927)
#'
#' Mirrors `historicaldata::hd_detection_power()`'s 5-state verdict shape.
#' The SECOND number in the short label is always the "years needed" figure
#' OPERATIVE for that row's final verdict -- the single-test figure for
#' every state except `mtfail`, where the MT-corrected figure is shown
#' instead (that is the number that actually fails). This keeps the
#' available/needed comparison always readable as "pass" (available >=
#' needed shown) or "fail" (available < needed shown), regardless of which
#' test produced the verdict.
#'
#' @param strategy Strategy display name.
#' @param sr `leaderboard$sharpe`.
#' @param avail `leaderboard$years` (years of data available).
#' @param under `leaderboard$detection_underpowered`.
#' @param dmin `leaderboard$detection_min_n_years`.
#' @param under_mt `leaderboard$detection_underpowered_mt`.
#' @param dmin_mt `leaderboard$detection_min_n_years_mt`.
#' @param keff `leaderboard$k_eff_leaderboard`.
#' @return `list(rank = <int>, html = <string>)`.
#' @noRd
detection_badge <- function(strategy, sr, avail, under, dmin, under_mt, dmin_mt, keff) {
  links <- hd_pop_links(strategy, c(726, 903))

  if (is.na(sr) || sr <= 0) {
    body <- paste0(
      "<strong>&ndash; Not applicable</strong><br>",
      "Sharpe &le; 0: the one-sided detection test has no positive effect to test for. Not applicable &mdash; not the same as unproven.<br>",
      HD_DET_MEANING, "<br>",
      "<span class='pop-links'>", links, "</span>"
    )
    return(list(rank = 4L, html = hd_pop_wrap(
      "det-badge", "napp", "&ndash; n/a", body,
      "Detection: not applicable, Sharpe is not positive"
    )))
  }

  if (is.na(under)) {
    body <- paste0(
      "<strong>&#10007; NOT COMPUTED</strong><br>",
      "Positive Sharpe with NO detection verdict &mdash; this should never render live (QA gate S20, #726 item 3, is meant to block the build until it is fixed).<br>",
      HD_DET_MEANING, "<br>",
      "<span class='pop-links'>", links, "</span>"
    )
    return(list(rank = 5L, html = hd_pop_wrap(
      "det-badge", "notcomputed", "&#10007; ERR", body,
      "Detection: defect, verdict was not computed"
    )))
  }

  if (isTRUE(under)) {
    mt_line <- if (!is.na(under_mt)) {
      "Multiple-testing correction is academic here &mdash; the single test already fails."
    } else {
      "MT-corrected verdict not computed (k_eff unavailable for this strategy)."
    }
    body <- paste0(
      "<strong>&#9888; Underpowered</strong><br>",
      sprintf("Needs <b>%s yr</b> at &alpha;=0.05, one-sided; %s.<br>", .hd_fmt_yr1(dmin), hd_avail_phrase(avail)),
      mt_line, "<br>",
      HD_DET_MEANING, "<br>",
      "<span class='pop-links'>", links, "</span>"
    )
    short <- sprintf("&#9888; %s/%sy", .hd_fmt_yr(avail), .hd_fmt_yr(dmin))
    return(list(rank = 3L, html = hd_pop_wrap(
      "det-badge", "underpowered", short, body,
      sprintf("Detection: underpowered, needs %s years, %s years available", .hd_fmt_yr(dmin), .hd_fmt_yr(avail))
    )))
  }

  if (is.na(under_mt)) {
    body <- paste0(
      "<strong>&#10003; Detectable</strong><br>",
      sprintf("Needs <b>%s yr</b> at &alpha;=0.05, one-sided; %s.<br>", .hd_fmt_yr1(dmin), hd_avail_phrase(avail)),
      "MT-corrected verdict not computed (k_eff unavailable for this strategy).<br>",
      HD_DET_MEANING, "<br>",
      "<span class='pop-links'>", links, "</span>"
    )
    short <- sprintf("&#10003; %s/%sy", .hd_fmt_yr(avail), .hd_fmt_yr(dmin))
    return(list(rank = 1L, html = hd_pop_wrap(
      "det-badge", "detectable", short, body,
      sprintf("Detection: detectable, needs %s years, %s years available", .hd_fmt_yr(dmin), .hd_fmt_yr(avail))
    )))
  }

  if (isTRUE(under_mt)) {
    body <- paste0(
      "<strong>&#9670; Fails MT-correction</strong><br>",
      sprintf(
        "Passes the single test (needs <b>%s yr</b>; %s) but FAILS once corrected for testing multiple strategies (needs <b>%s yr</b> corrected, k_eff=%s).<br>",
        .hd_fmt_yr1(dmin), hd_avail_phrase(avail), .hd_fmt_yr1(dmin_mt), .hd_fmt_keff(keff)
      ),
      HD_DET_MEANING, "<br>",
      "<span class='pop-links'>", links, "</span>"
    )
    short <- sprintf("&#9670; %s/%sy", .hd_fmt_yr(avail), .hd_fmt_yr(dmin_mt))
    return(list(rank = 2L, html = hd_pop_wrap(
      "det-badge", "mtfail", short, body,
      sprintf("Detection: passes single test, fails multiple-testing correction, needs %s years corrected", .hd_fmt_yr(dmin_mt))
    )))
  }

  body <- paste0(
    "<strong>&#10003; Detectable</strong><br>",
    sprintf(
      "Needs <b>%s yr</b> at &alpha;=0.05, one-sided (<b>%s yr</b> corrected for multiple testing, k_eff=%s); %s.<br>",
      .hd_fmt_yr1(dmin), .hd_fmt_yr1(dmin_mt), .hd_fmt_keff(keff), hd_avail_phrase(avail)
    ),
    HD_DET_MEANING, "<br>",
    "<span class='pop-links'>", links, "</span>"
  )
  short <- sprintf("&#10003; %s/%sy", .hd_fmt_yr(avail), .hd_fmt_yr(dmin))
  list(rank = 1L, html = hd_pop_wrap(
    "det-badge", "detectable", short, body,
    "Detection: detectable, passes single test and multiple-testing correction"
  ))
}

#' P(SR>0) badge: short label + hover/focus pop-up (#851, #927)
#'
#' Mirrors `detection_badge()`'s exact 5-state shape and severity-rank
#' convention, applied to `historicaldata::hd_prob_sharpe_positive()`
#' instead of `hd_detection_power()`. Same "operative number" design
#' choice: the short label shows the single-test percentage for every state
#' except `mtfail`, where it shows the MT-corrected percentage (the number
#' that fails).
#'
#' @param strategy Strategy display name.
#' @param sr `leaderboard$sharpe`.
#' @param psr `leaderboard$prob_sharpe_positive`.
#' @param psr_insuff `leaderboard$prob_sharpe_positive_insufficient`.
#' @param psr_mt `leaderboard$prob_sharpe_positive_mt`.
#' @param psr_mt_insuff `leaderboard$prob_sharpe_positive_insufficient_mt`.
#' @param threshold `HD_PROB_SHARPE_POSITIVE_THRESHOLD` (R/plan_leaderboard.R).
#' @param keff `leaderboard$k_eff_leaderboard`.
#' @return `list(rank = <int>, html = <string>)`.
#' @noRd
psr_badge <- function(strategy, sr, psr, psr_insuff, psr_mt, psr_mt_insuff, threshold, keff) {
  links <- hd_pop_links(strategy, 851)

  if (is.na(sr) || sr <= 0) {
    body <- paste0(
      "<strong>&ndash; Not applicable</strong><br>",
      "Sharpe &le; 0: P(true Sharpe &gt; 0) is not a meaningful question when the point estimate itself is non-positive. Not applicable &mdash; not the same as unproven.<br>",
      HD_PSR_MEANING, "<br>",
      "<span class='pop-links'>", links, "</span>"
    )
    return(list(rank = 4L, html = hd_pop_wrap(
      "psr-badge", "napp", "&ndash; n/a", body,
      "P(SR>0): not applicable, Sharpe is not positive"
    )))
  }

  if (is.na(psr)) {
    body <- paste0(
      "<strong>&#10007; NOT COMPUTED</strong><br>",
      "Positive Sharpe with NO P(SR&gt;0) verdict &mdash; this should never render live (QA gate S40, #851, is meant to block the build until it is fixed).<br>",
      HD_PSR_MEANING, "<br>",
      "<span class='pop-links'>", links, "</span>"
    )
    return(list(rank = 5L, html = hd_pop_wrap(
      "psr-badge", "notcomputed", "&#10007; ERR", body,
      "P(SR>0): defect, verdict was not computed"
    )))
  }

  if (isTRUE(psr_insuff)) {
    mt_line <- if (!is.na(psr_mt_insuff)) {
      "Multiple-testing correction is academic here &mdash; the single test already fails."
    } else {
      "MT-corrected verdict not computed (k_eff unavailable for this strategy)."
    }
    body <- paste0(
      "<strong>&#9888; Insufficient</strong><br>",
      sprintf("P(true Sharpe &gt; 0) = <b>%s</b>, below the <b>%s</b> bar.<br>", .hd_fmt_pct(psr), .hd_fmt_pct(threshold)),
      mt_line, "<br>",
      HD_PSR_MEANING, "<br>",
      "<span class='pop-links'>", links, "</span>"
    )
    short <- sprintf("&#9888; %s", .hd_fmt_pct(psr))
    return(list(rank = 3L, html = hd_pop_wrap(
      "psr-badge", "insufficient", short, body,
      sprintf("P(SR>0): insufficient, %s below the %s threshold", .hd_fmt_pct(psr), .hd_fmt_pct(threshold))
    )))
  }

  if (is.na(psr_mt)) {
    body <- paste0(
      "<strong>&#10003; Sufficient</strong><br>",
      sprintf("P(true Sharpe &gt; 0) = <b>%s</b> (single test), at or above the <b>%s</b> bar.<br>", .hd_fmt_pct(psr), .hd_fmt_pct(threshold)),
      "MT-corrected verdict not computed (k_eff unavailable for this strategy).<br>",
      HD_PSR_MEANING, "<br>",
      "<span class='pop-links'>", links, "</span>"
    )
    short <- sprintf("&#10003; %s", .hd_fmt_pct(psr))
    return(list(rank = 1L, html = hd_pop_wrap(
      "psr-badge", "sufficient", short, body,
      sprintf("P(SR>0): sufficient, %s single test", .hd_fmt_pct(psr))
    )))
  }

  if (isTRUE(psr_mt_insuff)) {
    body <- paste0(
      "<strong>&#9670; Fails MT-correction</strong><br>",
      sprintf(
        "Passes the single-test bar (<b>%s</b>) but FAILS once corrected for multiple testing (<b>%s</b>, below the <b>%s</b> bar, k_eff=%s).<br>",
        .hd_fmt_pct(psr), .hd_fmt_pct(psr_mt), .hd_fmt_pct(threshold), .hd_fmt_keff(keff)
      ),
      HD_PSR_MEANING, "<br>",
      "<span class='pop-links'>", links, "</span>"
    )
    short <- sprintf("&#9670; %s", .hd_fmt_pct(psr_mt))
    return(list(rank = 2L, html = hd_pop_wrap(
      "psr-badge", "mtfail", short, body,
      sprintf("P(SR>0): passes single test, fails multiple-testing correction at %s", .hd_fmt_pct(psr_mt))
    )))
  }

  body <- paste0(
    "<strong>&#10003; Sufficient</strong><br>",
    sprintf(
      "P(true Sharpe &gt; 0): <b>%s</b> single-test, <b>%s</b> corrected for multiple testing (k_eff=%s) &mdash; both at or above the <b>%s</b> bar.<br>",
      .hd_fmt_pct(psr), .hd_fmt_pct(psr_mt), .hd_fmt_keff(keff), .hd_fmt_pct(threshold)
    ),
    HD_PSR_MEANING, "<br>",
    "<span class='pop-links'>", links, "</span>"
  )
  short <- sprintf("&#10003; %s", .hd_fmt_pct(psr))
  list(rank = 1L, html = hd_pop_wrap(
    "psr-badge", "sufficient", short, body,
    sprintf("P(SR>0): sufficient, %s single test, %s corrected", .hd_fmt_pct(psr), .hd_fmt_pct(psr_mt))
  ))
}
