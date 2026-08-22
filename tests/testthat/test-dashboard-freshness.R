testthat::local_edition(3)
source(here::here("scripts", "check_dashboard_freshness.R"))

# Regression / unit tests for scripts/check_dashboard_freshness.R (#695,
# Option A: detection only -- no re-rendering is exercised or expected here).
#
# scripts/check_dashboard_freshness.R defines all its logic as `.cdf_*`
# functions and only RUNS them when it is the Rscript entry point
# (`sys.nframe() == 0` at its own top level -- see that file's final block).
# source()'ing it here (sys.nframe() > 0) loads the functions without
# triggering a live check1/2/3 run against the real repo, which is what lets
# these tests exercise the extractor against small synthetic fixtures
# instead of the real docs/*.qmd tree.
#
# Fixture files inside withr::local_tempdir() use FIXED basenames
# ("toy_dashboard.qmd" etc.) -- basename(path) is the only part of the path
# this checker's cli_abort() messages ever include, so snapshots stay
# portable across checkouts/CI (portable-build-artifacts), matching the
# pattern in test-registry-unit-map-coverage.R.

# ── .cdf_call_head_name() ──────────────────────────────────────────────────

test_that(".cdf_call_head_name resolves a bare-symbol call head", {
  e <- quote(tar_read("x"))
  expect_equal(.cdf_call_head_name(e), "tar_read")
})

test_that(".cdf_call_head_name resolves a pkg::fn call head", {
  e <- quote(targets::tar_read_raw("x"))
  expect_equal(.cdf_call_head_name(e), "tar_read_raw")
})

test_that(".cdf_call_head_name returns NULL for a non-call", {
  expect_null(.cdf_call_head_name(quote(x)))
  expect_null(.cdf_call_head_name("just a string"))
})

# ── .cdf_extract_read_targets() ────────────────────────────────────────────

test_that(".cdf_extract_read_targets resolves the string-literal form", {
  exprs <- parse(text = 'x <- tar_read("target_a")')
  expect_equal(.cdf_extract_read_targets(exprs, "toy.qmd"), "target_a")
})

test_that(".cdf_extract_read_targets resolves the bare-symbol form", {
  exprs <- parse(text = "y <- tar_read(target_b)")
  expect_equal(.cdf_extract_read_targets(exprs, "toy.qmd"), "target_b")
})

test_that(".cdf_extract_read_targets resolves the targets::-qualified form (tar_read and tar_read_raw)", {
  exprs <- parse(text = paste(
    'a <- targets::tar_read("target_c")',
    "b <- targets::tar_read_raw(target_d)",
    sep = "\n"
  ))
  expect_equal(sort(.cdf_extract_read_targets(exprs, "toy.qmd")), c("target_c", "target_d"))
})

test_that(".cdf_extract_read_targets recognises safe_tar_read() as a read function", {
  exprs <- parse(text = 'z <- safe_tar_read("target_e")')
  expect_equal(.cdf_extract_read_targets(exprs, "toy.qmd"), "target_e")
})

test_that(".cdf_extract_read_targets de-duplicates repeated references to the same target", {
  exprs <- parse(text = paste(
    'a <- tar_read("target_f")',
    'b <- tar_read("target_f")',
    sep = "\n"
  ))
  expect_equal(.cdf_extract_read_targets(exprs, "toy.qmd"), "target_f")
})

test_that(".cdf_extract_read_targets ignores calls to unrelated functions with the same argument shape", {
  exprs <- parse(text = 'x <- some_other_fn("not_a_target")')
  expect_equal(.cdf_extract_read_targets(exprs, "toy.qmd"), character(0))
})

test_that(".cdf_extract_read_targets aborts informatively on a non-literal, non-symbol first argument (#695)", {
  exprs <- parse(text = 'x <- tar_read(paste0("prefix_", "suffix"))')
  expect_snapshot(error = TRUE, .cdf_extract_read_targets(exprs, "toy_dashboard.qmd"))
})

test_that(".cdf_extract_read_targets aborts informatively on a zero-argument read call (#695)", {
  exprs <- parse(text = "x <- tar_read()")
  expect_snapshot(error = TRUE, .cdf_extract_read_targets(exprs, "toy_dashboard.qmd"))
})

# ── .cdf_has_r_chunk_fence() ───────────────────────────────────────────────

test_that(".cdf_has_r_chunk_fence detects a fenced R chunk", {
  dir <- withr::local_tempdir()
  file <- file.path(dir, "toy_dashboard.qmd")
  writeLines(c("---", "title: Toy", "---", "", "```{r}", "1 + 1", "```"), file)
  expect_true(.cdf_has_r_chunk_fence(file))
})

