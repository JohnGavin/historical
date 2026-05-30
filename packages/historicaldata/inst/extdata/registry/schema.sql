-- Backtest registry — Phase 1 (#347 PR 1/4)
--
-- DuckDB schema. Two namespaces:
--   bt.* — backtest library (every backtest run + its params/metrics)
--   art.* — artefact registry (vignettes, deploys, dependency DAG)
--
-- Design notes:
--   - Long-form `bt.params` / `bt.metric` / `bt.diagnostic` keeps schema
--     evolution cost low; adding a new metric or diagnostic is a row, not
--     a column.
--   - `schema_version` row tracks applied migrations.
--   - Idempotent: every CREATE is `IF NOT EXISTS`.
--   - Foreign keys are enforced at row insert time by DuckDB (1.0+).

CREATE SCHEMA IF NOT EXISTS bt;
CREATE SCHEMA IF NOT EXISTS art;

-- ─────────────────────────────────────────────────────────────────────
-- bt.* — backtest library
-- ─────────────────────────────────────────────────────────────────────

-- One row per strategy definition. Mirrors `strategy_names` target but
-- carries the keyword columns from #346 plus lifecycle metadata.
CREATE TABLE IF NOT EXISTS bt.strategy (
  strategy_id        VARCHAR PRIMARY KEY,
  short_name         VARCHAR NOT NULL,
  long_name          VARCHAR NOT NULL,
  asset_class        VARCHAR,
  frequency          VARCHAR,
  ann_factor         INTEGER,
  directionality     VARCHAR,
  liquidity_tier     VARCHAR,
  time_horizon_days  INTEGER,
  trades_per_year    DOUBLE,
  turnover_pct       DOUBLE,
  tags               VARCHAR,
  research_paper_doi VARCHAR,
  lifecycle          VARCHAR DEFAULT 'stable',
  superseded_by      VARCHAR,
  created_at         TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- One row per point-in-time eligible asset set.
CREATE TABLE IF NOT EXISTS bt.universe (
  universe_id         VARCHAR PRIMARY KEY,
  description         VARCHAR,
  as_of_date          DATE,
  ticker_count        INTEGER,
  ticker_list         VARCHAR,
  survivorship_biased BOOLEAN,
  created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- One row per transaction-cost assumption.
CREATE TABLE IF NOT EXISTS bt.cost_model (
  cost_model_id   VARCHAR PRIMARY KEY,
  description     VARCHAR,
  slippage_bps    DOUBLE,
  commission_bps  DOUBLE,
  borrow_bps      DOUBLE,
  model_kind      VARCHAR,
  created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- One row per backtest invocation.
CREATE TABLE IF NOT EXISTS bt.run (
  run_uuid         VARCHAR PRIMARY KEY,
  strategy_id      VARCHAR NOT NULL REFERENCES bt.strategy(strategy_id),
  parent_uuid      VARCHAR,
  git_sha          VARCHAR,
  git_dirty        BOOLEAN,
  pipeline_version VARCHAR,
  partition        VARCHAR,
  universe_id      VARCHAR REFERENCES bt.universe(universe_id),
  cost_model_id    VARCHAR REFERENCES bt.cost_model(cost_model_id),
  started_at       TIMESTAMP,
  finished_at      TIMESTAMP,
  duration_sec     DOUBLE,
  status           VARCHAR DEFAULT 'success',
  notes            VARCHAR
);

CREATE INDEX IF NOT EXISTS idx_run_strategy ON bt.run(strategy_id);
CREATE INDEX IF NOT EXISTS idx_run_parent   ON bt.run(parent_uuid);
CREATE INDEX IF NOT EXISTS idx_run_git_sha  ON bt.run(git_sha);

-- Long-form key-value for parameters. One row per (run, param).
CREATE TABLE IF NOT EXISTS bt.params (
  run_uuid         VARCHAR NOT NULL REFERENCES bt.run(run_uuid),
  param_name       VARCHAR NOT NULL,
  param_value_text VARCHAR,
  param_value_num  DOUBLE,
  param_type       VARCHAR,
  PRIMARY KEY (run_uuid, param_name)
);

-- Long-form metrics. Sharpe, CAGR, MDD, etc. as rows.
CREATE TABLE IF NOT EXISTS bt.metric (
  run_uuid     VARCHAR NOT NULL REFERENCES bt.run(run_uuid),
  metric_name  VARCHAR NOT NULL,
  metric_value DOUBLE,
  metric_unit  VARCHAR,
  PRIMARY KEY (run_uuid, metric_name)
);

-- Robustness-layer diagnostics: WFC, PBO, K_eff_strat, deflated Sharpe,
-- max DD duration, loss clustering, etc.
CREATE TABLE IF NOT EXISTS bt.diagnostic (
  run_uuid        VARCHAR NOT NULL REFERENCES bt.run(run_uuid),
  diagnostic_name VARCHAR NOT NULL,
  value_num       DOUBLE,
  value_text      VARCHAR,
  PRIMARY KEY (run_uuid, diagnostic_name)
);

-- Pointers to artefacts the run produced (parquet, plot, target).
CREATE TABLE IF NOT EXISTS bt.output (
  run_uuid    VARCHAR NOT NULL REFERENCES bt.run(run_uuid),
  output_kind VARCHAR NOT NULL,
  path        VARCHAR,
  target_name VARCHAR,
  byte_size   BIGINT,
  -- COALESCE on the nullable cols to allow either path or target_name.
  PRIMARY KEY (run_uuid, output_kind, target_name, path)
);

-- ─────────────────────────────────────────────────────────────────────
-- art.* — artefact registry (vignettes, deploys, dependency DAG)
-- ─────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS art.vignette (
  vignette_id       VARCHAR PRIMARY KEY,
  qmd_path          VARCHAR,
  html_path         VARCHAR,
  url               VARCHAR,
  status            VARCHAR DEFAULT 'published',
  last_rendered_at  TIMESTAMP,
  last_render_sha   VARCHAR,
  render_warnings_n INTEGER DEFAULT 0,
  owner_note        VARCHAR
);

CREATE TABLE IF NOT EXISTS art.diagram (
  diagram_id   VARCHAR PRIMARY KEY,
  vignette_id  VARCHAR NOT NULL REFERENCES art.vignette(vignette_id),
  section      VARCHAR,
  diagram_type VARCHAR,
  target_name  VARCHAR,
  purpose      VARCHAR
);

CREATE TABLE IF NOT EXISTS art.deploy (
  deploy_id    VARCHAR PRIMARY KEY,
  git_sha      VARCHAR,
  built_at     TIMESTAMP,
  status       VARCHAR,
  duration_sec DOUBLE,
  pages_url    VARCHAR
);

CREATE TABLE IF NOT EXISTS art.dependency (
  from_vignette_id VARCHAR NOT NULL REFERENCES art.vignette(vignette_id),
  to_vignette_id   VARCHAR REFERENCES art.vignette(vignette_id),
  via_target_name  VARCHAR,
  kind             VARCHAR,
  PRIMARY KEY (from_vignette_id, to_vignette_id, via_target_name)
);

-- ─────────────────────────────────────────────────────────────────────
-- Schema version metadata
-- ─────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS schema_version (
  version     VARCHAR PRIMARY KEY,
  applied_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  description VARCHAR
);

INSERT INTO schema_version (version, description)
SELECT '1.0.0', 'Phase 1 — bt.* + art.* core tables (#347 PR 1/4)'
WHERE NOT EXISTS (SELECT 1 FROM schema_version WHERE version = '1.0.0');
