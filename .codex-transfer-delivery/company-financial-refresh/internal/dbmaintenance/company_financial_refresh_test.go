package dbmaintenance

import (
	"testing"
	"time"
)

func TestFinancialPeriodCalendarCompanies(t *testing.T) {
	got := financialPeriod(time.Date(2026, time.June, 30, 0, 0, 0, 0, time.UTC), false)
	if got != "2026 Q2" {
		t.Fatalf("financialPeriod() = %q", got)
	}
}

func TestFinancialPeriodNVIDIAFiscalYear(t *testing.T) {
	tests := []struct {
		month time.Month
		want  string
	}{
		{time.January, "FY26 Q4"}, {time.April, "FY27 Q1"},
		{time.July, "FY27 Q2"}, {time.October, "FY27 Q3"},
	}
	for _, test := range tests {
		got := financialPeriod(time.Date(2026, test.month, 30, 0, 0, 0, 0, time.UTC), true)
		if got != test.want {
			t.Errorf("month %s: got %q, want %q", test.month, got, test.want)
		}
	}
}

func TestRound2(t *testing.T) {
	if got := round2(106.198); got != 106.20 {
		t.Fatalf("round2 positive = %v", got)
	}
	if got := round2(-2.345); got != -2.35 {
		t.Fatalf("round2 negative = %v", got)
	}
}
