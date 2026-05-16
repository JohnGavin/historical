# Date vs POSIXct mismatch snapshot — user-facing warning text

    Code
      withCallingHandlers(probe_pairwise_alignment(reg, read_fn = reader), warning = function(
        w) {
        cat("WARNING:", conditionMessage(w), "\n")
        invokeRestart("muffleWarning")
      })
    Output
      WARNING: ! Date-class mismatch detected for pair "snap_date vs snap_posix".
      i snap_date: Date; snap_posix: POSIXct/POSIXt
      i A Date/POSIXct join produces 0 matching rows silently. Coerce both to `as.Date()` at the producing target. 
      # A tibble: 1 x 4
        pair                    dimension  status evidence                            
        <chr>                   <chr>      <chr>  <chr>                               
      1 snap_date vs snap_posix date_class warn   snap_date: Date; snap_posix: POSIXc~

# probe_pairwise_alignment result snapshot — column names and single-row structure

    Code
      names(result)
    Output
      [1] "pair"      "dimension" "status"    "evidence" 

---

    Code
      result$status
    Output
      [1] "ok"

