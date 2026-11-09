# build: aborts on a missing entry, an extra entry, and bad series

    Code
      build_strategy_realised_turnover(ok[c("a", "b")], toy_names)
    Condition
      Error in `build_strategy_realised_turnover()`:
      x build_strategy_realised_turnover(): entries and strategy_names disagree.
      i No entry for: "c".
      i Entry for a strategy not in strategy_names: .
      i Every strategy needs a measured series or an explicit na_reason.

---

    Code
      build_strategy_realised_turnover(c(ok, list(zzz = .rt_na_entry("q"))),
      toy_names)
    Condition
      Error in `build_strategy_realised_turnover()`:
      x build_strategy_realised_turnover(): entries and strategy_names disagree.
      i No entry for: .
      i Entry for a strategy not in strategy_names: "zzz".
      i Every strategy needs a measured series or an explicit na_reason.

---

    Code
      build_strategy_realised_turnover(modifyList(ok, list(a = .rt_entry(c(0.1, -0.2),
      "s", FALSE, "n"))), toy_names)
    Condition
      Error in `.rt_summarise()`:
      x "A": turnover must be finite and >= 0, with NA allowed only in the first period.
      i Got 0 NA, 0 non-finite, 1 negative.

---

    Code
      build_strategy_realised_turnover(modifyList(ok, list(a = .rt_entry(c(0.1, NA,
        0.2), "s", FALSE, "n"))), toy_names)
    Condition
      Error in `.rt_summarise()`:
      x "A": turnover must be finite and >= 0, with NA allowed only in the first period.
      i Got 1 NA, 0 non-finite, 0 negative.

---

    Code
      build_strategy_realised_turnover(modifyList(ok, list(a = .rt_entry(c(0.1, 0.2),
      "s", FALSE, "n", drop_leading = 2L))), toy_names)
    Condition
      Error in `.rt_summarise()`:
      x "A": drop_leading (2) leaves no periods out of 2.

---

    Code
      build_strategy_realised_turnover(ok, toy_names[, -1])
    Condition
      Error in `build_strategy_realised_turnover()`:
      x build_strategy_realised_turnover(): strategy_names_tbl lacks column(s) code_name.

# .rt_na_entry refuses a blank reason

    Code
      .rt_na_entry("")
    Condition
      Error in `.rt_na_entry()`:
      x .rt_na_entry(): `reason` must be one non-empty string.
      i A strategy with no measurable turnover must say why (fail-loud-not-null).

---

    Code
      .rt_na_entry(NA_character_)
    Condition
      Error in `.rt_na_entry()`:
      x .rt_na_entry(): `reason` must be one non-empty string.
      i A strategy with no measurable turnover must say why (fail-loud-not-null).

# managed futures with no live month aborts

    Code
      .rt_entry_managed_futures(mf)
    Condition
      Error in `.rt_entry_managed_futures()`:
      x .rt_entry_managed_futures(): no month has a non-zero position.

# gate fails a strategy with neither a value nor a reason

    Code
      check_strategy_realised_turnover(bad, toy_names)
    Condition
      Error in `check_strategy_realised_turnover()`:
      x 1 strategy with neither a measured turnover nor an na_reason: C.
      i A blank NA is forbidden (fail-loud-not-null.md): state why it cannot be measured.

# gate fails a strategy with both a value and a reason

    Code
      check_strategy_realised_turnover(bad, toy_names)
    Condition
      Error in `check_strategy_realised_turnover()`:
      x 1 strategy with BOTH a measured turnover and an na_reason: A.

# gate fails a derived column that disagrees with its definition

    Code
      check_strategy_realised_turnover(bad, toy_names)
    Condition
      Error in `check_strategy_realised_turnover()`:
      x Derived turnover columns disagree with their definitions for: A.
      i annualised = avg x periods_per_year; realised = annualised / 12 / legs.

# gate fails a roster that disagrees with strategy_names

    Code
      check_strategy_realised_turnover(bad, toy_names)
    Condition
      Error in `check_strategy_realised_turnover()`:
      x strategy_realised_turnover and strategy_names disagree.
      i In strategy_names only: B.

# gate fails a missing column

    Code
      check_strategy_realised_turnover(good[, -1], toy_names)
    Condition
      Error in `check_strategy_realised_turnover()`:
      x strategy_realised_turnover is missing 1 required column(s): strategy.
      i check_strategy_realised_turnover() requires strategy, n_periods, avg_turnover_oneway, annualised_turnover_oneway, periods_per_year, legs, turnover_realised, turnover_hand_typed, and na_reason.

