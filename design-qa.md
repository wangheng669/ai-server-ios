# Person Detail — Integrated Option 2 Design QA

- Source visual truth: `/Users/wangheng/.codex/generated_images/019f6ac9-1a7e-7a50-834e-2f64bdab427b/exec-826fd8ba-0045-4db8-9346-84035c464ffb.png`
- Physical-device implementation: `/Users/wangheng/Desktop/ai-server-ios/artifacts/implementation/people-redesign/person-detail-option-2-integrated-final.png`
- Full-view comparison: `/Users/wangheng/Desktop/ai-server-ios/artifacts/implementation/people-redesign/person-detail-option-2-integrated-comparison.png`
- Viewport: iPhone 14, 1170 × 2532 native pixels (390 × 844 logical points)
- State: dark appearance, Mark Zuckerberg detail, `相关讨论` selected, live API content loaded

## Findings

No actionable P0, P1, or P2 findings remain.

- Fonts and typography: system typography reproduces the mock's compact hierarchy. Person name, handle, role, tabs, group titles, author rows, time metadata, and three-line excerpts remain clearly differentiated without clipping.
- Spacing and layout rhythm: profile, biography, tabs, group headings, avatars, and discussion text share a consistent 20-point outer gutter. The former standalone context band is removed; `12 条相关讨论` is now attached to `今天`, so the content starts immediately after the tabs.
- Colors and visual tokens: black base surface, white primary copy, muted gray metadata, hairline separators, and restrained system-blue selection match the source.
- Image quality and assets: real X-backed profile and author avatars are used with crisp circular masks. No generated portraits or placeholders were introduced.
- Copy and content: live discussion data replaces mock copy while preserving the selected design's information architecture. Counts, date groups, authors, handles, timestamps, and X-sourced excerpts are real service data.

## Comparison History

- The preceding implementation had a P2 cohesion issue: a standalone summary line separated tabs from the feed, the header and rows used different density, and source labels added noise to every discussion row.
- Fixes: moved discussion count into the first date heading, tightened header and row typography, reduced compact avatars to 40 points, used three-line excerpts, removed repeated source labels, and aligned inset separators with row content.
- Post-fix evidence: `person-detail-option-2-integrated-comparison.png` shows the same compact header-to-feed progression, section density, and content alignment as the selected visual.

## Focused Comparison

No extra crop was needed. At 780 × 844, the normalized side-by-side keeps the header, tab indicator, date/count pairing, avatar sizes, author baselines, excerpts, and separators readable.

## Interaction Verification

- Person selection opens a full navigation destination and hides the root tab bar.
- Native back navigation returns to the people list.
- `他的动态` and `相关讨论` remain functional tabs.
- Biography expands inline from `展开`.
- Discussion rows open their post details.
- Loading, error, empty, and live-data states remain available.

## Follow-up Polish

- [P3] iOS 26 renders a larger Liquid Glass back control than the concept's thin chevron. It is retained for consistency with the rest of the native app and system accessibility behavior.
- [P3] Live author names occasionally wrap or truncate differently from the static concept because their lengths vary; the three-line body limit preserves overall feed density.

## Verification

- Signed Debug build succeeded for the physical iPhone.
- App installed and launched into the selected detail state.
- All 58 unit tests passed.
- `git diff --check` passed.

final result: passed

---

# X Timeline List — Original Style Design QA

- Source visual truth: `/var/folders/hy/lx7mb0353670bfxg43qd3pmw0000gn/T/codex-clipboard-4fe1dbaa-22ce-47b1-9ce0-df163f622d57.png`
- Simulator implementation: `/var/folders/hy/lx7mb0353670bfxg43qd3pmw0000gn/T/screenshot_optimized_9abfef6d-5772-4a62-9ea7-8da5fa0d94a5.jpg`
- Viewport: iPhone 17 Pro simulator, 368 × 800 capture
- State: X selected, Annie post loaded from the Debug preview fixture, dark appearance

## Findings

No actionable P0, P1, or P2 findings remain in the visible list structure.

