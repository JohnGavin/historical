# Strategy Digest — leaderboard delta computation, attention triage, and
# HTML email rendering.  Wire via R/plan_strategy_digest.R.
#
# Architecture:
#   - hd_digest_delta()          — compute per-strategy deltas vs prior snapshot
#   - hd_digest_attention()      — flag STRUCTURAL changes only
#                                  (resulting-prohibition: Sharpe drop alone NOT flagged)
#   - hd_digest_html()           — render HTML body; blastula-guarded, base-HTML fallback
#   - hd_digest_snapshot_write() — persist current leaderboard as parquet baseline
#
# Issue: #482 (Slice 1)
# Related rules: resulting-prohibition, snapshot-test-policy, namespace-discipline

# ── Internal helpers ──────────────────────────────────────────────────────────

.col_num <- function(df, col) {
  if (col %in% names(df)) df[[col]] else rep(NA_real_, nrow(df))
}

.col_lgl <- function(df, col) {
  if (col %in% names(df)) df[[col]] else rep(NA, nrow(df))
}

.col_chr <- function(df, col) {
  if (col %in% names(df)) df[[col]] else rep(NA_character_, nrow(df))
}

# Filter to Full Period rows; if 'period' column absent, keep all rows.
.full_period <- function(df) {
  if (is.null(df)) return(df)
  if ("period" %in% names(df)) df[!is.na(df$period) & df$period == "Full Period", ]
  else df
}

# Minimal HTML-safe escaping for user-controlled strings placed in HTML text.
.html_esc <- function(x) {
  x <- gsub("&",  "&amp;",  x, fixed = TRUE)
  x <- gsub("<",  "&lt;",   x, fixed = TRUE)
  x <- gsub(">",  "&gt;",   x, fixed = TRUE)
  x <- gsub("\"", "&quot;", x, fixed = TRUE)
  x
}

# ── 1. hd_digest_delta ───────────────────────────────────────────────────────

