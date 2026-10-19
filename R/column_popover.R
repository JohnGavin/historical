# Hover popovers for column headers (#788; first use: DSR conventions, #959)
#
# Layer 1 of #788: ONE glossary (data/column_glossary.yaml), one definition per
# column. Layer 2 (this file): content is built SERVER-SIDE from the glossary
# into Bootstrap 5 popover attributes, so it is deterministic, inspectable in
# the committed HTML, and testable without a browser. The single delegated
# hover/focus handler that instantiates popovers lives in
# docs/vignette-shared.js (nothing here runs in the browser).
#
# A column whose label would need a glossary entry that does not exist ABORTS
# (fail-loud-not-null): a missing definition must stop the build, never render
# a bare header.
#
# Sourced by docs/leaderboard.qmd after R/glossary.R (it reuses
# .repo_data_file() to find data/ from docs/).

#' Load the column glossary (data/column_glossary.yaml)
#'
#' @param path Character. Path to the YAML file. Defaults to the first
#'   `data/column_glossary.yaml` found walking up from the working directory
#'   (needs `.repo_data_file()` from R/glossary.R).
#' @return Named list of column entries (the `columns:` mapping).
#' @noRd
load_column_glossary <- function(path = .repo_data_file("column_glossary.yaml")) {
  if (!file.exists(path)) {
    cli::cli_abort(c(
      "x" = "Column glossary file not found: {.path {path}}.",
      "i" = "Expected {.path data/column_glossary.yaml} at the repo root (#788)."
    ), class = "hd_error_column_glossary_missing")
  }
  parsed <- yaml::read_yaml(path)
  cols <- parsed$columns
  if (!is.list(cols) || length(cols) == 0L) {
    cli::cli_abort(c(
      "x" = "{.path {path}} has no {.field columns} section.",
      "i" = "Add a {.field columns:} mapping keyed by canonical column name."
    ), class = "hd_error_column_glossary_malformed")
  }
  cols
}

# Plain text -> HTML text node. Glossary text is data, never markup.
.hd_esc <- function(x) htmltools::htmlEscape(x, attribute = FALSE)

# Plain text -> double-quoted attribute value.
.hd_esc_attr <- function(x) htmltools::htmlEscape(x, attribute = TRUE)

#' Build one Bootstrap popover span
#'
#' @param label Plain-text visible label.
#' @param title Plain-text popover title.
#' @param content_html Popover body, already-safe HTML.
#' @return Character scalar of HTML. `label`, `title` and `content_html` are
#'   attribute-escaped, so quotes and angle brackets survive intact.
#' @noRd
hd_popover_span <- function(label, title, content_html) {
  for (nm in c("label", "title", "content_html")) {
    v <- get(nm)
    if (!is.character(v) || length(v) != 1L || is.na(v) || !nzchar(v)) {
      cli::cli_abort(c(
        "x" = "{.arg {nm}} must be a single non-empty string.",
        "i" = "Got {.val {v}} (class {.cls {class(v)}}, length {length(v)})."
      ), class = "hd_error_popover_arg")
    }
  }
  sprintf(
    paste0(
      '<span class="hd-popover" tabindex="0" role="button" ',
      'data-bs-toggle="popover" data-bs-html="true" ',
      'data-bs-trigger="hover focus" data-bs-placement="bottom" ',
      'data-bs-title="%s" data-bs-content="%s">%s</span>'
    ),
    .hd_esc_attr(title), .hd_esc_attr(content_html), .hd_esc(label)
  )
}

