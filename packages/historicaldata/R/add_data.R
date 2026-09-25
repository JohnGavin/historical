# Chen-Zimmermann "Open Asset Pricing" dataset registration
#
# Source:
#   Chen, Andrew Y. and Zimmermann, Tom (2022). "Open Source Cross-Sectional
#   Asset Pricing." Critical Finance Review, 11(2), 207-264.
#   DOI: 10.1561/104.00000112
#   Dataset portal: https://www.openassetpricing.com/data/
#
# Verified 2026-09-11/25 (#862 P1-P4; see explorations/osap_verification/
# and scripts/fetch_osap.R): the free download provides two things useful
# to this repo --
#   1. SignalDoc.csv -- documentation for 331 anomaly signals.
#   2. portfolios_wide.csv -- MONTHLY LONG-SHORT PORTFOLIO returns, wide,
#      one column per predictor (212 columns as of the 2024 release), in
#      PERCENT scale, 1926-01 to 2024-12. [hd_osap_load()] tidies this to
#      long form and converts to the house-canonical fraction scale.
#
# It does NOT provide what an earlier draft of this file assumed: there is
# no per-stock quintile-assignment file, and the ~8.3GB firm-level
# characteristics file (deliberately not downloaded -- see
# scripts/fetch_osap.R) has NO return column of any kind (#862 P2 FAIL).
# So a per-stock ADD computation (quintile x stock x date) is NOT
# computable from the free OSAP download alone -- only the pre-built
# portfolio-level long-short series are available. hd_compute_add() in
# add_signal.R still expects a (stock, date, anomaly_id, quintile) table;
# that table must come from elsewhere (or from the firm-level file's
# per-stock signal VALUES combined with our own price/return data, which
# is future work, not this registration).
#
# Data licence (#862 P3): no licence is stated anywhere the authors
# publish. Operating position: compute freely, keep raw downloads local
# (scripts/fetch_osap.R never commits them), publish only derived
# statistics -- see .claude/rules/public-private-repo-boundary.md.
#
# References:
#   Kjær, M.M. & Posselt, A.M. (2025). "Anomaly-Driven Demand."
#   Aarhus University / Danish Finance Institute working paper, Nov 2025.
#   Presented at Cavalcade Asia-Pacific 2025.
#   See knowledge/wiki/anomaly-driven-demand.md for digest.
#
# Related issues:
#   #279 — ADD crowding / candidate signal
#   #160 — effective number of tested strategies (K_eff_strat) — must budget
#          ADD against existing correlated-strategy count before deployment

#' Register the Chen-Zimmermann Open Asset Pricing dataset source
#'
#' Returns a named list describing the Chen & Zimmermann (2022) "Open Source
#' Cross-Sectional Asset Pricing" dataset. This is a *registration* function
#' only — it does **not** download any data. Use [hd_osap_load()] (via
#' `scripts/fetch_osap.R`) for the actual download + load step, and this
#' metadata to describe what that step provides and what it does not.
#'
#' Verified 2026-09-11/25 (#862): the free download provides
#' `SignalDoc.csv` (documentation for 331 anomaly signals) and
#' `portfolios_wide.csv` (monthly long-short PORTFOLIO returns, 212
#' predictor columns as of the 2024 release, 1926-01 to 2024-12). It does
#' **not** provide a per-stock quintile-assignment file or any firm-level
#' return series — the ~8.3GB firm-level characteristics file has no return
#' column at all (#862 P2). So [hd_compute_add()]'s (stock, date,
#' anomaly_id, quintile) input cannot be built from the free OSAP download
#' alone; only the pre-built portfolio-level series in [hd_osap_load()]'s
#' output are currently available from this source.
#'
#' @return A named list with fields:
#'   \describe{
#'     \item{source_name}{Human-readable name of the data source.}
#'     \item{portal_url}{URL of the data portal (no authentication required
#'       as of 2026-09).}
#'     \item{download_url}{Direct download URL for the monthly long-short
#'       portfolio-returns file actually loaded by [hd_osap_load()].
#'       Google Drive file ids for this project's annual releases have
#'       been observed to persist across at least one release cycle, but
#'       are not guaranteed stable indefinitely — `scripts/fetch_osap.R`
#'       is the source of truth if this URL ever 404s.}
#'     \item{expected_schema}{Character vector of column names in
#'       [hd_osap_load()]'s output tibble (portfolio-level, not
#'       firm-level).}
#'     \item{frequency}{Rebalancing frequency of the anomaly portfolios.}
#'     \item{universe}{Description of the stock universe covered.}
#'     \item{sample_start}{Start of the data sample (character "YYYY-MM").}
#'     \item{sample_end}{End of the data sample (character "YYYY-MM").}
#'     \item{n_anomalies}{Number of predictor columns in
#'       `portfolios_wide.csv` (integer) — distinct from the 331 signals
#'       documented in `SignalDoc.csv`, which includes signals with no
#'       portfolio-return series.}
#'     \item{citation}{Full citation string for the dataset.}
#'     \item{related_issues}{Character vector of GitHub issue numbers
#'       relevant to this dataset.}
#'   }
#' @family add
#' @family osap
#' @export
hd_register_add_dataset <- function() {
  list(
    source_name    = "Chen-Zimmermann Open Asset Pricing (2022)",
    portal_url     = "https://www.openassetpricing.com/data/",
    download_url   = "https://drive.google.com/file/d/10sOryk_ddjkXagaajTKUk1nwJs2ZLRiI/view",
    expected_schema = c(
      "predictor", "date", "ret", "metric_unit",
      "signal_sign", "signal_authors", "signal_year", "signal_description",
      "signal_journal", "signal_category", "signal_data_category",
      "signal_economic_category", "signal_sample_start", "signal_sample_end"
    ),
    frequency      = "monthly",
    universe       = paste0(
      "Portfolio-level long-short series only (no per-stock/firm-level ",
      "returns available from the free download -- #862 P2). The ",
      "firm-level *signal values* (not returns) file, not ingested here, ",
      "covers a broader CRSP-derived universe including non-common-stock ",
      "securities (#862 P1 caveat 1)."
    ),
    sample_start   = "1926-01",
    sample_end     = "2024-12",
    n_anomalies    = 212L,
    citation       = paste0(
      "Chen, A.Y. and Zimmermann, T. (2022). ",
      "'Open Source Cross-Sectional Asset Pricing.' ",
      "Critical Finance Review, 11(2), 207-264. ",
      "DOI: 10.1561/104.00000112. ",
      "Dataset: https://www.openassetpricing.com/"
    ),
    related_issues = c("#279", "#160", "#816", "#862")
  )
}