#' Compute leaderboard deltas between the current run and a prior snapshot
#'
#' Joins the live \code{leaderboard} target (CURRENT) against a persisted
#' snapshot (PRIOR) on the \code{strategy} column, restricted to
#' \code{period == "Full Period"} rows where structural flags are meaningful.
#' Returns one row per strategy with numeric deltas and boolean change flags.
#'
#' @section Resulting-prohibition framing:
#' Sharpe and CAGR deltas are computed as \emph{information only} — they are
#' never automatically flagged as problems.  Only structural signals
#' (redundancy, crowding, WFC verdict, CI crossing zero, DSR significance loss)
#' are candidates for the "needs attention" workflow implemented in
#' \code{\link{hd_digest_attention}}.  See the \code{resulting-prohibition}
#' project rule.
#'
#' @section Baseline run (\code{prior = NULL}):
#' When no prior snapshot exists all strategies receive \code{status = "new"}
#' and all delta/flag columns are set to \code{NA} or \code{FALSE}.  This is
#' the expected first-run behaviour after bootstrapping the snapshot file.
#'
#' @section Missing columns:
#' Columns absent from either \code{current} or \code{prior} are tolerated:
#' numeric columns default to \code{NA_real_}, logical columns to \code{NA},
#' and character columns to \code{NA_character_}.  Flag computations that
#' require a column produce \code{FALSE} when that column is absent.
#'
#' @param current A data frame — the live \code{leaderboard} target.  Must
#'   contain at minimum a \code{strategy} character column.
#' @param prior A data frame (prior leaderboard snapshot) or \code{NULL}.
#'   When \code{NULL} all strategies are treated as new (baseline run).
#'
#' @return A \link[tibble]{tibble} with one row per strategy and columns:
#'   \describe{
#'     \item{strategy}{Character. Strategy name (join key).}
#'     \item{status}{Character. One of \code{"new"} (in current, absent from
#'       prior), \code{"changed"} (structural flag fired), \code{"unchanged"},
#'       or \code{"dropped"} (in prior, absent from current).}
#'     \item{sharpe_prev, sharpe_now, d_sharpe}{Numeric. Sharpe ratio deltas.}
#'     \item{net_cagr_prev, net_cagr_now, d_net_cagr}{Numeric. Net-CAGR
#'       (after costs) deltas.}
#'     \item{max_dd_prev, max_dd_now, d_max_dd}{Numeric. Max-drawdown deltas
#'       (positive = drawdown deepened).}
#'     \item{became_redundant}{Logical. \code{TRUE} when \code{redundant}
#'       flipped from non-TRUE to \code{TRUE}.}
#'     \item{became_crowded}{Logical. \code{TRUE} when \code{add_flag}
#'       flipped from non-TRUE to \code{TRUE}.}
#'     \item{wfc_verdict_changed}{Logical. \code{TRUE} when
#'       \code{wfc_verdict} changed between runs.}
#'     \item{wfc_verdict_from, wfc_verdict_to}{Character. Previous/current
#'       verdict values; \code{NA} when unchanged.}
#'     \item{ci_now_crosses_zero}{Logical. \code{TRUE} when
#'       \code{ci_crosses_zero} flipped from non-TRUE to \code{TRUE}.}
#'     \item{dsr_sig_flip}{Logical. \code{TRUE} when \code{dsr_pvalue} was
#'       below 0.05 in the prior run and is \eqn{\geq} 0.05 now (significance
#'       lost).}
#'   }
#'
#' @family digest
#' @export
#'
#' @examples
#' cur <- tibble::tibble(
#'   strategy        = c("Factor MAX", "Factor DRIF"),
#'   period          = c("Full Period", "Full Period"),
#'   sharpe          = c(1.2, 0.9),
#'   net_cagr        = c(0.12, 0.08),
#'   max_dd          = c(-0.15, -0.20),
#'   redundant       = c(FALSE, FALSE),
#'   add_flag        = c(FALSE, FALSE),
#'   wfc_verdict     = c("structural_edge", "noise"),
#'   ci_crosses_zero = c(FALSE, TRUE),
#'   dsr_pvalue      = c(0.03, 0.08)
#' )
#' delta <- hd_digest_delta(cur, prior = NULL)
#' delta$status  # "new" for all (baseline run)
hd_digest_delta <- function(current, prior) {
  if (!is.data.frame(current)) {
    cli::cli_abort(c(
      "x" = "{.arg current} must be a data frame.",
      "i" = "Got {.cls {class(current)}}."
    ))
  }
  if (!is.null(prior) && !is.data.frame(prior)) {
    cli::cli_abort(c(
      "x" = "{.arg prior} must be a data frame or NULL.",
      "i" = "Got {.cls {class(prior)}}."
    ))
  }
  if (!"strategy" %in% names(current)) {
    cli::cli_abort(c(
      "x" = "{.arg current} must contain a {.col strategy} column."
    ))
  }

  cur <- .full_period(current)

  # ── Baseline run (prior = NULL) ───────────────────────────────────────────
  if (is.null(prior)) {
    return(tibble::tibble(
      strategy            = .col_chr(cur, "strategy"),
      status              = "new",
      sharpe_prev         = NA_real_,
      sharpe_now          = .col_num(cur, "sharpe"),
      d_sharpe            = NA_real_,
      net_cagr_prev       = NA_real_,
      net_cagr_now        = .col_num(cur, "net_cagr"),
      d_net_cagr          = NA_real_,
      max_dd_prev         = NA_real_,
      max_dd_now          = .col_num(cur, "max_dd"),
      d_max_dd            = NA_real_,
      became_redundant    = FALSE,
      became_crowded      = FALSE,
      wfc_verdict_changed = FALSE,
      wfc_verdict_from    = NA_character_,
      wfc_verdict_to      = NA_character_,
      ci_now_crosses_zero = FALSE,
      dsr_sig_flip        = FALSE
    ))
  }

  # ── Incremental run: diff current vs prior ────────────────────────────────
  pri <- .full_period(prior)

  strats_cur <- .col_chr(cur, "strategy")
  strats_pri <- .col_chr(pri, "strategy")
  all_strats <- union(strats_cur, strats_pri)

  out_rows <- lapply(all_strats, function(s) {
    c_row <- cur[!is.na(strats_cur) & strats_cur == s, ]
    p_row <- pri[!is.na(strats_pri) & strats_pri == s, ]

    # is_new  = TRUE → strategy absent from current run (was in prior, now dropped)
    # is_gone = TRUE → strategy absent from prior (new in this current run)
    is_new  <- nrow(c_row) == 0L
    is_gone <- nrow(p_row) == 0L

    # Scalar extractors (first row; NA when col absent or row absent)
    cn <- function(col) {
      if (!is_new && col %in% names(c_row)) c_row[[col]][1L] else NA_real_
    }
    pn <- function(col) {
      if (!is_gone && col %in% names(p_row)) p_row[[col]][1L] else NA_real_
    }
    cl <- function(col) {
      if (!is_new && col %in% names(c_row)) c_row[[col]][1L] else NA
    }
    pl <- function(col) {
      if (!is_gone && col %in% names(p_row)) p_row[[col]][1L] else NA
    }
    cc <- function(col) {
      if (!is_new && col %in% names(c_row)) as.character(c_row[[col]][1L]) else NA_character_
    }
    pc <- function(col) {
      if (!is_gone && col %in% names(p_row)) as.character(p_row[[col]][1L]) else NA_character_
    }

    sharpe_now  <- cn("sharpe")
    sharpe_prev <- pn("sharpe")
    net_cagr_now  <- cn("net_cagr")
    net_cagr_prev <- pn("net_cagr")
    max_dd_now  <- cn("max_dd")
    max_dd_prev <- pn("max_dd")

    # ── Boolean structural flags ─────────────────────────────────────────────
    # became_redundant: was NOT TRUE, is now TRUE
    became_redundant <- isTRUE(cl("redundant")) && !isTRUE(pl("redundant"))

    # became_crowded: add_flag was NOT TRUE, is now TRUE
    became_crowded <- isTRUE(cl("add_flag")) && !isTRUE(pl("add_flag"))

    # wfc_verdict changed (both non-NA and different)
    wfc_cur <- cc("wfc_verdict")
    wfc_pri <- pc("wfc_verdict")
    wfc_verdict_changed <- !is.na(wfc_cur) && !is.na(wfc_pri) && wfc_cur != wfc_pri
    wfc_verdict_from <- if (wfc_verdict_changed) wfc_pri else NA_character_
    wfc_verdict_to   <- if (wfc_verdict_changed) wfc_cur else NA_character_

    # ci_now_crosses_zero: FALSE/NA → TRUE
    ci_now_crosses_zero <- isTRUE(cl("ci_crosses_zero")) && !isTRUE(pl("ci_crosses_zero"))

    # dsr_sig_flip: was < 0.05 (significant), now >= 0.05 (significance lost)
    dsr_cur <- cn("dsr_pvalue")
    dsr_pri <- pn("dsr_pvalue")
    dsr_sig_flip <- !is.na(dsr_pri) && !is.na(dsr_cur) &&
      dsr_pri < 0.05 && dsr_cur >= 0.05

    # ── Status ────────────────────────────────────────────────────────────────
    any_structural_change <- became_redundant || became_crowded ||
      wfc_verdict_changed || ci_now_crosses_zero || dsr_sig_flip

    # is_gone = not in prior → "new" this run.
    # is_new  = not in current → "dropped" from prior (kept in output for visibility).
    status <- if (is_gone) "new" else if (is_new) "dropped" else if (any_structural_change) "changed" else "unchanged"

    tibble::tibble(
      strategy            = s,
      status              = status,
      sharpe_prev         = sharpe_prev,
      sharpe_now          = sharpe_now,
      d_sharpe            = sharpe_now - sharpe_prev,
      net_cagr_prev       = net_cagr_prev,
      net_cagr_now        = net_cagr_now,
      d_net_cagr          = net_cagr_now - net_cagr_prev,
      max_dd_prev         = max_dd_prev,
      max_dd_now          = max_dd_now,
      d_max_dd            = max_dd_now - max_dd_prev,
      became_redundant    = became_redundant,
      became_crowded      = became_crowded,
      wfc_verdict_changed = wfc_verdict_changed,
      wfc_verdict_from    = wfc_verdict_from,
      wfc_verdict_to      = wfc_verdict_to,
      ci_now_crosses_zero = ci_now_crosses_zero,
      dsr_sig_flip        = dsr_sig_flip
    )
  })

  dplyr::bind_rows(out_rows)
}