- Information hierarchy: the X-specific card restores the original avatar/content column, bold author, verified badge, handle/time metadata, full long-form body, media slot, and six-part engagement row.
- Typography: the body uses 17-point system text with a six-point line spacing. Numbered items are separated into readable paragraphs, and ticker symbols use the system blue accent.
- Layout: the body, media, and engagement row share the same leading edge and available width, matching the source timeline's content rail.
- Media behavior: X video posts render an inline, muted native player using the source dimensions. Image-only posts continue through the existing media grid.
- Theme: the source is light and the simulator capture is dark. The implementation intentionally uses adaptive system colors rather than forcing the source's white background.

## Interaction Verification

- Selecting the card still opens the existing post detail route.
- Inline video starts muted on appearance and pauses when the row leaves the screen.
- Reply, repost, like, view, bookmark, and share affordances remain visible in the original order.
- Other feed sources keep their existing card implementations.

## Verification

- All 59 unit tests passed.
- Simulator Debug build succeeded and launched with the X feed preview fixture.
- Reference and implementation were inspected together at the same content state.
- `git diff --check` passed.

## Follow-up Polish

- [P3] The supplied source includes the tail of a preceding post and a thread connector. The standalone feed card does not invent a connector when no parent post is present.
- [P3] The source's exact X brand mark is omitted because the project does not contain an official X logo asset; no substitute glyph was introduced.

final result: passed

---

# Integrated Dark Market Map — Design QA

- Source visual truth: `/Users/wangheng/.codex/generated_images/019f6b14-fded-7783-9aef-96c331169ea1/exec-49b85efe-e1ef-4ed3-8a00-e5d38a2b9152.png`
- User-provided issue evidence: `/Users/wangheng/Desktop/ai-server-ios/artifacts/audit/market-map-unity-2026-07-16/01-current.png`
- Implementation screenshot: `/Users/wangheng/Desktop/ai-server-ios/artifacts/implementation/market-map-integrated-dark-final-v2.png`
- Comparison evidence: `/Users/wangheng/Desktop/ai-server-ios/artifacts/comparisons/market-map-integrated-dark-qa.png`
- Viewport: iPhone 17 Pro simulator, dark appearance, approximately 393 × 852 logical points
- State: United States selected, live market data loaded, map scrolled into view

## Findings

No actionable P0, P1, or P2 findings remain.

- Fonts and typography: the map title, live status, country labels, percentages, cities, and session states use the existing native type hierarchy without clipping or wrapping.
- Spacing and layout rhythm: the former white card and nested marker cards are gone. The map and status row now share the page background, one hairline divider, and the existing 14/18-point margins.
- Colors and visual tokens: the map uses a neutral graphite treatment in dark appearance. Blue is limited to selection, while live gains/losses preserve the app's red/green market convention.
- Image quality and asset fidelity: the full-world high-resolution map asset remains crisp after dark-mode processing; no visible rectangular white asset background remains.
- Copy and content: all four countries and city/session states remain present. No new metrics or controls were introduced.

## Comparison History

- Pass 1 identified a P2 integration mismatch in the physical-device screenshot: the white map asset, floating gray marker cards, and filled city selection created three conflicting surface treatments.
- Fixes: converted the map to a seamless adaptive dark asset treatment, removed all marker materials/borders/shadows, replaced selected fill with a blue point and short underline, and reduced the status strip to one divider.
- Pass 2 identified a P3 warm tint in the inverted map asset. The asset was desaturated to neutral graphite before final capture.
- Final evidence in `market-map-integrated-dark-final-v2.png` shows one continuous dark surface with unobstructed market labels and a lighter information hierarchy.

## Focused Comparison

The full map section is large enough in the normalized comparison to judge marker separation, asset tone, title/status alignment, divider weight, and city selection treatment; no additional crop was required.

## Interaction Verification

- Market dots and city labels remain buttons bound to the shared region selection.
- Selected market is expressed through the existing blue accent without a filled container.
- Live data and market-session status continue to come from `MarketStore`.

## Verification

- All 57 unit tests passed.
- Simulator Debug build and dark-mode capture succeeded.
- Signed physical-device build succeeded, installed, and launched on 王恒的 iPhone.

final result: passed
