# hd_strategy_idea_priorities is the single priority vocabulary

    Code
      print(hd_strategy_idea_priorities())
    Output
      # A tibble: 3 x 2
        priority description                                               
        <chr>    <chr>                                                     
      1 low      Parked: named in a source, not worth working on now.      
      2 queued   Worth doing; waiting for a slot, data source or gate.     
      3 active   Being worked on now (a pre-registration is the next step).

# missing source aborts

    Code
      hd_strategy_idea_append(name = "a", economic_claim = "c", priority = "low",
        asset_class = "equity", base_dir = .sl_tmp_dir())
    Condition
      Error in `hd_strategy_idea_append()`:
      x `source` is required: an idea with no origin cannot be audited.
      i Pass a URL or an issue reference.

# unknown priority aborts naming value and allowed set

    Code
      hd_strategy_idea_append(name = "a", economic_claim = "c", source = "s",
        priority = "urgent", asset_class = "equity", base_dir = .sl_tmp_dir())
    Condition
      Error in `hd_strategy_idea_append()`:
      x Unknown idea `priority`: "urgent"
      i Allowed values: "low", "queued", and "active"

# unknown status aborts naming value and allowed set

    Code
      hd_strategy_idea_append(name = "a", economic_claim = "c", source = "s",
        priority = "low", asset_class = "equity", status = "maybe", base_dir = .sl_tmp_dir())
    Condition
      Error in `hd_strategy_idea_append()`:
      x Unknown idea `status`: "maybe"
      i Allowed values: "proposed", "testing", "supported", "refuted", "inconclusive-underpowered", "inconclusive-unmeasurable", and "withdrawn"

# deprecated status 'tested' is refused

    Code
      hd_strategy_idea_append(name = "a", economic_claim = "c", source = "s",
        priority = "low", asset_class = "equity", status = "tested", base_dir = .sl_tmp_dir())
    Condition
      Error in `hd_strategy_idea_append()`:
      x Status "tested" is deprecated and ambiguous; it is refused for new ideas.
      i Use one of: "proposed", "testing", "supported", "refuted", "inconclusive-underpowered", "inconclusive-unmeasurable", and "withdrawn"

# empty name aborts

    Code
      hd_strategy_idea_append(name = "", economic_claim = "c", source = "s",
        priority = "low", asset_class = "equity", base_dir = .sl_tmp_dir())
    Condition
      Error in `hd_strategy_idea_append()`:
      x `name` must be a single non-empty character string.
      i Got "".

# an out-of-vocabulary status already in the log aborts the ledger

    Code
      hd_strategy_ledger(base_dir = d)
    Condition
      Error in `hd_strategy_ledger()`:
      x Hypotheses in the research log have status outside the vocabulary: "maybe"
      i Allowed values: "proposed", "testing", "supported", "refuted", "inconclusive-underpowered", "inconclusive-unmeasurable", "withdrawn", and "tested"

# empty log returns a zero-row ledger with the full column set

    Code
      names(led)
    Output
       [1] "ledger_id"     "name"          "kind"          "stage"        
       [5] "priority"      "latest_status" "n_attempts"    "source"       
       [9] "issue"         "strategy_id"   "last_updated" 

# registry path NULL: research-log part only, reported not silent

    Code
      led <- hd_strategy_ledger(base_dir = d)
    Message
      i No `registry_path`: ledger lists research-log rows only (no live strategies).

# legacy 'tested' entries are not counted but are reported

    Code
      n <- hd_strategy_trial_count(base_dir = d)
    Message
      i 1 entry with deprecated status "tested" not counted as trials (outcome unknown).

# function signatures are stable

    Code
      args(hd_strategy_idea_append)
    Output
      function (name, economic_claim, source, priority, asset_class, 
          issue = NULL, strategy_id = NULL, status = "proposed", parent_uuid = NULL, 
          base_dir = NULL) 
      NULL

---

    Code
      args(hd_strategy_ledger)
    Output
      function (base_dir = NULL, registry_path = NULL) 
      NULL

---

    Code
      args(hd_strategy_ledger_register)
    Output
      function (con, base_dir = NULL) 
      NULL

---

    Code
      args(hd_strategy_trial_count)
    Output
      function (base_dir = NULL) 
      NULL