# ── 2. hd_digest_attention ───────────────────────────────────────────────────

#' Identify strategies requiring structural attention from a digest delta
#'
#' Returns a character vector of human-readable attention lines.  Only
#' STRUCTURAL flag changes are reported; a pure Sharpe or CAGR decline is not
#' flagged.  This implements the \code{resulting-prohibition} project rule:
#' outcome-driven signals without new structural evidence are information, not
#' action items.
#'
#' @section Flagged conditions:
#' \enumerate{
#'   \item Strategy newly \strong{redundant} (\code{became_redundant = TRUE}).
#'   \item Strategy newly flagged for \strong{ADD crowding}
#'     (\code{became_crowded = TRUE}).
#'   \item \code{wfc_verdict} changed \strong{to}
#'     \code{"consistently_loss_making"}.
#'   \item Sharpe bootstrap CI \strong{now crosses zero}
#'     (\code{ci_now_crosses_zero = TRUE}).
#'   \item \strong{DSR significance lost} — \code{dsr_pvalue} crossed 0.05
#'     from below (\code{dsr_sig_flip = TRUE}).
#' }
#'
#' @section Not flagged:
#' Sharpe drop, CAGR decline, or max-drawdown increase alone are NOT flagged.
#' Surface them in the narrative caption as information, not as problems.
#'
#' @param delta A tibble as returned by \code{\link{hd_digest_delta}}.
#'
#' @return A character vector of attention lines, empty when nothing is
#'   flagged.  Each line is formatted as \code{"[STRATEGY]: <reason>"}.
#'
#' @family digest
#' @export
#'
#' @examples
#' delta <- tibble::tibble(
#'   strategy            = c("Factor MAX", "Factor DRIF"),
#'   status              = c("changed", "unchanged"),
#'   d_sharpe            = c(-0.3, 0.0),    # drop: NOT flagged
#'   became_redundant    = c(FALSE, FALSE),
#'   became_crowded      = c(TRUE,  FALSE),
#'   wfc_verdict_changed = c(FALSE, FALSE),
#'   wfc_verdict_from    = c(NA_character_, NA_character_),
#'   wfc_verdict_to      = c(NA_character_, NA_character_),
#'   ci_now_crosses_zero = c(FALSE, FALSE),
#'   dsr_sig_flip        = c(FALSE, FALSE)
#' )
#' hd_digest_attention(delta)
#' # "[Factor MAX]: newly flagged for ADD crowding (anomaly-driven demand)"
hd_digest_attention <- function(delta) {
  if (!is.data.frame(delta)) {
    cli::cli_abort(c(
      "x" = "{.arg delta} must be a data frame.",
      "i" = "Got {.cls {class(delta)}}."
    ))
  }
  if (!"strategy" %in% names(delta)) {
    cli::cli_abort(c(
      "x" = "{.arg delta} must contain a {.col strategy} column."
    ))
  }

  lines <- character(0L)

  strats   <- .col_chr(delta, "strategy")
  red      <- .col_lgl(delta, "became_redundant")
  crowd    <- .col_lgl(delta, "became_crowded")
  wfc_chg  <- .col_lgl(delta, "wfc_verdict_changed")
  wfc_to   <- .col_chr(delta, "wfc_verdict_to")
  wfc_from <- .col_chr(delta, "wfc_verdict_from")
  ci_cross <- .col_lgl(delta, "ci_now_crosses_zero")
  dsr_flip <- .col_lgl(delta, "dsr_sig_flip")

  for (i in seq_len(nrow(delta))) {
    s <- strats[i]

    if (isTRUE(red[i])) {
      lines <- c(lines, sprintf("[%s]: newly classified as redundant", s))
    }

    if (isTRUE(crowd[i])) {
      lines <- c(lines, sprintf(
        "[%s]: newly flagged for ADD crowding (anomaly-driven demand)", s))
    }

    if (isTRUE(wfc_chg[i]) && !is.na(wfc_to[i]) &&
        wfc_to[i] == "consistently_loss_making") {
      from_str <- if (!is.na(wfc_from[i])) sprintf(" (was: %s)", wfc_from[i]) else ""
      lines <- c(lines, sprintf(
        "[%s]: wfc_verdict changed to consistently_loss_making%s", s, from_str))
    }

    if (isTRUE(ci_cross[i])) {
      lines <- c(lines, sprintf(
        "[%s]: Sharpe bootstrap CI now crosses zero", s))
    }

    if (isTRUE(dsr_flip[i])) {
      lines <- c(lines, sprintf(
        "[%s]: deflated-Sharpe significance lost (dsr_pvalue crossed 0.05)", s))
    }
    # NOTE: Sharpe / CAGR / max-DD movements are NOT flagged.
    # Per resulting-prohibition: outcome deltas alone are information only;
    # they do not constitute structural evidence for strategy revision.
  }

  lines
}

