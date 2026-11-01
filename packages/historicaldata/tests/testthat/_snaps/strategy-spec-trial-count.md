# legacy 'tested' groups are left out and reported

    Code
      n <- hd_strategy_spec_trial_count(base_dir = d)
    Message
      i 1 entry with deprecated status "tested" not counted as trials (outcome unknown).

# unparseable or missing params fail loud

    Code
      hd_strategy_spec_trial_count(base_dir = d)
    Condition
      Error:
      x Implementation "impl-bad-json" has unparseable params_json.
      i Parser said: lexical error: invalid string in json text.  not json (right here) ------^

---

    Code
      hd_strategy_spec_trial_count(base_dir = d2)
    Condition
      Error:
      x Implementation "impl-na-params" has a missing or empty params_json.
      i The specification trial count cannot tell whether it is a new specification.

# function signature is stable

    Code
      args(hd_strategy_spec_trial_count)
    Output
      function (base_dir = NULL) 
      NULL

