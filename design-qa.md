# Xueqiu Detail — Design QA

- Source visual truth: `/Users/wangheng/Downloads/IMG_4697.PNG`
- Implementation screenshot: `/Users/wangheng/Desktop/ai_server_ios/artifacts/implementation/xueqiu-detail/implementation.png`
- Full-view comparison: `/Users/wangheng/Desktop/ai_server_ios/artifacts/implementation/xueqiu-detail/comparison.png`
- Viewport: iPhone 17 Pro simulator, light appearance, live Snowball post

## Findings

No actionable P0, P1, or P2 findings remain. The custom title bar, verified author row, large rich-text body, conversation affordance, inset quote card, risk notice, engagement area, and fixed discussion bar reproduce the supplied Snowball detail hierarchy. Long-form scrolling was inspected through the quote and risk sections; no private-use glyphs, numeric HTML entities, clipping, or horizontal overflow remain. Engagement counts are shown only when supplied by live metadata.

final result: passed

---

# Xueqiu Native-Style Feed — Design QA

- Source visual truth: `/var/folders/7n/8nzt6jms3f18b912d97wd0jr0000gn/T/codex-clipboard-d5e2668c-2dd1-47da-b2fc-2cb3ad04dc37.png`
- Implementation screenshot: `/Users/wangheng/Desktop/ai_server_ios/artifacts/implementation/xueqiu-tab/simulator-final-v2.jpg`
- Full-view comparison: `/Users/wangheng/Desktop/ai_server_ios/artifacts/implementation/xueqiu-tab/comparison-v2.jpg`
- Viewport: iPhone 17 Pro simulator, 368 × 800 optimized capture; light appearance
- State: `观察` bottom section selected, `雪球` top source selected, live merged posts from RSS feeds 14 and 16

## Comparison history

- Pass 1 found one P2 density mismatch: live Snowball posts rendered forwarded and original text as one long block, unlike the selected design's distinct quote surface.
- Pass 2 split HTML blockquotes into a restrained secondary-system-background quote region, kept the original post as the primary reading surface, and added orange-red stock-tag emphasis when a ticker exists.
- Pass 3 adopted the user-provided Snowball-native reference: larger body typography, blue mentions, orange verification, modified-time metadata, related-discussion footer, and a four-action bottom row.
- Pass 3 also found and fixed one P1 media issue: a Snowball hand-gesture emoji was incorrectly promoted to a full-width feed image. Known Snowball emoji asset paths are now excluded from the media grid.
- The post-fix evidence is the v2 implementation screenshot and comparison above.

## Required fidelity surfaces

- Fonts and typography: native system Chinese type, medium author names, tertiary modified-time metadata, 17 pt body copy with expanded line spacing, blue mention runs, and compact action labels follow the new reference hierarchy.
- Spacing and layout rhythm: the 53 pt source bar, flat feed rows, 16 pt horizontal margins, subtle dividers, quote insets, and persistent three-item bottom navigation match the selected direction without nested cards.
- Colors and visual tokens: system background and labels remain adaptive; blue is used for mentions and selected navigation, orange for verification, orange-red for available stock tags, and quote blocks use the native secondary system background.
- Image quality and assets: real RSS author avatars and server images are used. The current above-the-fold posts have no media, so no placeholder imagery is introduced.
- Copy and content: authors, modified timestamps, Snowball body text, quoted reposts, tickers, and media are live server data. Engagement numbers remain hidden when the API does not supply them instead of inventing values from the reference.

## Findings

No actionable P0, P1, or P2 findings remain. The `雪球` source sits in the top horizontal source selector, while the bottom navigation remains exactly `观点 / 市场 / 事件`.

Focused comparison was not needed because the navigation, typography, quote surface, separators, and interaction icons are readable at full-view scale in the combined evidence.

## Follow-up polish

- [P3] A future API enhancement could expose native Snowball like/comment/bookmark counts more consistently; the UI already renders them when present.

final result: passed

---

# Zhihu Detail Option 2 — Design QA

