# hd_rlog_append() aborts on unknown hypothesis status

    Code
      hd_rlog_append("hypotheses", .rlog_status_helper_row("bogus-status"), base_dir = tmp)
    Condition
      Error in `hd_rlog_append()`:
      x Unknown hypothesis status: "bogus-status"
      i Allowed values: "proposed", "testing", "supported", "refuted", "inconclusive-underpowered", "inconclusive-unmeasurable", "withdrawn", and "tested"

# hd_rlog_append() aborts when hypothesis status is NA

    Code
      hd_rlog_append("hypotheses", .rlog_status_helper_row(NA_character_), base_dir = tmp)
    Condition
      Error in `hd_rlog_append()`:
      x status is required for every hypothesis row; it cannot be "NA".
      i Allowed values: "proposed", "testing", "supported", "refuted", "inconclusive-underpowered", "inconclusive-unmeasurable", "withdrawn", and "tested"

# hd_rlog_append() warns on deprecated 'tested' status but still writes

    Code
      suppressMessages(hd_rlog_append("hypotheses", .rlog_status_helper_row("tested"),
      base_dir = tmp))
    Condition
      Warning:
      ! Status "tested" is deprecated and ambiguous -- it does not say what the test concluded.
      i Use one of: "supported", "refuted", "inconclusive-underpowered", and "inconclusive-unmeasurable"