# ── 3. hd_digest_html ────────────────────────────────────────────────────────

# Internal: build a self-contained HTML document from digest components.
# Called by hd_digest_html(); also used directly in unit tests.
.build_digest_body_html <- function(delta, attention, caption) {
  n_changed <- sum(delta$status == "changed",   na.rm = TRUE)
  n_new     <- sum(delta$status == "new",       na.rm = TRUE)
  n_total   <- nrow(delta)
  n_attn    <- length(attention)

  # ── Attention section ──────────────────────────────────────────────────────
  attn_html <- if (n_attn == 0L) {
    "<p><em>No structural flags this run.</em></p>"
  } else {
    items <- paste0("<li>", .html_esc(attention), "</li>", collapse = "\n")
    paste0('<ul class="attention">\n', items, "\n</ul>")
  }

  # ── Delta table ────────────────────────────────────────────────────────────
  fmt_pct <- function(x) ifelse(is.na(x), "&mdash;", sprintf("%+.1f%%", x * 100))
  fmt_num <- function(x, d = 2L) ifelse(is.na(x), "&mdash;", sprintf("%+.*f", d, x))
  flag    <- function(x) ifelse(is.na(x) | !x, "", "&#10004;")

  make_row <- function(i) {
    r    <- delta[i, ]
    st   <- r[["status"]]
    rcls <- switch(st, changed = ' class="changed"', new = ' class="new"', "")
    paste0(
      "<tr", rcls, ">",
      "<td>", .html_esc(r[["strategy"]]), "</td>",
      "<td>", .html_esc(st), "</td>",
      "<td>", fmt_num(r[["d_sharpe"]]), "</td>",
      "<td>", fmt_pct(r[["d_net_cagr"]]), "</td>",
      "<td>", fmt_pct(r[["d_max_dd"]]), "</td>",
      "<td>", flag(r[["became_redundant"]]), "</td>",
      "<td>", flag(r[["became_crowded"]]), "</td>",
      "<td>", flag(r[["wfc_verdict_changed"]]), "</td>",
      "<td>", flag(r[["ci_now_crosses_zero"]]), "</td>",
      "<td>", flag(r[["dsr_sig_flip"]]), "</td>",
      "</tr>"
    )
  }

  rows_html   <- paste0(vapply(seq_len(nrow(delta)), make_row, character(1L)),
                        collapse = "\n")
  table_html  <- paste0(
    '<table class="digest-table">\n',
    "<thead><tr>",
    "<th>Strategy</th><th>Status</th>",
    "<th>&Delta; Sharpe</th><th>&Delta; Net CAGR</th><th>&Delta; Max DD</th>",
    "<th>Redundant?</th><th>Crowded?</th><th>WFC&Delta;?</th>",
    "<th>CI&rarr;0?</th><th>DSR flip?</th>",
    "</tr></thead>\n",
    "<tbody>\n", rows_html, "\n</tbody>\n</table>"
  )

  css <- paste0(
    "<style>\n",
    "body{font-family:sans-serif;max-width:960px;margin:1rem auto;",
    "color:#1a1a1a;background:#fff}\n",
    "table.digest-table{border-collapse:collapse;width:100%;font-size:.875rem}\n",
    "table.digest-table th,table.digest-table td{border:1px solid #ccc;",
    "padding:4px 8px;text-align:left}\n",
    "table.digest-table thead{background:#f5f5f5}\n",
    "tr.changed td{background:#fff8e1}\n",
    "tr.new td{background:#e8f5e9}\n",
    "ul.attention{color:#c0392b}\n",
    "</style>\n"
  )

  paste0(
    "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n",
    "<meta charset=\"utf-8\">\n",
    "<meta name=\"color-scheme\" content=\"light\">\n",
    "<title>Strategy Digest</title>\n",
    css,
    "</head>\n<body>\n",
    "<h1>Strategy Digest</h1>\n",
    "<p>", .html_esc(caption), "</p>\n",
    "<h2>Needs Attention (", n_attn, " item",
    if (n_attn != 1L) "s" else "", ")</h2>\n",
    attn_html, "\n",
    "<h2>Delta Summary</h2>\n",
    "<p><strong>", n_total, "</strong> strategies &mdash; ",
    "<strong>", n_new, "</strong> new &mdash; ",
    "<strong>", n_changed, "</strong> structurally changed.</p>\n",
    table_html, "\n",
    "</body>\n</html>"
  )
}

