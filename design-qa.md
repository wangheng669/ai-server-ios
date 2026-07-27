# Industry Panorama Design QA

- Source visual truth: `/var/folders/hy/lx7mb0353670bfxg43qd3pmw0000gn/T/codex-clipboard-83663614-790e-4a29-a001-5b81f78fceab.png`
- Implementation screenshot: `/var/folders/hy/lx7mb0353670bfxg43qd3pmw0000gn/T/screenshot_optimized_3f51291c-5c14-4b9f-9d34-c4fd12802704.jpg`
- Viewport: iPhone 17 Pro Max simulator, portrait
- Source pixels: 852 × 1846, normalized to 369 × 800
- Implementation pixels: 368 × 800
- State: Data → Industry Panorama → New Energy Vehicle, top of page

## Full-view comparison evidence

The revised implementation now matches the reference's principal composition: one compact industry selector; asymmetric scale block with large green serif value on the left and a four-point green area/line chart on the right; amber section rule; three connected upstream/midstream/downstream groups; company monograms embedded in the relevant groups; and an off-white editorial surface.

The app's existing bottom tab bar remains visible because it is global product navigation. The reference omits that app-owned chrome. Unsupported quote prices and percentage changes were not copied from the concept; the implementation's footer uses real ticker codes from the API.

## Focused region comparison evidence

- Scale block: the value/unit split, chart domain, axis labels, point markers, source attribution, and spacing were checked at native simulator density.
- Chain block: three stage circles, continuous connector, stage headings, descriptions, chips, and company placement were checked directly.
- Data integrity: chart points are 2021 `352.1`, 2022 `688.7`, 2023 `949.5`, and 2024 `1286.6` 万辆, each with an official source URL in the API.

## Required fidelity surfaces

- Fonts and typography: system Chinese UI type plus a serif display value reproduce the reference hierarchy and remain readable.
- Spacing and layout rhythm: 16 pt page margins, compact selector, asymmetric scale/chart region, and three-stage vertical rhythm align with the normalized source.
- Colors and visual tokens: warm off-white, emerald, pale green chips, dark ink text, and the amber rule match the source.
- Image quality and asset fidelity: no raster assets are required; native Swift Charts and SF Symbols remain sharp at device density.
- Copy and content: visible values, historical points, stage relationships, company roles, and tickers come from the source-backed API or the identical offline fallback.

## Findings

- No actionable P0, P1, or P2 fidelity issues remain.
- Accepted product constraint: global bottom navigation remains present.
- Accepted data constraint: illustrative stock prices and percentage changes are replaced by verified ticker codes.

## Comparison history

- Pass 1 found a P1 mismatch: no historical chart, four small chain nodes, and a repeated company section.
- Fix: added source-backed historical data, native chart, three grouped chain stages, embedded company anchors, and a single ticker strip.
- Pass 2 found a P2 mismatch: the chart was compressed and rendered the year values as a continuous axis.
- Fix: allocated explicit width to the scale value, changed years to categorical labels, and fixed the verified 200–1,400 万辆 domain.
- Post-fix evidence: the current simulator screenshot shows the same left-value/right-chart structure and three-stage chain as the source.

## Interaction and verification

- Industry selection, vertical scrolling, source link, and bottom navigation remain functional.
- Simulator build succeeded without warnings.
- iOS test suite: 109 passed, 0 failed, 0 skipped.
- Public API returned all four historical points and company `stage_id`/ticker metadata.

final result: passed
