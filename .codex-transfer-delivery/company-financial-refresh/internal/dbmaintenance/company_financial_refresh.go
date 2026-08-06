package dbmaintenance

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"sort"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

const tradingViewScanURL = "https://scanner.tradingview.com/global/scan"

type companyFinancialTarget struct {
	ID, Symbol, Unit        string
	NVIDIA, ConvertUSDToCNY bool
}
type financialPoint struct {
	Period    string  `json:"period"`
	Revenue   float64 `json:"revenue"`
	NetProfit float64 `json:"netProfit"`
}
type financialForecast struct {
	Period    string   `json:"period"`
	Range     string   `json:"range,omitempty"`
	Revenue   *float64 `json:"revenue,omitempty"`
	NetProfit *float64 `json:"netProfit,omitempty"`
	Note      string   `json:"note,omitempty"`
}
type companyFinancials struct {
	Unit      string              `json:"unit"`
	Years     json.RawMessage     `json:"years"`
	Quarters  []financialPoint    `json:"quarters"`
	Forecasts []financialForecast `json:"forecasts,omitempty"`
	Source    json.RawMessage     `json:"source,omitempty"`
}
type fetchedFinancial struct {
	Period, Currency, SourceURL string
	Revenue, NetProfit          float64
	End                         time.Time
}
type companyFinancialRefreshResult struct {
	Checked          int               `json:"checked"`
	Updated          int               `json:"updated"`
	Unchanged        int               `json:"unchanged"`
	Errors           map[string]string `json:"errors,omitempty"`
	UpdatedCompanies []string          `json:"updatedCompanies,omitempty"`
}

var companyFinancialTargets = []companyFinancialTarget{
	{"kweichow-moutai", "SSE:600519", "亿元", false, false},
	{"wuliangye", "SZSE:000858", "亿元", false, false},
	{"pdd-holdings", "NASDAQ:PDD", "亿元", false, true},
	{"nvidia", "NASDAQ:NVDA", "亿美元", true, false},
	{"alphabet", "NASDAQ:GOOGL", "亿美元", false, false},
}

func runCompanyFinancialRefreshJob(ctx context.Context, pool *pgxpool.Pool) (companyFinancialRefreshResult, error) {
	result := companyFinancialRefreshResult{Errors: map[string]string{}}
	client := &http.Client{Timeout: 20 * time.Second}
	for _, target := range companyFinancialTargets {
		result.Checked++
		item, err := fetchTradingViewQuarter(ctx, client, target)
		if err == nil && target.ConvertUSDToCNY {
			item, err = convertFinancialToCNY(ctx, client, item)
		}
		if err != nil {
			result.Errors[target.ID] = err.Error()
			continue
		}
		changed, err := storeFinancialQuarter(ctx, pool, target, item)
		if err != nil {
			result.Errors[target.ID] = err.Error()
			continue
		}
		if changed {
			result.Updated++
			result.UpdatedCompanies = append(result.UpdatedCompanies, target.ID)
		} else {
			result.Unchanged++
		}
	}
	if len(result.Errors) == 0 {
		result.Errors = nil
	}
	if result.Checked > 0 && result.Checked == len(result.Errors) {
		return result, fmt.Errorf("all company financial refreshes failed")
	}
	return result, nil
}

