# 知名投资人截图还原 Design QA

- Source visual truth: normalized reference preserved as the left side of `artifacts/implementation/investor-screenshot-recreation/final-comparison.png`
- Implementation screenshot: `artifacts/implementation/investor-screenshot-recreation/simulator-verification/top-layer-corrected.png`
- Full-view comparison: `artifacts/implementation/investor-screenshot-recreation/simulator-verification/top-layer-final-comparison.png`
- Focused top-region comparison: `artifacts/implementation/investor-screenshot-recreation/simulator-verification/top-layer-focused-comparison.png`
- Simulator verification contact sheet: `artifacts/implementation/investor-screenshot-recreation/simulator-verification/contact-sheet.png`
- Final navigation screenshot: `artifacts/implementation/investor-screenshot-recreation/simulator-verification/navigation-final.png`
- Top safe-area correction screenshot: `artifacts/implementation/investor-screenshot-recreation/simulator-verification/top-safe-area-fixed.png`
- Final navigation comparison: `artifacts/implementation/investor-screenshot-recreation/simulator-verification/navigation-final-comparison.png`
- Secondary investor evidence: `artifacts/implementation/investor-screenshot-recreation/simulator-verification/warren-buffett.png`
- Detail navigation evidence: `artifacts/implementation/investor-screenshot-recreation/simulator-verification/detail-tab-hidden.png`
- Viewport: iPhone 17 Pro simulator, 368 × 800-point optimized inspection / 1206 × 2622-pixel native capture; comparison normalized to 942 × 2048 pixels
- State: ARK / Cathie Wood, 2026 Q1, light appearance, overview at top scroll position

**Findings**

- No actionable P0/P1/P2 findings remain.
- The supplied source portrait depicts a different Cathie Wood photo. The implementation intentionally uses the existing production transparent portrait asset so the person remains authentic and the live investor carousel continues working.

**Required fidelity surfaces**

- Fonts and typography: native San Francisco weights reproduce the reference hierarchy; the Chinese display name, English name, institution, metric labels, values, section titles, badges, and notes remain readable without clipping.
- Spacing and layout rhythm: the selector now starts 6 points below the device safe area, sits wholly on the hero gradient, and keeps an identical baseline when switching between market and holdings. The summary card follows the hero edge, the donut/actions and biggest-change sections use separate rounded cards, and all primary content fits the intended narrow viewport without horizontal overflow.
- Colors and visual tokens: the light grouped canvas, white cards, indigo selection, violet accents, blue/green/orange/pink action palette, soft shadows, and semantic secondary labels match the source direction.
- Image quality and asset fidelity: production transparent investor portraits and live company logos are used; no placeholder portrait, emoji, handmade SVG, or code-drawn company mark replaces a visible asset.
- Copy and content: the visible names, institution, follower count, report date, filing date, position count, total value, action counts/percentages, company rows, actions, and weight changes match the supplied reference state.

**Interactions tested**

- Launched directly into the investor screen with the debug preview state.
- Switched from `知名投资人` to `市场` and back successfully.
- Confirmed `查看更多`, root tabs, investor swipe accessibility actions, and the vertical scroll remain exposed as interactive controls.
- Runtime UI snapshot showed no clipped or off-screen primary control.
- Rechecked both `市场` and `知名投资人` after the top-safe-area correction: both selectors remain fully visible below the status bar, with no transform-driven clipping.
- Rechecked the selector while switching in both directions; neither label nor underline changes vertical position.
- Swiped from Cathie Wood to Warren Buffett and confirmed that portrait, identity, institution, filing summary, donut segments, action counts, and biggest-change rows all refreshed together.
- Entered the complete holdings screen, changed the filter to `增持 (86)`, scrolled the holdings list, and returned successfully.
- Checked the latest simulator runtime log for fatal errors, crashes, assertions, errors, faults, and warnings; none were emitted during the verification flow.

**Comparison history**

- Pass 1: the old compact segmented control, small portrait card, missing donut chart, and combined insights card were major mismatches.
- Fix: rebuilt the header, immersive hero, four-metric summary, donut/action distribution, independent biggest-change card, and reference-like styling.
- Pass 2: the simulator safe-area placed the header and hero lower than the source and hid more of the final card behind the tab bar.
- Fix: extended the holdings hero into the top safe area and retained explicit status/header spacing, moving the whole content rhythm upward while keeping controls clear.
- Simulator verification pass: opening `查看更多` left the root tab bar visible over the complete holdings list, obscuring its bottom rows (P2).
- Fix: propagated `holdingsShowsDetail` to the root tab visibility state. The post-fix runtime snapshot exposes only detail controls, and `detail-tab-hidden.png` confirms the root tab bar no longer overlaps the list.
- Navigation correction pass: the iOS 26 system tab bar introduced a selected glass capsule, used `投资` instead of the source's `数据`, floated too high, and was narrower than the reference. The top selector was also one safe-area offset too low, with oversized spacing and underline (P1).
- Fix: replaced the system TabView chrome with a custom three-button root shell, matched the white near-full-width capsule, gray/purple selected states, source labels and outline icons, and retained automatic hiding on details. Tightened and raised the top selector, then reduced the hero height so the summary card aligns with the reference's vertical rhythm.
- Post-fix evidence: `navigation-final-comparison.png` shows the top selector and bottom navigation aligned to the normalized source; simulator snapshots confirm `观点 / 数据 / 人物` switch correctly and detail screens expose no root navigation controls.
- Top clipping regression: raising the selector with a negative vertical offset moved its glyphs outside the parent render bounds, so `市场` could be visibly cropped at the top (P1).
- Fix: removed the negative offset, let only the investment overview background extend into the top safe area, and reserved an explicit 46-point status/header inset. `top-safe-area-fixed.png` confirms both labels and the underline are fully rendered; market and holdings-detail checks confirm the correction does not leak into other screens.
- Safe-area layering pass: the explicit 46-point inset still placed the selector inside the iPhone 17 Pro status-bar region, while the hero began at the system safe-area boundary. This created a visible horizontal cut through the selector region; the market variant also added symmetric vertical padding, causing an 8-point jump when switching sections (P1).
- Fix: restored system-managed top safe-area layout, removed the fixed top compensation, and moved the market-only spacing to bottom padding so both sections share one selector baseline. `top-layer-focused-comparison.png` confirms the selector is below the status bar and fully contained in the continuous hero treatment; the market, holdings, and detail simulator captures show no regression.
- Final spacing refinement: the selector still touched the safe-area boundary too tightly (P3). Added a shared 6-point top inset and reduced only the market header's bottom spacer from 16 to 10 points, preserving the downstream content position and the identical market/holdings baseline. The refreshed focused comparison confirms the intended breathing room.
- Automated verification: 72 tests passed, 0 failed, 0 skipped after the safe-area fix.
- Final visual evidence: `artifacts/implementation/investor-screenshot-recreation/simulator-verification/top-layer-final-comparison.png`.

**Follow-up polish**

- A source-matching Cathie Wood cutout could make the portrait pose exact if that licensed image is supplied later.

final result: passed
