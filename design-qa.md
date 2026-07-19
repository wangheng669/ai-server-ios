# 知名投资人透明主视觉 Design QA

- Source visual truth: `artifacts/implementation/investor-transparent-hero/selected-option-2.png`
- Implementation screenshots: `artifacts/implementation/investor-transparent-hero/light.png`, `artifacts/implementation/investor-transparent-hero/dark.png`
- Full comparison: `artifacts/implementation/investor-transparent-hero/comparison-light.png`
- Eight-investor light contact sheet: `artifacts/audit/investor-portraits-light-fixed/contact-sheet.jpg`
- Eight-investor dark contact sheet: `artifacts/audit/investor-portraits-dark-fixed/contact-sheet.jpg`
- Viewport: iPhone 17 Pro simulator, 368 × 800 capture
- State: ARK 2026 Q1 overview, light and dark appearances

**Findings**

- No actionable P0/P1/P2 findings remain.
- The implementation intentionally retains the existing compact app header and denser data cards instead of copying the concept image's enlarged decorative chrome.

**Required fidelity surfaces**

- Fonts and typography: native San Francisco hierarchy is readable; name, institution, metrics, section titles, and secondary notes do not clip.
- Spacing and layout rhythm: restored immersive hero occupies the original page position; no avatar strip or duplicate profile card remains; the filing summary begins immediately below the hero.
- Colors and tokens: the hero uses semantic light/dark gradients, a theme-aware violet halo, and a localized left text veil; cards continue using Apple grouped system colors.
- Image quality: the server transparent WebP is rendered as a large editorial cutout with no circle crop, rectangular photo boundary, visible white fringe, or dark baked background.
- Copy and content: the top switch reads `市场 / 知名投资人`; `查看完整持仓` remains a quiet title-row action.

**Interactions tested**

- Switched from `知名投资人` to `市场` successfully.
- Verified the investor page exposes swipe-based previous/next accessibility actions.
- Verified Share and `查看完整持仓` remain accessible controls.

**Comparison history**

- Pass 1: main portrait sat too close to the center and was dimmed by the left veil.
- Fix: moved the transparent cutout right, increased its scale, and limited the text veil to the left portion of the hero.
- Pass 2: light and dark captures show clear text, a readable portrait, and stable semantic surfaces.

**Follow-up polish**

- No residual per-investor focal adjustment is needed after the eight-person review.

**Eight-investor verification**

- Reviewed ARK, Berkshire, Duan Yongping, Li Lu, Dan Bin, Bridgewater, Soros, and Masayoshi Son in sequence in both appearances.
- Fixed a reused-image defect: when the live API omitted `portraitUrl`, the image task previously kept the first manager's portrait. It now refreshes by `manager.key` and clears stale state before loading.
- All eight final portraits keep the face clear of the left text block, retain the head and shoulders, and preserve a consistent eye line. No per-person focal override is currently necessary.

final result: passed
