# Market Redesign Design QA

- source visual truth path: `/Users/wangheng/.codex/generated_images/019f6392-579d-77e2-b48d-df618cf47589/exec-f3610e60-a4ab-4928-9cc7-42cc42045a8e.png`
- implementation screenshot path: `/Users/wangheng/Desktop/ai_server_ios/.artifacts/market-redesign/03-implementation-final.png`
- viewport: iPhone 17 Pro simulator, 390 × 844 points (1206 × 2622 pixels)
- state: Market tab, United States selected, US session closed, live production dashboard data
- full-view comparison evidence: `/Users/wangheng/Desktop/ai_server_ios/.artifacts/market-redesign/03-comparison-preview.png`
- focused hero comparison: `/Users/wangheng/Desktop/ai_server_ios/.artifacts/market-redesign/03-hero-comparison.png`
- focused table comparison: `/Users/wangheng/Desktop/ai_server_ios/.artifacts/market-redesign/03-table-comparison.png`
- detail regression evidence: `/Users/wangheng/Desktop/ai_server_ios/.artifacts/market-redesign/04-detail-regression.png`

## Findings

No actionable P0, P1, or P2 differences remain.

- Typography: The implementation uses system typography with tabular numerals, matching the mock's hierarchy. The lead price, region selector, table headers, quote names, and changes remain legible without wrapping or truncation in the captured state.
- Spacing and layout rhythm: The dark hero, rounded light content sheet, region selector, quote table, and global overview follow the reference composition. Native iOS status-bar space moves the content slightly lower than the frameless mock; this is an accepted platform constraint.
- Colors and visual tokens: The implementation matches the near-black header, warm light content surface, blue selection state, and red-up/green-down semantics. Dividers and fills remain restrained.
- Image and asset fidelity: The target contains no required raster imagery. Charts and the sentiment ring are live data-driven UI. Country flags from the generated concept were intentionally omitted rather than replaced with fake or inconsistent assets.
- Copy and content: Visible labels match the selected concept where backed by available data. Russell 2000, TOPIX, and KOSDAQ shown in the generated concept were not implemented because the current backend does not provide reliable real data for them.
- Accessibility: Region controls and quote rows retain button semantics, selected state, 44-point-or-larger interaction targets, and accessible contrast. VoiceOver reading order and Dynamic Type still require a separate device audit.

## Comparison History

1. Initial implementation: P1 — the lead price wrapped onto a second line at 390 points wide. Fix: reduced the display size, tightened tracking, and added a single-line scaling guard. Post-fix evidence: `03-hero-comparison.png`; the full price now renders on one line.
2. Initial table density: P2 — quote rows delayed the global overview too far below the fold. Fix: reduced table header, row, and session-note heights while preserving readable type and touch targets. Post-fix evidence: `03-table-comparison.png`; the global overview heading now appears above the persistent tab bar.

## Interaction Verification

- The market screen loads real dashboard data and live connection state.
- The primary quote and table rows remain wired to the existing index-detail route.
- The detail route was launched after the redesign and rendered successfully; existing chart ranges, watchlist, share, and edge-swipe return code remain intact.
- Region selection uses local SwiftUI state and changes the lead quote, table rows, and session footnote together.

## Follow-up Polish

- P3: Run a dedicated VoiceOver and largest-Dynamic-Type pass on physical hardware.
- P3: Consider adding verified TOPIX or KOSDAQ feeds later; do not add placeholder values.

final result: passed