test_that(".cdf_has_r_chunk_fence is FALSE for a pure-prose page", {
  dir <- withr::local_tempdir()
  file <- file.path(dir, "toy_dashboard.qmd")
  writeLines(c("---", "title: Toy", "---", "", "Just prose, no chunks."), file)
  expect_false(.cdf_has_r_chunk_fence(file))
})

# ── .cdf_is_redirect_stub() (#695 follow-up) ────────────────────────────────
# Requires BOTH no-R-chunk-fence AND the <meta http-equiv="refresh"> marker
# -- see the function's own comment in check_dashboard_freshness.R for why
# "no R chunks" alone is not used as the test.

test_that(".cdf_is_redirect_stub is TRUE for a drif.qmd-style redirect stub", {
  dir <- withr::local_tempdir()
  file <- file.path(dir, "toy_dashboard.qmd")
  writeLines(c(
    "---", "title: Redirect stub", "---", "",
    "> **This page has moved.**", "",
    "Redirecting automatically…", "",
    '<meta http-equiv="refresh" content="0; url=elsewhere.html">',
    '<script>window.location.href = "elsewhere.html";</script>'
  ), file)
  expect_true(.cdf_is_redirect_stub(file))
})

test_that(".cdf_is_redirect_stub is FALSE for a page with no R chunks and no redirect marker (pins the #695 decision)", {
  dir <- withr::local_tempdir()
  file <- file.path(dir, "toy_dashboard.qmd")
  writeLines(c(
    "---", "title: Bare prose page", "---", "",
    "Just prose, no chunks, and definitely no redirect to anywhere."
  ), file)
  expect_false(.cdf_has_r_chunk_fence(file)) # would wrongly qualify under the weaker test
  expect_false(.cdf_is_redirect_stub(file))
})

test_that(".cdf_is_redirect_stub is FALSE for a page that has R chunks, even if it also carries a meta-refresh tag", {
  dir <- withr::local_tempdir()
  file <- file.path(dir, "toy_dashboard.qmd")
  writeLines(c(
    "---", "title: Not actually a stub", "---", "",
    "```{r}", "1 + 1", "```", "",
    '<meta http-equiv="refresh" content="30">'
  ), file)
  expect_false(.cdf_is_redirect_stub(file))
})

test_that(".cdf_is_redirect_stub is FALSE for a normal dashboard page (has chunks, no redirect marker)", {
  dir <- withr::local_tempdir()
  file <- file.path(dir, "toy_dashboard.qmd")
  writeLines(c(
    "---", "title: Real dashboard", "---", "",
    "```{r}", 'a <- tar_read("some_target")', "```"
  ), file)
  expect_false(.cdf_is_redirect_stub(file))
})

# ── .cdf_extract_qmd_targets() ─────────────────────────────────────────────
# End-to-end: knitr::purl() + parse() + .cdf_extract_read_targets(), against
# small synthetic .qmd fixtures under a fixed basename.

test_that(".cdf_extract_qmd_targets returns an empty set for a redirect stub with zero R chunks (drif.qmd-style, #695)", {
  dir <- withr::local_tempdir()
  file <- file.path(dir, "toy_dashboard.qmd")
  writeLines(c(
    "---", "title: Redirect stub", "---", "",
    "> **This page has moved.**", "",
    '<meta http-equiv="refresh" content="0; url=elsewhere.html">'
  ), file)
  expect_equal(.cdf_extract_qmd_targets(file), character(0))
})

test_that(".cdf_extract_qmd_targets returns an empty set for a page with chunks but no tar_read calls (index.qmd-style, #695)", {
  dir <- withr::local_tempdir()
  file <- file.path(dir, "toy_dashboard.qmd")
  writeLines(c(
    "---", "title: Landing page", "---", "",
    "```{r}", "#| label: setup", "x <- 1 + 1", "```"
  ), file)
  expect_equal(.cdf_extract_qmd_targets(file), character(0))
})

test_that(".cdf_extract_qmd_targets extracts a mix of string-literal, symbol, and safe_tar_read forms from real chunks", {
  dir <- withr::local_tempdir()
  file <- file.path(dir, "toy_dashboard.qmd")
  writeLines(c(
    "---", "title: Mixed dashboard", "---", "",
    "```{r}", "#| label: load-a",
    'a <- tar_read("mix_target_a")',
    "```",
    "",
    "```{r}", "#| label: load-b",
    "b <- tar_read(mix_target_b)",
    'c <- safe_tar_read("mix_target_c")',
    "```"
  ), file)
  expect_equal(
    sort(.cdf_extract_qmd_targets(file)),
    c("mix_target_a", "mix_target_b", "mix_target_c")
  )
})

test_that(".cdf_extract_qmd_targets aborts when a chunk fence is present but purl() extracts zero expressions (#695)", {
  dir <- withr::local_tempdir()
  file <- file.path(dir, "toy_dashboard.qmd")
  writeLines(c(
    "---", "title: Comment-only chunk", "---", "",
    "```{r}", "# just a comment, no executable code", "```"
  ), file)
  expect_snapshot(error = TRUE, .cdf_extract_qmd_targets(file))
})

