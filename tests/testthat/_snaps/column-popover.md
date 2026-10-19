# a convention with no glossary entry aborts loudly with a classed error

    Code
      hd_dsr_header_popover("gamma", gl)
    Condition
      Error in `hd_dsr_header_popover()`:
      x DSR convention "gamma" has no entry in the column glossary.
      i Known conventions: "alpha" and "beta".
      i Add it under dsr_pvalue.conventions in 'data/column_glossary.yaml'.

# a column with no convention, or several, or no glossary entry aborts

    Code
      hd_dsr_header_popover(NA_character_, gl)
    Condition
      Error in `hd_dsr_header_popover()`:
      x No hurdle_convention value available for this DSR column.
      i Carry `hd_deflated_sharpe()$hurdle_convention` into the data; the convention is never guessed.

---

    Code
      hd_dsr_header_popover(c("alpha", "beta"), gl)
    Condition
      Error in `hd_dsr_header_popover()`:
      x One DSR column mixes 2 conventions: "alpha" and "beta".
      i Split the column per convention so each header names exactly one.

---

    Code
      hd_dsr_header_popover("alpha", list())
    Condition
      Error in `hd_dsr_header_popover()`:
      x Column glossary has no dsr_pvalue entry with conventions.
      i Add it to 'data/column_glossary.yaml' (#788, #959).

# popover and container builders reject bad input with classed errors

    Code
      hd_popover_span("", "t", "<p>x</p>")
    Condition
      Error in `hd_popover_span()`:
      x `label` must be a single non-empty string.
      i Got "" (class <character>, length 1).

---

    Code
      hd_dt_header_container(c("a", "b"), list(zzz = "<span>x</span>"))
    Condition
      Error in `hd_dt_header_container()`:
      x `html_headers` names columns not in the table: "zzz".

---

    Code
      load_column_glossary(path = "no/such/dir/column_glossary.yaml")
    Condition
      Error in `load_column_glossary()`:
      x Column glossary file not found: 'no/such/dir/column_glossary.yaml'.
      i Expected 'data/column_glossary.yaml' at the repo root (#788).

