package dbmaintenance

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

func runOnceCommand(ctx context.Context, pool *pgxpool.Pool, cfg config, cli cliOptions) error {
	switch cli.Once {
	case "maintain":
		return runMaintenanceOnce(ctx, pool, cli)
	case "observe":
		return runObservabilityOnce(ctx, pool, cfg, cli)
	case "configure-observability":
		return runConfigureObservabilityOnce(ctx, pool, cli)
	case "cleanup-indexes":
		return runCleanupIndexesOnce(ctx, pool, cli)
	case "strict-schema":
		return runStrictSchemaMigrationOnce(ctx, pool, cli)
	case "unified-content":
		return runUnifiedContentOnce(ctx, pool, cli)
	case "archive":
		return runArchiveOnce(ctx, pool, cfg, cli)
	case "company-financials":
		result, err := runCompanyFinancialRefreshJob(ctx, pool)
		if err == nil {
			printJSON(result)
		}
		return err
	default:
		return fmt.Errorf("unknown --once value %q; expected maintain, observe, archive, company-financials, configure-observability, cleanup-indexes, strict-schema, or unified-content", cli.Once)
	}
}

func runMaintenanceOnce(ctx context.Context, pool *pgxpool.Pool, cli cliOptions) error {
	tableNames := normalizeTableNames(cli.Tables)
	profiles := filterMaintenanceProfiles(tableNames)
	before, err := getTableMaintenanceStats(ctx, pool, tableNames)
	if err != nil {
		return err
	}
	result := make(map[string]any, 3)
	result["before"] = before
	if !cli.StatsOnly && !cli.SkipSettings {
		settings, err := ensureTableMaintenanceSettings(ctx, pool, profiles)
		if err != nil {
			return err
		}
		result["settings"] = settings
	}
	if !cli.StatsOnly {
		vacuum, err := vacuumAnalyzeTables(ctx, pool, tableNames, cli.AnalyzeOnly)
		if err != nil {
			return err
		}
		if cli.AnalyzeOnly {
			result["analyze"] = vacuum
		} else {
			result["vacuum_analyze"] = vacuum
		}
	}
	after, err := getTableMaintenanceStats(ctx, pool, tableNames)
	if err != nil {
		return err
	}
	result["after"] = after
	printJSON(result)
	return nil
}

func runObservabilityOnce(ctx context.Context, pool *pgxpool.Pool, cfg config, cli cliOptions) error {
	observability, err := getPostgresObservabilityStatus(ctx, pool, true, cli.Limit)
	if err != nil {
		return err
	}
	maintenance, err := getTableMaintenanceStats(ctx, pool, defaultMaintenanceTables())
	if err != nil {
		return err
	}
	archive, err := getContentArchiveStats(ctx, pool, effectiveRetainDays(cli.RetainDays, cfg.ArchiveRetainDays, cli.RetainDaysSet), true)
	if err != nil {
		return err
	}
	printJSON(map[string]any{
		"observedAt":    time.Now().Format(time.RFC3339Nano),
		"observability": observability,
		"maintenance":   maintenance,
		"archive":       archive,
	})
	return nil
}

func runConfigureObservabilityOnce(ctx context.Context, pool *pgxpool.Pool, cli cliOptions) error {
	result, err := configurePostgresObservability(ctx, pool, cli.DryRun, cli.SlowMs)
	if err != nil {
		return err
	}
	printJSON(result)
	return nil
}

func runCleanupIndexesOnce(ctx context.Context, pool *pgxpool.Pool, cli cliOptions) error {
	result, err := cleanupObsoleteIndexes(ctx, pool, cli.DryRun)
	if err != nil {
		return err
	}
	printJSON(result)
	return nil
}

func runStrictSchemaMigrationOnce(ctx context.Context, pool *pgxpool.Pool, cli cliOptions) error {
	result, err := migrateStrictSchema(ctx, pool, cli.DryRun)
	if err != nil {
		return err
	}
	printJSON(result)
	return nil
}

