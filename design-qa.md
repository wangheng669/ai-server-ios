# Zhihu Feed Redesign Design QA

- source visual truth path: `/Users/wangheng/Desktop/ai-server-ios/artifacts/reference/zhihu-redesign-option-2.png`
- implementation screenshot path: `/Users/wangheng/Desktop/ai-server-ios/artifacts/implementation/zhihu-redesign/pass-3-real-answers.png`
- viewport: iPhone 17 Pro simulator, 402 × 874 points (1206 × 2622 pixels)
- state: Observation tab, Zhihu selected, light mode, live production feed data
- full-view comparison evidence: `/Users/wangheng/Desktop/ai-server-ios/artifacts/implementation/zhihu-redesign/comparison-pass-2.png`
- focused first-card comparison evidence: `/Users/wangheng/Desktop/ai-server-ios/artifacts/implementation/zhihu-redesign/comparison-pass-2-focused.png`

## Findings

No actionable P0, P1, or P2 visual differences remain.

- Fonts and typography: The implementation uses native iOS Chinese system typography with a clear 18-point question title, 15.5-point preview, and compact secondary metadata. It is intentionally slightly larger and more readable than the generated mock's unusually small rasterized text.
- Spacing and layout rhythm: The selected concept's topic label, question title, pale-blue preview region, source row, lightweight divider, bookmark, and overflow sequence are preserved. The live implementation shows about three complete rows instead of four because it maintains platform-readable type and touch targets.
- Colors and visual tokens: System white, near-black text, secondary gray, restrained Zhihu blue, pale-blue preview surfaces, and subtle dividers match the selected direction and the existing app.
- Image quality and asset fidelity: No decorative raster assets are required. The implementation uses the existing Zhihu source asset and real remote avatars when the backend supplies an answer author. It does not substitute generated people for missing real identities.
- Copy and content: Question titles, heat, answer counts, timestamps, and topics come from the live backend. When answer metadata is present, the card switches to a real “高赞回答” excerpt, vote/comment metrics, and answer-author identity. The production feed captured in pass 3 still omitted those fields, so it correctly rendered an honest “热榜概览” fallback rather than fabricated answer content.
- Affordances and accessibility: Bookmark is a working local action with selected feedback and an accessibility label. Overflow exposes real “open original” and share actions. The current channel renders as visible “知乎” text. Full card navigation remains on the existing feed tap gesture.

## Comparison History

1. Pass 1: P2 — short question fragments such as “才有最佳体验吗” could be mistaken for a topic label. Fix: replaced permissive tag selection with deterministic stable topic categories and a small safe-label fallback set. Post-fix evidence: `pass-2.jpg`.
2. Pass 1: P2 — heat and answer count were duplicated in the preview and metadata row. Fix: preview now communicates heat and the action to open discussion; metadata shows answer count plus recency. Post-fix evidence: `comparison-pass-2-focused.png`.
3. Pass 1: P2 — the icon-only selected channel remained less explicit than the chosen mock. Fix: the active Zhihu source now renders the visible label “知乎” while keeping the surrounding app navigation system unchanged. Post-fix evidence: `pass-2.jpg`.
4. Pass 3: P2 — answer metrics competed with author identity and a missing answer avatar could reuse the source logo. Fix: moved vote/comment metrics into the answer panel, separated real-answer and fallback labels, and restricted avatar fallback to the “知乎热榜” state. Post-fix evidence: `pass-3-real-answers.png` for the live fallback state; answer-state decoding and avatar behavior are covered by unit tests.

## Interaction Verification

- Live Zhihu metadata was verified from the production list API after the posts-api deployment: rank, heat, answer count, question ID, and canonical URL are present.
- Local bookmark state has a real toggle and persistence path; overflow contains real open-original and share actions.
- Navigation and refresh/load-more reuse the existing feed flow.
- Automated UI tapping and VoiceOver tree capture were not available because the local Xcode Beta installation is missing the SimulatorKit private framework expected by the UI-inspection tool. The app was launched directly in the simulator and captured in the Zhihu state. Build and 22 unit tests passed.

## Follow-up Polish

- P3: Complete the backend/Browser Bridge answer-metadata path so the live list consistently supplies answer excerpt, author, vote count, and comment count; the iOS rendering and decoding path is ready.
- P3: Run VoiceOver, largest Dynamic Type, and dark-mode checks on a physical device or a repaired Simulator installation.

final result: passed
