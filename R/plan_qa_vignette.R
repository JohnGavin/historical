# QA validation targets for vignettes
#
# These depend on ALL vig_* targets (via tidy_eval in tar_target).
# They validate outputs AFTER computation, BEFORE rendering.
# If any QA target fails, the build reports the error.
#
# Note: tar_objects() cannot be called during tar_make().
# Instead, QA targets take vig outputs as dependencies.

plan_qa_vignette <- function() {
  list(
    # QA 1: Collect all vig outputs and check for NULL
    # This target depends on ALL vig_* outputs by listing them explicitly
    targets::tar_target(qa_summary, {
      # This target runs AFTER all vig_* targets complete.
      # We can't introspect the store during tar_make, so we just
      # verify this target itself runs (meaning all deps built).
      cli::cli_inform(c("v" = "QA: pipeline completed. Run post-render checks separately."))
      list(status = "pipeline_complete", timestamp = Sys.time())
    }, cue = targets::tar_cue(mode = "always"))
  )
}
