package dbmaintenance

import (
	"context"
	"errors"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"

	"ai-server/internal/runtimecfg"
)

const (
	envHashKeyFallback               = "env:config"
	defaultMaintenanceCron           = "15 4 * * *"
	defaultObservabilityCron         = "5 * * * *"
	defaultArchiveCron               = "45 4 * * *"
	defaultCompanyFinancialCron      = "20 * * * *"
	defaultArchiveRetainDays         = 36500
	defaultArchiveBatchSize          = 1000
	defaultArchiveMaxBatches         = 50
	defaultObservabilitySlowMs       = 500
	minObservabilitySlowMs           = 50
	observabilityBaseIntervalMs      = int64(time.Hour / time.Millisecond)
	defaultNightStartHour            = 0
	defaultNightEndHour              = 7
	defaultNightModeMultiplier       = 4
	dbObservabilityDefaultMultiplier = 3
)

var tableMaintenanceProfiles = []tableMaintenanceProfile{
	{
		Table: "ai_content_items",
		Options: map[string]string{
			"autovacuum_vacuum_scale_factor":  "0.02",
			"autovacuum_vacuum_threshold":     "5000",
			"autovacuum_analyze_scale_factor": "0.01",
			"autovacuum_analyze_threshold":    "2000",
		},
	},
	{
		Table: "ai_tags",
		Options: map[string]string{
			"autovacuum_vacuum_scale_factor":  "0.02",
			"autovacuum_vacuum_threshold":     "20",
			"autovacuum_analyze_scale_factor": "0.01",
			"autovacuum_analyze_threshold":    "20",
		},
	},
	{
		Table: "ai_content_processing_jobs",
		Options: map[string]string{
			"autovacuum_vacuum_scale_factor":  "0.05",
			"autovacuum_vacuum_threshold":     "50",
			"autovacuum_analyze_scale_factor": "0.02",
			"autovacuum_analyze_threshold":    "20",
		},
	},
}
var observabilitySettings = []string{
	"shared_preload_libraries",
	"log_min_duration_statement",
	"log_statement",
	"log_lock_waits",
	"deadlock_timeout",
	"track_io_timing",
	"track_functions",
	"pg_stat_statements.max",
	"pg_stat_statements.track",
}

type requiredOperationalIndex struct {
	Name    string
	Table   string
	Purpose string
}

var requiredOperationalIndexes = []requiredOperationalIndex{
	{
		Name:    "idx_ai_rss_author_items_group_v2",
		Table:   "ai_rss_author_items",
		Purpose: "rss_author_default_grouping",
	},
	{
		Name:    "idx_ai_usage_events_openrouter_status_window",
		Table:   "ai_usage_events",
		Purpose: "openrouter_free_model_status_window",
	},
	{
		Name:    "idx_ai_usage_events_translation_quota_window",
		Table:   "ai_usage_events",
		Purpose: "translation_monthly_character_quota",
	},
	{
		Name:    "idx_ai_rss_feeds_enabled_due_order",
		Table:   "ai_rss_feeds",
		Purpose: "rss_due_feed_scan",
	},
	{
		Name:    "idx_ai_content_items_post_source_article_lookup",
		Table:   "ai_content_items",
		Purpose: "post_source_article_lookup",
	},
}

