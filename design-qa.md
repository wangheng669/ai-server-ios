# Design QA — AI Server iOS news feed

## Scope

- Source product: `http://47.100.175.141:3001/`
- Source screenshots:
  - `artifacts/reference/m-site-x.png`
  - `artifacts/reference/m-site-bilibili.png`
  - `artifacts/reference/m-site-rss.png`
- Implementation screenshots:
  - `artifacts/implementation/final-x.png`
  - `artifacts/implementation/final-bilibili.png`
  - `artifacts/implementation/final-rss.png`
  - `artifacts/implementation/native-top-tabs.png`
- Combined comparisons:
  - `artifacts/comparisons/x-pass1.png`
  - `artifacts/comparisons/bilibili-final.png`
  - `artifacts/comparisons/rss-final.png`
  - `artifacts/comparisons/top-tabs-pass1.png`
- Reference viewport: 390 × 844 CSS px
- Implementation viewport: iPhone 14, 1170 × 2532 px, normalized to 390 × 844
- State: signed-out public feed, live production data, light appearance

## Comparison history

### Pass 1 — blocked

- P1: the native screen used a large navigation title and left a large blank region above the feed.
- P1: only four source tabs were present, while the mobile source exposes X, 微博, 抖音, B站, 知乎, Truth, RSS, 老中, YouTube, 快讯, 日报.
- P1: one generic rounded card was used for every source; B站 and RSS density did not match.
- P2: feed rows used disclosure chevrons and card insets absent from the source.
- P2: the fixed three-item bottom navigation was missing.

Resolution: replaced the generic navigation/list shell with edge-to-edge source tabs, source-specific cards, compact separators, and the fixed mobile bottom bar.

### Pass 2 — blocked after device regression report

- Full-screen X comparison: hierarchy, edge-to-edge rhythm, tab underline, author metadata, media slot, actions, separators, and bottom navigation align with the mobile source.
- Focused B站 comparison: compact avatar/text/thumbnail rows, metadata, score badge, and density align.
- Focused RSS comparison: long-form hierarchy, author/source metadata, readable line spacing, media, actions, and tags align.
- Native-only safe-area/status presentation is retained intentionally; live post order and content can differ between captures.
- Interaction check: source switching, pull-to-refresh, pagination, detail navigation/back, original link/share, settings, and bottom destinations are wired.
- State check: initial loading, empty channel, retry, non-blocking pagination error, cached images/data, and server timeout are represented.

Resolution: the reported media and channel-source issues were corrected in the following implementation pass. Per the user's direction, the current pass does not repeat data validation and is scoped to bottom navigation.

### Pass 3 — native bottom navigation redesign

- Reference: the three-destination structure in `artifacts/reference/m-site-x.png`.
- Full implementation: `artifacts/implementation/native-tabbar.png`.
- Focused implementation: `artifacts/implementation/native-tabbar-focus.png`.
- The destination count and labels remain 主页、市场、事件, preserving the mobile product's information architecture.
- The previous custom full-width bar is intentionally replaced by the iOS 27 native Liquid Glass tab bar.
- The system supplies equal touch targets, safe-area placement, selected-state tint, material behavior, and SF Symbols.
- Feed content remains visible beneath the translucent system material as intended by the platform.
- Visual check on the physical iPhone found no clipping, crowding, incorrect inset, or ambiguous selected state.

### Pass 4 — native top channel navigation redesign

- Source visual truth: `artifacts/reference/m-site-x-top-tabs.png`.
- Full implementation: `artifacts/implementation/native-top-tabs.png`.
- Focused implementation: `artifacts/implementation/native-top-tabs-focus.png`.
- Combined comparison: `artifacts/comparisons/top-tabs-pass1.png`.
- Viewport and state: iPhone 14, 1170 × 2532, light appearance, X selected, live feed.
- Information architecture remains faithful: the same ordered channel labels are horizontally scrollable, with 日报 retained after the feed sources.
- The selected underline is intentionally replaced by a system-blue capsule with a matched native transition; the bar uses system material and selection haptics.
- The settings action is fixed at the trailing edge so horizontal channel scrolling cannot hide it.
- Typography: system text styles and semantic weights remain readable without changing the product's label hierarchy.
- Spacing and layout: 34-point controls sit in a 52-point bar; the selected state, divider, and fixed settings target have no clipping or crowding.
- Colors: semantic tint, primary text, system bar material, and separators adapt to system appearance.
- Image and icon fidelity: this region has no raster assets; the settings action uses the platform SF Symbol rather than a custom drawing.
- Copy: all channel names and 日报 remain unchanged.
- Interaction: source selection, animated centering, persistent source state, selection feedback, 日报, and settings actions remain wired. Physical-device build and launch passed.
- Findings: P0 none, P1 none, P2 none.

### Pass 5 — icon channel rail with scroll refinement

- Source visual truth: `artifacts/reference/icon-top-tabs-reference.png`.
- Full implementation: `artifacts/implementation/icon-top-tabs-scroll.png`.
- Focused implementation: `artifacts/implementation/icon-top-tabs-scroll-focus.png`.
- Combined comparison: `artifacts/comparisons/icon-top-tabs-scroll.png`.
- Viewport and state: iPhone 14, 1170 × 2532, light appearance, X selected, live feed.
- Earlier finding: the first icon implementation forced all 12 actions into one screen width, making the channel rail feel cramped.
- Fix: increased source icons to 21 points and touch slots to 40 × 50 points, made channels horizontally scrollable, and kept settings fixed at the trailing edge.
- Typography: the reference contains no visible tab labels; implementation likewise relies on icons while retaining full accessibility labels.
- Spacing and layout: larger evenly spaced icons match the requested rhythm; overflow is intentionally available through horizontal scrolling.
- Colors: real brand marks use recognizable semantic brand colors; the selected source uses only a restrained system-blue underline.
- Image quality: Weibo, TikTok, Bilibili, Zhihu, and YouTube use vector marks from Simple Icons; remaining actions use SF Symbols. No emoji, text glyph substitutes, or handcrafted vectors are used.
- Copy: channel names remain available to VoiceOver and the underlying source order is unchanged.
- Interaction: channel switching, animated reveal of the selected source, selection haptics, 日报, and the fixed settings action remain wired.
- Intentional difference: only the leading channels are visible at once because the user explicitly preferred larger icons and horizontal scrolling over fitting every tab on screen.
- Findings after fix: P0 none, P1 none, P2 none.

## Pass 2 findings (resolved in later implementation)

- P0: none
- P1: X media requests bypass the server image proxy and remain in a loading state on the physical device.
- P1: 微博、抖音、老中、YouTube、快讯 use the generic post-list source parameter even though the mobile web uses dedicated hot-list, flash, and RSS-category endpoints.
- P2: The previous interaction check validated tab switching but did not assert non-empty decoded content and successful media rendering for every tab.

## Current navigation findings

- P0: none
- P1: none
- P2: none

final result: passed
