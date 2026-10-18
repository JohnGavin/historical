# seed script appends one status row and is idempotent

    Code
      cat(sub("(uuid|parent_uuid): [0-9a-f-]+", "\\1: <uuid>", c(first,
        "--- second run ---", second)), sep = "\n")
    Output
      seed_olmar_status: written=1 skipped=0
        uuid: <uuid> 
        parent_uuid: <uuid> 
      --- second run ---
      seed_olmar_status: written=0 skipped=1
        skipped (status already recorded for this claim)

