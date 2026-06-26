# Plan: Strategy Digest — leaderboard delta + blastula email-to-file  (#482)
#
# Slice 1 only.  Deferred to follow-up:
#   - Embedded dashboard summary page
#   - Link from docs/index.qmd
#   - SMTP send / scheduling
#
# Architecture decisions (no redesign; see issue #482):
#   - Source:   existing `leaderboard` target; NO schema changes.
#   - Snapshot: committed parquet at packages/historicaldata/inst/extdata/digest/
#               leaderboard_snapshot.parquet.
#               If absent → first-run BASELINE (no deltas, all strategies "new").
#   - Email:    HTML file only; NO send.  blastula-guarded with graceful fallback.
#   - Snapshot refresh: call hd_digest_snapshot_write() MANUALLY after review.
#
# Applicable rules:
#   resulting-prohibition  — Sharpe drop alone is NOT flagged in attention output
#   portable-paths         — here::here() throughout; no absolute paths
#   namespace-discipline   — no library() inside target bodies
#   btw-timeouts           — all R via Bash/nix develop at verification stage
#
# Targets (6 total):
#   digest_snapshot_path       — path to the committed snapshot parquet
#   digest_prior               — prior leaderboard or NULL (first-run baseline)
#   strategy_digest_delta      — per-strategy delta tibble
#   strategy_digest_attention  — character vector of attention lines
#   strategy_digest_caption    — dynamic narrative string
#   strategy_digest_email      — HTML file written to docs/digest-preview.html

plan_strategy_digest <- function() {
  list(

    # ── Snapshot path ─────────────────────────────────────────────────────────
    # Resolved via here::here() so it works correctly under tar_make() called
    # from the repo root (pipeline-invocation rule).
    targets::tar_target(
      digest_snapshot_path,
      here::here(
        "packages/historicaldata/inst/extdata/digest/leaderboard_snapshot.parquet"
      ),
      cue = targets::tar_cue(mode = "always")
    ),

    # ── Prior state ───────────────────────────────────────────────────────────
    # Reads the committed snapshot when it exists; returns NULL on the first
    # run (triggering baseline mode in hd_digest_delta).
    # arrow is in Suggests — guard with requireNamespace.
    targets::tar_target(
      digest_prior,
      {
        p <- digest_snapshot_path
        if (!file.exists(p)) {
          cli::cli_inform(c(
            "i" = "No snapshot at {.path {p}}.",
            "i" = "First-run baseline: all strategies will show as 'new'.",
            "i" = "Bootstrap with {.fn hd_digest_snapshot_write} after this run."
          ))
          return(NULL)
        }
        if (!requireNamespace("arrow", quietly = TRUE)) {
          cli::cli_warn(c(
            "!" = "{.pkg arrow} not available; cannot read snapshot.",
            "i" = "Treating this run as a baseline (prior = NULL)."
          ))
          return(NULL)
        }
        arrow::read_parquet(p)
      }
    ),

    # ── Delta tibble ─────────────────────────────────────────────────────────
    # One row per strategy with numeric deltas and boolean structural flags.
    # Depends on `leaderboard` (from plan_leaderboard) and `digest_prior`.
    targets::tar_target(
      strategy_digest_delta,
      historicaldata::hd_digest_delta(leaderboard, digest_prior)
    ),

    # ── Attention lines ───────────────────────────────────────────────────────
    # Character vector of "[STRATEGY]: <reason>" lines.
    # Structural flags only; Sharpe drops are NOT flagged (resulting-prohibition).
    targets::tar_target(
      strategy_digest_attention,
      historicaldata::hd_digest_attention(strategy_digest_delta)
    ),

    # ── Dynamic narrative caption ─────────────────────────────────────────────
    # No hardcoded counts.  Embeds the resulting-prohibition framing so the
    # email reader understands that structural flags—not metric moves—drive
    # the "needs attention" section.
    targets::tar_target(
      strategy_digest_caption,
      {
        n_total   <- nrow(strategy_digest_delta)
        n_new     <- sum(strategy_digest_delta$status == "new",     na.rm = TRUE)
        n_changed <- sum(strategy_digest_delta$status == "changed", na.rm = TRUE)
        n_attn    <- length(strategy_digest_attention)

        snap_path <- digest_snapshot_path
        snap_date <- if (file.exists(snap_path)) {
          format(as.Date(file.info(snap_path)$mtime), "%Y-%m-%d")
        } else {
          "no prior snapshot (first run)"
        }

        paste0(
          n_total, " strategies in the current leaderboard. ",
          n_new, " new since the prior snapshot (", snap_date, "). ",
          n_changed, " have structural flag changes. ",
          n_attn, " need attention. ",
          "Note: Sharpe or CAGR moves alone are not flagged as problems ",
          "(resulting-prohibition framing). Only redundancy, crowding, ",
          "walk-forward verdict changes, CI zero-crossing, and ",
          "deflated-Sharpe significance loss trigger the attention list."
        )
      }
    ),

    # ── HTML digest file ──────────────────────────────────────────────────────
    # Writes docs/digest-preview.html.  format = "file" so targets tracks the
    # output file content hash and rebuilds when the HTML changes.
    # NO SMTP send; no credentials.
    targets::tar_target(
      strategy_digest_email,
      {
        html <- historicaldata::hd_digest_html(
          strategy_digest_delta,
          strategy_digest_attention,
          strategy_digest_caption
        )
        out_path <- here::here("docs/digest-preview.html")
        writeLines(html, out_path)
        out_path
      },
      format = "file"
    )
  )
}