#' Popover body for one DSR convention, built from the glossary entry
#'
#' @param entry The `dsr_pvalue` glossary entry.
#' @param convention Name of the convention that produced the number.
#' @return Character scalar of safe HTML.
#' @noRd
.hd_dsr_content_html <- function(entry, convention) {
  conv <- entry$conventions[[convention]]
  others <- setdiff(names(entry$conventions), convention)
  one <- function(c_entry) {
    paste0(
      "<strong>", .hd_esc(c_entry$label), "</strong> (", .hd_esc(c_entry$role),
      "). ", .hd_esc(c_entry$definition),
      " <code>", .hd_esc(c_entry$formula), "</code>"
    )
  }
  links <- vapply(entry$links, function(l) {
    paste0('<a href="', .hd_esc_attr(l$url), '" target="_blank" rel="noopener noreferrer">',
           .hd_esc(l$label), "</a>")
  }, character(1))
  paste0(
    "<p>", .hd_esc(entry$short), "</p>",
    "<p><strong>This number:</strong> ", one(conv), "</p>",
    paste0("<p><strong>Other convention:</strong> ",
           vapply(others, function(o) one(entry$conventions[[o]]), character(1)),
           "</p>", collapse = ""),
    "<p><strong>Difference:</strong> ", .hd_esc(entry$difference), "</p>",
    "<p>", .hd_esc(entry$ratio), "</p>",
    "<p>Details: ", paste(links, collapse = " &middot; "), "</p>"
  )
}

#' Header label with a popover for a DSR column
#'
#' @param conventions Character vector of `hurdle_convention` values for the
#'   rows of the column (as returned by `hd_deflated_sharpe()`).
#' @param glossary Column glossary (default: loaded from data/).
#' @return Character scalar of HTML: "DSR p-value (<convention>)" with the
#'   popover. Aborts (class `hd_error_dsr_convention_unknown`) if the column
#'   carries no convention, mixed conventions, or a convention with no
#'   glossary entry: the convention is never guessed.
#' @noRd
hd_dsr_header_popover <- function(conventions, glossary = load_column_glossary()) {
  entry <- glossary$dsr_pvalue
  if (is.null(entry) || is.null(entry$conventions)) {
    cli::cli_abort(c(
      "x" = "Column glossary has no {.field dsr_pvalue} entry with {.field conventions}.",
      "i" = "Add it to {.path data/column_glossary.yaml} (#788, #959)."
    ), class = "hd_error_dsr_convention_unknown")
  }
  conv <- unique(as.character(conventions[!is.na(conventions)]))
  if (length(conv) == 0L) {
    cli::cli_abort(c(
      "x" = "No {.field hurdle_convention} value available for this DSR column.",
      "i" = "Carry {.code hd_deflated_sharpe()$hurdle_convention} into the data; the convention is never guessed."
    ), class = "hd_error_dsr_convention_unknown")
  }
  if (length(conv) > 1L) {
    cli::cli_abort(c(
      "x" = "One DSR column mixes {length(conv)} conventions: {.val {conv}}.",
      "i" = "Split the column per convention so each header names exactly one."
    ), class = "hd_error_dsr_convention_unknown")
  }
  if (!conv %in% names(entry$conventions)) {
    cli::cli_abort(c(
      "x" = "DSR convention {.val {conv}} has no entry in the column glossary.",
      "i" = "Known conventions: {.val {names(entry$conventions)}}.",
      "i" = "Add it under {.field dsr_pvalue.conventions} in {.path data/column_glossary.yaml}."
    ), class = "hd_error_dsr_convention_unknown")
  }
  hd_popover_span(
    label = paste0(entry$title, " (", entry$conventions[[conv]]$label, ")"),
    title = paste0(entry$title, ": ", entry$conventions[[conv]]$label, " convention"),
    content_html = .hd_dsr_content_html(entry, conv)
  )
}

#' DT table container whose headers may carry HTML (popover labels)
#'
#' @param col_names Character vector of the data frame's column names.
#' @param html_headers Named list: column name -> header HTML (replaces the
#'   plain, escaped name for that column).
#' @return An `htmltools` table tag for `DT::datatable(container = )`.
#' @noRd
hd_dt_header_container <- function(col_names, html_headers = list()) {
  unknown <- setdiff(names(html_headers), col_names)
  if (length(unknown) > 0L) {
    cli::cli_abort(c(
      "x" = "{.arg html_headers} names columns not in the table: {.val {unknown}}."
    ), class = "hd_error_header_container")
  }
  ths <- lapply(col_names, function(nm) {
    if (nm %in% names(html_headers)) {
      htmltools::tags$th(htmltools::HTML(html_headers[[nm]]))
    } else {
      htmltools::tags$th(nm)
    }
  })
  htmltools::tags$table(
    class = "display",
    htmltools::tags$thead(htmltools::tags$tr(ths))
  )
}
