# Market detail audit

## Scope

- Surface: Nasdaq 100 market detail screen on iPhone 17 Pro simulator.
- Goal: inspect hierarchy, chart clarity, data trust, interaction affordances, and visible accessibility risks.
- Accepted evidence: `01-detail-top.png`.
- Capture limitation: the Xcode Beta installation is missing the private-framework path expected by the UI automation bridge, so scrolling and accessibility hierarchy capture were unavailable. Later blank/home/feed captures were rejected as audit evidence because the audit harness terminated and relaunched the child process.

## Findings

1. High priority: the screen says both `交易中 07-16 01:38` and `延迟 15 分钟`. The timestamp appears current while the quote explicitly reports a 15-minute delay, which makes price freshness ambiguous.
2. High priority: the 1-day chart connects points across a long overnight/non-trading gap as one continuous, evenly spaced line. The axis labels jump from `07-15 01:39` to `07-15 22:24`, so elapsed time is not represented faithfully.
3. Medium priority: volume is rendered as near-hairline red/green marks and is not practically readable; the `成交量` label is also visually detached from those marks.
4. Medium priority: `TradingViewBrowser` is an internal source identifier exposed directly in user-facing copy. A plain source name and separate freshness statement would be easier to understand.
5. Medium priority: delay status is repeated in both Key Data and Daily Summary, but neither location explains whether the chart and headline price share the same delay.
6. Accessibility risk: several secondary labels use light gray on a light grouped background. Contrast and Dynamic Type behavior need device/Accessibility Inspector verification.

## Strengths

- The screen leads with name, code, price, change, and session state in a clear order.
- Range controls, back, share, and watchlist actions are easy to locate and visually consistent.
- The chart line is now clear and its latest value aligns visually with the headline quote.
- Key metrics and the daily summary are grouped cleanly without crowding the price area.

## Recommended order

1. Correct freshness semantics and show the actual quote time.
2. Make the intraday chart time-aware and break the line across closed-market gaps.
3. Redesign or remove unusable index volume bars.
4. Replace raw source IDs and consolidate repeated delay messaging.
5. Verify contrast, VoiceOver order, and large Dynamic Type on device.
