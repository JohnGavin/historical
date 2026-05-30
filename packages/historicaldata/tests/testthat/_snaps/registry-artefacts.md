# check_artefact_registry strict-mode error message

    Code
      check_artefact_registry(s$con, docs_dir = docs, strict = TRUE)
    Condition
      Error in `check_artefact_registry()`:
      ! Artefact registry references 1 missing HTML file:
      x '<docs_dir>/missing-vignette.html'
      i Either re-render the vignette or mark its row as `status = 'draft'` / `status = 'archived'`.

