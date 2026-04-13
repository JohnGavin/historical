# Post-build QA checks for vignette targets
#
# Run AFTER tar_make(), BEFORE quarto render.
# Catches NULL outputs, raw SQL, invalid plots.
#
# Usage:
#   Rscript scripts/qa_vignette.R

library(targets)
library(cli)

store <- if (dir.exists("docs/_targets")) "docs/_targets" else "_targets"
cli_h1("QA: Vignette Target Validation")
cat("Store:", store, "\n")

all_names <- tar_objects(store = store)
vig_names <- all_names[grepl("^vig_", all_names) & !grepl("^code_vig_", all_names)]
code_names <- all_names[grepl("^code_vig_", all_names)]

# QA 1: No NULL outputs
cli_h2("Check 1: NULL outputs")
nulls <- character()
for (nm in vig_names) {
  obj <- tryCatch(tar_read_raw(nm, store = store), error = function(e) NULL)
  if (is.null(obj)) nulls <- c(nulls, nm)
}
if (length(nulls) > 0) {
  cli_alert_danger("{length(nulls)} targets returned NULL: {paste(nulls, collapse = ', ')}")
} else {
  cli_alert_success("{length(vig_names)} vig targets checked, 0 NULL")
}

# QA 2: No raw SQL in code targets
cli_h2("Check 2: Raw SQL in code targets")
sql_violations <- character()
for (nm in code_names) {
  code <- tryCatch(tar_read_raw(nm, store = store), error = function(e) "")
  if (is.character(code) && grepl("DBI::dbGetQuery|dbExecute.*SELECT|paste0.*SELECT.*FROM", code)) {
    sql_violations <- c(sql_violations, nm)
  }
}
if (length(sql_violations) > 0) {
  cli_alert_warning("{length(sql_violations)} code targets contain raw SQL: {paste(sql_violations, collapse = ', ')}")
} else {
  cli_alert_success("{length(code_names)} code targets checked, 0 SQL violations")
}

# QA 3: Plot targets are valid ggplot or data.frame
cli_h2("Check 3: Plot/data target types")
plot_names <- vig_names[!grepl("meta_|setup|coverage$", vig_names)]
invalid <- character()
for (nm in plot_names) {
  obj <- tryCatch(tar_read_raw(nm, store = store), error = function(e) NULL)
  if (is.null(obj)) {
    invalid <- c(invalid, paste0(nm, " (NULL)"))
  } else if (!inherits(obj, c("ggplot", "gg", "data.frame", "tbl_df", "tbl", "character"))) {
    invalid <- c(invalid, paste0(nm, " (", class(obj)[1], ")"))
  }
}
if (length(invalid) > 0) {
  cli_alert_danger("{length(invalid)} invalid targets: {paste(invalid, collapse = ', ')}")
} else {
  cli_alert_success("{length(plot_names)} plot/data targets valid")
}

# Summary
cli_h2("Summary")
n_errors <- length(nulls) + length(invalid)
if (n_errors > 0) {
  cli_alert_danger("FAIL: {n_errors} errors found. Fix before rendering.")
  quit(status = 1)
} else {
  cli_alert_success("PASS: All QA checks passed.")
}
