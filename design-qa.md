# 知名投资人截图还原 Design QA

- Source visual truth: `/var/folders/hy/lx7mb0353670bfxg43qd3pmw0000gn/T/codex-clipboard-99801b5f-7dcc-4c99-9e76-b82be095653c.png`
- Implementation screenshot: `artifacts/implementation/investor-screenshot-recreation/final-light.png`
- Full-view comparison: `artifacts/implementation/investor-screenshot-recreation/final-comparison.png`
- Viewport: iPhone 17 Pro simulator, 368 × 800 points / 942 × 2048 pixels
- State: ARK / Cathie Wood, 2026 Q1, light appearance, overview at top scroll position

**Findings**

- No actionable P0/P1/P2 findings remain.
- The supplied source portrait depicts a different Cathie Wood photo. The implementation intentionally uses the existing production transparent portrait asset so the person remains authentic and the live investor carousel continues working.

**Required fidelity surfaces**

- Fonts and typography: native San Francisco weights reproduce the reference hierarchy; the Chinese display name, English name, institution, metric labels, values, section titles, badges, and notes remain readable without clipping.
- Spacing and layout rhythm: the header overlays the immersive hero, summary card follows the hero edge, the donut/actions and biggest-change sections use separate rounded cards, and all primary content fits the intended narrow viewport without horizontal overflow.
- Colors and visual tokens: the light grouped canvas, white cards, indigo selection, violet accents, blue/green/orange/pink action palette, soft shadows, and semantic secondary labels match the source direction.
- Image quality and asset fidelity: production transparent investor portraits and live company logos are used; no placeholder portrait, emoji, handmade SVG, or code-drawn company mark replaces a visible asset.
- Copy and content: the visible names, institution, follower count, report date, filing date, position count, total value, action counts/percentages, company rows, actions, and weight changes match the supplied reference state.

**Interactions tested**

- Launched directly into the investor screen with the debug preview state.
- Switched from `知名投资人` to `市场` and back successfully.
- Confirmed `查看更多`, root tabs, investor swipe accessibility actions, and the vertical scroll remain exposed as interactive controls.
- Runtime UI snapshot showed no clipped or off-screen primary control.

**Comparison history**

- Pass 1: the old compact segmented control, small portrait card, missing donut chart, and combined insights card were major mismatches.
- Fix: rebuilt the header, immersive hero, four-metric summary, donut/action distribution, independent biggest-change card, and reference-like styling.
- Pass 2: the simulator safe-area placed the header and hero lower than the source and hid more of the final card behind the tab bar.
- Fix: extended the holdings hero into the top safe area and retained explicit status/header spacing, moving the whole content rhythm upward while keeping controls clear.
- Final visual evidence: `artifacts/implementation/investor-screenshot-recreation/final-comparison.png`.

**Follow-up polish**

- A source-matching Cathie Wood cutout could make the portrait pose exact if that licensed image is supplied later.

final result: passed