#' Render a strategy digest as a self-contained HTML string
#'
#' Builds a self-contained HTML document suitable for saving as
#' \code{docs/digest-preview.html} or attaching to an email.
#'
#' @section blastula integration (Slice 2):
#' \pkg{blastula} is listed in \code{Suggests} and guarded with
#' \code{requireNamespace("blastula", quietly = TRUE)}.  In Slice 1 the
#' guard is a no-op: the function returns the plain self-contained HTML
#' document produced by \code{.build_digest_body_html()}.  Slice 2 (#482)
#' will wrap the content in \code{blastula::compose_email()} for proper
#' email-client CSS and MIME envelope when SMTP is configured.  No
#' \code{cli_warn()} is emitted in Slice 1 because no fallback is needed.
#'
#' @param delta A tibble as returned by \code{\link{hd_digest_delta}}.
#' @param attention A character vector as returned by
#'   \code{\link{hd_digest_attention}}.
#' @param caption A length-1 character string.  Dynamic narrative caption;
#'   see \code{strategy_digest_caption} target in
#'   \code{R/plan_strategy_digest.R}.
#'
#' @return A length-1 character string containing a complete HTML document.
#'
#' @family digest
#' @export
#'
#' @examples
#' delta  <- hd_digest_delta(
#'   tibble::tibble(
#'     strategy = "Factor MAX", period = "Full Period",
#'     sharpe = 1.1, net_cagr = 0.10, max_dd = -0.15
#'   ),
#'   prior = NULL
#' )
#' attn   <- hd_digest_attention(delta)
#' html   <- hd_digest_html(delta, attn, caption = "Baseline run.")
#' nzchar(html)   # TRUE
hd_digest_html <- function(delta, attention, caption) {
  if (!is.data.frame(delta)) {
    cli::cli_abort(c(
      "x" = "{.arg delta} must be a data frame.",
      "i" = "Got {.cls {class(delta)}}."
    ))
  }
  if (!is.character(attention)) {
    cli::cli_abort(c(
      "x" = "{.arg attention} must be a character vector.",
      "i" = "Got {.cls {class(attention)}}."
    ))
  }
  if (!is.character(caption) || length(caption) != 1L) {
    cli::cli_abort(c(
      "x" = "{.arg caption} must be a length-1 character string.",
      "i" = "Got length-{length(caption)} {.cls {class(caption)}}."
    ))
  }

  body_html <- .build_digest_body_html(delta, attention, caption)

  # ── Self-contained HTML (Slice 1) ────────────────────────────────────────
  # Slice 1 writes to docs/digest-preview.html only (no SMTP send).
  # Our self-contained .build_digest_body_html() output is the correct
  # return value here.
  #
  # TODO Slice 2 (#482): wrap in blastula::compose_email() for proper
  # email-client CSS and MIME envelope when SMTP is configured.
  # blastula is in Suggests; blastula::html() does not exist in the current
  # API — use blastula::md() or blastula::blocks() in Slice 2.
  body_html
}