test_that(".cdf_extract_qmd_targets aborts informatively when knitr::purl() itself fails (#695)", {
  dir <- withr::local_tempdir()
  missing_file <- file.path(dir, "toy_dashboard.qmd")
  # Never created -- purl() must fail to open it.
  expect_snapshot(error = TRUE, .cdf_extract_qmd_targets(missing_file))
})

# ── .cdf_extract_include_paths() ────────────────────────────────────────────

test_that(".cdf_extract_include_paths finds the unquoted bare-path form (the one real usage in this repo)", {
  dir <- withr::local_tempdir()
  file <- file.path(dir, "toy_dashboard.qmd")
  writeLines(c(
    "---", "title: Parent", "---", "",
    "{{< include _includes/build-info-footer.qmd >}}"
  ), file)
  expect_equal(.cdf_extract_include_paths(file), "_includes/build-info-footer.qmd")
})

test_that(".cdf_extract_include_paths finds the double-quoted form", {
  dir <- withr::local_tempdir()
  file <- file.path(dir, "toy_dashboard.qmd")
  writeLines(c(
    "---", "title: Parent", "---", "",
    '{{< include "path with space.qmd" >}}'
  ), file)
  expect_equal(.cdf_extract_include_paths(file), "path with space.qmd")
})

test_that(".cdf_extract_include_paths returns character(0) for a page with no include directive", {
  dir <- withr::local_tempdir()
  file <- file.path(dir, "toy_dashboard.qmd")
  writeLines(c("---", "title: Parent", "---", "", "Just prose, no includes."), file)
  expect_equal(.cdf_extract_include_paths(file), character(0))
})

test_that(".cdf_extract_include_paths finds multiple include directives", {
  dir <- withr::local_tempdir()
  file <- file.path(dir, "toy_dashboard.qmd")
  writeLines(c(
    "---", "title: Parent", "---", "",
    "{{< include one.qmd >}}", "", "{{< include two.qmd >}}"
  ), file)
  expect_equal(.cdf_extract_include_paths(file), c("one.qmd", "two.qmd"))
})

# ── .cdf_resolve_include_path() ─────────────────────────────────────────────

test_that(".cdf_resolve_include_path resolves relative to the INCLUDING file's directory, not the cwd", {
  dir <- withr::local_tempdir()
  including <- file.path(dir, "toy_dashboard.qmd")
  writeLines("parent", including)
  target <- file.path(dir, "toy_child.qmd")
  writeLines("child", target)
  resolved <- .cdf_resolve_include_path("toy_child.qmd", including)
  expect_equal(normalizePath(resolved), normalizePath(target))
})

test_that(".cdf_resolve_include_path aborts informatively when the include target does not exist (#695 follow-up)", {
  dir <- withr::local_tempdir()
  including <- file.path(dir, "toy_dashboard.qmd")
  writeLines("parent", including)
  expect_snapshot(error = TRUE, .cdf_resolve_include_path("toy_missing_child.qmd", including))
})

# ── .cdf_extract_qmd_targets() -- {{< include >}} resolution (#695 follow-up) ──
# The gap this closes: knitr::purl() never sees a target file's contents
# through a Quarto include shortcode, so a tar_read() living only inside an
# included file was previously invisible to Check 1/Check 3. These tests use
# FIXED basenames per file (toy_parent.qmd / toy_child.qmd / toy_grandchild.qmd)
# so any future cli_abort() snapshot stays portable (portable-build-artifacts).

test_that(".cdf_extract_qmd_targets sees a tar_read() that lives only inside an included file", {
  dir <- withr::local_tempdir()
  parent <- file.path(dir, "toy_parent.qmd")
  child <- file.path(dir, "toy_child.qmd")
  writeLines(c(
    "---", "title: Parent", "---", "",
    "```{r}", "#| label: parent-chunk", "x <- 1", "```", "",
    "{{< include toy_child.qmd >}}"
  ), parent)
  writeLines(c(
    "```{r}", "#| label: child-chunk",
    'y <- tar_read("included_target")',
    "```"
  ), child)
  expect_equal(.cdf_extract_qmd_targets(parent), "included_target")
})

test_that(".cdf_extract_qmd_targets sees a tar_read() through a NESTED include chain (parent -> child -> grandchild)", {
  dir <- withr::local_tempdir()
  parent <- file.path(dir, "toy_parent.qmd")
  child <- file.path(dir, "toy_child.qmd")
  grandchild <- file.path(dir, "toy_grandchild.qmd")
  writeLines(c("---", "title: Parent", "---", "", "{{< include toy_child.qmd >}}"), parent)
  writeLines(c("{{< include toy_grandchild.qmd >}}"), child)
  writeLines(c(
    "```{r}", "#| label: grandchild-chunk",
    'z <- tar_read("nested_target")',
    "```"
  ), grandchild)
  expect_equal(.cdf_extract_qmd_targets(parent), "nested_target")
})