- Source visual truth: `/Users/wangheng/.codex/generated_images/019f6470-aa65-7472-8166-7074977d4fde/exec-ca355ea4-3937-4ba4-8d2e-fbfba29ca588.png`
- Implementation screenshot: `/Users/wangheng/Desktop/ai_server_ios/artifacts/implementation/zhihu-detail-compact-toolbar/final.png`
- Full-view comparison: `/Users/wangheng/Desktop/ai_server_ios/artifacts/implementation/zhihu-detail-compact-toolbar/comparison.png`
- Focused comparison: `/Users/wangheng/Desktop/ai_server_ios/artifacts/implementation/zhihu-detail-compact-toolbar/focused-comparison.png`
- Viewport: iPhone simulator, 944 × 2048 pixels (native capture; approximately 430 × 932 points). The concept was generated at 390 × 844 points, so wrapping and visible body length differ slightly.
- State: first Zhihu high-vote answer detail, light appearance, live full-answer server data

## Findings

No actionable P0, P1, or P2 findings remain.

- Top integration: the oversized native navigation area and floating Liquid Glass buttons are removed. A compact 44 pt article toolbar now sits directly inside the white reading surface, eliminating the empty band and creating the requested edge-to-edge continuity.
- Typography: the editorial headline, metadata, author row, drop cap, section heading, quote, and long-form body preserve the selected concept's hierarchy without clipping or horizontal overflow.
- Spacing: 18 pt article margins and a restrained toolbar-to-title gap keep the page dense but readable. The title begins materially higher than the previous implementation.
- Data fidelity: title, heat, rank, author, avatar, vote count, comments, and full answer text are all live data. The duplicate summary is suppressed whenever a full answer exists.
- Assets: the real server-provided avatar is used and remains sharp and correctly cropped.
- Controls: back, native share, overflow menu, agree, comment, bookmark, and open-original actions are wired. The bottom action bar remains fully visible.

## Comparison Result

- Full and focused side-by-side comparisons confirm that the compact top toolbar, flat white surface, editorial rhythm, and persistent bottom actions match the chosen direction.
- The implementation shows the live `119 万热度` value in addition to rank, while the concept only showed rank. This is intentional live-data enrichment and does not disturb the hierarchy.
- The implementation uses the actual target device width, which produces slightly larger-looking type and different wrapping than the narrower generated concept.

## Verification

- Debug simulator build succeeded.
- All 22 unit tests passed.
- Full answer renders without the previously duplicated excerpt.

## Follow-up Polish

- [P3] A later typography-density preference could expose compact/comfortable reading modes, but it is not needed for fidelity or usability.

final result: passed

---

# Flash Feed — Option 3 Design QA

- Source visual truth: `/Users/wangheng/.codex/generated_images/019f66f1-bddf-7512-b773-da38856ad071/exec-0ee8b1bf-0949-4a1c-9e61-b70c66e5a9f0.png`
- Implementation screenshot: `/Users/wangheng/Desktop/ai-server-ios/artifacts/implementation/flash-feed/final.png`
- Full-view comparison: `/Users/wangheng/Desktop/ai-server-ios/artifacts/implementation/flash-feed/comparison.png`
- Viewport: iPhone 17 Pro simulator, 1206 × 2622 native pixels; light appearance
- State: live flash feed, `全部` filter selected

## Comparison history

- Pass 1 found one P1 density mismatch: live provider copy could be much longer than the concise mock data, allowing a single item to consume nearly the full viewport.
- Pass 2 capped feed copy at four lines while preserving the full article in the existing detail view. Build verification passed after the fix.

## Required fidelity surfaces

- Fonts and typography: native system Chinese typography, 16 pt feed copy, rounded monospaced times, compact metadata, and selected-filter emphasis preserve the reference hierarchy.
- Spacing and layout rhythm: the title/live row, horizontal filters, 66 pt time rail, inset separators, and full-width flat list match the selected direction without nested cards.
- Colors and visual tokens: system background and labels remain adaptive; blue denotes the active filter and red is reserved for live/important semantics.
- Image quality and assets: this screen intentionally contains no content imagery; existing project source icons and SF Symbols remain sharp at native scale.
- Copy and content: live API text and provider names replace mock copy. Long text is limited to four lines in the feed and remains fully available in detail.

## Findings

No actionable P0, P1, or P2 findings remain. The implementation adds functioning category filters and retains existing navigation, refresh, pagination, and detail behavior.

## Follow-up polish

- [P3] The static concept uses hand-curated two-line examples; live copy varies in sentence length, so row heights remain intentionally flexible within the four-line cap.

final result: passed

---

# Truth Detail — Option 1 Design QA