# ── 4. hd_digest_snapshot_write ──────────────────────────────────────────────

#' Write a leaderboard snapshot to parquet for use as the next digest baseline
#'
#' Persists the current \code{leaderboard} target as a parquet file.  Call
#' this \emph{manually} after reviewing the digest output — do NOT wire it
#' into the same targets plan that reads the snapshot, as that would create a
#' read/write race condition.
#'
#' @param leaderboard A data frame — the current \code{leaderboard} target.
#' @param path File path to write.  Defaults to the canonical snapshot
#'   location inside the package's
#'   \code{inst/extdata/digest/} directory.
#'
#' @return Invisibly returns \code{path}.
#'
#' @family digest
#' @export
#'
#' @examples
#' \dontrun{
#'   # After reviewing the digest, refresh the baseline:
#'   hd_digest_snapshot_write(
#'     targets::tar_read(leaderboard),
#'     path = here::here(
#'       "packages/historicaldata/inst/extdata/digest/leaderboard_snapshot.parquet"
#'     )
#'   )
#' }
hd_digest_snapshot_write <- function(
    leaderboard,
    path = here::here(
      "packages/historicaldata/inst/extdata/digest/leaderboard_snapshot.parquet"
    )) {
  if (!is.data.frame(leaderboard)) {
    cli::cli_abort(c(
      "x" = "{.arg leaderboard} must be a data frame.",
      "i" = "Got {.cls {class(leaderboard)}}."
    ))
  }
  if (!requireNamespace("arrow", quietly = TRUE)) {
    cli::cli_abort(c(
      "x" = "Package {.pkg arrow} is required to write parquet snapshots.",
      "i" = "It is listed in {.field Suggests} in DESCRIPTION.",
      "i" = "Install with {.code install.packages('arrow')}."
    ))
  }
  dir.create(dirname(path), showWarnings = FALSE, recursive = TRUE)
  arrow::write_parquet(leaderboard, path)
  cli::cli_inform(c(
    "v" = "Snapshot written: {.path {path}}",
    "i" = "{nrow(leaderboard)} rows, {ncol(leaderboard)} columns."
  ))
  invisible(path)
}