func fetchTradingViewQuarter(ctx context.Context, client *http.Client, target companyFinancialTarget) (fetchedFinancial, error) {
	payload := map[string]any{"symbols": map[string]any{"tickers": []string{target.Symbol}, "query": map[string]any{"types": []string{}}}, "columns": []string{"total_revenue_fq", "net_income_fq", "currency", "fiscal_period_end_fq"}}
	body, _ := json.Marshal(payload)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, tradingViewScanURL, bytes.NewReader(body))
	if err != nil {
		return fetchedFinancial{}, err
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := client.Do(req)
	if err != nil {
		return fetchedFinancial{}, err
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return fetchedFinancial{}, err
	}
	if resp.StatusCode != http.StatusOK {
		return fetchedFinancial{}, fmt.Errorf("scanner status %d", resp.StatusCode)
	}
	var decoded struct {
		Data []struct {
			D []json.RawMessage `json:"d"`
		} `json:"data"`
	}
	if err := json.Unmarshal(data, &decoded); err != nil || len(decoded.Data) == 0 || len(decoded.Data[0].D) < 4 {
		return fetchedFinancial{}, fmt.Errorf("invalid scanner response")
	}
	var revenue, profit, epoch float64
	var currency string
	if json.Unmarshal(decoded.Data[0].D[0], &revenue) != nil || json.Unmarshal(decoded.Data[0].D[1], &profit) != nil || json.Unmarshal(decoded.Data[0].D[2], &currency) != nil || json.Unmarshal(decoded.Data[0].D[3], &epoch) != nil {
		return fetchedFinancial{}, fmt.Errorf("incomplete scanner values")
	}
	end := time.Unix(int64(epoch), 0).UTC()
	return fetchedFinancial{Period: financialPeriod(end, target.NVIDIA), Revenue: revenue / 1e8, NetProfit: profit / 1e8, Currency: currency, End: end, SourceURL: "https://www.tradingview.com/markets/stocks-usa/market-movers-all-stocks/"}, nil
}

func convertFinancialToCNY(ctx context.Context, client *http.Client, item fetchedFinancial) (fetchedFinancial, error) {
	if item.Currency == "CNY" {
		return item, nil
	}
	url := fmt.Sprintf("https://api.frankfurter.app/%s?from=%s&to=CNY", item.End.Format("2006-01-02"), item.Currency)
	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	resp, err := client.Do(req)
	if err != nil {
		return item, err
	}
	defer resp.Body.Close()
	var decoded struct {
		Rates map[string]float64 `json:"rates"`
	}
	if resp.StatusCode != http.StatusOK || json.NewDecoder(io.LimitReader(resp.Body, 1<<20)).Decode(&decoded) != nil || decoded.Rates["CNY"] <= 0 {
		return item, fmt.Errorf("failed to load fiscal-period exchange rate")
	}
	item.Revenue *= decoded.Rates["CNY"]
	item.NetProfit *= decoded.Rates["CNY"]
	item.Currency = "CNY"
	item.SourceURL = "https://investor.pddholdings.com/financial-information/quarterly-results"
	return item, nil
}

func financialPeriod(end time.Time, nvidia bool) string {
	if nvidia {
		fy := end.Year()
		q := 4
		switch end.Month() {
		case time.April:
			fy++
			q = 1
		case time.July:
			fy++
			q = 2
		case time.October:
			fy++
			q = 3
		}
		return fmt.Sprintf("FY%d Q%d", fy%100, q)
	}
	return fmt.Sprintf("%d Q%d", end.Year(), (int(end.Month())-1)/3+1)
}

func storeFinancialQuarter(ctx context.Context, pool *pgxpool.Pool, target companyFinancialTarget, item fetchedFinancial) (bool, error) {
	var raw []byte
	if err := pool.QueryRow(ctx, `SELECT financials FROM ai_company_research_profiles WHERE id=$1 AND is_active=TRUE`, target.ID).Scan(&raw); err != nil {
		return false, err
	}
	var f companyFinancials
	if err := json.Unmarshal(raw, &f); err != nil {
		return false, err
	}
	for _, q := range f.Quarters {
		if strings.EqualFold(q.Period, item.Period) {
			return false, nil
		}
	}
	f.Quarters = append(f.Quarters, financialPoint{Period: item.Period, Revenue: round2(item.Revenue), NetProfit: round2(item.NetProfit)})
	sort.SliceStable(f.Quarters, func(i, j int) bool { return f.Quarters[i].Period < f.Quarters[j].Period })
	kept := f.Forecasts[:0]
	for _, forecast := range f.Forecasts {
		if !strings.EqualFold(forecast.Period, item.Period) {
			kept = append(kept, forecast)
		}
	}
	f.Forecasts = kept
	updated, err := json.Marshal(f)
	if err != nil {
		return false, err
	}
	command, err := pool.Exec(ctx, `UPDATE ai_company_research_profiles SET financials=$2::jsonb, updated_at=NOW() WHERE id=$1`, target.ID, updated)
	return command.RowsAffected() == 1, err
}

func round2(v float64) float64 {
	if v < 0 {
		return float64(int64(v*100-0.5)) / 100
	}
	return float64(int64(v*100+0.5)) / 100
}
