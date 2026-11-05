# #631: S50 (qa_no_bare_source_urls) scans docs/*.qmd, so it cannot see
# source links that pipeline code builds with a_(label, paste0(base, "/x.R")).
# Those links reach the rendered dashboards as captions. This guard covers
# them: every such link in R/*.R must carry a #L<n> anchor, and line <n> of
# the target file must define the linked symbol (or, for a file-name label,
# define a function at all).

generated_source_links <- function(files) {
  pat <- 'a_\\("([^"]+)", paste0\\([A-Za-z_.]+, "(/[^"#]+\\.R)(#L([0-9]+))?"\\)\\)'
  rows <- lapply(files, function(f) {
    lines <- readLines(f, warn = FALSE)
    hit <- which(grepl(pat, lines))
    if (length(hit) == 0L) return(NULL)
    m <- regmatches(lines[hit], regexec(pat, lines[hit]))
    a <- vapply(m, `[`, "", 5L)
    data.frame(
      file = basename(f), line = hit,
      label = vapply(m, `[`, "", 2L),
      path = vapply(m, `[`, "", 3L),
      anchor = as.integer(replace(a, !nzchar(a), NA_character_)),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

anchor_problems <- function(links, repo_root) {
  bad <- character(0)
  for (i in seq_len(nrow(links))) {
    l <- links[i, ]
    where <- sprintf("%s:%d %s", l$file, l$line, l$label)
    if (is.na(l$anchor)) {
      bad <- c(bad, paste(where, "-- no #L anchor"))
      next
    }
    target <- file.path(repo_root, sub("^/", "", l$path))
    if (!file.exists(target)) {
      bad <- c(bad, paste(where, "-- target file missing"))
      next
    }
    src <- readLines(target, warn = FALSE)
    def <- if (l$anchor <= length(src)) src[l$anchor] else ""
    sym <- sub("\\(\\)$", "", l$label)
    want <- if (grepl("\\.R$", sym)) "<- function" else paste0(sym, " <- function")
    if (!grepl(want, def, fixed = TRUE)) {
      bad <- c(bad, sprintf("%s -- #L%d does not define it", where, l$anchor))
    }
  }
  bad
}

test_that("#631: source links generated in R/ code carry a correct #L anchor", {
  files <- list.files(here::here("R"), pattern = "\\.R$", full.names = TRUE)
  links <- generated_source_links(files)
  # Finding none means the pattern drifted from the code, not a pass.
  expect_false(is.null(links))
  if (is.null(links)) return(invisible())
  bad <- anchor_problems(links, here::here())
  expect_equal(bad, character(0))
})

test_that("#631 guard goes red on a bare and on a stale generated link", {
  tmp <- withr::local_tempdir()
  dir.create(file.path(tmp, "R"))
  writeLines("foo <- function() 1", file.path(tmp, "R", "foo.R"))
  writeLines(c(
    'x <- a_("foo()", paste0(gh, "/R/foo.R"))',
    'y <- a_("foo()", paste0(gh, "/R/foo.R#L1"))',
    'z <- a_("bar()", paste0(gh, "/R/foo.R#L1"))'
  ), file.path(tmp, "R", "caller.R"))
  links <- generated_source_links(file.path(tmp, "R", "caller.R"))
  expect_equal(nrow(links), 3L)
  bad <- anchor_problems(links, tmp)
  expect_length(bad, 2L)
  expect_match(bad[1], "no #L anchor")
  expect_match(bad[2], "does not define it")
})

# Links can also come from data (data/column_glossary.yaml), and any other
# route we have not thought of ends up in the rendered page. So check the
# shipped artifact too: no committed docs/*.html may hold a bare .R link.
bare_source_links_in <- function(text) {
  pat <- "github\\.com/JohnGavin/historical/blob/main/[^\"'#&<> ]+\\.R(\"|'|&quot;)"
  regmatches(text, gregexpr(pat, text))[[1]]
}

test_that("#631: data/column_glossary.yaml source links carry #L anchors", {
  path <- here::here("data", "column_glossary.yaml")
  skip_if_not(file.exists(path), "column_glossary.yaml not present")
  hits <- bare_source_links_in(paste(readLines(path, warn = FALSE), collapse = "\n"))
  expect_equal(hits, character(0))
})

test_that("#631: rendered docs/*.html hold no bare .R source links", {
  pages <- Sys.glob(here::here("docs", "*.html"))
  # No rendered pages means nothing was checked, not a pass.
  expect_gt(length(pages), 0L)
  bad <- unlist(lapply(pages, function(p) {
    hits <- bare_source_links_in(paste(readLines(p, warn = FALSE), collapse = "\n"))
    if (length(hits)) paste(basename(p), hits) else character(0)
  }))
  expect_equal(bad, character(0))
})

test_that("#631 bare-link matcher goes red on bare links and passes anchored ones", {
  gh <- "https://github.com/JohnGavin/historical/blob/main/R/x.R"
  expect_length(bare_source_links_in(paste0('<a href="', gh, '">')), 1L)
  expect_length(bare_source_links_in(paste0("&lt;a href=&quot;", gh, "&quot;")), 1L)
  expect_length(bare_source_links_in(paste0('url: "', gh, '"')), 1L)
  expect_length(bare_source_links_in(paste0('<a href="', gh, '#L3">')), 0L)
})