var strictSchemaSteps = []strictSchemaStep{
	countryGDPSchemaStep, globalAssetsSchemaStep, chinaMacroSchemaStep, companyResearchSchemaStep,
	learningSchemaStep,
	peopleDirectorySchemaStep,
	peopleAvatarQualityStep,
	peopleDuanYongpingIdentityStep,
	iosPersonPushDeliverySchemaStep,
	{
		Title: "Create market ingestion tables and indexes",
		SQL: `
CREATE TABLE IF NOT EXISTS ai_market_ticks (
  symbol VARCHAR(32) NOT NULL,
  timestamp_ms BIGINT NOT NULL,
  tick_at TIMESTAMPTZ NOT NULL,
  price NUMERIC(20, 8) NOT NULL,
  volume NUMERIC(20, 4),
  source VARCHAR(32) NOT NULL DEFAULT 'finnhub',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (symbol, timestamp_ms)
);
CREATE INDEX IF NOT EXISTS idx_ai_market_ticks_symbol_time ON ai_market_ticks (symbol, timestamp_ms DESC);
CREATE INDEX IF NOT EXISTS idx_ai_market_ticks_tick_at ON ai_market_ticks (tick_at DESC);
CREATE TABLE IF NOT EXISTS ai_market_candles (
  symbol VARCHAR(32) NOT NULL,
  interval VARCHAR(16) NOT NULL,
  timestamp_ms BIGINT NOT NULL,
  candle_at TIMESTAMPTZ NOT NULL,
  open NUMERIC(20, 8) NOT NULL,
  high NUMERIC(20, 8) NOT NULL,
  low NUMERIC(20, 8) NOT NULL,
  close NUMERIC(20, 8) NOT NULL,
  volume NUMERIC(24, 4),
  source VARCHAR(64) NOT NULL DEFAULT 'unknown',
  first_trade_ms BIGINT,
  last_trade_ms BIGINT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (symbol, interval, timestamp_ms)
);
ALTER TABLE ai_market_candles ADD COLUMN IF NOT EXISTS state VARCHAR(16) NOT NULL DEFAULT 'confirmed';
ALTER TABLE ai_market_candles ADD COLUMN IF NOT EXISTS source_priority INTEGER NOT NULL DEFAULT 0;
ALTER TABLE ai_market_candles ADD COLUMN IF NOT EXISTS provider_timestamp_ms BIGINT;
UPDATE ai_market_candles SET state='invalid', updated_at=NOW()
WHERE state <> 'invalid' AND (
  timestamp_ms > (EXTRACT(EPOCH FROM NOW() + INTERVAL '5 minutes') * 1000)::BIGINT
  OR open <= 0 OR high <= 0 OR low <= 0 OR close <= 0
  OR high < low OR high < open OR high < close OR low > open OR low > close
);
CREATE INDEX IF NOT EXISTS idx_ai_market_candles_symbol_interval_time ON ai_market_candles (symbol, interval, timestamp_ms DESC);
CREATE INDEX IF NOT EXISTS idx_ai_market_candles_daily_high ON ai_market_candles (symbol, high DESC, timestamp_ms ASC) WHERE interval = '1d';
CREATE INDEX IF NOT EXISTS idx_ai_market_candles_daily_low ON ai_market_candles (symbol, low ASC, timestamp_ms ASC) WHERE interval = '1d';
CREATE INDEX IF NOT EXISTS idx_ai_market_candles_candle_at ON ai_market_candles (candle_at DESC);
CREATE TABLE IF NOT EXISTS ai_market_data_gaps (
  symbol VARCHAR(32) NOT NULL,
  interval VARCHAR(16) NOT NULL,
  trading_date DATE NOT NULL,
  start_ms BIGINT NOT NULL,
  end_ms BIGINT NOT NULL,
  status VARCHAR(16) NOT NULL DEFAULT 'open',
  attempts INTEGER NOT NULL DEFAULT 0,
  last_error TEXT,
  detected_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_attempt_at TIMESTAMPTZ,
  repaired_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (symbol, interval, trading_date, start_ms, end_ms)
);
CREATE INDEX IF NOT EXISTS idx_ai_market_data_gaps_status ON ai_market_data_gaps (status, updated_at);
CREATE INDEX IF NOT EXISTS idx_users_like_today_id ON ai_users (is_like DESC, today_count DESC, user_id ASC);
CREATE TABLE IF NOT EXISTS ai_market_ashare_overview_snapshots (
  id BIGSERIAL PRIMARY KEY,
  source VARCHAR(64) NOT NULL DEFAULT 'ashareoverview',
  fetched_at TIMESTAMPTZ NOT NULL,
  up_count INTEGER NOT NULL DEFAULT 0,
  down_count INTEGER NOT NULL DEFAULT 0,
  flat_count INTEGER NOT NULL DEFAULT 0,
  total_count INTEGER NOT NULL DEFAULT 0,
  breadth JSONB NOT NULL DEFAULT '{}'::jsonb,
  hot_sectors JSONB NOT NULL DEFAULT '[]'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE ai_market_ashare_overview_snapshots ADD COLUMN IF NOT EXISTS source VARCHAR(64) NOT NULL DEFAULT 'ashareoverview';
ALTER TABLE ai_market_ashare_overview_snapshots ADD COLUMN IF NOT EXISTS fetched_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
ALTER TABLE ai_market_ashare_overview_snapshots ADD COLUMN IF NOT EXISTS up_count INTEGER NOT NULL DEFAULT 0;
ALTER TABLE ai_market_ashare_overview_snapshots ADD COLUMN IF NOT EXISTS down_count INTEGER NOT NULL DEFAULT 0;
ALTER TABLE ai_market_ashare_overview_snapshots ADD COLUMN IF NOT EXISTS flat_count INTEGER NOT NULL DEFAULT 0;
ALTER TABLE ai_market_ashare_overview_snapshots ADD COLUMN IF NOT EXISTS total_count INTEGER NOT NULL DEFAULT 0;
ALTER TABLE ai_market_ashare_overview_snapshots ADD COLUMN IF NOT EXISTS breadth JSONB NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE ai_market_ashare_overview_snapshots ADD COLUMN IF NOT EXISTS hot_sectors JSONB NOT NULL DEFAULT '[]'::jsonb;
ALTER TABLE ai_market_ashare_overview_snapshots ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
CREATE INDEX IF NOT EXISTS idx_market_ashare_overview_snapshots_fetched_at ON ai_market_ashare_overview_snapshots (fetched_at DESC);
CREATE INDEX IF NOT EXISTS idx_market_ashare_overview_snapshots_created_at ON ai_market_ashare_overview_snapshots (created_at DESC);
		`,
	},
	{
		Title: "Create post daily source counts index concurrently",
		SQL: `CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_ai_content_items_post_daily_source_counts
ON ai_content_items ((COALESCE(published_at, origin_created_at, created_at)), source, category_id)
WHERE content_kind = 'post' AND origin_table = 'post' AND source IS NOT NULL AND source <> '' AND source <> 'weibo'`,
	},
	{
		Title: "Create RSS daily source counts index concurrently",
		SQL: `CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_ai_content_items_post_rss_daily_source_counts
ON ai_content_items (source, (COALESCE(published_at, origin_created_at, created_at)))
WHERE content_kind = 'post' AND origin_table = 'post' AND source LIKE 'rss:%'`,
	},
	{
		Title: "Create content score governance review schema",
		SQL: `
CREATE TABLE IF NOT EXISTS ai_content_score_governance_reviews (
  id BIGSERIAL PRIMARY KEY,
  content_kind VARCHAR(24) NOT NULL,
  source VARCHAR(160) NOT NULL,
  current_min_final_score DOUBLE PRECISION NOT NULL,
  proposed_min_final_score DOUBLE PRECISION NOT NULL,
  action VARCHAR(32) NOT NULL,
  status VARCHAR(32) NOT NULL,
  confidence DOUBLE PRECISION NOT NULL DEFAULT 0,
  reason TEXT NOT NULL DEFAULT '',
  review_window_start TIMESTAMPTZ NOT NULL,
  checked_at TIMESTAMPTZ NOT NULL,
  metrics JSONB NOT NULL DEFAULT '{}'::jsonb,
  samples JSONB NOT NULL DEFAULT '[]'::jsonb,
  evidence JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (content_kind, source)
);
CREATE INDEX IF NOT EXISTS idx_ai_content_score_governance_reviews_action_updated
  ON ai_content_score_governance_reviews (action, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_content_score_governance_reviews_updated
  ON ai_content_score_governance_reviews (updated_at DESC);
		`,
	},
	{
		Title: "Create task run snapshot schema",
		SQL: `
CREATE TABLE IF NOT EXISTS ai_task_run_snapshots (
  id BIGSERIAL PRIMARY KEY,
  run_key VARCHAR(160) NOT NULL UNIQUE,
  task_name VARCHAR(64) NOT NULL,
  flow_key VARCHAR(64),
  label VARCHAR(160),
  state VARCHAR(16) NOT NULL,
  step VARCHAR(64),
  started_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL,
  completed_at TIMESTAMPTZ,
  payload JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE ai_task_run_snapshots ADD COLUMN IF NOT EXISTS flow_key VARCHAR(64);
ALTER TABLE ai_task_run_snapshots ADD COLUMN IF NOT EXISTS label VARCHAR(160);
ALTER TABLE ai_task_run_snapshots ADD COLUMN IF NOT EXISTS step VARCHAR(64);
ALTER TABLE ai_task_run_snapshots ADD COLUMN IF NOT EXISTS payload JSONB NOT NULL DEFAULT '{}'::jsonb;
CREATE INDEX IF NOT EXISTS idx_ai_task_run_snapshots_task_name_updated_at
  ON ai_task_run_snapshots (task_name, updated_at DESC, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_task_run_snapshots_updated_at
  ON ai_task_run_snapshots (updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_task_run_snapshots_state_updated_at
  ON ai_task_run_snapshots (state, updated_at DESC);
		`,
	},
	{
		Title: "Create AI usage event schema",
		SQL: `
CREATE TABLE IF NOT EXISTS ai_usage_events (
  id BIGSERIAL PRIMARY KEY,
  usage_date DATE NOT NULL DEFAULT CURRENT_DATE,
  provider VARCHAR(32) NOT NULL,
  model VARCHAR(128),
  kind VARCHAR(16) NOT NULL DEFAULT 'chat',
  scene VARCHAR(64) NOT NULL DEFAULT 'general',
  status VARCHAR(16) NOT NULL DEFAULT 'ok',
  input_tokens BIGINT NOT NULL DEFAULT 0,
  output_tokens BIGINT NOT NULL DEFAULT 0,
  total_tokens BIGINT NOT NULL DEFAULT 0,
  cost_native NUMERIC(20, 8) NOT NULL DEFAULT 0,
  currency VARCHAR(8) NOT NULL DEFAULT 'CNY',
  fx_rate_to_cny NUMERIC(20, 8) NOT NULL DEFAULT 1,
  cost_cny NUMERIC(20, 8) NOT NULL DEFAULT 0,
  price_input_per_1k NUMERIC(20, 8) NOT NULL DEFAULT 0,
  price_output_per_1k NUMERIC(20, 8) NOT NULL DEFAULT 0,
  request_id TEXT,
  latency_ms INTEGER,
  queue_wait_ms INTEGER,
  post_id BIGINT,
  user_id TEXT,
  raw_usage JSONB,
  meta JSONB,
  error_code VARCHAR(64),
  error_status INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_ai_usage_events_usage_date ON ai_usage_events (usage_date DESC);
CREATE INDEX IF NOT EXISTS idx_ai_usage_events_provider_model_date ON ai_usage_events (provider, model, usage_date DESC);
CREATE INDEX IF NOT EXISTS idx_ai_usage_events_scene_date ON ai_usage_events (scene, usage_date DESC);
CREATE INDEX IF NOT EXISTS idx_ai_usage_events_status_date ON ai_usage_events (status, usage_date DESC);
CREATE INDEX IF NOT EXISTS idx_ai_usage_events_created_at ON ai_usage_events (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_usage_events_post_id ON ai_usage_events (post_id);
CREATE INDEX IF NOT EXISTS idx_ai_usage_events_request_id ON ai_usage_events (request_id);
		`,
	},
	{
		Title: "Create pizza index history schema",
		SQL: `
CREATE TABLE IF NOT EXISTS ai_market_pizza_index_events (
  id BIGSERIAL PRIMARY KEY,
  source VARCHAR(64) NOT NULL DEFAULT 'pizzint.watch',
  available BOOLEAN NOT NULL DEFAULT FALSE,
  overall_index NUMERIC(8, 2),
  defcon_level NUMERIC(6, 2),
  active_spikes NUMERIC(8, 2),
  has_active_spikes BOOLEAN NOT NULL DEFAULT FALSE,
  data_freshness VARCHAR(64),
  source_updated_at TIMESTAMPTZ,
  sampled_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  top_event JSONB,
  recent_events JSONB,
  trend JSONB,
  payload JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE ai_market_pizza_index_events ADD COLUMN IF NOT EXISTS source VARCHAR(64) NOT NULL DEFAULT 'pizzint.watch';
ALTER TABLE ai_market_pizza_index_events ADD COLUMN IF NOT EXISTS available BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE ai_market_pizza_index_events ADD COLUMN IF NOT EXISTS overall_index NUMERIC(8, 2);
ALTER TABLE ai_market_pizza_index_events ADD COLUMN IF NOT EXISTS defcon_level NUMERIC(6, 2);
ALTER TABLE ai_market_pizza_index_events ADD COLUMN IF NOT EXISTS active_spikes NUMERIC(8, 2);
ALTER TABLE ai_market_pizza_index_events ADD COLUMN IF NOT EXISTS has_active_spikes BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE ai_market_pizza_index_events ADD COLUMN IF NOT EXISTS data_freshness VARCHAR(64);
ALTER TABLE ai_market_pizza_index_events ADD COLUMN IF NOT EXISTS source_updated_at TIMESTAMPTZ;
ALTER TABLE ai_market_pizza_index_events ADD COLUMN IF NOT EXISTS sampled_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
ALTER TABLE ai_market_pizza_index_events ADD COLUMN IF NOT EXISTS top_event JSONB;
ALTER TABLE ai_market_pizza_index_events ADD COLUMN IF NOT EXISTS recent_events JSONB;
ALTER TABLE ai_market_pizza_index_events ADD COLUMN IF NOT EXISTS trend JSONB;
ALTER TABLE ai_market_pizza_index_events ADD COLUMN IF NOT EXISTS payload JSONB;
ALTER TABLE ai_market_pizza_index_events ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
ALTER TABLE ai_market_pizza_index_events ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
CREATE UNIQUE INDEX IF NOT EXISTS idx_market_pizza_index_events_source_updated_at
  ON ai_market_pizza_index_events (source, source_updated_at)
  WHERE source_updated_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_market_pizza_index_events_sampled_at
  ON ai_market_pizza_index_events (sampled_at DESC);
CREATE INDEX IF NOT EXISTS idx_market_pizza_index_events_source_updated_at_desc
  ON ai_market_pizza_index_events (source_updated_at DESC);
		`,
	},
	{
		Title:     "Add flash columns to ai_content_items once",
		MarkerKey: "ai-content-flash-columns-v1",
		SQL: `
ALTER TABLE ai_content_items
  ADD COLUMN IF NOT EXISTS source_key TEXT,
  ADD COLUMN IF NOT EXISTS dedupe_key TEXT,
  ADD COLUMN IF NOT EXISTS flash_time TEXT,
  ADD COLUMN IF NOT EXISTS normalized_text TEXT,
  ADD COLUMN IF NOT EXISTS text_hash TEXT,
  ADD COLUMN IF NOT EXISTS is_important BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS category TEXT,
  ADD COLUMN IF NOT EXISTS is_geopolitical BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS geopolitical_score SMALLINT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS geopolitical_entity TEXT,
  ADD COLUMN IF NOT EXISTS geopolitical_action TEXT,
  ADD COLUMN IF NOT EXISTS geopolitical_details JSONB,
  ADD COLUMN IF NOT EXISTS link_url TEXT,
  ADD COLUMN IF NOT EXISTS source_avatar_url TEXT,
  ADD COLUMN IF NOT EXISTS raw_payload JSONB,
  ADD COLUMN IF NOT EXISTS final_score DOUBLE PRECISION
`,
	},
	{
		Title: "Create flash ingestion runtime schema",
		SQL: `
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE SEQUENCE IF NOT EXISTS ai_content_flash_origin_id_seq;
CREATE TABLE IF NOT EXISTS ai_source_article_counts (
  id BIGSERIAL PRIMARY KEY,
  source_key VARCHAR(32) NOT NULL,
  source_label VARCHAR(64) NOT NULL,
  content_type VARCHAR(16) NOT NULL,
  content_id BIGINT NOT NULL,
  content_date DATE NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT ux_ai_source_article_counts_content UNIQUE (content_type, content_id)
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_ai_source_article_counts_content
  ON ai_source_article_counts (content_type, content_id);
CREATE INDEX IF NOT EXISTS idx_source_article_counts_date_source
  ON ai_source_article_counts (content_date, source_key);
CREATE INDEX IF NOT EXISTS idx_ai_content_processing_jobs_type_status_available
  ON ai_content_processing_jobs (job_type, status, available_at ASC, id ASC);
CREATE INDEX IF NOT EXISTS idx_ai_content_processing_jobs_kind_origin
  ON ai_content_processing_jobs (content_kind, origin_id, job_type);
		`,
	},
	{
		Title:     "Initialize flash origin sequence once",
		MarkerKey: "flash-origin-sequence-v1",
		SQL: `
SELECT setval(
  'ai_content_flash_origin_id_seq',
  GREATEST(
    COALESCE((SELECT MAX(origin_id) FROM ai_content_items WHERE content_kind='flash' AND origin_table='flash'), 0),
    COALESCE((SELECT last_value FROM ai_content_flash_origin_id_seq), 0),
    1
  ),
  TRUE
)
`,
	},
	{
		Title: "Create flash source dedupe index concurrently",
		SQL: `CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS ux_ai_content_items_flash_source_dedupe
ON ai_content_items (source_key, dedupe_key)
WHERE content_kind='flash' AND origin_table='flash' AND source_key IS NOT NULL AND dedupe_key IS NOT NULL`,
	},
	{
		Title: "Create native content embedding column",
		SQL: `CREATE EXTENSION IF NOT EXISTS vector;
ALTER TABLE ai_content_items ADD COLUMN IF NOT EXISTS embedding_vector vector(1024);
ALTER TABLE ai_content_items ADD COLUMN IF NOT EXISTS similarity_group_id BIGINT;
ALTER TABLE ai_content_items ADD COLUMN IF NOT EXISTS similarity_score REAL`,
	},
	{
		Title: "Create flash embedding HNSW index concurrently",
		SQL: `CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_ai_content_items_flash_embedding_hnsw
ON ai_content_items USING hnsw (embedding_vector vector_cosine_ops)
WHERE content_kind='flash' AND origin_table='flash' AND embedding_vector IS NOT NULL`,
	},
	{
		Title: "Create flash similarity group index concurrently",
		SQL: `CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_ai_content_items_flash_similarity_group
ON ai_content_items (similarity_group_id, published_at DESC, id DESC)
WHERE content_kind='flash' AND origin_table='flash' AND similarity_group_id IS NOT NULL`,
	},
	flashMarketEventKeyColumnStep,
	flashEventRegroupAuditSchemaStep,
	importantFlashEventIndexStep,
	{
		Title: "Create flash published index concurrently",
		SQL: `CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_ai_content_items_flash_published_created
ON ai_content_items (published_at DESC NULLS LAST, origin_created_at DESC, origin_id DESC)
WHERE content_kind='flash' AND origin_table='flash'`,
	},
	{
		Title: "Create flash source-created index concurrently",
		SQL: `CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_ai_content_items_flash_source_created_latest
ON ai_content_items (source_key, created_at DESC NULLS LAST, origin_id DESC)
WHERE content_kind='flash' AND origin_table='flash'`,
	},
	{
		Title: "Create flash source-published index concurrently",
		SQL: `CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_ai_content_items_flash_source_published_latest
ON ai_content_items (source_key, published_at DESC NULLS LAST, origin_id DESC)
WHERE content_kind='flash' AND origin_table='flash'`,
	},
	{
		Title: "Create flash id-source index concurrently",
		SQL: `CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_ai_content_items_flash_id_source_key
ON ai_content_items (id, source_key)
WHERE content_kind='flash' AND origin_table='flash'`,
	},
	{
		Title: "Create flash search index concurrently",
		SQL: `CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_ai_content_items_flash_search_trgm
ON ai_content_items USING GIN (((COALESCE(text, '') || ' ' || COALESCE(source_item_id, '') || ' ' || COALESCE(source, ''))) gin_trgm_ops)
WHERE content_kind='flash' AND origin_table='flash'`,
	},
	{
		Title: "Create content embedding enqueue trigger",
		SQL: `
CREATE OR REPLACE FUNCTION enqueue_post_embedding_job() RETURNS trigger AS $$
BEGIN
  IF NEW.content_kind = 'post'
     AND NEW.origin_table = 'post'
     AND COALESCE(NEW.embedding, '') = ''
     AND NEW.base_score IS NOT NULL
     AND length(TRIM(CONCAT_WS(' ', NEW.title, NEW.summary, NEW.content_zh, NEW.text, NEW.content))) >= 20 THEN
    INSERT INTO ai_content_processing_jobs (
      content_id, content_kind, origin_id, job_type, source_key, status,
      attempts, available_at, locked_at, last_error, payload, created_at, updated_at
    ) VALUES (
      NEW.id, 'post', NEW.origin_id, 'embedding',
      md5(CONCAT_WS(E'\n', COALESCE(NEW.title, ''), COALESCE(NEW.summary, ''), COALESCE(NEW.content_zh, ''), COALESCE(NEW.text, ''), COALESCE(NEW.content, ''))),
      'pending', 0, NOW(), NULL, NULL,
      jsonb_build_object('source', COALESCE(NEW.source, ''), 'createdAt', NEW.created_at, 'score', COALESCE(NEW.final_score, NEW.base_score, 0)),
      NOW(), NOW()
    )
    ON CONFLICT (content_id, job_type) DO UPDATE
    SET source_key = EXCLUDED.source_key, status = 'pending', attempts = 0,
        available_at = NOW(), locked_at = NULL, last_error = NULL,
        payload = EXCLUDED.payload, updated_at = NOW()
    WHERE ai_content_processing_jobs.status IN ('done', 'skipped', 'dead')
       OR ai_content_processing_jobs.source_key IS DISTINCT FROM EXCLUDED.source_key;
	ELSIF NEW.content_kind = 'flash'
	   AND NEW.origin_table = 'flash'
	   AND NEW.embedding_vector IS NULL
	   AND length(TRIM(CONCAT_WS(' ', NEW.title, NEW.summary, NEW.content_zh, NEW.text, NEW.content))) >= 20 THEN
	  INSERT INTO ai_content_processing_jobs (
	    content_id, content_kind, origin_id, job_type, source_key, status,
	    attempts, available_at, locked_at, last_error, payload, created_at, updated_at
	  ) VALUES (
	    NEW.id, 'flash', NEW.origin_id, 'flash_teacher_embedding',
	    md5(CONCAT_WS(E'\n', COALESCE(NEW.title, ''), COALESCE(NEW.summary, ''), COALESCE(NEW.content_zh, ''), COALESCE(NEW.text, ''), COALESCE(NEW.content, ''))),
	    'pending', 0, NOW(), NULL, NULL,
	    jsonb_build_object('source', COALESCE(NEW.source, ''), 'createdAt', NEW.created_at, 'labelSource', 'flash_live'),
	    NOW(), NOW()
	  )
	  ON CONFLICT (content_id, job_type) DO UPDATE
	  SET source_key = EXCLUDED.source_key, status = 'pending', attempts = 0,
	      available_at = NOW(), locked_at = NULL, last_error = NULL,
	      payload = EXCLUDED.payload, updated_at = NOW()
	  WHERE ai_content_processing_jobs.status IN ('done', 'skipped', 'dead')
	     OR ai_content_processing_jobs.source_key IS DISTINCT FROM EXCLUDED.source_key;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE OR REPLACE TRIGGER trg_enqueue_post_embedding_job
AFTER INSERT OR UPDATE OF final_score, base_score, title, summary, content_zh, text, content, embedding
ON ai_content_items FOR EACH ROW EXECUTE FUNCTION enqueue_post_embedding_job();
		`,
	},
	{
		Title: "Create CNN fear-greed history schema",
		SQL: `
CREATE TABLE IF NOT EXISTS ai_market_cnn_fear_greed_events (
  id BIGSERIAL PRIMARY KEY,
  source VARCHAR(64) NOT NULL DEFAULT 'CNN Fear & Greed',
  available BOOLEAN NOT NULL DEFAULT FALSE,
  stale BOOLEAN NOT NULL DEFAULT FALSE,
  stale_reason VARCHAR(128),
  score NUMERIC(6, 2),
  score_rounded NUMERIC(6, 1),
  rating VARCHAR(32),
  rating_zh VARCHAR(32),
  previous_close NUMERIC(6, 2),
  previous_week NUMERIC(6, 2),
  previous_month NUMERIC(6, 2),
  previous_year NUMERIC(6, 2),
  source_updated_at TIMESTAMPTZ,
  first_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_checked_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_notified_at TIMESTAMPTZ,
  notify_count INTEGER NOT NULL DEFAULT 0,
  payload JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE ai_market_cnn_fear_greed_events ADD COLUMN IF NOT EXISTS source VARCHAR(64) NOT NULL DEFAULT 'CNN Fear & Greed';
ALTER TABLE ai_market_cnn_fear_greed_events ADD COLUMN IF NOT EXISTS available BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE ai_market_cnn_fear_greed_events ADD COLUMN IF NOT EXISTS stale BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE ai_market_cnn_fear_greed_events ADD COLUMN IF NOT EXISTS stale_reason VARCHAR(128);
ALTER TABLE ai_market_cnn_fear_greed_events ADD COLUMN IF NOT EXISTS score NUMERIC(6, 2);
ALTER TABLE ai_market_cnn_fear_greed_events ADD COLUMN IF NOT EXISTS score_rounded NUMERIC(6, 1);
ALTER TABLE ai_market_cnn_fear_greed_events ADD COLUMN IF NOT EXISTS rating VARCHAR(32);
ALTER TABLE ai_market_cnn_fear_greed_events ADD COLUMN IF NOT EXISTS rating_zh VARCHAR(32);
ALTER TABLE ai_market_cnn_fear_greed_events ADD COLUMN IF NOT EXISTS previous_close NUMERIC(6, 2);
ALTER TABLE ai_market_cnn_fear_greed_events ADD COLUMN IF NOT EXISTS previous_week NUMERIC(6, 2);
ALTER TABLE ai_market_cnn_fear_greed_events ADD COLUMN IF NOT EXISTS previous_month NUMERIC(6, 2);
ALTER TABLE ai_market_cnn_fear_greed_events ADD COLUMN IF NOT EXISTS previous_year NUMERIC(6, 2);
ALTER TABLE ai_market_cnn_fear_greed_events ADD COLUMN IF NOT EXISTS source_updated_at TIMESTAMPTZ;
ALTER TABLE ai_market_cnn_fear_greed_events ADD COLUMN IF NOT EXISTS first_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
ALTER TABLE ai_market_cnn_fear_greed_events ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
ALTER TABLE ai_market_cnn_fear_greed_events ADD COLUMN IF NOT EXISTS last_checked_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
ALTER TABLE ai_market_cnn_fear_greed_events ADD COLUMN IF NOT EXISTS last_notified_at TIMESTAMPTZ;
ALTER TABLE ai_market_cnn_fear_greed_events ADD COLUMN IF NOT EXISTS notify_count INTEGER NOT NULL DEFAULT 0;
ALTER TABLE ai_market_cnn_fear_greed_events ADD COLUMN IF NOT EXISTS payload JSONB;
ALTER TABLE ai_market_cnn_fear_greed_events ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
ALTER TABLE ai_market_cnn_fear_greed_events ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
CREATE UNIQUE INDEX IF NOT EXISTS idx_market_cnn_fear_greed_events_source_updated_at ON ai_market_cnn_fear_greed_events (source, source_updated_at);
CREATE INDEX IF NOT EXISTS idx_market_cnn_fear_greed_events_last_checked_at ON ai_market_cnn_fear_greed_events (last_checked_at DESC);
CREATE INDEX IF NOT EXISTS idx_market_cnn_fear_greed_events_source_updated_at_desc ON ai_market_cnn_fear_greed_events (source_updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_market_cnn_fear_greed_events_available_source_last ON ai_market_cnn_fear_greed_events (available, source_updated_at DESC NULLS LAST, last_checked_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_market_cnn_fear_greed_events_score_rounded ON ai_market_cnn_fear_greed_events (score_rounded);
CREATE INDEX IF NOT EXISTS idx_market_cnn_fear_greed_events_rating_zh ON ai_market_cnn_fear_greed_events (rating_zh);
CREATE TABLE IF NOT EXISTS ai_market_cnn_fear_greed_quote_snapshots (
  id BIGSERIAL PRIMARY KEY,
  source VARCHAR(64) NOT NULL DEFAULT 'CNN Fear & Greed',
  source_updated_at TIMESTAMPTZ,
  notified_at TIMESTAMPTZ NOT NULL,
  symbol VARCHAR(32) NOT NULL,
  name VARCHAR(64),
  price NUMERIC(20, 8) NOT NULL,
  quote_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_market_cnn_fear_greed_quote_snapshots_notified ON ai_market_cnn_fear_greed_quote_snapshots (notified_at DESC);
CREATE INDEX IF NOT EXISTS idx_market_cnn_fear_greed_quote_snapshots_symbol_notified ON ai_market_cnn_fear_greed_quote_snapshots (symbol, notified_at DESC);
		`,
	},
	{
		Title: "Create event summary schema",
		SQL: `
CREATE TABLE IF NOT EXISTS ai_people (
  id BIGSERIAL PRIMARY KEY,
  person_key VARCHAR(64) NOT NULL UNIQUE,
  name_zh VARCHAR(128) NOT NULL,
  name_en VARCHAR(128),
  aliases JSONB NOT NULL DEFAULT '[]'::jsonb,
  contextual_aliases JSONB NOT NULL DEFAULT '[]'::jsonb,
  titles JSONB NOT NULL DEFAULT '[]'::jsonb,
  org_keywords JSONB NOT NULL DEFAULT '[]'::jsonb,
  country_codes JSONB NOT NULL DEFAULT '[]'::jsonb,
  avatar_url TEXT,
  avatar_source_url TEXT,
  avatar_thumb_url TEXT,
  avatar_status VARCHAR(16) NOT NULL DEFAULT 'ready',
  avatar_updated_at TIMESTAMPTZ,
  importance INTEGER NOT NULL DEFAULT 0,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE IF NOT EXISTS ai_content_item_people (
  id BIGSERIAL PRIMARY KEY,
  content_id BIGINT NOT NULL REFERENCES ai_content_items(id) ON DELETE CASCADE,
  content_kind VARCHAR(24) NOT NULL,
  origin_id BIGINT NOT NULL,
  person_id BIGINT NOT NULL REFERENCES ai_people(id) ON DELETE CASCADE,
  confidence NUMERIC(4, 3) NOT NULL DEFAULT 0,
  match_type VARCHAR(32) NOT NULL,
  matched_text VARCHAR(255),
  evidence JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (content_id, person_id)
);
CREATE INDEX IF NOT EXISTS idx_ai_content_item_people_kind_origin
  ON ai_content_item_people (content_kind, origin_id);
CREATE TABLE IF NOT EXISTS ai_content_event_clusters (
  id BIGSERIAL PRIMARY KEY,
  cluster_key VARCHAR(64) NOT NULL UNIQUE,
  title TEXT NOT NULL DEFAULT '',
  summary TEXT NOT NULL DEFAULT '',
  representative_text TEXT NOT NULL DEFAULT '',
  topic_keys TEXT NOT NULL DEFAULT '',
  source_keys TEXT NOT NULL DEFAULT '',
  first_post_id BIGINT,
  last_post_id BIGINT,
  first_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  member_count INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE IF NOT EXISTS ai_content_event_members (
  id BIGSERIAL PRIMARY KEY,
  cluster_id BIGINT NOT NULL REFERENCES ai_content_event_clusters(id) ON DELETE CASCADE,
  content_kind VARCHAR(32) NOT NULL DEFAULT 'post',
  content_id BIGINT NOT NULL,
  post_id BIGINT,
  relation VARCHAR(32) NOT NULL DEFAULT 'same_event',
  confidence INTEGER NOT NULL DEFAULT 0,
  reason TEXT,
  source VARCHAR(64),
  article_id TEXT,
  text_hash VARCHAR(64) NOT NULL,
  text TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE IF NOT EXISTS ai_event_roots (
  id BIGSERIAL PRIMARY KEY,
  root_key VARCHAR(96) NOT NULL UNIQUE,
  title TEXT NOT NULL DEFAULT '',
  summary TEXT NOT NULL DEFAULT '',
  topic_keys TEXT NOT NULL DEFAULT '',
  status VARCHAR(32) NOT NULL DEFAULT 'active',
  first_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  node_count INTEGER NOT NULL DEFAULT 0,
  member_count INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE IF NOT EXISTS ai_event_nodes (
  id BIGSERIAL PRIMARY KEY,
  root_id BIGINT NOT NULL REFERENCES ai_event_roots(id) ON DELETE CASCADE,
  parent_id BIGINT REFERENCES ai_event_nodes(id) ON DELETE CASCADE,
  node_key VARCHAR(128) NOT NULL UNIQUE,
  event_cluster_id BIGINT REFERENCES ai_content_event_clusters(id) ON DELETE SET NULL,
  title TEXT NOT NULL DEFAULT '',
  summary TEXT NOT NULL DEFAULT '',
  topic_keys TEXT NOT NULL DEFAULT '',
  event_type VARCHAR(48) NOT NULL DEFAULT 'short_event',
  level INTEGER NOT NULL DEFAULT 0,
  first_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  member_count INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE IF NOT EXISTS ai_event_node_members (
  id BIGSERIAL PRIMARY KEY,
  root_id BIGINT NOT NULL REFERENCES ai_event_roots(id) ON DELETE CASCADE,
  node_id BIGINT NOT NULL REFERENCES ai_event_nodes(id) ON DELETE CASCADE,
  event_cluster_id BIGINT REFERENCES ai_content_event_clusters(id) ON DELETE SET NULL,
  content_kind VARCHAR(32) NOT NULL,
  content_id BIGINT NOT NULL,
  post_id BIGINT,
  relation VARCHAR(32) NOT NULL DEFAULT 'primary',
  confidence INTEGER NOT NULL DEFAULT 0,
  reason TEXT,
  source VARCHAR(64),
  article_id TEXT,
  text_hash VARCHAR(64) NOT NULL,
  text TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT ai_event_node_members_content_unique UNIQUE (content_kind, content_id)
);
CREATE TABLE IF NOT EXISTS ai_event_member_people (
  id BIGSERIAL PRIMARY KEY,
  root_id BIGINT NOT NULL REFERENCES ai_event_roots(id) ON DELETE CASCADE,
  node_id BIGINT NOT NULL REFERENCES ai_event_nodes(id) ON DELETE CASCADE,
  event_cluster_id BIGINT REFERENCES ai_content_event_clusters(id) ON DELETE SET NULL,
  content_kind VARCHAR(32) NOT NULL,
  content_id BIGINT NOT NULL,
  person_id BIGINT REFERENCES ai_people(id) ON DELETE SET NULL,
  person_key VARCHAR(96) NOT NULL,
  person_name TEXT NOT NULL DEFAULT '',
  source VARCHAR(32) NOT NULL DEFAULT 'rule',
  confidence INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT ai_event_member_people_content_unique UNIQUE (content_kind, content_id, person_key)
);
CREATE TABLE IF NOT EXISTS ai_event_node_people (
  id BIGSERIAL PRIMARY KEY,
  root_id BIGINT NOT NULL REFERENCES ai_event_roots(id) ON DELETE CASCADE,
  node_id BIGINT NOT NULL REFERENCES ai_event_nodes(id) ON DELETE CASCADE,
  event_cluster_id BIGINT REFERENCES ai_content_event_clusters(id) ON DELETE SET NULL,
  person_id BIGINT REFERENCES ai_people(id) ON DELETE SET NULL,
  person_key VARCHAR(96) NOT NULL,
  person_name TEXT NOT NULL DEFAULT '',
  mention_count INTEGER NOT NULL DEFAULT 0,
  source_keys TEXT NOT NULL DEFAULT '',
  first_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT ai_event_node_people_unique UNIQUE (node_id, person_key)
);
CREATE TABLE IF NOT EXISTS ai_event_root_people (
  id BIGSERIAL PRIMARY KEY,
  root_id BIGINT NOT NULL REFERENCES ai_event_roots(id) ON DELETE CASCADE,
  person_id BIGINT REFERENCES ai_people(id) ON DELETE SET NULL,
  person_key VARCHAR(96) NOT NULL,
  person_name TEXT NOT NULL DEFAULT '',
  mention_count INTEGER NOT NULL DEFAULT 0,
  source_keys TEXT NOT NULL DEFAULT '',
  first_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT ai_event_root_people_unique UNIQUE (root_id, person_key)
);
CREATE INDEX IF NOT EXISTS idx_content_event_clusters_last_seen ON ai_content_event_clusters (last_seen_at DESC);
DROP INDEX IF EXISTS idx_content_event_clusters_topic_keys;
CREATE INDEX IF NOT EXISTS idx_content_event_clusters_topic_key_array ON ai_content_event_clusters USING GIN ((string_to_array(lower(topic_keys), '|')));
CREATE INDEX IF NOT EXISTS idx_event_roots_last_seen ON ai_event_roots (last_seen_at DESC);
CREATE INDEX IF NOT EXISTS idx_event_roots_status ON ai_event_roots (status, last_seen_at DESC);
CREATE INDEX IF NOT EXISTS idx_event_nodes_root_parent ON ai_event_nodes (root_id, parent_id, level);
CREATE INDEX IF NOT EXISTS idx_event_nodes_parent ON ai_event_nodes (parent_id) WHERE parent_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_event_nodes_root_short_event ON ai_event_nodes (root_id) WHERE event_cluster_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_event_nodes_cluster ON ai_event_nodes (event_cluster_id);
CREATE INDEX IF NOT EXISTS idx_event_nodes_last_seen ON ai_event_nodes (last_seen_at DESC);
CREATE INDEX IF NOT EXISTS idx_event_node_members_root ON ai_event_node_members (root_id);
CREATE INDEX IF NOT EXISTS idx_event_node_members_root_updated ON ai_event_node_members (root_id, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_event_node_members_node ON ai_event_node_members (node_id);
CREATE INDEX IF NOT EXISTS idx_event_node_members_cluster ON ai_event_node_members (event_cluster_id);
CREATE INDEX IF NOT EXISTS idx_event_node_members_kind ON ai_event_node_members (content_kind, content_id);
CREATE INDEX IF NOT EXISTS idx_event_member_people_person ON ai_event_member_people (person_key, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_event_member_people_root ON ai_event_member_people (root_id, person_key);
CREATE INDEX IF NOT EXISTS idx_event_member_people_node ON ai_event_member_people (node_id, person_key);
CREATE INDEX IF NOT EXISTS idx_event_node_people_person ON ai_event_node_people (person_key, mention_count DESC);
CREATE INDEX IF NOT EXISTS idx_event_node_people_node ON ai_event_node_people (node_id, mention_count DESC);
CREATE INDEX IF NOT EXISTS idx_event_root_people_person ON ai_event_root_people (person_key, mention_count DESC);
CREATE INDEX IF NOT EXISTS idx_event_root_people_root ON ai_event_root_people (root_id, mention_count DESC);
CREATE OR REPLACE FUNCTION merge_pipe_keys(left_value TEXT, right_value TEXT)
RETURNS TEXT AS $$
DECLARE
  merged TEXT;
BEGIN
  SELECT COALESCE(string_agg(DISTINCT item.value, '|' ORDER BY item.value), '')
  INTO merged
  FROM regexp_split_to_table(CONCAT_WS('|', left_value, right_value), '\|') AS item(value)
  WHERE item.value <> '';
  RETURN merged;
END;
$$ LANGUAGE plpgsql IMMUTABLE;`,
	},
	{
		Title: "Create person candidate schema",
		SQL: `
CREATE TABLE IF NOT EXISTS ai_people (
				id BIGSERIAL PRIMARY KEY,
				person_key VARCHAR(64) NOT NULL UNIQUE,
				name_zh VARCHAR(128) NOT NULL,
				name_en VARCHAR(128),
				aliases JSONB NOT NULL DEFAULT '[]'::jsonb,
				contextual_aliases JSONB NOT NULL DEFAULT '[]'::jsonb,
				titles JSONB NOT NULL DEFAULT '[]'::jsonb,
				org_keywords JSONB NOT NULL DEFAULT '[]'::jsonb,
				country_codes JSONB NOT NULL DEFAULT '[]'::jsonb,
				avatar_url TEXT,
				avatar_source_url TEXT,
				avatar_thumb_url TEXT,
				avatar_status VARCHAR(16) NOT NULL DEFAULT 'ready',
				avatar_updated_at TIMESTAMPTZ,
				importance INTEGER NOT NULL DEFAULT 0,
				is_active BOOLEAN NOT NULL DEFAULT TRUE,
				sort_order INTEGER NOT NULL DEFAULT 0,
				created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
				updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
			);
CREATE TABLE IF NOT EXISTS ai_content_item_people (
				id BIGSERIAL PRIMARY KEY,
				content_id BIGINT NOT NULL REFERENCES ai_content_items(id) ON DELETE CASCADE,
				content_kind VARCHAR(24) NOT NULL,
				origin_id BIGINT NOT NULL,
				person_id BIGINT NOT NULL REFERENCES ai_people(id) ON DELETE CASCADE,
				confidence NUMERIC(4, 3) NOT NULL DEFAULT 0,
				match_type VARCHAR(32) NOT NULL,
				matched_text VARCHAR(255),
				evidence JSONB,
				created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
				updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
				UNIQUE (content_id, person_id)
			);
CREATE TABLE IF NOT EXISTS ai_person_candidates (
				id BIGSERIAL PRIMARY KEY,
				candidate_key VARCHAR(128) NOT NULL UNIQUE,
			name VARCHAR(128) NOT NULL,
			normalized_name VARCHAR(128) NOT NULL,
			hit_count INTEGER NOT NULL DEFAULT 0,
			title_hints JSONB NOT NULL DEFAULT '[]'::jsonb,
			source_keys JSONB NOT NULL DEFAULT '[]'::jsonb,
			sample_text TEXT,
			sample_content_id BIGINT,
			status VARCHAR(24) NOT NULL DEFAULT 'pending_review',
			avatar_url TEXT,
			avatar_source_url TEXT,
			avatar_thumb_url TEXT,
			avatar_status VARCHAR(16) NOT NULL DEFAULT 'pending',
			avatar_updated_at TIMESTAMPTZ,
			wiki_title VARCHAR(255),
			wiki_lang VARCHAR(16),
			metadata JSONB,
			first_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
			last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
			created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
			updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
		);
CREATE TABLE IF NOT EXISTS ai_content_item_person_candidates (
			id BIGSERIAL PRIMARY KEY,
			content_id BIGINT NOT NULL REFERENCES ai_content_items(id) ON DELETE CASCADE,
			content_kind VARCHAR(24) NOT NULL,
			origin_id BIGINT NOT NULL,
			candidate_id BIGINT NOT NULL REFERENCES ai_person_candidates(id) ON DELETE CASCADE,
			confidence NUMERIC(4, 3) NOT NULL DEFAULT 0,
			match_type VARCHAR(32) NOT NULL,
			matched_text VARCHAR(255),
			evidence JSONB,
			created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
			updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
			UNIQUE (content_id, candidate_id)
		);
CREATE TABLE IF NOT EXISTS ai_content_processing_jobs (
			id BIGSERIAL PRIMARY KEY,
			content_id BIGINT NOT NULL REFERENCES ai_content_items(id) ON DELETE CASCADE,
			content_kind VARCHAR(24) NOT NULL,
			origin_id BIGINT NOT NULL,
			job_type VARCHAR(64) NOT NULL,
			source_key VARCHAR(64) NOT NULL DEFAULT '',
			status VARCHAR(16) NOT NULL DEFAULT 'pending',
			attempts INTEGER NOT NULL DEFAULT 0,
			available_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
			locked_at TIMESTAMPTZ,
			last_error TEXT,
			payload JSONB,
			created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
			updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
			UNIQUE (content_id, job_type)
		);
CREATE INDEX IF NOT EXISTS idx_ai_person_candidates_status_hits ON ai_person_candidates (status, hit_count DESC, last_seen_at DESC);
ALTER TABLE ai_person_candidates ADD COLUMN IF NOT EXISTS sample_content_id BIGINT;
CREATE INDEX IF NOT EXISTS idx_ai_person_candidates_normalized_name ON ai_person_candidates (normalized_name);
CREATE INDEX IF NOT EXISTS idx_ai_person_candidates_avatar_status ON ai_person_candidates (avatar_status, hit_count DESC, last_seen_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_people_sort_order ON ai_people (sort_order ASC, id ASC);
CREATE INDEX IF NOT EXISTS idx_ai_people_active_importance ON ai_people (is_active, importance DESC, sort_order ASC);
CREATE UNIQUE INDEX IF NOT EXISTS ux_ai_content_item_people_content_person ON ai_content_item_people (content_id, person_id);
CREATE INDEX IF NOT EXISTS idx_ai_content_item_people_kind_origin ON ai_content_item_people (content_kind, origin_id);
CREATE INDEX IF NOT EXISTS idx_ai_content_item_people_person_id ON ai_content_item_people (person_id, content_kind, origin_id DESC);
CREATE UNIQUE INDEX IF NOT EXISTS ux_ai_content_item_person_candidates_content_candidate ON ai_content_item_person_candidates (content_id, candidate_id);
CREATE INDEX IF NOT EXISTS idx_ai_content_item_person_candidates_kind_origin ON ai_content_item_person_candidates (content_kind, origin_id);
CREATE INDEX IF NOT EXISTS idx_ai_content_item_person_candidates_candidate ON ai_content_item_person_candidates (candidate_id, content_kind, origin_id DESC);
CREATE INDEX IF NOT EXISTS idx_ai_content_processing_jobs_type_status_available ON ai_content_processing_jobs (job_type, status, available_at ASC, id ASC);
CREATE INDEX IF NOT EXISTS idx_ai_content_processing_jobs_kind_origin ON ai_content_processing_jobs (content_kind, origin_id, job_type);
		`,
	},
	{
		Title:     "Add unified identity columns to event members once",
		MarkerKey: "event-member-identity-columns-v1",
		SQL: `
ALTER TABLE ai_content_event_members
  ADD COLUMN IF NOT EXISTS content_kind VARCHAR(32) NOT NULL DEFAULT 'post',
  ADD COLUMN IF NOT EXISTS content_id BIGINT;
ALTER TABLE ai_content_event_members ALTER COLUMN post_id DROP NOT NULL
`,
	},
	{
		Title:     "Backfill unified event member identity once",
		MarkerKey: "event-member-content-identity-v1",
		SQL: `
UPDATE ai_content_event_members SET content_kind = 'post' WHERE COALESCE(content_kind, '') = '';
UPDATE ai_content_event_members SET content_id = post_id WHERE content_id IS NULL AND post_id IS NOT NULL
`,
	},
	{
		Title:     "Require event member content identity once",
		MarkerKey: "event-member-content-not-null-v1",
		SQL:       `ALTER TABLE ai_content_event_members ALTER COLUMN content_id SET NOT NULL`,
	},
	{
		Title: "Create event member identity index concurrently",
		SQL: `CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS ai_content_event_members_content_unique
ON ai_content_event_members (content_kind, content_id)`,
	},
	{
		Title: "Attach event member identity constraint",
		SQL: `
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.ai_content_event_members'::regclass
      AND conname = 'ai_content_event_members_content_unique'
  ) THEN
    ALTER TABLE ai_content_event_members
      ADD CONSTRAINT ai_content_event_members_content_unique
      UNIQUE USING INDEX ai_content_event_members_content_unique;
  END IF;
END;
$$
`,
	},
	{
		Title: "Create event member cluster index concurrently",
		SQL:   `CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_content_event_members_cluster ON ai_content_event_members (cluster_id)`,
	},
	{
		Title: "Create event member kind index concurrently",
		SQL:   `CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_content_event_members_kind ON ai_content_event_members (content_kind, content_id)`,
	},
	{
		Title: "Create event member post index concurrently",
		SQL:   `CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_content_event_members_post ON ai_content_event_members (post_id)`,
	},
	{
		Title: "Create event member source index concurrently",
		SQL:   `CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_content_event_members_source ON ai_content_event_members (source)`,
	},
	{
		Title: "Create event member hash index concurrently",
		SQL:   `CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_content_event_members_text_hash_cluster ON ai_content_event_members (text_hash, cluster_id)`,
	},
	{
		Title: "Create event member source-article index concurrently",
		SQL: `CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_content_event_members_source_article_cluster
ON ai_content_event_members (source, article_id, cluster_id) WHERE article_id IS NOT NULL AND article_id <> ''`,
	},
	{
		Title: "Create brand and company alias schema",
		SQL: `
CREATE TABLE IF NOT EXISTS ai_brands (
			id BIGSERIAL PRIMARY KEY,
			brand_key VARCHAR(128) NOT NULL UNIQUE,
			company_id INTEGER NOT NULL REFERENCES ai_companies(id) ON DELETE CASCADE,
			name VARCHAR(128) NOT NULL,
			normalized_name VARCHAR(128) NOT NULL,
			brand_type VARCHAR(24) NOT NULL DEFAULT 'brand',
			status VARCHAR(16) NOT NULL DEFAULT 'active',
			confidence NUMERIC(4, 3) NOT NULL DEFAULT 0,
			source VARCHAR(24) NOT NULL DEFAULT 'static',
			sample_content_id BIGINT,
			metadata JSONB,
			first_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
			last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
			created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
			updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
			UNIQUE (company_id, normalized_name)
		);
CREATE TABLE IF NOT EXISTS ai_brand_aliases (
			id BIGSERIAL PRIMARY KEY,
			brand_id BIGINT NOT NULL REFERENCES ai_brands(id) ON DELETE CASCADE,
			alias VARCHAR(128) NOT NULL,
			normalized_alias VARCHAR(128) NOT NULL,
			alias_type VARCHAR(24) NOT NULL DEFAULT 'brand',
			status VARCHAR(16) NOT NULL DEFAULT 'active',
			confidence NUMERIC(4, 3) NOT NULL DEFAULT 0,
			source VARCHAR(24) NOT NULL DEFAULT 'static',
			hit_count INTEGER NOT NULL DEFAULT 1,
			sample_content_id BIGINT,
			metadata JSONB,
			first_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
			last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
			created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
			updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
			UNIQUE (brand_id, normalized_alias)
		);
CREATE TABLE IF NOT EXISTS ai_content_item_brands (
			id BIGSERIAL PRIMARY KEY,
			content_id BIGINT NOT NULL REFERENCES ai_content_items(id) ON DELETE CASCADE,
			content_kind VARCHAR(24) NOT NULL,
			origin_id BIGINT NOT NULL,
			brand_id BIGINT NOT NULL REFERENCES ai_brands(id) ON DELETE CASCADE,
			company_id INTEGER NOT NULL REFERENCES ai_companies(id) ON DELETE CASCADE,
			matched_text VARCHAR(128),
			confidence NUMERIC(4, 3) NOT NULL DEFAULT 0,
			match_type VARCHAR(32) NOT NULL DEFAULT 'brand_alias',
			is_primary BOOLEAN NOT NULL DEFAULT FALSE,
			metadata JSONB,
			created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
			updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
			UNIQUE (content_id, brand_id)
		);
CREATE INDEX IF NOT EXISTS idx_ai_brands_company_id ON ai_brands (company_id, last_seen_at DESC);
ALTER TABLE ai_brands ADD COLUMN IF NOT EXISTS sample_content_id BIGINT;
ALTER TABLE ai_brand_aliases ADD COLUMN IF NOT EXISTS sample_content_id BIGINT;
CREATE INDEX IF NOT EXISTS idx_ai_brands_brand_key ON ai_brands (brand_key);
CREATE UNIQUE INDEX IF NOT EXISTS ux_ai_brands_company_normalized_name ON ai_brands (company_id, normalized_name);
CREATE UNIQUE INDEX IF NOT EXISTS ux_ai_brand_aliases_brand_normalized_alias ON ai_brand_aliases (brand_id, normalized_alias);
CREATE INDEX IF NOT EXISTS idx_ai_brand_aliases_brand_id ON ai_brand_aliases (brand_id, last_seen_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_brand_aliases_alias ON ai_brand_aliases (status, normalized_alias);
CREATE UNIQUE INDEX IF NOT EXISTS ux_ai_content_item_brands_content_brand ON ai_content_item_brands (content_id, brand_id);
CREATE INDEX IF NOT EXISTS idx_ai_content_item_brands_kind_origin ON ai_content_item_brands (content_kind, origin_id, is_primary DESC, id ASC);
CREATE INDEX IF NOT EXISTS idx_ai_content_item_brands_brand_id ON ai_content_item_brands (brand_id, content_kind, origin_id DESC);
CREATE INDEX IF NOT EXISTS idx_ai_content_item_brands_company_id ON ai_content_item_brands (company_id, content_kind, origin_id DESC);
		`,
	},
	{
		Title: "Create API usage and article workspace schema",
		SQL: `
CREATE TABLE IF NOT EXISTS ai_usage_events (
			id BIGSERIAL PRIMARY KEY,
			usage_date DATE NOT NULL DEFAULT CURRENT_DATE,
			provider VARCHAR(32) NOT NULL,
			model VARCHAR(128),
			kind VARCHAR(16) NOT NULL DEFAULT 'chat',
			scene VARCHAR(64) NOT NULL DEFAULT 'general',
			status VARCHAR(16) NOT NULL DEFAULT 'ok',
			input_tokens BIGINT NOT NULL DEFAULT 0,
			output_tokens BIGINT NOT NULL DEFAULT 0,
			total_tokens BIGINT NOT NULL DEFAULT 0,
			cost_native NUMERIC(20, 8) NOT NULL DEFAULT 0,
			currency VARCHAR(8) NOT NULL DEFAULT 'CNY',
			fx_rate_to_cny NUMERIC(20, 8) NOT NULL DEFAULT 1,
			cost_cny NUMERIC(20, 8) NOT NULL DEFAULT 0,
			price_input_per_1k NUMERIC(20, 8) NOT NULL DEFAULT 0,
			price_output_per_1k NUMERIC(20, 8) NOT NULL DEFAULT 0,
			request_id TEXT,
			latency_ms INTEGER,
			queue_wait_ms INTEGER,
			post_id BIGINT,
			user_id TEXT,
			raw_usage JSONB,
			meta JSONB,
			error_code VARCHAR(64),
			error_status INTEGER,
			created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
		);
CREATE INDEX IF NOT EXISTS idx_ai_usage_events_usage_date ON ai_usage_events (usage_date DESC);
CREATE INDEX IF NOT EXISTS idx_ai_usage_events_provider_model_date ON ai_usage_events (provider, model, usage_date DESC);
CREATE INDEX IF NOT EXISTS idx_ai_usage_events_scene_date ON ai_usage_events (scene, usage_date DESC);
CREATE INDEX IF NOT EXISTS idx_ai_usage_events_status_date ON ai_usage_events (status, usage_date DESC);
CREATE INDEX IF NOT EXISTS idx_ai_usage_events_created_at ON ai_usage_events (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_usage_events_post_id ON ai_usage_events (post_id);
CREATE INDEX IF NOT EXISTS idx_ai_usage_events_request_id ON ai_usage_events (request_id);
CREATE TABLE IF NOT EXISTS ai_usage_daily_rollups (
			usage_date DATE NOT NULL,
			provider VARCHAR(32) NOT NULL,
			model VARCHAR(128) NOT NULL DEFAULT '',
			scene VARCHAR(64) NOT NULL,
			status VARCHAR(16) NOT NULL,
			kind VARCHAR(16) NOT NULL,
			events BIGINT NOT NULL DEFAULT 0,
			input_tokens BIGINT NOT NULL DEFAULT 0,
			output_tokens BIGINT NOT NULL DEFAULT 0,
			total_tokens BIGINT NOT NULL DEFAULT 0,
			cost_native NUMERIC(30, 8) NOT NULL DEFAULT 0,
			cost_cny NUMERIC(30, 8) NOT NULL DEFAULT 0,
			updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
			PRIMARY KEY (usage_date, provider, model, scene, status, kind)
		);
CREATE INDEX IF NOT EXISTS idx_ai_usage_daily_rollups_date_provider ON ai_usage_daily_rollups (usage_date DESC, provider, model);
CREATE OR REPLACE FUNCTION upsert_ai_usage_daily_rollup() RETURNS trigger AS $$
BEGIN
	INSERT INTO ai_usage_daily_rollups (
		usage_date, provider, model, scene, status, kind,
		events, input_tokens, output_tokens, total_tokens, cost_native, cost_cny, updated_at
	)
	VALUES (
		NEW.usage_date,
		COALESCE(NULLIF(NEW.provider, ''), 'unknown'),
		COALESCE(NEW.model, ''),
		COALESCE(NULLIF(NEW.scene, ''), 'general'),
		COALESCE(NULLIF(NEW.status, ''), 'ok'),
		COALESCE(NULLIF(NEW.kind, ''), 'chat'),
		1,
		COALESCE(NEW.input_tokens, 0),
		COALESCE(NEW.output_tokens, 0),
		COALESCE(NEW.total_tokens, 0),
		COALESCE(NEW.cost_native, 0),
		COALESCE(NEW.cost_cny, 0),
		NOW()
	)
	ON CONFLICT (usage_date, provider, model, scene, status, kind)
	DO UPDATE SET
		events = ai_usage_daily_rollups.events + EXCLUDED.events,
		input_tokens = ai_usage_daily_rollups.input_tokens + EXCLUDED.input_tokens,
		output_tokens = ai_usage_daily_rollups.output_tokens + EXCLUDED.output_tokens,
		total_tokens = ai_usage_daily_rollups.total_tokens + EXCLUDED.total_tokens,
		cost_native = ai_usage_daily_rollups.cost_native + EXCLUDED.cost_native,
		cost_cny = ai_usage_daily_rollups.cost_cny + EXCLUDED.cost_cny,
		updated_at = NOW();
	RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE OR REPLACE TRIGGER trg_ai_usage_daily_rollup
AFTER INSERT ON ai_usage_events
FOR EACH ROW
EXECUTE FUNCTION upsert_ai_usage_daily_rollup();
CREATE TABLE IF NOT EXISTS ai_article_previews (
  id SERIAL PRIMARY KEY,
  url TEXT NOT NULL UNIQUE,
  host TEXT,
  source VARCHAR(16),
  title TEXT,
  byline TEXT,
  excerpt TEXT,
  site_name TEXT,
  content TEXT,
  text_content TEXT,
  title_zh TEXT,
  excerpt_zh TEXT,
  content_zh TEXT,
  text_content_zh TEXT,
  translated_at TIMESTAMPTZ,
  raw_json JSONB,
  lang VARCHAR(16),
  is_english BOOLEAN,
  length INTEGER,
  fetched_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE IF NOT EXISTS ai_article_studio_generations (
			id BIGSERIAL PRIMARY KEY,
			run_id UUID NOT NULL,
			phase VARCHAR(32) NOT NULL,
			status VARCHAR(32) NOT NULL DEFAULT 'ok',
			article_url TEXT,
			article_title TEXT,
			article_account TEXT,
			style_preset VARCHAR(32),
			voice_preset VARCHAR(32),
			output_format VARCHAR(32),
			requested_scene_count VARCHAR(16),
			requested_image_count VARCHAR(16),
			recommended_scene_count INTEGER,
			recommended_image_count INTEGER,
			generated_image_count INTEGER NOT NULL DEFAULT 0,
			audio_generated BOOLEAN NOT NULL DEFAULT FALSE,
			ai_provider VARCHAR(32),
			ai_model VARCHAR(128),
			total_tokens BIGINT NOT NULL DEFAULT 0,
			estimated_cost_cny NUMERIC(20, 8) NOT NULL DEFAULT 0,
			actual_cost_cny NUMERIC(20, 8) NOT NULL DEFAULT 0,
			article JSONB,
			project JSONB,
			ai JSONB,
			images JSONB,
			audio JSONB,
			cost JSONB,
			errors JSONB,
			meta JSONB,
			created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
		);
ALTER TABLE ai_article_studio_generations ADD COLUMN IF NOT EXISTS run_id UUID;
ALTER TABLE ai_article_studio_generations ADD COLUMN IF NOT EXISTS phase VARCHAR(32) NOT NULL DEFAULT 'unknown';
ALTER TABLE ai_article_studio_generations ADD COLUMN IF NOT EXISTS status VARCHAR(32) NOT NULL DEFAULT 'ok';
ALTER TABLE ai_article_studio_generations ADD COLUMN IF NOT EXISTS article_url TEXT;
ALTER TABLE ai_article_studio_generations ADD COLUMN IF NOT EXISTS article_title TEXT;
ALTER TABLE ai_article_studio_generations ADD COLUMN IF NOT EXISTS article_account TEXT;
ALTER TABLE ai_article_studio_generations ADD COLUMN IF NOT EXISTS style_preset VARCHAR(32);
ALTER TABLE ai_article_studio_generations ADD COLUMN IF NOT EXISTS voice_preset VARCHAR(32);
ALTER TABLE ai_article_studio_generations ADD COLUMN IF NOT EXISTS output_format VARCHAR(32);
ALTER TABLE ai_article_studio_generations ADD COLUMN IF NOT EXISTS requested_scene_count VARCHAR(16);
ALTER TABLE ai_article_studio_generations ADD COLUMN IF NOT EXISTS requested_image_count VARCHAR(16);
ALTER TABLE ai_article_studio_generations ADD COLUMN IF NOT EXISTS recommended_scene_count INTEGER;
ALTER TABLE ai_article_studio_generations ADD COLUMN IF NOT EXISTS recommended_image_count INTEGER;
ALTER TABLE ai_article_studio_generations ADD COLUMN IF NOT EXISTS generated_image_count INTEGER NOT NULL DEFAULT 0;
ALTER TABLE ai_article_studio_generations ADD COLUMN IF NOT EXISTS audio_generated BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE ai_article_studio_generations ADD COLUMN IF NOT EXISTS ai_provider VARCHAR(32);
ALTER TABLE ai_article_studio_generations ADD COLUMN IF NOT EXISTS ai_model VARCHAR(128);
ALTER TABLE ai_article_studio_generations ADD COLUMN IF NOT EXISTS total_tokens BIGINT NOT NULL DEFAULT 0;
ALTER TABLE ai_article_studio_generations ADD COLUMN IF NOT EXISTS estimated_cost_cny NUMERIC(20, 8) NOT NULL DEFAULT 0;
ALTER TABLE ai_article_studio_generations ADD COLUMN IF NOT EXISTS actual_cost_cny NUMERIC(20, 8) NOT NULL DEFAULT 0;
ALTER TABLE ai_article_studio_generations ADD COLUMN IF NOT EXISTS article JSONB;
ALTER TABLE ai_article_studio_generations ADD COLUMN IF NOT EXISTS project JSONB;
ALTER TABLE ai_article_studio_generations ADD COLUMN IF NOT EXISTS ai JSONB;
ALTER TABLE ai_article_studio_generations ADD COLUMN IF NOT EXISTS images JSONB;
ALTER TABLE ai_article_studio_generations ADD COLUMN IF NOT EXISTS audio JSONB;
ALTER TABLE ai_article_studio_generations ADD COLUMN IF NOT EXISTS cost JSONB;
ALTER TABLE ai_article_studio_generations ADD COLUMN IF NOT EXISTS errors JSONB;
ALTER TABLE ai_article_studio_generations ADD COLUMN IF NOT EXISTS meta JSONB;
ALTER TABLE ai_article_studio_generations ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
CREATE INDEX IF NOT EXISTS idx_ai_article_studio_generations_run_id ON ai_article_studio_generations (run_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_article_studio_generations_article_url ON ai_article_studio_generations (article_url);
CREATE INDEX IF NOT EXISTS idx_ai_article_studio_generations_phase_created ON ai_article_studio_generations (phase, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_article_studio_generations_created_at ON ai_article_studio_generations (created_at DESC);
		`,
	},
	{
		Title: "Create API processed-key and duplicate cache schema",
		SQL: `
CREATE TABLE IF NOT EXISTS ai_content_processed_keys (
  source VARCHAR(64) NOT NULL,
  article_id TEXT NOT NULL,
  first_post_id BIGINT,
  last_post_id BIGINT,
  user_id TEXT,
  status VARCHAR(32) NOT NULL DEFAULT 'processed',
  reason TEXT,
  meta JSONB,
  first_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (source, article_id)
);
CREATE TABLE IF NOT EXISTS ai_daily_dingtalk_duplicate_checks (
  date_key TEXT NOT NULL,
  tz TEXT NOT NULL,
  notified_start_at TIMESTAMPTZ NOT NULL,
  notified_end_at TIMESTAMPTZ NOT NULL,
  latest_notified_at TIMESTAMPTZ,
  source_count INTEGER NOT NULL DEFAULT 0,
  duplicate_group_count INTEGER NOT NULL DEFAULT 0,
  duplicate_article_count INTEGER NOT NULL DEFAULT 0,
  payload JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (date_key, tz)
);
		`,
	},
	{
		Title: "Create API feedback audit and person identity schema",
		SQL: `
CREATE TABLE IF NOT EXISTS ai_post_like_guess_audits (
			id BIGSERIAL PRIMARY KEY,
			post_id BIGINT NOT NULL,
			content_kind VARCHAR(32) NOT NULL DEFAULT 'unknown',
			source VARCHAR(128),
			status VARCHAR(32) NOT NULL DEFAULT 'ok',
			provider VARCHAR(32),
			model VARCHAR(128),
			request_id TEXT,
			cached BOOLEAN NOT NULL DEFAULT FALSE,
			force BOOLEAN NOT NULL DEFAULT FALSE,
			prompt_hash VARCHAR(64),
			user_interests TEXT,
			content_snapshot TEXT,
			prompt_snapshot TEXT,
			result JSONB NOT NULL DEFAULT '{}'::jsonb,
			ai_error TEXT,
			created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
		);
CREATE INDEX IF NOT EXISTS idx_post_like_guess_audits_post_id ON ai_post_like_guess_audits (post_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_post_like_guess_audits_created_at ON ai_post_like_guess_audits (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_post_like_guess_audits_status ON ai_post_like_guess_audits (status, created_at DESC);
CREATE TABLE IF NOT EXISTS ai_post_dislike_guess_audits (
			id BIGSERIAL PRIMARY KEY,
			post_id BIGINT NOT NULL,
			content_kind VARCHAR(32) NOT NULL DEFAULT 'unknown',
			source VARCHAR(128),
			status VARCHAR(32) NOT NULL DEFAULT 'ok',
			provider VARCHAR(32),
			model VARCHAR(128),
			request_id TEXT,
			cached BOOLEAN NOT NULL DEFAULT FALSE,
			force BOOLEAN NOT NULL DEFAULT FALSE,
			prompt_hash VARCHAR(64),
			user_interests TEXT,
			content_snapshot TEXT,
			prompt_snapshot TEXT,
			result JSONB NOT NULL DEFAULT '{}'::jsonb,
			ai_error TEXT,
			created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
		);
CREATE INDEX IF NOT EXISTS idx_post_dislike_guess_audits_post_id ON ai_post_dislike_guess_audits (post_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_post_dislike_guess_audits_created_at ON ai_post_dislike_guess_audits (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_post_dislike_guess_audits_status ON ai_post_dislike_guess_audits (status, created_at DESC);
ALTER TABLE ai_post_dislike_guess_audits ADD COLUMN IF NOT EXISTS content_kind VARCHAR(32) NOT NULL DEFAULT 'unknown';
ALTER TABLE ai_post_dislike_guess_audits ADD COLUMN IF NOT EXISTS user_interests TEXT;
ALTER TABLE ai_post_dislike_guess_audits ADD COLUMN IF NOT EXISTS content_snapshot TEXT;
ALTER TABLE ai_post_dislike_guess_audits ADD COLUMN IF NOT EXISTS prompt_snapshot TEXT;
ALTER TABLE ai_post_dislike_guess_audits ADD COLUMN IF NOT EXISTS result JSONB NOT NULL DEFAULT '{}'::jsonb;
CREATE TABLE IF NOT EXISTS ai_person_candidates (
			id BIGSERIAL PRIMARY KEY,
			candidate_key VARCHAR(128) NOT NULL UNIQUE,
			name VARCHAR(128) NOT NULL,
			normalized_name VARCHAR(128) NOT NULL,
			hit_count INTEGER NOT NULL DEFAULT 0,
			title_hints JSONB NOT NULL DEFAULT '[]'::jsonb,
			source_keys JSONB NOT NULL DEFAULT '[]'::jsonb,
			sample_text TEXT,
			sample_content_id BIGINT,
			status VARCHAR(24) NOT NULL DEFAULT 'pending_review',
			avatar_url TEXT,
			avatar_source_url TEXT,
			avatar_thumb_url TEXT,
			avatar_status VARCHAR(16) NOT NULL DEFAULT 'pending',
			avatar_updated_at TIMESTAMPTZ,
			wiki_title VARCHAR(255),
			wiki_lang VARCHAR(16),
			metadata JSONB,
			first_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
			last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
			created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
			updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
		);
ALTER TABLE ai_person_candidates ADD COLUMN IF NOT EXISTS avatar_url TEXT;
ALTER TABLE ai_person_candidates ADD COLUMN IF NOT EXISTS sample_content_id BIGINT;
ALTER TABLE ai_person_candidates ADD COLUMN IF NOT EXISTS avatar_source_url TEXT;
ALTER TABLE ai_person_candidates ADD COLUMN IF NOT EXISTS avatar_thumb_url TEXT;
ALTER TABLE ai_person_candidates ADD COLUMN IF NOT EXISTS avatar_status VARCHAR(16) NOT NULL DEFAULT 'pending';
ALTER TABLE ai_person_candidates ADD COLUMN IF NOT EXISTS avatar_updated_at TIMESTAMPTZ;
ALTER TABLE ai_person_candidates ADD COLUMN IF NOT EXISTS wiki_title VARCHAR(255);
ALTER TABLE ai_person_candidates ADD COLUMN IF NOT EXISTS wiki_lang VARCHAR(16);
CREATE TABLE IF NOT EXISTS ai_person_identity_resolutions (
			id BIGSERIAL PRIMARY KEY,
			candidate_key VARCHAR(128) UNIQUE,
			normalized_name VARCHAR(128) NOT NULL UNIQUE,
			canonical_name VARCHAR(128) NOT NULL,
			qid VARCHAR(32),
			wiki_title VARCHAR(255),
			wiki_lang VARCHAR(16),
			avatar_source_type VARCHAR(24) NOT NULL DEFAULT 'manual',
			avatar_url TEXT,
			avatar_thumb_url TEXT,
			source_url TEXT,
			status VARCHAR(16) NOT NULL DEFAULT 'ready',
			notes TEXT,
			verified_by VARCHAR(64),
			created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
			updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
		);
CREATE INDEX IF NOT EXISTS idx_ai_person_candidates_status_hits ON ai_person_candidates (status, hit_count DESC, last_seen_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_person_candidates_normalized_name ON ai_person_candidates (normalized_name);
CREATE INDEX IF NOT EXISTS idx_ai_person_candidates_avatar_status ON ai_person_candidates (avatar_status, hit_count DESC, last_seen_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_person_identity_resolutions_status_name ON ai_person_identity_resolutions (status, normalized_name);
CREATE INDEX IF NOT EXISTS idx_ai_person_identity_resolutions_qid ON ai_person_identity_resolutions (qid);
		`,
	},
	{
		Title: "Create Weibo hot topic schema",
		SQL: `

		`,
	},
	{
		Title: "Create Douyin hot topic schema",
		SQL: `
CREATE TABLE IF NOT EXISTS ai_douyin_hot_topics (
			id BIGSERIAL PRIMARY KEY,
			topic_key VARCHAR(96) NOT NULL UNIQUE,
			keyword VARCHAR(255) NOT NULL,
			normalized_keyword VARCHAR(255) NOT NULL,
			source_topic_id VARCHAR(128),
			search_link TEXT,
			source VARCHAR(64) NOT NULL DEFAULT 'douyin.creator.cookie',
			is_active BOOLEAN NOT NULL DEFAULT TRUE,
			first_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
			last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
			latest_snapshot_at TIMESTAMPTZ,
			latest_rank INTEGER,
			previous_rank INTEGER,
			rank_change INTEGER,
			best_rank INTEGER,
			latest_heat BIGINT,
			primary_category VARCHAR(32),
			sentiment_label VARCHAR(24),
			sentiment_score NUMERIC(6, 3),
			risk_level VARCHAR(16),
			summary TEXT,
			reason TEXT,
			meta JSONB,
			created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
			updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
		);
CREATE TABLE IF NOT EXISTS ai_douyin_hot_snapshots (
			id BIGSERIAL PRIMARY KEY,
			topic_id BIGINT NOT NULL REFERENCES ai_douyin_hot_topics(id) ON DELETE CASCADE,
			snapshot_at TIMESTAMPTZ NOT NULL,
			rank INTEGER NOT NULL,
			title VARCHAR(255) NOT NULL,
			heat BIGINT,
			search_link TEXT,
			payload JSONB,
			created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
		);
ALTER TABLE ai_douyin_hot_topics ADD COLUMN IF NOT EXISTS topic_key VARCHAR(96);
ALTER TABLE ai_douyin_hot_topics ADD COLUMN IF NOT EXISTS keyword VARCHAR(255);
ALTER TABLE ai_douyin_hot_topics ADD COLUMN IF NOT EXISTS normalized_keyword VARCHAR(255);
ALTER TABLE ai_douyin_hot_topics ADD COLUMN IF NOT EXISTS source_topic_id VARCHAR(128);
ALTER TABLE ai_douyin_hot_topics ADD COLUMN IF NOT EXISTS search_link TEXT;
ALTER TABLE ai_douyin_hot_topics ADD COLUMN IF NOT EXISTS source VARCHAR(64) NOT NULL DEFAULT 'douyin.creator.cookie';
ALTER TABLE ai_douyin_hot_topics ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE ai_douyin_hot_topics ADD COLUMN IF NOT EXISTS first_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
ALTER TABLE ai_douyin_hot_topics ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
ALTER TABLE ai_douyin_hot_topics ADD COLUMN IF NOT EXISTS latest_snapshot_at TIMESTAMPTZ;
ALTER TABLE ai_douyin_hot_topics ADD COLUMN IF NOT EXISTS latest_rank INTEGER;
ALTER TABLE ai_douyin_hot_topics ADD COLUMN IF NOT EXISTS previous_rank INTEGER;
ALTER TABLE ai_douyin_hot_topics ADD COLUMN IF NOT EXISTS rank_change INTEGER;
ALTER TABLE ai_douyin_hot_topics ADD COLUMN IF NOT EXISTS best_rank INTEGER;
ALTER TABLE ai_douyin_hot_topics ADD COLUMN IF NOT EXISTS latest_heat BIGINT;
ALTER TABLE ai_douyin_hot_topics ADD COLUMN IF NOT EXISTS primary_category VARCHAR(32);
ALTER TABLE ai_douyin_hot_topics ADD COLUMN IF NOT EXISTS sentiment_label VARCHAR(24);
ALTER TABLE ai_douyin_hot_topics ADD COLUMN IF NOT EXISTS sentiment_score NUMERIC(6, 3);
ALTER TABLE ai_douyin_hot_topics ADD COLUMN IF NOT EXISTS risk_level VARCHAR(16);
ALTER TABLE ai_douyin_hot_topics ADD COLUMN IF NOT EXISTS summary TEXT;
ALTER TABLE ai_douyin_hot_topics ADD COLUMN IF NOT EXISTS reason TEXT;
ALTER TABLE ai_douyin_hot_topics ADD COLUMN IF NOT EXISTS meta JSONB;
ALTER TABLE ai_douyin_hot_topics ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
ALTER TABLE ai_douyin_hot_topics ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
ALTER TABLE ai_douyin_hot_snapshots ADD COLUMN IF NOT EXISTS topic_id BIGINT;
ALTER TABLE ai_douyin_hot_snapshots ADD COLUMN IF NOT EXISTS snapshot_at TIMESTAMPTZ;
ALTER TABLE ai_douyin_hot_snapshots ADD COLUMN IF NOT EXISTS rank INTEGER;
ALTER TABLE ai_douyin_hot_snapshots ADD COLUMN IF NOT EXISTS title VARCHAR(255);
ALTER TABLE ai_douyin_hot_snapshots ADD COLUMN IF NOT EXISTS heat BIGINT;
ALTER TABLE ai_douyin_hot_snapshots ADD COLUMN IF NOT EXISTS search_link TEXT;
ALTER TABLE ai_douyin_hot_snapshots ADD COLUMN IF NOT EXISTS payload JSONB;
ALTER TABLE ai_douyin_hot_snapshots ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
CREATE UNIQUE INDEX IF NOT EXISTS idx_ai_douyin_hot_topics_topic_key ON ai_douyin_hot_topics (topic_key);
CREATE INDEX IF NOT EXISTS idx_ai_douyin_hot_topics_active_rank ON ai_douyin_hot_topics (is_active, latest_rank ASC, id DESC);
CREATE INDEX IF NOT EXISTS idx_ai_douyin_hot_topics_latest_snapshot_at ON ai_douyin_hot_topics (latest_snapshot_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_douyin_hot_topics_primary_category ON ai_douyin_hot_topics (primary_category, latest_rank ASC);
CREATE INDEX IF NOT EXISTS idx_ai_douyin_hot_topics_sentiment ON ai_douyin_hot_topics (risk_level, sentiment_label, latest_rank);
CREATE INDEX IF NOT EXISTS idx_ai_douyin_hot_topics_latest_heat ON ai_douyin_hot_topics (latest_heat DESC, latest_rank ASC);
CREATE INDEX IF NOT EXISTS idx_ai_douyin_hot_snapshots_topic_time ON ai_douyin_hot_snapshots (topic_id, snapshot_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_douyin_hot_snapshots_snapshot_time ON ai_douyin_hot_snapshots (snapshot_at DESC, rank ASC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_ai_douyin_hot_snapshots_topic_snapshot_rank ON ai_douyin_hot_snapshots (topic_id, snapshot_at);
		`,
	},
	{
		Title: "Create post search notification functions and triggers",
		SQL: `
CREATE OR REPLACE FUNCTION ai_post_search_index_notify_content()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.content_kind = 'post' AND OLD.origin_table = 'post' THEN
      PERFORM pg_notify('ai_post_search_index', 'delete:' || OLD.origin_id::text);
    END IF;
    RETURN OLD;
  END IF;
  IF NEW.content_kind = 'post' AND NEW.origin_table = 'post' THEN
    PERFORM pg_notify('ai_post_search_index', 'upsert:' || NEW.origin_id::text);
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER ai_post_search_index_notify_content
AFTER INSERT OR UPDATE OF
  source, article_id, author_id, published_at, origin_created_at, origin_updated_at,
  updated_at, base_score, final_score, is_like, category_id, company_id, title,
  summary, content_zh, content, text, embedding, meta, videos
OR DELETE ON ai_content_items
FOR EACH ROW
EXECUTE FUNCTION ai_post_search_index_notify_content();

CREATE OR REPLACE FUNCTION ai_post_search_index_notify_tags()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  target_post_id bigint;
BEGIN
  target_post_id := COALESCE(NEW.post_id, OLD.post_id);
  IF target_post_id IS NOT NULL THEN
    PERFORM pg_notify('ai_post_search_index', 'upsert:' || target_post_id::text);
  END IF;
  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER ai_post_search_index_notify_tags
AFTER INSERT OR UPDATE OR DELETE ON post_tags
FOR EACH ROW
EXECUTE FUNCTION ai_post_search_index_notify_tags();`,
	},
	{
		Title: "Create curated post-person relation matcher",
		SQL: `
    INSERT INTO ai_person_candidates (
      candidate_key, name, normalized_name, hit_count, title_hints, source_keys,
      status, metadata, first_seen_at, last_seen_at, created_at, updated_at
    )
    SELECT
      'curated-person:' || md5(lower(alias)), alias, lower(alias), 0,
      '[]'::jsonb, '["post"]'::jsonb, 'ready',
      jsonb_build_object('curated_post_person', true),
      NOW(), NOW(), NOW(), NOW()
    FROM unnest(ARRAY[
      '奥特曼', 'Sam Altman', '阿莫迪', 'Dario Amodei',
      '哈萨比斯', 'Demis Hassabis', '黄仁勋', 'Jensen Huang',
      '马斯克', 'Elon Musk', '梁文锋', '纳德拉', 'Satya Nadella',
      '皮查伊', 'Sundar Pichai', '扎克伯格', '马克·扎克伯格', 'Mark Zuckerberg'
      , 'Greg Brockman', '布罗克曼', 'Alexandr Wang', 'Jakub Pachocki', 'Lex Fridman'
      , '马云', 'Jack Ma', '雷军', 'Lei Jun', '李彦宏', 'Robin Li', '百度'
      , '董明珠', 'Dong Mingzhu', '格力', 'Peter Thiel', '彼得·蒂尔'
      , '但斌', '大道无形我有型', '猫笔刀', '大牛猫', 'OōEli', 'ooeli_eth'
      , '一口新饭', 'onenewbite', '习近平', 'Xi Jinping'
      , '特朗普', 'Donald Trump', '毛泽东', 'Mao Zedong'
      , '邓小平', 'Deng Xiaoping', '改革开放'
    ]::text[]) AS alias
    ON CONFLICT (candidate_key) DO UPDATE SET
      name = EXCLUDED.name,
      normalized_name = EXCLUDED.normalized_name,
      status = 'ready',
      metadata = COALESCE(ai_person_candidates.metadata, '{}'::jsonb) || EXCLUDED.metadata,
      updated_at = NOW();

    CREATE OR REPLACE FUNCTION sync_curated_post_person_relations()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    BEGIN
      IF NEW.content_kind <> 'post' OR NEW.origin_table <> 'post' THEN
        RETURN NEW;
      END IF;

      DELETE FROM ai_content_item_person_candidates relation
      USING ai_person_candidates candidate
      WHERE relation.content_id = NEW.id
        AND relation.candidate_id = candidate.id
        AND COALESCE(candidate.metadata, '{}'::jsonb) @> '{"curated_post_person": true}'::jsonb;

      INSERT INTO ai_content_item_person_candidates (
        content_id, content_kind, origin_id, candidate_id, confidence,
        match_type, matched_text, evidence, created_at, updated_at
      )
      SELECT
        NEW.id, NEW.content_kind, NEW.origin_id, candidate.id, 0.920,
        'curated_alias', candidate.name,
        jsonb_build_object('rule', 'curated_alias', 'version', 1), NOW(), NOW()
      FROM ai_person_candidates candidate
      WHERE COALESCE(candidate.metadata, '{}'::jsonb) @> '{"curated_post_person": true}'::jsonb
        AND lower(concat_ws(' ', NEW.title, NEW.summary, NEW.content_zh, NEW.content, NEW.text))
            LIKE '%' || lower(candidate.name) || '%'
      ON CONFLICT (content_id, candidate_id) DO UPDATE SET
        confidence = EXCLUDED.confidence,
        match_type = EXCLUDED.match_type,
        matched_text = EXCLUDED.matched_text,
        evidence = EXCLUDED.evidence,
        updated_at = NOW();
      RETURN NEW;
    END $$;

    CREATE OR REPLACE TRIGGER trg_sync_curated_post_person_relations
    AFTER INSERT OR UPDATE OF title, summary, content_zh, content, text
    ON ai_content_items
    FOR EACH ROW
    EXECUTE FUNCTION sync_curated_post_person_relations();
    `,
	},
	{
		Title:     "Backfill curated post-person relations once",
		MarkerKey: "curated-post-person-relations-backfill-v2",
		SQL: `
    INSERT INTO ai_content_item_person_candidates (
      content_id, content_kind, origin_id, candidate_id, confidence,
      match_type, matched_text, evidence, created_at, updated_at
    )
    SELECT
      item.id, item.content_kind, item.origin_id, candidate.id, 0.920,
      'curated_alias', candidate.name,
      jsonb_build_object('rule', 'curated_alias', 'version', 1), NOW(), NOW()
    FROM ai_content_items item
    JOIN ai_person_candidates candidate
      ON COALESCE(candidate.metadata, '{}'::jsonb) @> '{"curated_post_person": true}'::jsonb
     AND lower(concat_ws(' ', item.title, item.summary, item.content_zh, item.content, item.text))
         LIKE '%' || lower(candidate.name) || '%'
    WHERE item.content_kind = 'post'
      AND item.origin_table = 'post'
      AND COALESCE(item.published_at, item.origin_created_at, item.created_at) >= NOW() - INTERVAL '30 days'
    ON CONFLICT (content_id, candidate_id) DO UPDATE SET
      confidence = EXCLUDED.confidence,
      match_type = EXCLUDED.match_type,
      matched_text = EXCLUDED.matched_text,
      evidence = EXCLUDED.evidence,
      updated_at = NOW();
    `,
	},
	{
		Title: "Create ai_score_rules if missing",
		SQL: `
    CREATE TABLE IF NOT EXISTS ai_score_rules (
      id SERIAL PRIMARY KEY,
      name VARCHAR(100) NOT NULL,
      description TEXT,
      keywords TEXT,
      keyword_norm TEXT,
      pattern TEXT,
      score_adjustment DECIMAL(4,2) DEFAULT -3.0,
      rule_type VARCHAR(20) DEFAULT 'keyword',
      match_mode VARCHAR(10) DEFAULT 'any',
      min_score_trigger INTEGER DEFAULT 6,
      enabled BOOLEAN DEFAULT true,
      case_sensitive BOOLEAN DEFAULT false,
      hit_count INTEGER DEFAULT 0,
      created_at TIMESTAMP DEFAULT NOW(),
      updated_at TIMESTAMP DEFAULT NOW()
    )
    `,
	},
	{
		Title: "Rename penalty -> score_adjustment when needed",
		SQL: `
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'ai_score_rules'
          AND column_name = 'penalty'
      ) AND NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'ai_score_rules'
          AND column_name = 'score_adjustment'
      ) THEN
        ALTER TABLE ai_score_rules RENAME COLUMN penalty TO score_adjustment;
      END IF;
    END $$;
    `,
	},
	{
		Title: "Add missing ai_score_rules columns for strict schema",
		SQL: `
    ALTER TABLE ai_score_rules
      ADD COLUMN IF NOT EXISTS keyword_norm TEXT,
      ADD COLUMN IF NOT EXISTS score_adjustment DECIMAL(4,2) DEFAULT -3.0,
      ADD COLUMN IF NOT EXISTS min_score_trigger INTEGER DEFAULT 6,
      ADD COLUMN IF NOT EXISTS case_sensitive BOOLEAN DEFAULT false
    `,
	},
	{
		Title: "Create ai_rule_hits if missing",
		SQL: `
    CREATE TABLE IF NOT EXISTS ai_rule_hits (
      id SERIAL PRIMARY KEY,
      rule_id INTEGER NOT NULL REFERENCES ai_score_rules(id) ON DELETE CASCADE,
      post_id VARCHAR(50) NOT NULL,
      score_adjustment DECIMAL(4,2),
      matched_at TIMESTAMP DEFAULT NOW()
    )
    `,
	},
	{
		Title: "Create ai_preference_rules if missing",
		SQL: `
    CREATE TABLE IF NOT EXISTS ai_preference_rules (
      id BIGSERIAL PRIMARY KEY,
      rule_key TEXT NOT NULL UNIQUE,
      source VARCHAR(64) NOT NULL DEFAULT 'ai_dislike_guess',
      polarity VARCHAR(16) NOT NULL DEFAULT 'negative',
      name TEXT NOT NULL,
      description TEXT,
      positive_keywords JSONB NOT NULL DEFAULT '[]'::jsonb,
      negative_keywords JSONB NOT NULL DEFAULT '[]'::jsonb,
      required_keywords JSONB NOT NULL DEFAULT '[]'::jsonb,
      excluded_keywords JSONB NOT NULL DEFAULT '[]'::jsonb,
      score_adjustment DECIMAL(5,2) NOT NULL DEFAULT -1.0,
      confidence DECIMAL(4,3) NOT NULL DEFAULT 0.5,
      status VARCHAR(16) NOT NULL DEFAULT 'enabled',
      hit_count INTEGER NOT NULL DEFAULT 0,
      learn_count INTEGER NOT NULL DEFAULT 1,
      sample_post_ids JSONB NOT NULL DEFAULT '[]'::jsonb,
      last_audit_id BIGINT,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
    `,
	},
	{
		Title: "Create ai_preference_rule_candidates if missing",
		SQL: `
    CREATE TABLE IF NOT EXISTS ai_preference_rule_candidates (
      id BIGSERIAL PRIMARY KEY,
      candidate_key TEXT NOT NULL UNIQUE,
      source VARCHAR(64) NOT NULL DEFAULT 'score_replay',
      content_kind VARCHAR(24) NOT NULL DEFAULT '',
      content_source VARCHAR(160) NOT NULL DEFAULT '',
      polarity VARCHAR(16) NOT NULL DEFAULT 'negative',
      name TEXT NOT NULL,
      description TEXT,
      required_keywords JSONB NOT NULL DEFAULT '[]'::jsonb,
      score_adjustment DECIMAL(5,2) NOT NULL DEFAULT -1.0,
      confidence DECIMAL(4,3) NOT NULL DEFAULT 0.5,
      risk_score DOUBLE PRECISION NOT NULL DEFAULT 0,
      sample_count INTEGER NOT NULL DEFAULT 0,
      sample_content_ids JSONB NOT NULL DEFAULT '[]'::jsonb,
      sample_origin_ids JSONB NOT NULL DEFAULT '[]'::jsonb,
      samples JSONB NOT NULL DEFAULT '[]'::jsonb,
      evidence JSONB NOT NULL DEFAULT '{}'::jsonb,
      status VARCHAR(16) NOT NULL DEFAULT 'pending',
      first_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
    `,
	},
	{
		Title: "Create ai_preference_event_lines if missing",
		SQL: `
    CREATE TABLE IF NOT EXISTS ai_preference_event_lines (
      id BIGSERIAL PRIMARY KEY,
      line_key TEXT NOT NULL UNIQUE,
      scope VARCHAR(16) NOT NULL DEFAULT 'cluster',
      source VARCHAR(64) NOT NULL DEFAULT 'ai_dislike_guess',
      polarity VARCHAR(16) NOT NULL DEFAULT 'negative',
      root_id BIGINT,
      node_id BIGINT,
      cluster_id BIGINT,
      title TEXT NOT NULL DEFAULT '',
      summary TEXT,
      score_adjustment DECIMAL(5,2) NOT NULL DEFAULT -1.0,
      confidence DECIMAL(4,3) NOT NULL DEFAULT 0.5,
      status VARCHAR(16) NOT NULL DEFAULT 'enabled',
      hit_count INTEGER NOT NULL DEFAULT 0,
      learn_count INTEGER NOT NULL DEFAULT 1,
      sample_content JSONB NOT NULL DEFAULT '[]'::jsonb,
      last_audit_id BIGINT,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
    `,
	},
	{
		Title: "Create idx_ai_content_items_final_score for strict schema",
		SQL: `
    CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_ai_content_items_final_score
    ON ai_content_items (final_score DESC NULLS LAST, published_at DESC NULLS LAST)
    `,
	},
	{
		Title: "Add ai_rule_hits.score_adjustment if missing",
		SQL: `
    ALTER TABLE ai_rule_hits
      ADD COLUMN IF NOT EXISTS score_adjustment DECIMAL(4,2)
    `,
	},
	{
		Title:     "Deduplicate ai_rule_hits before unique rule/post index",
		MarkerKey: "deduplicate-ai-rule-hits-v1",
		SQL: `
    DELETE FROM ai_rule_hits a
    USING ai_rule_hits b
    WHERE a.rule_id = b.rule_id
      AND a.post_id = b.post_id
      AND a.id > b.id
    `,
	},
	{
		Title: "Create idx_rule_hits_rule_post_unique",
		SQL: `
    CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS idx_rule_hits_rule_post_unique
    ON ai_rule_hits(rule_id, post_id)
    `,
	},
	{
		Title: "Create ai_rss_feeds if missing",
		SQL: `
    CREATE TABLE IF NOT EXISTS ai_rss_feeds (
      id SERIAL PRIMARY KEY,
      name TEXT NOT NULL,
      feed_url TEXT NOT NULL UNIQUE,
      category_id INTEGER,
      polling_interval INTEGER NOT NULL DEFAULT 300,
      is_enabled BOOLEAN NOT NULL DEFAULT TRUE,
      special_notify BOOLEAN NOT NULL DEFAULT FALSE,
      display_field VARCHAR(16) NOT NULL DEFAULT 'summary',
      notes TEXT,
      icon TEXT,
      folo_meta JSONB,
      ai_prompt TEXT,
      last_fetched_at TIMESTAMPTZ,
      last_data_updated_at TIMESTAMPTZ,
      last_item_at TIMESTAMPTZ,
      last_status VARCHAR(32),
      last_error TEXT,
      last_fetch_total INTEGER NOT NULL DEFAULT 0,
      last_fetch_new INTEGER NOT NULL DEFAULT 0,
      consecutive_failures INTEGER NOT NULL DEFAULT 0,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
    `,
	},
	{
		Title: "Add missing ai_rss_feeds columns for strict schema",
		SQL: `
    ALTER TABLE ai_rss_feeds
      ADD COLUMN IF NOT EXISTS special_notify BOOLEAN NOT NULL DEFAULT FALSE,
      ADD COLUMN IF NOT EXISTS icon TEXT,
      ADD COLUMN IF NOT EXISTS folo_meta JSONB,
      ADD COLUMN IF NOT EXISTS ai_prompt TEXT,
      ADD COLUMN IF NOT EXISTS display_field VARCHAR(16) NOT NULL DEFAULT 'summary',
      ADD COLUMN IF NOT EXISTS last_data_updated_at TIMESTAMPTZ,
      ADD COLUMN IF NOT EXISTS last_item_at TIMESTAMPTZ
    `,
	},
	peopleContentSourcesSeedStep,
	{
		Title:     "Backfill empty display_field",
		MarkerKey: "rss-display-field-backfill-v1",
		SQL: `
    UPDATE ai_rss_feeds
    SET display_field = 'summary'
    WHERE display_field IS NULL OR btrim(display_field) = ''
	`,
	},
	{
		Title: "Create ai_rss_dedup_fingerprints if missing",
		SQL: `
    CREATE TABLE IF NOT EXISTS ai_rss_dedup_fingerprints (
      origin_id BIGINT PRIMARY KEY,
      source VARCHAR(128) NOT NULL,
      article_id TEXT NOT NULL,
      article_link_key TEXT NOT NULL DEFAULT '',
      body_key TEXT NOT NULL DEFAULT '',
      combined_key TEXT NOT NULL DEFAULT '',
      title_key TEXT NOT NULL DEFAULT '',
      body_compact TEXT NOT NULL DEFAULT '',
      body_rune_len INTEGER NOT NULL DEFAULT 0,
      observed_at TIMESTAMPTZ NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
    `,
	},
	{
		Title: "Create RSS dedup fingerprint lookup indexes",
		SQL: `
    CREATE INDEX IF NOT EXISTS idx_ai_rss_dedup_link_recent ON ai_rss_dedup_fingerprints (article_link_key, observed_at DESC);
    CREATE INDEX IF NOT EXISTS idx_ai_rss_dedup_body_recent ON ai_rss_dedup_fingerprints (body_key, observed_at DESC);
    CREATE INDEX IF NOT EXISTS idx_ai_rss_dedup_combined_recent ON ai_rss_dedup_fingerprints (combined_key, observed_at DESC);
    CREATE INDEX IF NOT EXISTS idx_ai_rss_dedup_title_recent ON ai_rss_dedup_fingerprints (title_key, observed_at DESC);
    CREATE INDEX IF NOT EXISTS idx_ai_rss_dedup_observed ON ai_rss_dedup_fingerprints (observed_at)
    `,
	},
	{
		Title: "Create ai_rss_author_items if missing",
		SQL: `
    CREATE TABLE IF NOT EXISTS ai_rss_author_items (
      post_id BIGINT PRIMARY KEY,
      source TEXT NOT NULL,
      author_id TEXT NOT NULL,
      label TEXT NOT NULL,
      avatar_url TEXT NOT NULL DEFAULT '',
      post_time TIMESTAMP,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
    `,
	},
	{
		Title: "Create ai_openrouter_model_status_daily if missing",
		SQL: `
    CREATE TABLE IF NOT EXISTS ai_openrouter_model_status_daily (
      usage_date DATE NOT NULL,
      model TEXT NOT NULL,
      events BIGINT NOT NULL DEFAULT 0,
      ok_events BIGINT NOT NULL DEFAULT 0,
      error_events BIGINT NOT NULL DEFAULT 0,
      last_called_at TIMESTAMPTZ,
      last_ok_at TIMESTAMPTZ,
      last_error_at TIMESTAMPTZ,
      last_status TEXT,
      last_error_status INTEGER,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      PRIMARY KEY (usage_date, model)
    )
    `,
	},
	{
		Title: "Create idx_rule_hits_rule_id",
		SQL: `
    CREATE INDEX IF NOT EXISTS idx_rule_hits_rule_id ON ai_rule_hits(rule_id)
    `,
	},
	{
		Title: "Create idx_rule_hits_post_id",
		SQL: `
    CREATE INDEX IF NOT EXISTS idx_rule_hits_post_id ON ai_rule_hits(post_id)
    `,
	},
	{
		Title: "Create idx_rule_hits_rule_id_matched_at",
		SQL: `
    CREATE INDEX IF NOT EXISTS idx_rule_hits_rule_id_matched_at ON ai_rule_hits(rule_id, matched_at DESC)
    `,
	},
	{
		Title: "Create idx_ai_preference_rules_status",
		SQL: `
    CREATE INDEX IF NOT EXISTS idx_ai_preference_rules_status ON ai_preference_rules (status, updated_at DESC)
    `,
	},
	{
		Title: "Create idx_ai_preference_rules_polarity",
		SQL: `
    CREATE INDEX IF NOT EXISTS idx_ai_preference_rules_polarity ON ai_preference_rules (polarity, updated_at DESC)
    `,
	},
	{
		Title: "Create idx_ai_preference_rule_candidates_status",
		SQL: `
    CREATE INDEX IF NOT EXISTS idx_ai_preference_rule_candidates_status ON ai_preference_rule_candidates (status, risk_score DESC, updated_at DESC)
    `,
	},
	{
		Title: "Create idx_ai_preference_rule_candidates_source",
		SQL: `
    CREATE INDEX IF NOT EXISTS idx_ai_preference_rule_candidates_source ON ai_preference_rule_candidates (content_kind, content_source, updated_at DESC)
    `,
	},
	{
		Title: "Create idx_ai_preference_event_lines_status",
		SQL: `
    CREATE INDEX IF NOT EXISTS idx_ai_preference_event_lines_status ON ai_preference_event_lines (status, updated_at DESC)
    `,
	},
	{
		Title: "Create idx_ai_preference_event_lines_cluster",
		SQL: `
    CREATE INDEX IF NOT EXISTS idx_ai_preference_event_lines_cluster ON ai_preference_event_lines (cluster_id)
    `,
	},
	{
		Title: "Create idx_ai_preference_event_lines_node",
		SQL: `
    CREATE INDEX IF NOT EXISTS idx_ai_preference_event_lines_node ON ai_preference_event_lines (node_id)
    `,
	},
	{
		Title: "Create idx_ai_preference_event_lines_root",
		SQL: `
    CREATE INDEX IF NOT EXISTS idx_ai_preference_event_lines_root ON ai_preference_event_lines (root_id)
    `,
	},
	{
		Title: "Create idx_ai_rss_feeds_enabled",
		SQL: `
    CREATE INDEX IF NOT EXISTS idx_ai_rss_feeds_enabled ON ai_rss_feeds (is_enabled)
    `,
	},
	{
		Title: "Create idx_ai_rss_feeds_category",
		SQL: `
    CREATE INDEX IF NOT EXISTS idx_ai_rss_feeds_category ON ai_rss_feeds (category_id)
    `,
	},
	{
		Title: "Create idx_ai_rss_feeds_enabled_due_order",
		SQL: `
    CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_ai_rss_feeds_enabled_due_order
    ON ai_rss_feeds ((COALESCE(last_fetched_at, TIMESTAMPTZ 'epoch')), id)
    WHERE is_enabled = TRUE
    `,
	},
	{
		Title: "Ensure pg_trgm extension",
		SQL: `
    CREATE EXTENSION IF NOT EXISTS pg_trgm
    `,
	},
	personVideoCreateSchemaStep,
	personVideoTitleSchemaStep,
	personVideoSubtitleSchemaStep,
	personVideoDuplicateSchemaStep,
	personVideoRankSchemaStep,
	{
		Title: "Create person_articles",
		SQL: `
    CREATE TABLE IF NOT EXISTS person_articles (
      id BIGSERIAL PRIMARY KEY,
      person_id TEXT NOT NULL,
      source_name TEXT NOT NULL,
      source_url TEXT NOT NULL DEFAULT '',
      title TEXT NOT NULL,
      title_zh TEXT NOT NULL DEFAULT '',
      summary TEXT NOT NULL DEFAULT '',
      content TEXT NOT NULL DEFAULT '',
      canonical_url TEXT NOT NULL UNIQUE,
      published_at TIMESTAMPTZ,
      reading_minutes INTEGER NOT NULL DEFAULT 0,
      language TEXT NOT NULL DEFAULT 'en',
      imported_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
    `,
	},
	{
		Title: "Create idx_person_articles_person_date",
		SQL: `
    CREATE INDEX IF NOT EXISTS idx_person_articles_person_date
    ON person_articles (person_id, published_at DESC NULLS LAST, id DESC)
    `,
	},
	{
		Title: "Add Chinese summary and content to person_articles",
		SQL: `
    ALTER TABLE person_articles
      ADD COLUMN IF NOT EXISTS summary_zh TEXT NOT NULL DEFAULT '',
      ADD COLUMN IF NOT EXISTS content_zh TEXT NOT NULL DEFAULT ''
    `,
	},
	{
		Title: "Create ai_schema_migration_markers if missing",
		SQL: `
    CREATE TABLE IF NOT EXISTS ai_schema_migration_markers (
      marker_key TEXT PRIMARY KEY,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
    `,
	},
	{
		Title: "Create idx_ai_rss_author_items_group_v2",
		SQL: `
    CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_ai_rss_author_items_group_v2
    ON ai_rss_author_items (author_id, label, post_time DESC)
    `,
	},
	{
		Title: "Create idx_ai_usage_events_openrouter_status_window",
		SQL: `
    CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_ai_usage_events_openrouter_status_window
    ON ai_usage_events (usage_date DESC, model, created_at DESC)
    INCLUDE (status, error_status)
    WHERE provider = 'openrouter'
		`,
	},
	{
		Title: "Create idx_ai_usage_events_translation_quota_window",
		SQL: `
    CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_ai_usage_events_translation_quota_window
    ON ai_usage_events (provider, usage_date DESC, ((meta ->> 'input_chars')::bigint))
    WHERE kind = 'translation'
      AND status = 'ok'
      AND meta ->> 'input_chars' ~ '^[0-9]+$'
    `,
	},
	{
		Title: "Create ai_openrouter_model_status_daily sync function",
		SQL: `
    CREATE OR REPLACE FUNCTION sync_ai_openrouter_model_status_daily()
    RETURNS TRIGGER AS $$
    BEGIN
      IF NEW.provider = 'openrouter' THEN
        INSERT INTO ai_openrouter_model_status_daily (
          usage_date,
          model,
          events,
          ok_events,
          error_events,
          last_called_at,
          last_ok_at,
          last_error_at,
          last_status,
          last_error_status,
          updated_at
        )
        VALUES (
          NEW.usage_date,
          COALESCE(NEW.model, ''),
          1,
          CASE WHEN NEW.status = 'ok' THEN 1 ELSE 0 END,
          CASE WHEN NEW.status <> 'ok' THEN 1 ELSE 0 END,
          NEW.created_at,
          CASE WHEN NEW.status = 'ok' THEN NEW.created_at ELSE NULL END,
          CASE WHEN NEW.status <> 'ok' THEN NEW.created_at ELSE NULL END,
          NEW.status,
          NEW.error_status,
          NOW()
        )
        ON CONFLICT (usage_date, model) DO UPDATE SET
          events = ai_openrouter_model_status_daily.events + 1,
          ok_events = ai_openrouter_model_status_daily.ok_events + EXCLUDED.ok_events,
          error_events = ai_openrouter_model_status_daily.error_events + EXCLUDED.error_events,
          last_called_at = CASE
            WHEN ai_openrouter_model_status_daily.last_called_at IS NULL
              OR EXCLUDED.last_called_at >= ai_openrouter_model_status_daily.last_called_at
            THEN EXCLUDED.last_called_at
            ELSE ai_openrouter_model_status_daily.last_called_at
          END,
          last_ok_at = CASE
            WHEN EXCLUDED.last_ok_at IS NULL THEN ai_openrouter_model_status_daily.last_ok_at
            WHEN ai_openrouter_model_status_daily.last_ok_at IS NULL
              OR EXCLUDED.last_ok_at >= ai_openrouter_model_status_daily.last_ok_at
            THEN EXCLUDED.last_ok_at
            ELSE ai_openrouter_model_status_daily.last_ok_at
          END,
          last_error_at = CASE
            WHEN EXCLUDED.last_error_at IS NULL THEN ai_openrouter_model_status_daily.last_error_at
            WHEN ai_openrouter_model_status_daily.last_error_at IS NULL
              OR EXCLUDED.last_error_at >= ai_openrouter_model_status_daily.last_error_at
            THEN EXCLUDED.last_error_at
            ELSE ai_openrouter_model_status_daily.last_error_at
          END,
          last_status = CASE
            WHEN ai_openrouter_model_status_daily.last_called_at IS NULL
              OR EXCLUDED.last_called_at >= ai_openrouter_model_status_daily.last_called_at
            THEN EXCLUDED.last_status
            ELSE ai_openrouter_model_status_daily.last_status
          END,
          last_error_status = CASE
            WHEN ai_openrouter_model_status_daily.last_called_at IS NULL
              OR EXCLUDED.last_called_at >= ai_openrouter_model_status_daily.last_called_at
            THEN EXCLUDED.last_error_status
            ELSE ai_openrouter_model_status_daily.last_error_status
          END,
          updated_at = NOW();
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql
    `,
	},
	{
		Title: "Create ai_openrouter_model_status_daily insert trigger",
		SQL: `
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1
        FROM pg_trigger
        WHERE tgname = 'trg_ai_usage_events_openrouter_rollup'
      ) THEN
        CREATE TRIGGER trg_ai_usage_events_openrouter_rollup
        AFTER INSERT ON ai_usage_events
        FOR EACH ROW
        EXECUTE FUNCTION sync_ai_openrouter_model_status_daily();
      END IF;
    END $$;
    `,
	},
	{
		Title:     "Backfill ai_openrouter_model_status_daily",
		MarkerKey: "openrouter-model-status-backfill-v1",
		SQL: `
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1
        FROM ai_openrouter_model_status_daily
        WHERE usage_date >= CURRENT_DATE - INTERVAL '90 days'
        LIMIT 1
      ) THEN
        WITH source_rows AS (
          SELECT
            usage_date,
            COALESCE(model, '') AS model,
            status,
            error_status,
            created_at
          FROM ai_usage_events
          WHERE provider = 'openrouter'
            AND usage_date >= CURRENT_DATE - INTERVAL '90 days'
        ),
        aggregated AS (
          SELECT
            usage_date,
            model,
            COUNT(*)::bigint AS events,
            COUNT(*) FILTER (WHERE status = 'ok')::bigint AS ok_events,
            COUNT(*) FILTER (WHERE status <> 'ok')::bigint AS error_events,
            MAX(created_at) AS last_called_at,
            MAX(created_at) FILTER (WHERE status = 'ok') AS last_ok_at,
            MAX(created_at) FILTER (WHERE status <> 'ok') AS last_error_at
          FROM source_rows
          GROUP BY usage_date, model
        ),
        latest AS (
          SELECT DISTINCT ON (usage_date, model)
            usage_date,
            model,
            status AS last_status,
            error_status AS last_error_status
          FROM source_rows
          ORDER BY usage_date, model, created_at DESC
        )
        INSERT INTO ai_openrouter_model_status_daily (
          usage_date,
          model,
          events,
          ok_events,
          error_events,
          last_called_at,
          last_ok_at,
          last_error_at,
          last_status,
          last_error_status,
          updated_at
        )
        SELECT
          aggregated.usage_date,
          aggregated.model,
          aggregated.events,
          aggregated.ok_events,
          aggregated.error_events,
          aggregated.last_called_at,
          aggregated.last_ok_at,
          aggregated.last_error_at,
          latest.last_status,
          latest.last_error_status,
          NOW()
        FROM aggregated
        LEFT JOIN latest ON latest.usage_date = aggregated.usage_date
          AND latest.model = aggregated.model
        ON CONFLICT (usage_date, model) DO UPDATE SET
          events = EXCLUDED.events,
          ok_events = EXCLUDED.ok_events,
          error_events = EXCLUDED.error_events,
          last_called_at = EXCLUDED.last_called_at,
          last_ok_at = EXCLUDED.last_ok_at,
          last_error_at = EXCLUDED.last_error_at,
          last_status = EXCLUDED.last_status,
          last_error_status = EXCLUDED.last_error_status,
          updated_at = NOW();
      END IF;
    END $$;
    `,
	},
}