- Source visual truth: `/Users/wangheng/.codex/generated_images/019f660e-f757-79f1-a4d7-da2a57af196e/exec-f500121e-eaad-4299-8425-642028e6d83b.png`
- Physical-device capture: `/Users/wangheng/Desktop/ai-server-ios/artifacts/implementation/truth-detail/final.png`
- Full comparison: `/Users/wangheng/Desktop/ai-server-ios/artifacts/implementation/truth-detail/comparison.png`
- Focused comparison: `/Users/wangheng/Desktop/ai-server-ios/artifacts/implementation/truth-detail/focused-comparison.png`
- Viewport: iPhone 14, 1170 × 2532 native pixels; dark appearance
- State: live Truth post with two attached images

## Comparison history

- Pass 1 found one P2 copy/polish issue: the API ISO timestamp was exposed verbatim in the source row. It was replaced with a localized Chinese date/time formatter.
- Pass 2 evidence is the final physical-device capture and the full/focused comparison listed above.

## Required fidelity surfaces

- Fonts and typography: system Chinese typography, weights, body scale, line spacing, and hierarchy match the selected direction; live text wraps differently because the content is not the static copper-tariff example.
- Spacing and layout rhythm: compact toolbar, author block, divider, body, media, source row, open-original row, and persistent bottom actions follow the reference proportions without clipping or horizontal overflow.
- Colors and tokens: black system background, white primary copy, gray metadata/dividers, and red verification/relevance/impact emphasis match the established Truth feed language.
- Image quality and assets: after user review, the detail and feed were intentionally restored to the existing anime `TruthMark` avatar rather than the mock's realistic portrait. It remains sharp at circular-avatar size. Live post images use the server originals and the shared zoomable media grid; this post has two attachments, so it intentionally uses a two-column layout instead of the mock's single hero image.
- Copy and content: only the Chinese translation is shown. English original copy and engagement metrics remain absent. `影响` is omitted for this live post because its API response does not contain a usable impact clause.

## Findings

No actionable P0, P1, or P2 findings remain.

## Follow-up polish

- [P3] The generated reference omits the iOS status area while the physical-device capture includes it; this is an expected platform framing difference.
- [P3] Dynamic relevance, time, body, image count, and impact availability differ from the static concept by design.

final result: passed

---

# Truth Feed Design QA

- Reference: `/Users/wangheng/.codex/generated_images/019f660e-f757-79f1-a4d7-da2a57af196e/exec-8aa5669b-fef9-4232-a569-66d295d0612d.png`
- Physical-device capture: `/Users/wangheng/Desktop/ai-server-ios/artifacts/implementation/truth-feed/final.png`
- Full comparison: `/Users/wangheng/Desktop/ai-server-ios/artifacts/implementation/truth-feed/comparison.png`
- Focused comparison: `/Users/wangheng/Desktop/ai-server-ios/artifacts/implementation/truth-feed/focused-comparison.png`
- Device: iPhone 14, iOS 27.0, dark appearance

## Iteration history

- Pass 1 was too reductive: it omitted the dynamic count, red selected state, relevance tiers, impact summaries, and the reference-style avatar. It also used an oversized server avatar and changed the bottom label from `观点` to `观察`.
- Pass 2 restored the information hierarchy, red channel treatment, count, filter affordance, relevance levels, compact density, and `观点` label.
- Pass 3 removed the extra quote marks introduced during pass 2 and replaced the caricature/server avatar with a project-local editorial portrait asset designed for the circular slot.

## Final comparison

- Header structure, selected-channel color, summary row, author row, relevance placement, text density, separators, and bottom navigation now align with the reference.
- The implementation remains live-data faithful: the current newest posts do not include media, while image posts farther down render with the same single- and multi-image grid used elsewhere.
- `影响` appears only when `weight_reason` contains an explicit, usable impact clause. Model-fallback and “insufficient information” explanations are suppressed instead of being presented as analysis.
- English originals, raw links, engagement controls, the left timeline, and duplicate metadata remain absent.
- The iPhone 14 capture includes the system status area and has a narrower logical viewport than the generated reference, causing expected line-wrap differences.

## Severity review

- P0: none
- P1: none
- P2: none
- P3: dynamic post order/content differs from the static concept because the implementation preserves the live chronological feed.

## Verification

- Physical-device Debug build, signing, installation, and launch succeeded.
- All 32 unit tests passed.
- Full and focused side-by-side comparisons were reviewed after the final installation.

final result: passed