test_that(".cdf_extract_qmd_targets unions the parent's own targets with its include's targets", {
  dir <- withr::local_tempdir()
  parent <- file.path(dir, "toy_parent.qmd")
  child <- file.path(dir, "toy_child.qmd")
  writeLines(c(
    "---", "title: Parent", "---", "",
    "```{r}", "#| label: parent-chunk",
    'a <- tar_read("parent_target")',
    "```", "",
    "{{< include toy_child.qmd >}}"
  ), parent)
  writeLines(c(
    "```{r}", "#| label: child-chunk",
    'b <- tar_read("child_target")',
    "```"
  ), child)
  expect_equal(
    sort(.cdf_extract_qmd_targets(parent)),
    c("child_target", "parent_target")
  )
})

test_that(".cdf_extract_qmd_targets aborts when a page includes a file that does not exist (#695 follow-up)", {
  dir <- withr::local_tempdir()
  parent <- file.path(dir, "toy_parent.qmd")
  writeLines(c(
    "---", "title: Parent", "---", "",
    "{{< include toy_missing_child.qmd >}}"
  ), parent)
  expect_snapshot(error = TRUE, .cdf_extract_qmd_targets(parent))
})

test_that(".cdf_extract_qmd_targets does not infinite-loop on a circular include graph", {
  dir <- withr::local_tempdir()
  parent <- file.path(dir, "toy_parent.qmd")
  child <- file.path(dir, "toy_child.qmd")
  writeLines(c(
    "---", "title: Parent", "---", "",
    "```{r}", "#| label: parent-chunk",
    'a <- tar_read("parent_target")',
    "```", "",
    "{{< include toy_child.qmd >}}"
  ), parent)
  writeLines(c(
    "```{r}", "#| label: child-chunk",
    'b <- tar_read("child_target")',
    "```", "",
    "{{< include toy_parent.qmd >}}"
  ), child)
  expect_equal(
    sort(.cdf_extract_qmd_targets(parent)),
    c("child_target", "parent_target")
  )
})

# ── .cdf_env_flag_true() ───────────────────────────────────────────────────
# Exists specifically because isTRUE(as.logical(Sys.getenv(...))) is a known
# footgun -- as.logical("1") is NA, not TRUE (.claude/rules/fail-loud-not-null.md).

test_that(".cdf_env_flag_true recognises the documented truthy vocabulary, case-insensitively", {
  withr::local_envvar(c(HD_TEST_FLAG = "1"))
  expect_true(.cdf_env_flag_true("HD_TEST_FLAG"))
  withr::local_envvar(c(HD_TEST_FLAG = "true"))
  expect_true(.cdf_env_flag_true("HD_TEST_FLAG"))
  withr::local_envvar(c(HD_TEST_FLAG = "TRUE"))
  expect_true(.cdf_env_flag_true("HD_TEST_FLAG"))
  withr::local_envvar(c(HD_TEST_FLAG = "YES"))
  expect_true(.cdf_env_flag_true("HD_TEST_FLAG"))
})

test_that(".cdf_env_flag_true is FALSE for unset, empty, or non-truthy values -- crucially including \"1\" is NOT what breaks it", {
  withr::local_envvar(c(HD_TEST_FLAG = NA)) # unset
  expect_false(.cdf_env_flag_true("HD_TEST_FLAG"))
  withr::local_envvar(c(HD_TEST_FLAG = ""))
  expect_false(.cdf_env_flag_true("HD_TEST_FLAG"))
  withr::local_envvar(c(HD_TEST_FLAG = "0"))
  expect_false(.cdf_env_flag_true("HD_TEST_FLAG"))
  withr::local_envvar(c(HD_TEST_FLAG = "no"))
  expect_false(.cdf_env_flag_true("HD_TEST_FLAG"))
})

# ── .cdf_check_dead_references() ───────────────────────────────────────────
# Pure logic, no filesystem/store needed.

test_that(".cdf_check_dead_references flags a page referencing a target absent from the manifest", {
  page_targets <- list("a.qmd" = c("real_target"), "b.qmd" = c("real_target", "ghost_target"))
  manifest_names <- c("real_target", "other_target")
  problems <- .cdf_check_dead_references(page_targets, manifest_names)
  expect_equal(names(problems), "b.qmd")
  expect_equal(problems[["b.qmd"]], "ghost_target")
})

test_that(".cdf_check_dead_references returns an empty list when every reference resolves", {
  page_targets <- list("a.qmd" = c("real_target"))
  manifest_names <- c("real_target", "other_target")
  expect_equal(.cdf_check_dead_references(page_targets, manifest_names), list())
})

