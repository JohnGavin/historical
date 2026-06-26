# non-data-frame current raises informative error

    Code
      hd_digest_delta("not_a_df", prior = NULL)
    Condition
      Error in `hd_digest_delta()`:
      x `current` must be a data frame.
      i Got <character>.

# missing strategy column raises informative error

    Code
      hd_digest_delta(tibble::tibble(sharpe = 1, period = "Full Period"), prior = NULL)
    Condition
      Error in `hd_digest_delta()`:
      x `current` must contain a `strategy` column.

# attention: correct lines for structural flags

    Code
      attn
    Output
      [1] "[Factor MAX]: Sharpe bootstrap CI now crosses zero"
      [2] "[LTR]: newly classified as redundant"              

# hd_digest_html snapshot stable on fixed input

    Code
      cat(substr(html, 1L, 2000L))
    Output
      <!DOCTYPE html>
      <html lang="en">
      <head>
      <meta charset="utf-8">
      <meta name="color-scheme" content="light">
      <title>Strategy Digest</title>
      <style>
      body{font-family:sans-serif;max-width:960px;margin:1rem auto;color:#1a1a1a;background:#fff}
      table.digest-table{border-collapse:collapse;width:100%;font-size:.875rem}
      table.digest-table th,table.digest-table td{border:1px solid #ccc;padding:4px 8px;text-align:left}
      table.digest-table thead{background:#f5f5f5}
      tr.changed td{background:#fff8e1}
      tr.new td{background:#e8f5e9}
      ul.attention{color:#c0392b}
      </style>
      </head>
      <body>
      <h1>Strategy Digest</h1>
      <p>2 strategies; 1 needs attention.</p>
      <h2>Needs Attention (1 item)</h2>
      <ul class="attention">
      <li>[Factor MAX]: newly flagged for ADD crowding (anomaly-driven demand)</li>
      </ul>
      <h2>Delta Summary</h2>
      <p><strong>2</strong> strategies &mdash; <strong>1</strong> new &mdash; <strong>1</strong> structurally changed.</p>
      <table class="digest-table">
      <thead><tr><th>Strategy</th><th>Status</th><th>&Delta; Sharpe</th><th>&Delta; Net CAGR</th><th>&Delta; Max DD</th><th>Redundant?</th><th>Crowded?</th><th>WFC&Delta;?</th><th>CI&rarr;0?</th><th>DSR flip?</th></tr></thead>
      <tbody>
      <tr class="changed"><td>Factor MAX</td><td>changed</td><td>-0.30</td><td>-3.0%</td><td>-5.0%</td><td></td><td>&#10004;</td><td></td><td></td><td></td></tr>
      <tr class="new"><td>Factor DRIF</td><td>new</td><td>&mdash;</td><td>&mdash;</td><td>&mdash;</td><td></td><td></td><td></td><td></td><td></td></tr>
      </tbody>
      </table>
      </body>
      </html>

# hd_digest_html: function signature is stable

    Code
      args(hd_digest_html)
    Output
      function (delta, attention, caption) 
      NULL

