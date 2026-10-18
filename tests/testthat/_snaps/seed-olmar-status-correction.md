# correction script appends one row and is idempotent

    Code
      cat(sub("(uuid|parent_uuid): [0-9a-f-]+", "\\1: <uuid>", c(first,
        "--- second run ---", second)), sep = "\n")
    Output
      seed_olmar_status_correction: written=1 skipped=0
        uuid: <uuid> 
        parent_uuid: <uuid> 
      --- second run ---
      seed_olmar_status_correction: written=0 skipped=1
        skipped (correction already recorded for this claim)

