# Sealing hypotheses at inception (#598)
#
# The research log (research_log.R) already records hypotheses with UUID
# lineage, a git commit and an environment hash.  What it could not do is stop
# a claim being quietly reworded after the outcome was known.  Sealing closes
# that: the substantive fields are canonically serialised and hashed, so any
# later edit changes the hash and is detectable.
#
# ── What a seal does and does not prove ────────────────────────────────────
#
# Proves: this exact claim existed no later than the attesting timestamp.
#
# Does NOT prove:
#   * that the hypothesis came from the model or reasoning we claim;
#   * that it was our ONLY hypothesis - sealing 100 and publishing 20 leaves
#     the file drawer wide open.  Only a gapless, monotonically-numbered chain
#     closes that, and we do not have one yet.
#   * anything about the remedy chosen after a hypothesis fails.  Sealing the
#     forecast but not the fix rebuilds the same hole with better cryptography.
#
# ── Attestation: option 2, with option 3 as the upgrade path (#598) ────────
#
# The hash itself is only as good as the timestamp attached to it.  Ranked by
# how hard the timestamp is to forge:
#
#   1. git commit + push   - author/committer dates are client-settable and
#                            branches get force-pushed.  Baseline, not enough
#                            on its own.
#   2. HuggingFace commit  - CHOSEN.  Server-side timestamp, not settable by
#                            us, on infrastructure we already publish to.
#                            See hd_rlog_seal_export().
#   3. RFC-3161 TSA        - UPGRADE PATH, not implemented.  A genuine trusted
#                            third party (FreeTSA, DigiCert), offline-
#                            verifiable, ~2KB .tsr committed beside the
#                            parquet.  Wire this if anyone outside the project
#                            ever has money or reputation riding on our
#                            forecasts:
#                              openssl ts -query -data seals.parquet -sha256 \
#                                -cert -out seals.tsq
#                              curl -s -H "Content-Type: application/timestamp-query" \
#                                --data-binary @seals.tsq \
#                                https://freetsa.org/tsr -o seals.tsr
#                              openssl ts -verify -data seals.parquet \
#                                -in seals.tsr -CAfile cacert.pem
#   4. OpenTimestamps      - REJECTED for now.  Free and trust-minimised, but
#                            it answers a question nobody is asking us and
#                            adds a verification dependency that will rot.

# Fields that constitute the claim.  `status` is deliberately excluded: it
# legitimately moves proposed -> tested -> rejected after sealing.  Lineage
# columns are excluded except `uuid`, which pins the seal to one row so two
# identical claims do not collide.
.HD_SEAL_FIELDS <- c(
  "uuid", "economic_claim", "dependent_var", "predictor",
  "sample_spec", "null_hypothesis"
)

# Canonical serialisation: fixed field order, trimmed, UTF-8, explicit NA
# sentinel.  Any change here is a breaking change to every existing seal.
.hd_seal_serialise <- function(rows, call = rlang::caller_env()) {
  missing <- setdiff(.HD_SEAL_FIELDS, names(rows))
  if (length(missing) > 0L) {
    # Bind to a local first: a cli `{}` expression starting with a dot is
    # parsed as a style, not a variable (cli >= 3.4.0).
    required <- .HD_SEAL_FIELDS
    cli::cli_abort(c(
      "x" = "Cannot seal: missing field{?s} {.field {missing}}.",
      "i" = "Sealing requires all of: {.field {required}}."
    ), call = call)
  }
  parts <- lapply(.HD_SEAL_FIELDS, function(f) {
    v <- as.character(rows[[f]])
    v <- trimws(enc2utf8(ifelse(is.na(v), "NA", v)))
    paste0(f, "=", v)
  })
  do.call(paste, c(parts, list(sep = "\n")))
}

#' Seal hypothesis rows by hashing their canonical form
#'
#' Computes a SHA-256 over a canonical serialisation of the claim fields
#' (\code{uuid}, \code{economic_claim}, \code{dependent_var},
#' \code{predictor}, \code{sample_spec}, \code{null_hypothesis}) and fills
#' \code{commit_hash}, \code{sealed_at} and \code{seal_method}.
#'
#' \code{status} is excluded from the hash on purpose — it legitimately
#' changes after sealing (proposed to tested to rejected). Everything else in
#' the claim is frozen: reword any of it and \code{hd_rlog_seal_verify()}
#' fails.
#'
#' Seal at **inception**, before the hypothesis is tested. A hash applied
#' after you have seen the result commits to nothing.
#'
#' @param rows A data frame of hypothesis rows.
#' @param method Character scalar recorded in \code{seal_method}. Default
#'   \code{"sha256-v1"}.
#' @param sealed_at \code{POSIXct} recorded in \code{sealed_at}. Defaults to
#'   \code{Sys.time()}; pass an explicit value for reproducible tests.
#' @param overwrite Logical. If \code{FALSE} (default), rows that already
#'   carry a \code{commit_hash} are left untouched — resealing an existing row
#'   would defeat the purpose.
#'
#' @return \code{rows} with \code{commit_hash}, \code{sealed_at} and
#'   \code{seal_method} populated.
#'
#' @family research-log
#' @export
hd_rlog_seal <- function(rows, method = "sha256-v1",
                         sealed_at = Sys.time(), overwrite = FALSE) {
  if (nrow(rows) == 0L) return(rows)

  hashes <- vapply(
    .hd_seal_serialise(rows),
    function(s) digest::digest(s, algo = "sha256", serialize = FALSE),
    character(1), USE.NAMES = FALSE
  )

  existing <- if ("commit_hash" %in% names(rows)) rows$commit_hash else NA_character_
  existing <- rep_len(existing, nrow(rows))
  already <- !is.na(existing) & nzchar(existing)

  if (any(already) && !overwrite) {
    cli::cli_inform(c(
      "i" = "{sum(already)} row{?s} already sealed; leaving untouched.",
      "i" = "Pass {.code overwrite = TRUE} only if you intend to break the existing commitment."
    ))
  }

  keep <- already & !overwrite
  rows$commit_hash <- ifelse(keep, existing, hashes)
  rows$seal_method <- ifelse(keep,
                             if ("seal_method" %in% names(rows)) rows$seal_method else NA_character_,
                             method)
  prev_at <- if ("sealed_at" %in% names(rows)) rows$sealed_at else as.POSIXct(NA)
  rows$sealed_at <- as.POSIXct(ifelse(keep, prev_at, sealed_at),
                               origin = "1970-01-01", tz = "UTC")
  rows
}

