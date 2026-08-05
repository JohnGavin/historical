# check_no_published_validation_reads detects period=="Validation" (no spaces)

    Code
      names(hits)
    Output
      [1] "file" "line" "code"

# qa_no_published_validation_reads scanner function signature is stable (catches API drift)

    Code
      args(check_no_published_validation_reads)
    Output
      function (files) 
      NULL