# ── .cdf_git_last_commit_time() / .cdf_check_source_staleness() ────────────
# Uses a scratch git repo with explicit GIT_AUTHOR_DATE/GIT_COMMITTER_DATE so
# commit times are reproducible rather than "whenever the test happened to run".

.make_scratch_git_repo <- function(env = parent.frame()) {
  # .local_envir = env (the CALLER's frame, i.e. the test_that() block) is
  # required here: withr::local_tempdir()'s default .local_envir =
  # parent.frame() would otherwise tie cleanup to THIS helper function's own
  # (already-returned) execution frame, deleting the tempdir before the test
  # body ever uses it -- confirmed empirically (every test using this helper
  # failed with "cannot open the connection" until this fix was added).
  dir <- withr::local_tempdir(.local_envir = env)
  system2("git", c("-C", dir, "init", "-q"))
  system2("git", c("-C", dir, "config", "user.email", "test@example.com"))
  system2("git", c("-C", dir, "config", "user.name", "Test"))
  dir
}

.commit_file_at <- function(repo_dir, rel_path, content, iso_date) {
  full_path <- file.path(repo_dir, rel_path)
  writeLines(content, full_path)
  withr::with_envvar(
    c(GIT_AUTHOR_DATE = iso_date, GIT_COMMITTER_DATE = iso_date),
    {
      system2("git", c("-C", repo_dir, "add", rel_path))
      system2("git", c(
        "-C", repo_dir, "commit", "-q", "-m", shQuote(paste("add", rel_path))
      ))
    }
  )
  invisible(full_path)
}

test_that(".cdf_git_last_commit_time reads a committed file's commit time", {
  repo <- .make_scratch_git_repo()
  .commit_file_at(repo, "toy_dashboard.qmd", "content", "2026-01-01T00:00:00")
  t <- .cdf_git_last_commit_time(file.path(repo, "toy_dashboard.qmd"), repo)
  expect_false(is.na(t))
  expect_equal(as.Date(t), as.Date("2026-01-01"))
})

test_that(".cdf_git_last_commit_time returns NA for an untracked path", {
  repo <- .make_scratch_git_repo()
  t <- .cdf_git_last_commit_time(file.path(repo, "never_committed.qmd"), repo)
  expect_true(is.na(t))
})

test_that(".cdf_check_source_staleness flags a page whose .qmd source postdates its .html", {
  repo <- .make_scratch_git_repo()
  .commit_file_at(repo, "toy_dashboard.html", "old render", "2026-01-01T00:00:00")
  .commit_file_at(repo, "toy_dashboard.qmd", "new source", "2026-01-15T00:00:00")
  result <- .cdf_check_source_staleness(file.path(repo, "toy_dashboard.qmd"), repo)
  expect_equal(names(result$stale), "toy_dashboard.qmd")
  expect_equal(result$stale[["toy_dashboard.qmd"]], 14, tolerance = 0.1)
  expect_equal(result$no_html, character(0))
  expect_equal(result$untracked, character(0))
})

test_that(".cdf_check_source_staleness does not flag a page whose .html postdates its .qmd", {
  repo <- .make_scratch_git_repo()
  .commit_file_at(repo, "toy_dashboard.qmd", "source", "2026-01-01T00:00:00")
  .commit_file_at(repo, "toy_dashboard.html", "fresh render", "2026-01-15T00:00:00")
  result <- .cdf_check_source_staleness(file.path(repo, "toy_dashboard.qmd"), repo)
  expect_equal(result$stale, list())
})

test_that(".cdf_check_source_staleness reports a tracked .qmd with no committed .html separately from staleness", {
  repo <- .make_scratch_git_repo()
  .commit_file_at(repo, "toy_dashboard.qmd", "source", "2026-01-01T00:00:00")
  result <- .cdf_check_source_staleness(file.path(repo, "toy_dashboard.qmd"), repo)
  expect_equal(result$stale, list())
  expect_equal(result$no_html, "toy_dashboard.qmd")
})

test_that(".cdf_check_source_staleness reports an untracked .qmd separately from staleness", {
  repo <- .make_scratch_git_repo()
  # Never committed -- git has no history for it.
  writeLines("uncommitted", file.path(repo, "toy_dashboard.qmd"))
  result <- .cdf_check_source_staleness(file.path(repo, "toy_dashboard.qmd"), repo)
  expect_equal(result$stale, list())
  expect_equal(result$untracked, "toy_dashboard.qmd")
})

# ── .cdf_check_source_staleness() -- redirect stub exclusion (#695 follow-up) ──

