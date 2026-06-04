# Plan: Point-in-Time universe (STUB — not yet wired into _targets.R)
#
# Issue refs: #278 (OLMAR P4), #150 (survivorship bias).
#
# DO NOT register this in _targets.R until the user has:
#   1. Picked a PIT data source (CRSP / Norgate / Wayback+EODHD)
#   2. Confirmed pricing and credentials are in .Renviron
#   3. Run the known-delisted-ticker presence test
#
# See plans/olmar-phase4-scoping.md sections A-E for the rationale.
#
# Schema (when implemented):
#   ticker            character — ticker symbol as of the listed date
#   date              Date      — trading day
#   in_universe_pit   logical   — TRUE if constituent on that date
#   index_name        character — "SP600" / "SP500" / "SP400" (etc)
#   delisting_date    Date|NA   — date the ticker stopped trading / left index
#   delisting_reason  chr|NA    — "bankruptcy"/"acquired"/"merged"/"index_removed"/"other"
#   delisting_price   dbl|NA    — final traded price (0 for liquidations to zero)
#
# Intended consumption pattern (in plan_olmar.R Phase 4):
#   olmar_params_sp600_pit$tickers <- stk_universe_pit |>
#     dplyr::filter(in_universe_pit, index_name == "SP600",
#                   date == max(date)) |>
#     dplyr::pull(ticker)
#   ... then per-date filtering inside the backtest, NOT a static ticker list.

plan_universe_pit <- function() {
  list(

    # ── STUB target — aborts on build ─────────────────────────────
    # Keeps the target machinery honest: anything wired to depend on
    # stk_universe_pit_stub will receive a clear error pointing at the
    # scoping doc rather than silently using survivorship-biased data.
    targets::tar_target(stk_universe_pit_stub, {
      # Return the target schema (zero rows) so downstream code that
      # introspects the schema doesn't crash before reaching the abort.
      schema <- tibble::tibble(
        ticker           = character(0),
        date             = as.Date(character(0)),
        in_universe_pit  = logical(0),
        index_name       = character(0),
        delisting_date   = as.Date(character(0)),
        delisting_reason = character(0),
        delisting_price  = double(0)
      )

      cli::cli_abort(c(
        "x" = "PIT universe data has not been sourced yet.",
        "i" = "See plans/olmar-phase4-scoping.md for the data-source comparison.",
        "i" = "User must pick a source (CRSP / Norgate / Wayback+EODHD)",
        "i" = "  and confirm credentials before this target can be built.",
        " " = "",
        "*" = "Issue: https://github.com/JohnGavin/historical/issues/278",
        "*" = "Issue: https://github.com/JohnGavin/historical/issues/150",
        " " = "",
        "i" = "Schema this target will return (zero rows):",
        "i" = paste(names(schema), collapse = ", ")
      ))
    })

  )
}
