# hd_fundamentals(as_of=) errors loudly on an unparseable as_of (fail-loud-not-null)

    Code
      hd_fundamentals("AAPL", as_of = "not-a-date")
    Condition
      Error in `.hd_fundamentals_coerce_as_of()`:
      x `as_of` could not be coerced to a single Date: "not-a-date".
      i Pass a <Date> or an unambiguous character string, e.g. "2020-01-31".

# hd_fundamentals API stability snapshot

    Code
      names(result)
    Output
      [1] "ticker"         "fiscal_period"  "period_end"     "first_filed"   
      [5] "xbrl_tag"       "original_value" "source"        

---

    Code
      nrow(result)
    Output
      [1] 3