test_that(".cdf_check_source_staleness excludes a redirect stub from staleness, but names it in excluded_stub", {
  repo <- .make_scratch_git_repo()
  # Same shape as the real drif.qmd/factor-max.qmd/etc: old .html, much
  # newer .qmd -- which would be flagged STALE under the pre-#695 logic.
  .commit_file_at(repo, "toy_dashboard.html", "old render", "2026-01-01T00:00:00")
  stub_content <- c(
    "> **This page has moved.**",
    '<meta http-equiv="refresh" content="0; url=elsewhere.html">'
  )
  .commit_file_at(repo, "toy_dashboard.qmd", stub_content, "2026-01-15T00:00:00")
  result <- .cdf_check_source_staleness(file.path(repo, "toy_dashboard.qmd"), repo)
  expect_equal(result$stale, list())
  expect_equal(result$no_html, character(0))
  expect_equal(result$untracked, character(0))
  expect_equal(result$excluded_stub, "toy_dashboard.qmd")
})

test_that(".cdf_check_source_staleness excludes a stub while still flagging a genuinely stale real page alongside it", {
  repo <- .make_scratch_git_repo()
  .commit_file_at(repo, "toy_stub.html", "old render", "2026-01-01T00:00:00")
  stub_content <- c(
    "> **This page has moved.**",
    '<meta http-equiv="refresh" content="0; url=elsewhere.html">'
  )
  .commit_file_at(repo, "toy_stub.qmd", stub_content, "2026-01-15T00:00:00")

  .commit_file_at(repo, "toy_real.html", "old render", "2026-01-01T00:00:00")
  .commit_file_at(repo, "toy_real.qmd", "```{r}\n1+1\n```", "2026-01-20T00:00:00")

  result <- .cdf_check_source_staleness(
    c(file.path(repo, "toy_stub.qmd"), file.path(repo, "toy_real.qmd")),
    repo
  )
  expect_equal(result$excluded_stub, "toy_stub.qmd")
  expect_equal(names(result$stale), "toy_real.qmd")
})

test_that(".cdf_check_source_staleness does NOT exclude a stale page with no R chunks and no redirect marker (pins the #695 decision)", {
  repo <- .make_scratch_git_repo()
  .commit_file_at(repo, "toy_dashboard.html", "old render", "2026-01-01T00:00:00")
  # No R chunk fence, but also no redirect marker -- must be treated as a
  # normal page, i.e. still reported STALE, not silently excluded.
  .commit_file_at(repo, "toy_dashboard.qmd", "Just prose, no chunks, no redirect.", "2026-01-15T00:00:00")
  result <- .cdf_check_source_staleness(file.path(repo, "toy_dashboard.qmd"), repo)
  expect_equal(result$excluded_stub, character(0))
  expect_equal(names(result$stale), "toy_dashboard.qmd")
  expect_equal(result$stale[["toy_dashboard.qmd"]], 14, tolerance = 0.1)
})

# ── .cdf_page_render_time() ─────────────────────────────────────────────────

test_that(".cdf_page_render_time reads the build_info() footer timestamp when present", {
  repo <- .make_scratch_git_repo()
  html <- paste0(
    "<html><body>Some content ",
    "<strong>Built</strong> 2026-03-04 12:34:56 more text</body></html>"
  )
  .commit_file_at(repo, "toy_dashboard.html", html, "2026-01-01T00:00:00")
  result <- .cdf_page_render_time(file.path(repo, "toy_dashboard.html"), repo)
  expect_equal(result$source, "build_info() footer")
  expect_equal(format(result$time, "%Y-%m-%d %H:%M:%S", tz = Sys.timezone()), "2026-03-04 12:34:56")
})

test_that(".cdf_page_render_time falls back to the .html's git commit date when no footer is present (#695 follow-up)", {
  repo <- .make_scratch_git_repo()
  .commit_file_at(repo, "toy_dashboard.html", "<html><body>no footer here</body></html>", "2026-02-02T00:00:00")
  result <- .cdf_page_render_time(file.path(repo, "toy_dashboard.html"), repo)
  expect_match(result$source, "fallback")
  expect_equal(as.Date(result$time), as.Date("2026-02-02"))
})

test_that(".cdf_page_render_time reports unavailable when there is no footer and no git history", {
  repo <- .make_scratch_git_repo()
  result <- .cdf_page_render_time(file.path(repo, "never_existed.html"), repo)
  expect_true(is.na(result$time))
  expect_match(result$source, "unavailable")
})

# ── .cdf_check_data_staleness() ─────────────────────────────────────────────
# Pure logic against a synthetic meta_time vector -- no store needed.

