testthat::local_edition(3)

# .github/workflows/hl-weekly.yml (#1088): the properties that keep it safe, read from the
# file itself. The job cannot be run here; these are the facts a wrong edit would break.

.wf_lines <- function() readLines(here::here(".github", "workflows", "hl-weekly.yml"), warn = FALSE)
.wf <- function() yaml::read_yaml(here::here(".github", "workflows", "hl-weekly.yml"))

test_that("every action is pinned by a full commit SHA", {
  uses <- grep("^\\s*-?\\s*uses:", .wf_lines(), value = TRUE)
  expect_gt(length(uses), 0L)
  expect_true(all(grepl("@[0-9a-f]{40}( #.*)?$", uses)), info = paste(uses, collapse = "\n"))
})

test_that("HF_TOKEN reaches only the preflight comparison and the publish step", {
  steps <- .wf()$jobs$weekly$steps
  has_token <- vapply(steps, function(s) any(grepl("secrets.HF_TOKEN", unlist(s$env), fixed = TRUE)), logical(1))
  names(has_token) <- vapply(steps, function(s) s$name %||% s$uses, "")
  expect_setequal(names(has_token)[has_token],
                  c("Preflight, secrets configured", "Publish to Hugging Face (one commit)"))
  pre <- steps[[which(names(has_token) == "Preflight, secrets configured")]]
  expect_match(pre$env$HAS_HF_TOKEN, "!= ''", fixed = TRUE)          # presence only, never the value
  expect_match(pre$run, "exit 3", fixed = TRUE)                       # not configured is 3, not green
  expect_false(grepl("hf_upload_commit", paste(unlist(lapply(steps[!has_token], function(s) s$run)), collapse = " ")))
})

test_that("the job cannot overlap itself, stays inside the 6 hour limit and keeps a recovery copy", {
  wf <- .wf()
  expect_identical(wf$concurrency$`cancel-in-progress`, FALSE)
  expect_lt(wf$jobs$weekly$timeout_minutes %||% wf$jobs$weekly$`timeout-minutes`, 360)
  art <- Filter(function(s) grepl("upload-artifact", s$uses %||% ""), wf$jobs$weekly$steps)[[1]]
  expect_identical(art$`if`, "always()")
  expect_equal(art$with$`retention-days`, 14)
  # (YAML 1.1 reads the key `on` as TRUE, so the triggers are checked in the text)
  expect_true(any(grepl("^\\s+- cron: '[^']+'$", .wf_lines())))
  expect_true(any(grepl("^\\s+workflow_dispatch:", .wf_lines())))
})

test_that("the steps run in the order that makes the guard and the seed gate mean something", {
  runs <- vapply(.wf()$jobs$weekly$steps, function(s) paste(s$run %||% "", collapse = "\n"), "")
  at <- function(pat) grep(pat, runs)[1]
  expect_lt(at("hl_history_guard.R download"), at("fetch_hyperliquid.R"))
  expect_lt(at("fetch_hyperliquid.R"), at("hl_history_guard.R guard"))
  expect_lt(at("hl_history_guard.R guard"), at("hl_history_guard.R pack"))
  expect_lt(at("hl_history_guard.R pack"), at("hf_upload_commit.sh"))
  expect_match(runs[at("fetch_hyperliquid.R")], "--start=", fixed = TRUE)    # incremental, not from 2023
  expect_false(any(grepl("--resume", runs, fixed = TRUE)))                    # a fresh runner has no progress file
})