func runArchiveOnce(ctx context.Context, pool *pgxpool.Pool, cfg config, cli cliOptions) error {
	retainDays := effectiveRetainDays(cli.RetainDays, cfg.ArchiveRetainDays, cli.RetainDaysSet)
	batchSize := effectivePositive(cli.BatchSize, cfg.ArchiveBatchSize, cli.BatchSizeSet)
	maxBatches := effectivePositive(cli.MaxBatches, cfg.ArchiveMaxBatches, cli.MaxBatchesSet)
	excludeLiked := !cli.IncludeLiked
	if err := ensureContentArchiveTables(ctx, pool); err != nil {
		return err
	}
	before, err := getContentArchiveStats(ctx, pool, retainDays, excludeLiked)
	if err != nil {
		return err
	}
	result, err := archiveOldContents(ctx, pool, archiveOptions{
		DryRun:       cli.DryRun,
		RetainDays:   retainDays,
		BatchSize:    batchSize,
		MaxBatches:   maxBatches,
		ExcludeLiked: excludeLiked,
	})
	if err != nil {
		return err
	}
	after, err := getContentArchiveStats(ctx, pool, retainDays, excludeLiked)
	if err != nil {
		return err
	}
	printJSON(map[string]any{
		"before": before,
		"result": result,
		"after":  after,
	})
	return nil
}

func migrateStrictSchema(ctx context.Context, pool *pgxpool.Pool, dryRun bool) (strictSchemaMigrationResult, error) {
	result := strictSchemaMigrationResult{
		DryRun: dryRun,
		Steps:  make([]strictSchemaStepResult, 0, len(strictSchemaSteps)),
	}
	for _, step := range strictSchemaSteps {
		stepResult := strictSchemaStepResult{
			Title:  step.Title,
			Status: "applied",
		}
		if dryRun {
			stepResult.Status = "dry_run"
			stepResult.SQL = strings.TrimSpace(step.SQL)
			result.Steps = append(result.Steps, stepResult)
			continue
		}
		if strings.TrimSpace(step.MarkerKey) != "" {
			applied, err := applyMarkedStrictSchemaStep(ctx, pool, step)
			if err != nil {
				return result, fmt.Errorf("%s: %w", step.Title, err)
			}
			if !applied {
				stepResult.Status = "skipped"
			}
			result.Steps = append(result.Steps, stepResult)
			continue
		}
		if _, err := pool.Exec(ctx, step.SQL); err != nil {
			return result, fmt.Errorf("%s: %w", step.Title, err)
		}
		result.Steps = append(result.Steps, stepResult)
	}
	return result, nil
}

func applyMarkedStrictSchemaStep(ctx context.Context, pool *pgxpool.Pool, step strictSchemaStep) (bool, error) {
	if pool == nil {
		return false, fmt.Errorf("postgres pool is nil")
	}
	if _, err := pool.Exec(ctx, `
CREATE TABLE IF NOT EXISTS ai_schema_migration_markers (
  marker_key TEXT PRIMARY KEY,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
)`); err != nil {
		return false, fmt.Errorf("ensure migration marker table: %w", err)
	}
	tx, err := pool.Begin(ctx)
	if err != nil {
		return false, err
	}
	defer func() { _ = tx.Rollback(ctx) }()
	var marker string
	err = tx.QueryRow(ctx, `
INSERT INTO ai_schema_migration_markers (marker_key)
VALUES ($1)
ON CONFLICT (marker_key) DO NOTHING
RETURNING marker_key`, strings.TrimSpace(step.MarkerKey)).Scan(&marker)
	if errors.Is(err, pgx.ErrNoRows) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	if _, err := tx.Exec(ctx, step.SQL); err != nil {
		return false, err
	}
	if err := tx.Commit(ctx); err != nil {
		return false, err
	}
	return true, nil
}
