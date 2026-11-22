testthat::local_edition(3)

# The Cloudflare Worker (cloudflare/hl-ctx-collector/worker.js) is JavaScript, so its
# tests are node's own (tests/hl_ctx_collector/worker.test.mjs). This file runs them
# from the R suite so one command (scripts/verify.sh) covers them. They use no network:
# `fetch` and the KV binding are stubs fed with recorded replies. Node comes from the
# dev shell (flake.nix). Without it the test is SKIPPED with a message, never passed.

test_that("the Worker's node tests pass (exchange list, key, framing, 429, marker, README hash)", {
  node <- Sys.which("node")
  testthat::skip_if(!nzchar(node), "node is not on PATH (add nodejs to the dev shell in flake.nix)")
  test_file <- here::here("tests", "hl_ctx_collector", "worker.test.mjs")
  expect_true(file.exists(test_file))
  out <- suppressWarnings(system2(node, c("--test", shQuote(test_file)), stdout = TRUE, stderr = TRUE))
  status <- attr(out, "status") %||% 0L
  expect_equal(status, 0L, info = paste(out, collapse = "\n"))
  expect_match(paste(out, collapse = "\n"), "pass 8", fixed = TRUE)   # all 8 ran, none cancelled
  expect_match(paste(out, collapse = "\n"), "fail 0", fixed = TRUE)
})
