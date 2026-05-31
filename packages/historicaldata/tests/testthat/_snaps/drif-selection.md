# non-data-frame predictions throws cli_abort

    Code
      hd_drif_select_topn("not_a_df", make_params(), 2L)
    Condition
      Error in `hd_drif_select_topn()`:
      x `predictions` must be a data frame.
      i Got <character>.

# missing params$factors throws cli_abort

    Code
      hd_drif_select_topn(make_preds(), list(), 2L)
    Condition
      Error in `hd_drif_select_topn()`:
      x `params` must be a list with a factors element.
      i Got <list>.

# non-positive top_n throws cli_abort

    Code
      hd_drif_select_topn(make_preds(), make_params(), 0L)
    Condition
      Error in `hd_drif_select_topn()`:
      x `top_n` must be a positive integer scalar.
      i Got 0.

# hd_drif_select_topn function signature is stable (catches API drift)

    Code
      args(hd_drif_select_topn)
    Output
      function (predictions, params, top_n) 
      NULL