test_that(".cdf_check_data_staleness flags a page whose own target was rebuilt after its render time", {
  repo <- .make_scratch_git_repo()
  html <- paste0("<html><body><strong>Built</strong> 2026-01-01 00:00:00</body></html>")
  qmd_path <- .commit_file_at(repo, "toy_dashboard.qmd", "source", "2026-01-01T00:00:00")
  .commit_file_at(repo, "toy_dashboard.html", html, "2026-01-01T00:00:00")
  page_targets <- list("toy_dashboard.qmd" = "some_target")
  meta_time <- stats::setNames(
    as.POSIXct("2026-01-05 00:00:00", tz = Sys.timezone()),
    "some_target"
  )
  result <- .cdf_check_data_staleness(qmd_path, page_targets, meta_time, repo)
  expect_equal(names(result), "toy_dashboard.qmd")
  expect_equal(result[["toy_dashboard.qmd"]]$gap_hrs, 96, tolerance = 0.1)
})

test_that(".cdf_check_data_staleness skips pages with no referenced targets", {
  repo <- .make_scratch_git_repo()
  qmd_path <- .commit_file_at(repo, "toy_dashboard.qmd", "source", "2026-01-01T00:00:00")
  page_targets <- list("toy_dashboard.qmd" = character(0))
  meta_time <- stats::setNames(numeric(0), character(0))
  result <- .cdf_check_data_staleness(qmd_path, page_targets, meta_time, repo)
  expect_equal(result, list())
})

test_that(".cdf_check_data_staleness cannot flag a redirect stub: end-to-end, a stub purls to zero targets and is therefore always skipped (#695 follow-up)", {
  # Confirms Check 3 needs NO stub-specific exclusion logic: a stub's own
  # .cdf_extract_qmd_targets() output feeds page_targets, and it is always
  # character(0) (see .cdf_extract_qmd_targets 'redirect stub' test above),
  # which .cdf_check_data_staleness() already `next`s past. This wires the
  # real extractor's output into the check, rather than hand-constructing an
  # empty page_targets entry as the generic test above does.
  dir <- withr::local_tempdir()
  stub_file <- file.path(dir, "toy_stub.qmd")
  writeLines(c(
    "> **This page has moved.**",
    '<meta http-equiv="refresh" content="0; url=elsewhere.html">'
  ), stub_file)
  extracted <- .cdf_extract_qmd_targets(stub_file)
  expect_equal(extracted, character(0))

  repo <- .make_scratch_git_repo()
  qmd_path <- .commit_file_at(repo, "toy_stub.qmd", "stub source", "2026-01-01T00:00:00")
  page_targets <- list("toy_stub.qmd" = extracted)
  # Even a target rebuilt long after any plausible render time cannot matter,
  # because the stub references nothing -- there is no known_refs entry to
  # compare against.
  meta_time <- stats::setNames(as.POSIXct("2099-01-01", tz = Sys.timezone()), "unrelated_target")
  result <- .cdf_check_data_staleness(qmd_path, page_targets, meta_time, repo)
  expect_equal(result, list())
})

test_that(".cdf_check_data_staleness surfaces unknown (never-built) references via note_fn without failing", {
  repo <- .make_scratch_git_repo()
  html <- paste0("<html><body><strong>Built</strong> 2026-01-01 00:00:00</body></html>")
  qmd_path <- .commit_file_at(repo, "toy_dashboard.qmd", "source", "2026-01-01T00:00:00")
  .commit_file_at(repo, "toy_dashboard.html", html, "2026-01-01T00:00:00")
  page_targets <- list("toy_dashboard.qmd" = c("never_built_target"))
  meta_time <- stats::setNames(numeric(0), character(0))
  noted <- list()
  result <- .cdf_check_data_staleness(
    qmd_path, page_targets, meta_time, repo,
    note_fn = function(base, unknown_refs) {
      noted[[base]] <<- unknown_refs
    }
  )
  expect_equal(result, list())
  expect_equal(noted[["toy_dashboard.qmd"]], "never_built_target")
})

# ── Escalation policy (#695 rescope) ────────────────────────────────────────
# Check 2 (source staleness) gets ZERO grace once HD_FAIL_ON_STALE_DASHBOARDS
# is set; Check 3 (data staleness) gets a configurable grace period via
# HD_STALE_DASHBOARD_DATA_THRESHOLD_DAYS (default 14 days). See this file's
# "ESCALATION POLICY" header comment for the full rationale.

test_that(".cdf_check_source_staleness flags a page stale even when the gap is a single hour (zero grace at the detection level, #695 rescope)", {
  # There is no minimum-age parameter to .cdf_check_source_staleness() --
  # unlike Check 3's threshold, ANY positive gap is reported stale. This pins
  # that as a deliberate fact: Check 2 escalation (tested at the .cdf_main()
  # driver level is impractical here -- it needs a real manifest/store, see
  # this file's header comment on why .cdf_main() itself is not unit-tested)
  # has nothing to gate on except "is `stale` non-empty", which this proves
  # is true for even a tiny gap.
  repo <- .make_scratch_git_repo()
  .commit_file_at(repo, "toy_dashboard.html", "old render", "2026-01-01T00:00:00")
  .commit_file_at(repo, "toy_dashboard.qmd", "```{r}\n1+1\n```", "2026-01-01T01:00:00")
  result <- .cdf_check_source_staleness(file.path(repo, "toy_dashboard.qmd"), repo)
  expect_equal(names(result$stale), "toy_dashboard.qmd")
  expect_equal(result$stale[["toy_dashboard.qmd"]], 1 / 24, tolerance = 0.01)
})