#' Verify that sealed hypothesis rows have not been edited
#'
#' Recomputes the canonical hash for each row and compares it with the stored
#' \code{commit_hash}.
#'
#' @param rows A data frame of previously sealed hypothesis rows.
#' @param strict Logical. If \code{TRUE}, abort on any mismatch instead of
#'   returning the report. Default \code{FALSE}.
#'
#' @return A tibble with \code{uuid}, \code{commit_hash},
#'   \code{recomputed_hash} and \code{ok}, one row per input row. Rows with no
#'   stored hash are reported with \code{ok = NA} (unsealed, not tampered).
#'
#' @family research-log
#' @export
hd_rlog_seal_verify <- function(rows, strict = FALSE) {
  if (nrow(rows) == 0L) {
    return(tibble::tibble(uuid = character(), commit_hash = character(),
                          recomputed_hash = character(), ok = logical()))
  }
  if (!"commit_hash" %in% names(rows)) {
    cli::cli_abort(c(
      "x" = "No {.field commit_hash} column — these rows were never sealed.",
      "i" = "Seal them with {.fn hd_rlog_seal} before verifying."
    ))
  }

  recomputed <- vapply(
    .hd_seal_serialise(rows),
    function(s) digest::digest(s, algo = "sha256", serialize = FALSE),
    character(1), USE.NAMES = FALSE
  )

  stored <- as.character(rows$commit_hash)
  ok <- ifelse(is.na(stored) | !nzchar(stored), NA, stored == recomputed)

  out <- tibble::tibble(
    uuid            = as.character(rows$uuid),
    commit_hash     = stored,
    recomputed_hash = recomputed,
    ok              = ok
  )

  bad <- which(!is.na(ok) & !ok)
  if (length(bad) > 0L) {
    msg <- c(
      "x" = "{length(bad)} sealed hypothes{?is/es} no longer match{?es/} {?its/their} hash.",
      "i" = "First mismatch: uuid {.val {out$uuid[bad[1]]}}.",
      "i" = "A claim was edited after sealing. Recover the original from git history rather than resealing."
    )
    if (strict) cli::cli_abort(msg) else cli::cli_warn(msg)
  }
  out
}

#' Export sealed hypotheses for third-party timestamping
#'
#' Writes every sealed hypothesis to a single parquet file ready to be pushed
#' to the HuggingFace dataset repo. The HF commit — not our git commit — is
#' the attestation: its timestamp is server-side and we cannot set it.
#'
#' Publishing is deliberately **not** performed here. Pushing to HF is a
#' cross-boundary action and needs an explicit decision plus a token, so this
#' function stops at writing the file and printing the command:
#'
#' \preformatted{
#' hf upload <owner>/<dataset> <out_path> research_log/hypothesis_seals.parquet \
#'   --repo-type dataset \
#'   --commit-message "seal: N hypotheses through YYYY-MM-DD"
#' }
#'
#' @param base_dir Research-log base directory. Default \code{hd_rlog_path()}.
#' @param out_path Destination parquet path.
#' @param repo_id HuggingFace dataset id used to build the printed command.
#'
#' @return Invisibly, the tibble that was written.
#'
#' @family research-log
#' @export
hd_rlog_seal_export <- function(base_dir = NULL,
                                out_path = file.path(tempdir(), "hypothesis_seals.parquet"),
                                repo_id = "JohnGavin/historical-research-log") {
  rows <- hd_rlog_query("hypotheses", base_dir = base_dir)

  sealed <- rows[!is.na(rows$commit_hash) & nzchar(rows$commit_hash), , drop = FALSE]
  n_unsealed <- nrow(rows) - nrow(sealed)

  if (n_unsealed > 0L) {
    cli::cli_warn(c(
      "!" = "{n_unsealed} of {nrow(rows)} hypothes{?is/es} {?is/are} unsealed and will not be exported.",
      "i" = "An unsealed hypothesis is invisible to the audit — it is exactly the file-drawer case."
    ))
  }
  if (nrow(sealed) == 0L) {
    cli::cli_inform("i" = "No sealed hypotheses to export.")
    return(invisible(sealed))
  }

  arrow::write_parquet(sealed, out_path)

  cli::cli_inform(c(
    "v" = "Wrote {nrow(sealed)} sealed hypothes{?is/es} to {.path {out_path}}.",
    "i" = "Publish with (not run here — cross-boundary action):",
    " " = "hf upload {repo_id} {out_path} research_log/hypothesis_seals.parquet --repo-type dataset --commit-message \"seal: {nrow(sealed)} hypotheses through {format(Sys.Date())}\""
  ))
  invisible(sealed)
}