type config struct {
	RedisURL                   string
	PostgresURL                string
	MaintenanceCron            string
	ObservabilityCron          string
	ArchiveCron                string
	CompanyFinancialCron       string
	CompanyFinancialRunOnStart bool
	ArchiveEnabled             bool
	ArchiveRunOnStart          bool
	MaintenanceRunOnStart      bool
	ArchiveRetainDays          int
	ArchiveBatchSize           int
	ArchiveMaxBatches          int
	ObservabilityNight         nightModeConfig
	ESRetentionEnabled         bool
	ESNode                     string
	ESIndex                    string
	ESRetentionDays            int
}

type cliOptions struct {
	Once          string
	DryRun        bool
	StatsOnly     bool
	AnalyzeOnly   bool
	SkipSettings  bool
	IncludeLiked  bool
	Tables        []string
	Limit         int
	SlowMs        int
	RetainDays    int
	RetainDaysSet bool
	BatchSize     int
	BatchSizeSet  bool
	MaxBatches    int
	MaxBatchesSet bool
}

func Main(args []string) {
	log.SetFlags(log.LstdFlags)
	runtimecfg.LoadDotEnv(".env")
	cli := parseCLIOptions(args)

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	redisClient := loadRuntimeEnv(ctx)
	if redisClient != nil {
		defer func() {
			_ = redisClient.Close()
		}()
	}

	cfg := loadConfig()
	pool, err := connectPostgres(ctx, cfg.PostgresURL)
	if err != nil {
		log.Fatalf("[db-maintenance-runner] PostgreSQL 连接失败: %v", err)
	}
	defer pool.Close()

	if err := pool.Ping(ctx); err != nil {
		log.Fatalf("[db-maintenance-runner] PostgreSQL ping 失败: %v", err)
	}

	if cli.Once != "" {
		if err := runOnceCommand(ctx, pool, cfg, cli); err != nil {
			log.Fatalf("[db-maintenance-runner] once failed: %v", err)
		}
		return
	}

	if err := runScheduler(ctx, pool, cfg); err != nil && !errors.Is(err, context.Canceled) {
		log.Fatalf("[db-maintenance-runner] fatal: %v", err)
	}
}