test_that(".cdf_data_staleness_threshold_hours defaults to 14 days when the env var is unset", {
  withr::local_envvar(c(HD_STALE_DASHBOARD_DATA_THRESHOLD_DAYS = NA))
  expect_equal(.cdf_data_staleness_threshold_hours(), 14 * 24)
})

test_that(".cdf_data_staleness_threshold_hours honours HD_STALE_DASHBOARD_DATA_THRESHOLD_DAYS when set", {
  withr::local_envvar(c(HD_STALE_DASHBOARD_DATA_THRESHOLD_DAYS = "7"))
  expect_equal(.cdf_data_staleness_threshold_hours(), 7 * 24)
  withr::local_envvar(c(HD_STALE_DASHBOARD_DATA_THRESHOLD_DAYS = "0"))
  expect_equal(.cdf_data_staleness_threshold_hours(), 0)
})

test_that(".cdf_data_staleness_threshold_hours aborts informatively on an unparseable value (#695 rescope, fail-loud-not-null.md)", {
  withr::local_envvar(c(HD_STALE_DASHBOARD_DATA_THRESHOLD_DAYS = "not-a-number"))
  expect_snapshot(error = TRUE, .cdf_data_staleness_threshold_hours())
})

test_that(".cdf_data_staleness_threshold_hours aborts informatively on a negative value", {
  withr::local_envvar(c(HD_STALE_DASHBOARD_DATA_THRESHOLD_DAYS = "-1"))
  expect_snapshot(error = TRUE, .cdf_data_staleness_threshold_hours())
})

test_that(".cdf_data_staleness_over_threshold does not flag a page whose gap is under the threshold", {
  data_stale <- list("toy_dashboard.qmd" = list(gap_hrs = 100, source = "build_info() footer"))
  expect_equal(.cdf_data_staleness_over_threshold(data_stale, threshold_hrs = 14 * 24), character(0))
})

test_that(".cdf_data_staleness_over_threshold flags a page whose gap is over the threshold", {
  data_stale <- list("toy_dashboard.qmd" = list(gap_hrs = 400, source = "build_info() footer"))
  expect_equal(.cdf_data_staleness_over_threshold(data_stale, threshold_hrs = 14 * 24), "toy_dashboard.qmd")
})

test_that(".cdf_data_staleness_over_threshold is a strict >, not >=, at the boundary", {
  data_stale <- list("toy_dashboard.qmd" = list(gap_hrs = 336, source = "build_info() footer"))
  expect_equal(.cdf_data_staleness_over_threshold(data_stale, threshold_hrs = 336), character(0))
  data_stale_over <- list("toy_dashboard.qmd" = list(gap_hrs = 336.1, source = "build_info() footer"))
  expect_equal(.cdf_data_staleness_over_threshold(data_stale_over, threshold_hrs = 336), "toy_dashboard.qmd")
})

test_that(".cdf_data_staleness_over_threshold partitions a mix of under- and over-threshold pages correctly", {
  data_stale <- list(
    "under.qmd" = list(gap_hrs = 45.9, source = "build_info() footer"), # #695's own measured gap
    "over.qmd"  = list(gap_hrs = 1524, source = "build_info() footer") # #695's own measured worst-case gap
  )
  expect_equal(.cdf_data_staleness_over_threshold(data_stale, threshold_hrs = 14 * 24), "over.qmd")
})

# ── Function signature stability (catches API drift, snapshot-test-policy.md) ──

test_that("key .cdf_* function signatures are stable", {
  expect_snapshot(args(.cdf_extract_qmd_targets))
  expect_snapshot(args(.cdf_extract_read_targets))
  expect_snapshot(args(.cdf_extract_include_paths))
  expect_snapshot(args(.cdf_resolve_include_path))
  expect_snapshot(args(.cdf_purl_and_extract))
  expect_snapshot(args(.cdf_check_dead_references))
  expect_snapshot(args(.cdf_is_redirect_stub))
  expect_snapshot(args(.cdf_check_source_staleness))
  expect_snapshot(args(.cdf_check_data_staleness))
  expect_snapshot(args(.cdf_page_render_time))
  expect_snapshot(args(.cdf_git_last_commit_time))
  expect_snapshot(args(.cdf_data_staleness_threshold_hours))
  expect_snapshot(args(.cdf_data_staleness_over_threshold))
  expect_snapshot(args(.cdf_main))
})
