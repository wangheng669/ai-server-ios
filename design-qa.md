# Market Screen Design & Data QA

- Reference: `/var/folders/hy/lx7mb0353670bfxg43qd3pmw0000gn/T/codex-clipboard-8a42f2dc-939d-41f3-b806-67e945ad2df7.png`
- Live home capture: `/Users/wangheng/Desktop/ai-server-ios/artifacts/implementation/market-live-home-final.png`
- Live detail capture: `/Users/wangheng/Desktop/ai-server-ios/artifacts/implementation/market-live-detail-final.png`
- Viewport: iPhone 17 Pro simulator, 402 × 874 points, light mode
- API contract: `market_dashboard_v1`

## Result

The market home and Nasdaq 100 detail screen pass visual and live-data QA. The implementation preserves the reference's dense financial-dashboard hierarchy without clipping or overlapping content. Root tabs are sibling `TabView` pages, so switching to Market does not present it from the bottom; index detail remains a conventional in-stack push.

## Live-data coverage

- Dashboard: sentiment, VIX, US 10-year yield, six global indices, A-share breadth, and hot sectors.
- Detail: latest quote, previous-close move, intraday chart, OHLC, volume, status, generated market summary, and five component stocks.
- Freshness: dashboard polling follows the server-provided 15-second interval; pull-to-refresh is available.
- Realtime: `/post` WebSocket quote events merge into the visible dashboard and detail quote.
- Resilience: the last valid dashboard is cached locally; loading, stale, empty-range, and retryable error states are explicit.
- No reference prices or mock market fixtures remain in `AIClient/Features/Market`.

## Verification evidence

- iOS simulator build, install, launch, home capture, and detail capture succeeded.
- Two live dashboard reads 18 seconds apart showed the Nasdaq 100 timestamp advancing and the price changing.
- A live WebSocket session received a `^NDX` market event.
- Dashboard returned all 13 required symbols with `missingSymbols: []` and `stale: false` for Nasdaq 100.
- Backend market API tests and targeted ingestion/API route tests passed before deployment; the deployed market API container is healthy.
- Local and backend diff whitespace checks passed.

## Visual findings

- Typography, red/green semantics, warm canvas, low-elevation cards, two-column index grid, compact metric grid, and horizontal sector/stock rows match the intended visual language.
- VIX and yield values remain on one line at the tested viewport.
- Detail title, quote, range selector, area chart, volume bars, key-data grid, summary, and component row fit without layout defects.
- Approved exchange flags and company logo assets were not supplied, so consistent symbol/letter marks are used.

final result: passed
