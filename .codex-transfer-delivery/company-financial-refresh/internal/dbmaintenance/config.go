package dbmaintenance

import (
	"flag"
	"strings"

	"ai-server/internal/runtimecfg"
)

func parseCLIOptions(args []string) cliOptions {
	fs := flag.NewFlagSet("db-maintenance-runner", flag.ExitOnError)
	once := fs.String("once", "", "run one command: maintain, observe, archive, company-financials, configure-observability, cleanup-indexes, strict-schema, or unified-content")
	dryRun := fs.Bool("dry-run", false, "preview archive work without moving rows")
	statsOnly := fs.Bool("stats-only", false, "only print maintenance stats")
	analyzeOnly := fs.Bool("analyze-only", false, "run ANALYZE instead of VACUUM (ANALYZE)")
	skipSettings := fs.Bool("skip-settings", false, "skip table maintenance setting updates")
	includeLiked := fs.Bool("include-liked", false, "include liked posts in archive candidates")
	tables := fs.String("tables", "", "comma-separated tables for maintenance")
	limit := fs.Int("limit", 10, "slow query limit for observability")
	slowMs := fs.Int("slow-ms", defaultObservabilitySlowMs, "slow statement logging threshold in milliseconds")
	retainDays := fs.Int("retain-days", defaultArchiveRetainDays, "archive retention days")
	batchSize := fs.Int("batch-size", defaultArchiveBatchSize, "archive batch size")
	maxBatches := fs.Int("max-batches", defaultArchiveMaxBatches, "archive max batches")
	_ = fs.Parse(args)
	explicitFlags := make(map[string]bool, len(args))
	fs.Visit(func(flag *flag.Flag) {
		explicitFlags[flag.Name] = true
	})

	return cliOptions{
		Once:          normalizeOnceCommand(*once),
		DryRun:        *dryRun,
		StatsOnly:     *statsOnly,
		AnalyzeOnly:   *analyzeOnly,
		SkipSettings:  *skipSettings,
		IncludeLiked:  *includeLiked,
		Tables:        splitCSV(*tables),
		Limit:         maxInt(*limit, 1),
		SlowMs:        maxInt(*slowMs, minObservabilitySlowMs),
		RetainDays:    maxInt(*retainDays, 1),
		RetainDaysSet: explicitFlags["retain-days"],
		BatchSize:     maxInt(*batchSize, 1),
		BatchSizeSet:  explicitFlags["batch-size"],
		MaxBatches:    maxInt(*maxBatches, 1),
		MaxBatchesSet: explicitFlags["max-batches"],
	}
}

func normalizeOnceCommand(value string) string {
	normalized := strings.ToLower(strings.TrimSpace(value))
	switch normalized {
	case "", "none":
		return ""
	case "maintain", "maintenance", "db-maintain":
		return "maintain"
	case "observe", "observability", "db-observe":
		return "observe"
	case "configure", "configure-observability", "observe-configure", "db-observe-configure":
		return "configure-observability"
	case "cleanup-indexes", "cleanup-obsolete-indexes", "index-cleanup", "db-index-cleanup":
		return "cleanup-indexes"
	case "strict-schema", "migrate-strict-schema", "db-migrate-strict":
		return "strict-schema"
	case "unified-content", "content-unify", "content-unified", "db-content-unify":
		return "unified-content"
	case "archive", "db-archive":
		return "archive"
	case "company-financials", "financials", "refresh-company-financials":
		return "company-financials"
	default:
		return normalized
	}
}

func loadConfig() config {
	nightMode := resolveManagedNightModeConfig("db_observability", observabilityBaseIntervalMs, dbObservabilityDefaultMultiplier)
	return config{
		RedisURL:                   runtimecfg.RedisURLFromEnv(),
		PostgresURL:                runtimecfg.String("DB_MAINTENANCE_POSTGRES_URL", buildPostgresURLFromEnv()),
		MaintenanceCron:            runtimecfg.String("DB_MAINTENANCE_CRON", defaultMaintenanceCron),
		ObservabilityCron:          runtimecfg.String("DB_OBSERVABILITY_REPORT_CRON", defaultObservabilityCron),
		ArchiveCron:                runtimecfg.String("DB_ARCHIVE_CRON", defaultArchiveCron),
		CompanyFinancialCron:       runtimecfg.String("COMPANY_FINANCIAL_REFRESH_CRON", defaultCompanyFinancialCron),
		CompanyFinancialRunOnStart: runtimecfg.Bool("COMPANY_FINANCIAL_REFRESH_RUN_ON_START", true),
		ArchiveEnabled:             runtimecfg.Bool("DB_ARCHIVE_ENABLED", false),
		ArchiveRunOnStart:          runtimecfg.Bool("DB_ARCHIVE_RUN_ON_START", false),
		MaintenanceRunOnStart:      runtimecfg.Bool("DB_MAINTENANCE_RUN_ON_START", true),
		ArchiveRetainDays:          runtimecfg.IntRange("DB_ARCHIVE_RETAIN_DAYS", defaultArchiveRetainDays, 1, 36500),
		ArchiveBatchSize:           runtimecfg.IntRange("DB_ARCHIVE_BATCH_SIZE", defaultArchiveBatchSize, 1, 100000),
		ArchiveMaxBatches:          runtimecfg.IntRange("DB_ARCHIVE_MAX_BATCHES", defaultArchiveMaxBatches, 1, 10000),
		ObservabilityNight:         nightMode,
		ESRetentionEnabled:         runtimecfg.Bool("ES_POST_RETENTION_ENABLED", true),
		ESNode:                     runtimecfg.ElasticsearchNodeFromEnv(),
		ESIndex:                    runtimecfg.String("ES_POST_INDEX", "ai_contents_search_v2"),
		ESRetentionDays:            runtimecfg.IntRange("ES_POST_RETENTION_DAYS", 60, 1, 36500),
	}
}
