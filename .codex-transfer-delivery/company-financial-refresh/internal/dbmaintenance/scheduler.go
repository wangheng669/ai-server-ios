package dbmaintenance

import (
	"context"
	"log"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

func runScheduler(ctx context.Context, pool *pgxpool.Pool, cfg config) error {
	maintenanceSchedule := parseCronScheduleWithFallback(cfg.MaintenanceCron, defaultMaintenanceCron)
	observabilitySchedule := parseCronScheduleWithFallback(cfg.ObservabilityCron, defaultObservabilityCron)
	archiveSchedule := parseCronScheduleWithFallback(cfg.ArchiveCron, defaultArchiveCron)
	companyFinancialSchedule := parseCronScheduleWithFallback(cfg.CompanyFinancialCron, defaultCompanyFinancialCron)
	observabilityGate := newNightExecutionGate("db_observability", cfg.ObservabilityNight)

	logJSON("[db-maintenance-runner] 调度器已启动", map[string]any{
		"maintenanceCron":      cfg.MaintenanceCron,
		"observabilityCron":    cfg.ObservabilityCron,
		"archiveCron":          cfg.ArchiveCron,
		"companyFinancialCron": cfg.CompanyFinancialCron,
		"archiveEnabled":       cfg.ArchiveEnabled,
		"archiveRetainDays":    cfg.ArchiveRetainDays,
		"archiveBatchSize":     cfg.ArchiveBatchSize,
		"esRetentionEnabled":   cfg.ESRetentionEnabled,
		"esRetentionDays":      cfg.ESRetentionDays,
		"observabilityNightMode": map[string]any{
			"taskKey":           cfg.ObservabilityNight.TaskKey,
			"enabled":           cfg.ObservabilityNight.Enabled,
			"startHour":         cfg.ObservabilityNight.StartHour,
			"endHour":           cfg.ObservabilityNight.EndHour,
			"timeZone":          cfg.ObservabilityNight.TimeZone,
			"nightIntervalMs":   cfg.ObservabilityNight.NightIntervalMs,
			"baseIntervalMs":    cfg.ObservabilityNight.BaseIntervalMs,
			"defaultMultiplier": cfg.ObservabilityNight.DefaultMultiple,
		},
	})

	if cfg.MaintenanceRunOnStart {
		if err := runMaintenanceJob(ctx, pool, cfg); err != nil {
			log.Printf("[db-maintenance-runner] 启动维护失败: %v", err)
		}
		if err := runObservabilityJob(ctx, pool); err != nil {
			log.Printf("[db-maintenance-runner] 启动观测快照失败: %v", err)
		}
		observabilityGate.markStarted(time.Now())
		if cfg.ArchiveEnabled && cfg.ArchiveRunOnStart {
			if err := runArchiveJob(ctx, pool, cfg); err != nil {
				log.Printf("[db-maintenance-runner] 启动归档失败: %v", err)
			}
		}
	}
	if cfg.CompanyFinancialRunOnStart {
		if result, err := runCompanyFinancialRefreshJob(ctx, pool); err != nil {
			log.Printf("[db-maintenance-runner] 启动公司财报补数失败: %v", err)
		} else {
			logJSON("[db-maintenance-runner] 启动公司财报补数完成", result)
		}
	}

	go runCronLoop(ctx, maintenanceSchedule, func(jobCtx context.Context) {
		if err := runMaintenanceJob(jobCtx, pool, cfg); err != nil {
			log.Printf("[db-maintenance-runner] 日常维护失败: %v", err)
		}
	})
	go runCronLoop(ctx, observabilitySchedule, func(jobCtx context.Context) {
		inspection := observabilityGate.inspect(time.Now())
		if !inspection.ShouldRun {
			return
		}
		observabilityGate.markStarted(time.Now())
		if err := runObservabilityJob(jobCtx, pool); err != nil {
			log.Printf("[db-maintenance-runner] 观测快照失败: %v", err)
		}
	})
	go runCronLoop(ctx, archiveSchedule, func(jobCtx context.Context) {
		if err := runArchiveJob(jobCtx, pool, cfg); err != nil {
			log.Printf("[db-maintenance-runner] 归档任务失败: %v", err)
		}
	})
	go runCronLoop(ctx, companyFinancialSchedule, func(jobCtx context.Context) {
		result, err := runCompanyFinancialRefreshJob(jobCtx, pool)
		if err != nil {
			log.Printf("[db-maintenance-runner] 公司财报补数失败: %v", err)
			return
		}
		logJSON("[db-maintenance-runner] 公司财报补数完成", result)
	})

	<-ctx.Done()
	return ctx.Err()
}

func runMaintenanceJob(ctx context.Context, pool *pgxpool.Pool, cfg config) error {
	log.Printf("[db-maintenance-runner] 开始执行日常维护")
	settings, err := ensureTableMaintenanceSettings(ctx, pool, tableMaintenanceProfiles)
	if err != nil {
		return err
	}
	stats, err := getTableMaintenanceStats(ctx, pool, defaultMaintenanceTables())
	if err != nil {
		return err
	}
	tables, skipped := filterTablesForScheduledVacuum(stats, tableMaintenanceProfiles, time.Now())
	vacuum, err := vacuumAnalyzeTables(ctx, pool, tables, false)
	if err != nil {
		return err
	}
	vacuum.Skipped = append(vacuum.Skipped, skipped...)
	logJSON("[db-maintenance-runner] 日常维护完成", map[string]any{
		"settings": settings,
		"vacuum":   vacuum,
	})
	if cfg.ESRetentionEnabled {
		retention, err := deleteExpiredElasticsearchPosts(ctx, cfg.ESNode, cfg.ESIndex, cfg.ESRetentionDays)
		if err != nil {
			return err
		}
		logJSON("[db-maintenance-runner] Elasticsearch 保留策略完成", retention)
	}
	return nil
}

func runObservabilityJob(ctx context.Context, pool *pgxpool.Pool) error {
	observability, err := getPostgresObservabilityStatus(ctx, pool, true, 5)
	if err != nil {
		return err
	}
	logJSON("[db-maintenance-runner] 数据库观测快照", map[string]any{
		"ready":           observability.Ready,
		"issues":          observability.Issues,
		"slowQueries":     observability.SlowQueries,
		"requiredIndexes": observability.RequiredIndexes,
	})
	return nil
}

func runArchiveJob(ctx context.Context, pool *pgxpool.Pool, cfg config) error {
	if !cfg.ArchiveEnabled {
		log.Printf("[db-maintenance-runner] 归档任务已禁用")
		return nil
	}
	stats, err := getContentArchiveStats(ctx, pool, cfg.ArchiveRetainDays, true)
	if err != nil {
		return err
	}
	logJSON("[db-maintenance-runner] 归档前统计", stats)
	result, err := archiveOldContents(ctx, pool, archiveOptions{
		RetainDays:   cfg.ArchiveRetainDays,
		BatchSize:    cfg.ArchiveBatchSize,
		MaxBatches:   cfg.ArchiveMaxBatches,
		ExcludeLiked: true,
	})
	if err != nil {
		return err
	}
	logJSON("[db-maintenance-runner] 归档任务完成", result)
	return nil
}
