import SwiftUI
import UIKit

enum TodayBriefStyle {
    static let horizontalInset: CGFloat = 22
    static let maximumCardWidth: CGFloat = 480
    static let cardCornerRadius: CGFloat = 22
    static let surface = Color(uiColor: .systemBackground)
    static let rule = Color(uiColor: .separator).opacity(0.28)
    static let secondary = Color(uiColor: .secondaryLabel)
    static let ink = Color(uiColor: UIColor(red: 0.094, green: 0.145, blue: 0.118, alpha: 1))
    static var surfaceOutline: Color { accent.opacity(0.16) }
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.67, green: 0.84, blue: 0.72, alpha: 1)
            : UIColor(red: 0.22, green: 0.36, blue: 0.27, alpha: 1)
    })
}

private struct TodayMenuSurface: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18)
        content
            .background(TodayBriefStyle.surface, in: shape)
            .overlay { shape.strokeBorder(TodayBriefStyle.surfaceOutline).allowsHitTesting(false) }
            .shadow(color: TodayBriefStyle.accent.opacity(0.14), radius: 10, y: 5)
    }
}

enum TodayBriefDate {
    private static let iso = Date.ISO8601FormatStyle(timeZoneSeparator: .colon)
    private static let fractionalISO = Date.ISO8601FormatStyle(timeZoneSeparator: .colon, includingFractionalSeconds: true)
    private static let dateOnly = formatter("yyyy-MM-dd")
    private static let editionLabel = formatter("M 月 d 日 · EEE")
    private static let timeLabel = formatter("M 月 d 日 HH:mm")

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = format
        return formatter
    }

    static func edition(_ date: String) -> String? {
        dateOnly.date(from: date).map(editionLabel.string)
    }

    static func timestamp(_ value: String) -> String? {
        ((try? fractionalISO.parse(value)) ?? (try? iso.parse(value))).map(timeLabel.string)
    }

    static func timestamp(_ date: Date) -> String {
        timeLabel.string(from: date)
    }
}

enum TodayOverviewSelection {
    static func supplementarySystems(
        in section: TodayWorldFinalReportSection,
        overview: TodayWorldFinalReportOverview,
        highlightedFollowUps: [String: Set<String>]
    ) -> [TodayWorldFinalReportSystem] {
        let highlights = overview.highlights.map { (item: $0, postIDs: Set($0.postIDs)) }
        return section.systems.filter { system in
            let matches = highlights.filter {
                $0.item.systemKeys.contains(system.systemKey) || !$0.postIDs.isDisjoint(with: system.postIDs)
            }.map(\.item)
            guard !matches.isEmpty, !system.postIDs.isEmpty else { return true }
            let covered = Set(matches.flatMap(\.postIDs))
            let displayed = matches.map(\.text)
            let watch = TodayReadingEvent.canonical(system.watchItem ?? "")
            let hasAdditionalWatch = !watch.isEmpty && highlightedFollowUps[system.systemKey]?.contains(watch) != true
            // Sharing one source does not mean the entire company report is covered.
            return !Set(system.postIDs).isSubset(of: covered)
                || !TodayReadingEvent.additionalDetails(system.facts.map(\.text), excluding: displayed).isEmpty
                || hasAdditionalWatch
        }
    }
}

struct TodayBriefProjection: Sendable {
    private struct FollowUpKey: Equatable {
        let systems: Set<String>
        let posts: Set<Int>
        let text: String

        init?(systems: [String], posts: [Int], body: String?) {
            self.systems = Set(systems)
            self.posts = Set(posts.filter { $0 > 0 })
            text = TodayReadingEvent.canonical(body ?? "")
            guard !self.systems.isEmpty, !self.posts.isEmpty, !text.isEmpty else { return nil }
        }
    }

    fileprivate struct CompanyCard: Sendable {
        let name: String
        let avatar: TodaySystemAvatar.Source
        let text: String?
        let postIDs: [Int]

        init(_ system: TodayWorldFinalReportSystem, fact: TodayWorldFinalReportFact?) {
            name = todayBriefSystemName(system.systemName)
            avatar = TodaySystemAvatar.Source(system)
            let detail = fact.flatMap { TodayReadingEvent.additionalDetails([$0.text], excluding: []).first }
            let watch = system.watchItem.flatMap { $0.isEmpty ? nil : "后续关注 · " + $0 }
            let headline = system.headline.isEmpty ? nil : system.headline
            text = detail ?? watch ?? headline
            postIDs = Array(Set(system.postIDs.filter { $0 > 0 })).sorted()
        }
    }

    fileprivate struct Card: Identifiable, Sendable {
        enum Content: Sendable {
            case event(TodayReadingEvent)
            case company(CompanyCard)
        }

        let id: String
        let content: Content
        let followUps: [String]
        let title: String?
        let section: String

        var sourceLabel: String {
            switch content {
            case let .event(event): event.sourceLabel
            case let .company(company): company.name
            }
        }

        var text: String? {
            switch content {
            case let .event(event): event.text
            case let .company(company): company.text
            }
        }

        var postIDs: [Int] {
            switch content {
            case let .event(event): event.postIDs
            case let .company(company): company.postIDs
            }
        }
    }

    let date: String
    let isPartial: Bool
    fileprivate let cards: [Card]
    let sourceIDs: [Int]
    private(set) var sources: [Int: TodaySourcePresentation] = [:]
    private(set) var previews: [URL: UIImage] = [:]
    private(set) var hasPreparedPreviews = false

    var avatarURLs: [URL] {
        cards.flatMap { card in
            let companyAvatar: URL?
            if case .company(let company) = card.content, case .remote(let url) = company.avatar {
                companyAvatar = url
            } else {
                companyAvatar = nil
            }
            return [companyAvatar].compactMap { $0 } + card.postIDs.flatMap { id in
                [sources[id]?.avatarURL, sources[id]?.quoteAvatarURL].compactMap { $0 }
            }
        }
    }

    @MainActor
    mutating func preparePreviews() async {
        var seen = Set(previews.keys)
        let scale = UIScreen.main.scale
        let requests = cards.flatMap { card in
            card.postIDs.flatMap { sources[$0]?.previewURLs ?? [] }
        }.compactMap { url -> (URL, ImageLoader.Request)? in
            guard seen.insert(url).inserted else { return nil }
            let resolved = ImageLoader.request(for: url, targetSize: nil, scale: scale)
            return (url, ImageLoader.Request(url: resolved.url, pixelLimit: 640, scale: scale))
        }
        let prepared = await ImageLoader.prepareReadingImages(requests)
        previews.merge(prepared) { saved, _ in saved }
        hasPreparedPreviews = true
    }

    mutating func addSources(_ posts: [Int: Post]) {
        for (id, post) in posts {
            sources[id] = TodaySourcePresentation(post: post)
        }
    }

    init(edition: TodayPublishedEdition) {
        let report = edition.report
        let systems = report.systems
        date = edition.date
        isPartial = report.completenessStatus == "partial"
        let overview = report.overview
        var remainingWatches = overview.watchItems.map { item in
            (item: item, key: FollowUpKey(systems: item.systemKeys, posts: item.postIDs, body: item.context))
        }
        func takeFollowUps(for key: FollowUpKey?) -> [String] {
            guard let key else { return [] }
            let matched = remainingWatches.filter { $0.key == key }
            remainingWatches.removeAll { $0.key == key }
            return TodayReadingEvent.unique(matched.map(\.item.text))
        }

        var highlightedFollowUps: [String: Set<String>] = [:]
        let highlights = overview.highlights.map { item in
            let event = TodayReadingEvent.highlight(item, systems: systems)
            let key = FollowUpKey(systems: item.systemKeys, posts: item.postIDs, body: item.text)
            let followUps = takeFollowUps(for: key)
            for system in item.systemKeys {
                highlightedFollowUps[system, default: []].formUnion(followUps.map(TodayReadingEvent.canonical))
            }
            return Card(
                id: "highlight-" + event.id, content: .event(event), followUps: followUps,
                title: item.title, section: "重点"
            )
        }
        var companyCards: [Card] = []
        for section in report.sections {
            let eligibleIDs = Set(TodayOverviewSelection.supplementarySystems(
                in: section, overview: overview, highlightedFollowUps: highlightedFollowUps
            ).map(\.id))
            for group in section.groups {
                for system in group.systems where eligibleIDs.contains(system.id) {
                    let fact = system.facts.first { !TodayReadingEvent.canonical($0.text).isEmpty }
                    let key = fact.flatMap {
                        FollowUpKey(systems: [system.systemKey], posts: $0.postIDs, body: $0.text)
                    }
                    companyCards.append(Card(
                        id: "company-\(section.id)-\(group.id)-\(system.id)",
                        content: .company(CompanyCard(system, fact: fact)),
                        followUps: takeFollowUps(for: key),
                        title: system.headline,
                        section: section.sectionName
                    ))
                }
            }
        }
        let standaloneWatches = remainingWatches.map { watch in
            let event = TodayReadingEvent.highlight(watch.item, systems: systems)
            return Card(
                id: "watch-" + event.id, content: .event(event), followUps: [],
                title: watch.item.title, section: "后续关注"
            )
        }
        cards = highlights + companyCards + standaloneWatches
        sourceIDs = Set(cards.flatMap(\.postIDs)).sorted()
    }
}

struct TodayBriefOverviewView: View {
    let brief: TodayBriefProjection
    let viewport: CGSize
    let isLoadingSources: Bool
    let isHeaderPanelOpen: Bool
    let retryReport: () async -> Void

    var body: some View {
        Group {
            if brief.cards.isEmpty {
                Text("本期暂无可阅读的简报")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(TodayBriefStyle.horizontalInset)
            } else {
                TodayBriefDeck(
                    brief: brief, viewport: viewport, isLoadingSources: isLoadingSources,
                    isHeaderPanelOpen: isHeaderPanelOpen, retryReport: retryReport
                )
            }
        }
        .accessibilityIdentifier("today-overview")
    }
}

private struct TodayOriginalsPanel: View {
    @AccessibilityFocusState private var headingFocused: Bool
    @State private var headerHeight: CGFloat?
    @State private var contentHeight: CGFloat?
    @State private var selectedSourceID: Int?

    let sources: [TodaySourcePresentation]
    let referenceCount: Int
    let width: CGFloat
    let isCurrent: Bool
    let isLoadingSources: Bool
    let retryReport: () async -> Void
    let measure: (CGFloat) -> Void

    private var selectedSource: TodaySourcePresentation? {
        sources.first { $0.id == selectedSourceID } ?? sources.first
    }

    private var naturalHeight: CGFloat? {
        guard let headerHeight, let contentHeight else { return nil }
        return ceil(headerHeight + 1 + contentHeight)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Group {
                    if let selectedSource {
                        TodaySourceAuthorView(source: selectedSource)
                    } else {
                        Text("来源").font(.headline)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.trailing, 44)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($headingFocused)
                if sources.count > 1, let selectedSource {
                    HStack {
                        Text("来源").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Menu {
                            ForEach(sources) { source in
                                let label = [source.author, source.time].compactMap { $0 }.joined(separator: " · ")
                                Button {
                                    selectedSourceID = source.id
                                } label: {
                                    if source.id == selectedSource.id {
                                        Label(label, systemImage: "checkmark")
                                    } else {
                                        Text(label)
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(selectedSource.author)
                                    .lineLimit(1)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption2)
                            }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(TodayBriefStyle.accent)
                            .padding(.horizontal, 10)
                            .frame(minHeight: 36)
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(TodayBriefStyle.surfaceOutline)
                            }
                            .contentShape(Rectangle())
                        }
                        .accessibilityLabel("选择来源")
                        .accessibilityValue([selectedSource.author, selectedSource.time].compactMap { $0 }.joined(separator: "，"))
                    }
                }
            }
            .padding(.horizontal, TodayBriefStyle.horizontalInset)
            .padding(.vertical, 9)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { headerHeight = $0 }
            TodayBriefStyle.rule.frame(height: 1)
                .padding(.horizontal, TodayBriefStyle.horizontalInset)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let source = selectedSource {
                        TodayInlineSourceView(
                            source: source,
                            width: max(1, width - TodayBriefStyle.horizontalInset * 2)
                        )
                    }
                    sourceStatus
                }
                .padding(TodayBriefStyle.horizontalInset)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { contentHeight = $0 }
            }
            .id(selectedSource?.id)
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
        }
        .accessibilityElement(children: .contain)
        .onChange(of: naturalHeight, initial: true) { _, height in
            if let height { measure(height) }
        }
        .onChange(of: isCurrent, initial: true) { _, current in headingFocused = current }
    }

    @ViewBuilder
    private var sourceStatus: some View {
        let missing = referenceCount - sources.count
        if referenceCount == 0 {
            Text("暂无来源内容").font(.footnote).foregroundStyle(.secondary)
        } else if missing > 0, isLoadingSources {
            ProgressView("正在加载来源").controlSize(.small)
                .font(.footnote)
        } else if missing > 0 {
            HStack {
                Text("\(missing) 条来源暂不可用").font(.footnote).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                TodayReportRetryButton(isRefreshing: false, retry: retryReport)
            }
        }
    }
}

private struct TodayReportRetryButton: View {
    let isRefreshing: Bool
    let retry: () async -> Void

    var body: some View {
        if isRefreshing {
            ProgressView().controlSize(.small)
                .accessibilityLabel("正在刷新日报")
        } else {
            Button("重试") { Task { await retry() } }
                .font(.footnote.weight(.medium))
                .tint(TodayBriefStyle.accent)
                .frame(minHeight: 36)
        }
    }
}

private struct TodayBriefDeck: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.rootTabIsActive) private var rootTabIsActive
    @State private var selectedIndex = 0
    @State private var showsOriginals = false
    @State private var showsDirectory = false
    @State private var originalsHeights: [String: CGFloat] = [:]
    @State private var summaryHeights: [String: CGFloat] = [:]
    @State private var settlement: Settlement?
    @GestureState private var drag: Drag?

    let brief: TodayBriefProjection
    let viewport: CGSize
    let isLoadingSources: Bool
    let isHeaderPanelOpen: Bool
    let retryReport: () async -> Void

    private enum DragAxis {
        case horizontal
        case vertical

        init(_ translation: CGSize) {
            self = abs(translation.width) > abs(translation.height) ? .horizontal : .vertical
        }
    }

    private struct Shuffle {
        let direction: Int
        var progress: CGFloat = 0
    }

    private struct Drag {
        let selection: Int
        let axis: DragAxis
        var shuffle: Shuffle?
    }

    private struct Settlement {
        let id = UUID()
        var shuffle: Shuffle
    }

    private var shuffle: Shuffle? {
        settlement?.shuffle ?? (drag?.selection == selectedIndex ? drag?.shuffle : nil)
    }

    fileprivate static let layerSpacing: CGFloat = 7
    private let shape = RoundedRectangle(cornerRadius: TodayBriefStyle.cardCornerRadius)

    var body: some View {
        let backLayers = min(1, brief.cards.count - 1)
        let stackHeight = CGFloat(backLayers) * Self.layerSpacing
        let stagePadding: CGFloat = 26
        let maximumHeight = max(210, viewport.height - 52 - stagePadding - stackHeight)
        let cardWidth = min(max(0, viewport.width - TodayBriefStyle.horizontalInset * 2), TodayBriefStyle.maximumCardWidth)
        let selection = min(selectedIndex, brief.cards.count - 1)
        let cardHeight = summaryHeights[brief.cards[selection].id] ?? min(350, maximumHeight)
        VStack(spacing: 8) {
            readingProgress(selection: selection, width: cardWidth)
            ZStack(alignment: .top) {
                if showsOriginals {
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { setOriginals(false) }
                        .accessibilityHidden(true)
                }
                summaryDeck(selection: selection, width: cardWidth, height: cardHeight, maximumHeight: maximumHeight)
                    .opacity(showsOriginals ? 0 : 1)
                    .allowsHitTesting(!showsOriginals)
                    .accessibilityHidden(showsOriginals)
                if showsOriginals {
                    originalsDeck(selection: selection, width: cardWidth, maximumHeight: maximumHeight, backLayers: backLayers)
                        .transition(.opacity)
                }
            }
            .padding(.top, 6)
            .frame(width: viewport.width, height: max(maximumHeight, cardHeight) + stackHeight + stagePadding, alignment: .top)
            .clipped()
            .contentShape(Rectangle())
            .simultaneousGesture(swipeGesture(cardWidth: cardWidth), including: showsDirectory ? .none : .all)
            .accessibilityHidden(showsDirectory)
            .overlay(alignment: .top) {
                if showsDirectory {
                    ZStack(alignment: .top) {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { showsDirectory = false }
                            .accessibilityHidden(true)
                        directory(selection: selection)
                            .frame(width: cardWidth)
                            .modifier(TodayMenuSurface())
                            .padding(.top, 6)
                    }
                }
            }
        }
        .onChange(of: brief.cards.map(\.id)) { previous, current in
            if let id = previous.indices.contains(selectedIndex) ? previous[selectedIndex] : nil,
               let index = current.firstIndex(of: id) {
                selectedIndex = index
            } else {
                selectedIndex = min(selectedIndex, max(0, current.count - 1))
            }
            settlement = nil
            summaryHeights = summaryHeights.filter { current.contains($0.key) }
            originalsHeights = originalsHeights.filter { current.contains($0.key) }
        }
        .onChange(of: isHeaderPanelOpen) { _, open in
            if open { showsDirectory = false }
        }
        .onChange(of: rootTabIsActive) { _, active in
            if !active {
                showsDirectory = false
                settlement = nil
                endOriginals()
            }
        }
        .accessibilityIdentifier("today-card-pager")
    }

    private func summaryDeck(selection: Int, width: CGFloat, height: CGFloat, maximumHeight: CGFloat) -> some View {
        let lastIndex = brief.cards.count - 1
        let next = shuffle.flatMap { adjacentIndex(from: selection, direction: $0.direction) }
        let promotion = shuffle?.progress ?? 0
        return ZStack(alignment: .top) {
            if brief.cards.count > 1, selection == lastIndex || next == lastIndex {
                let opacity = selection == lastIndex ? 1 - promotion : promotion
                let lastHeight = summaryHeights[brief.cards[lastIndex].id] ?? height
                backingCard(width: width, height: lastHeight)
                    .opacity(opacity)
            }
            summaryCards(selection: selection, width: width, height: height, maximumHeight: maximumHeight)
        }
    }

    private func summaryCards(selection: Int, width: CGFloat, height: CGFloat, maximumHeight: CGFloat) -> some View {
        TodayBriefDeckLayers(
            selection: selection,
            cardCount: brief.cards.count,
            cardWidth: width,
            viewportWidth: viewport.width,
            frontHeight: height,
            cardHeight: { summaryHeights[brief.cards[$0].id] },
            direction: showsOriginals ? 1 : shuffle?.direction ?? 1,
            progress: showsOriginals ? 0 : shuffle?.progress ?? 0
        ) { index, visibleHeight, contentOpacity, depth in
            let card = brief.cards[index]
            TodayBriefCardFace(
                card: card,
                source: card.postIDs.lazy.compactMap { brief.sources[$0] }.first,
                maximumHeight: maximumHeight,
                openSource: { setOriginals(true) }
            )
            .frame(width: width)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self, of: { ceil($0.size.height) }) { measured in
                if summaryHeights[card.id] != measured { summaryHeights[card.id] = measured }
            }
            .opacity(contentOpacity)
            .frame(height: visibleHeight, alignment: .top)
            .clipShape(shape)
            .modifier(CardSurface(
                shape: shape, width: width, shadowOpacity: 0.07 - 0.045 * depth, backingDepth: depth
            ))
            .allowsHitTesting(index == selection)
            .accessibilityHidden(index != selection)
            .accessibilityIdentifier("today-card-\(card.id)")
            .id(card.id)
        }
    }

    private func readingProgress(selection: Int, width: CGFloat) -> some View {
        HStack(spacing: 10) {
            Button { showsDirectory.toggle() } label: {
                HStack(spacing: 6) {
                    Text("\(selection + 1) / \(brief.cards.count)").monospacedDigit()
                    Image(systemName: "list.bullet").accessibilityHidden(true)
                }
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(TodayBriefStyle.accent)
            .accessibilityLabel("本期目录")
            .accessibilityValue("第 \(selection + 1) 张，共 \(brief.cards.count) 张")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: advance(1)
                case .decrement: advance(-1)
                @unknown default: break
                }
            }
            .accessibilityIdentifier("today-card-position")

            GeometryReader { track in
                Capsule().fill(TodayBriefStyle.accent.opacity(0.10))
                    .overlay(alignment: .leading) {
                        Capsule().fill(TodayBriefStyle.accent)
                            .frame(width: track.size.width * CGFloat(selection + 1) / CGFloat(brief.cards.count))
                    }
            }
            .frame(height: 3)
            .accessibilityHidden(true)
            if selection == brief.cards.count - 1 {
                Text("本期末尾")
                    .font(.caption)
                    .foregroundStyle(TodayBriefStyle.accent)
                    .fixedSize()
            }
        }
        .frame(width: width)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: selection)
    }

    private func directory(selection: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("本期目录").font(.headline).accessibilityAddTraits(.isHeader)
                Spacer()
                Button { showsDirectory = false } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("关闭目录")
            }
            .padding(.leading, 10)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(brief.cards.enumerated()), id: \.element.id) { index, card in
                            Button {
                                settlement = nil
                                selectedIndex = index
                                showsDirectory = false
                            } label: {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text("\(index + 1)").monospacedDigit()
                                        .foregroundStyle(TodayBriefStyle.accent)
                                        .frame(minWidth: 22, alignment: .leading)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(card.title ?? card.text ?? card.sourceLabel)
                                            .lineLimit(2)
                                        if !card.sourceLabel.isEmpty {
                                            Text(card.sourceLabel).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                }
                                .font(.subheadline)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .frame(minHeight: 44, alignment: .leading)
                                .background(
                                    TodayBriefStyle.accent.opacity(index == selection ? 0.1 : 0),
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(index == selection ? .isSelected : [])
                            .id(card.id)
                        }
                    }
                }
                .onAppear { proxy.scrollTo(brief.cards[selection].id, anchor: .center) }
            }
            .scrollIndicators(.hidden)
            .frame(height: min(CGFloat(brief.cards.count) * 56, 272))
        }
        .padding([.horizontal, .bottom], 10)
        .accessibilityIdentifier("today-card-directory")
    }

    private func swipeGesture(cardWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 14)
            .updating($drag) { value, state, _ in
                guard settlement == nil, brief.cards.count > 1 else { return }
                var current = state ?? Drag(selection: selectedIndex, axis: DragAxis(value.translation))
                if current.axis == .horizontal, current.selection == selectedIndex {
                    current.shuffle = swipe(for: value.translation.width, cardWidth: cardWidth)
                }
                state = current
            }
            .onEnded { value in
                let horizontal = value.translation.width
                guard (drag?.axis ?? DragAxis(value.translation)) == .horizontal,
                      let swipe = swipe(for: horizontal, cardWidth: cardWidth) else { return }
                let projected = value.predictedEndTranslation.width
                let movedFarEnough = abs(horizontal) >= max(40, cardWidth * 0.18)
                let flicked = abs(horizontal) >= 22 && horizontal * projected > 0 && abs(projected) >= cardWidth * 0.46
                finishShuffle(swipe, commit: movedFarEnough || flicked)
            }
    }

    private func swipe(for translation: CGFloat, cardWidth: CGFloat) -> Shuffle? {
        guard translation != 0 else { return nil }
        let direction = translation < 0 ? 1 : -1
        guard adjacentIndex(from: selectedIndex, direction: direction) != nil else { return nil }
        let progress = reduceMotion ? 0 : min(1, abs(translation) / max(1, cardWidth * 0.84))
        return Shuffle(direction: direction, progress: progress)
    }

    private func advance(_ direction: Int) {
        guard shuffle == nil else { return }
        finishShuffle(Shuffle(direction: direction), commit: true)
    }

    private func adjacentIndex(from selection: Int, direction: Int) -> Int? {
        let index = selection + direction
        return brief.cards.indices.contains(index) ? index : nil
    }

    private func setOriginals(_ visible: Bool) {
        guard shuffle == nil else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
            if visible { showsOriginals = true }
            else { endOriginals() }
        }
    }

    private func endOriginals() {
        showsOriginals = false
    }

    private func finishShuffle(_ swipe: Shuffle, commit: Bool) {
        guard settlement == nil, let destination = adjacentIndex(from: selectedIndex, direction: swipe.direction) else { return }
        let next = commit ? destination : nil
        let target: CGFloat = next == nil ? 0 : 1
        let remaining = abs(target - swipe.progress)

        if reduceMotion || remaining < 0.001 {
            completeShuffle(next)
            return
        }

        let pending = Settlement(shuffle: swipe)
        settlement = pending
        let duration = (showsOriginals ? 0.28 : 0.40) * max(0.45, remaining)
        let animation: Animation = showsOriginals
            ? .easeOut(duration: duration)
            : .timingCurve(0.24, 0.16, 0.31, 1, duration: duration)
        withAnimation(animation, completionCriteria: .logicallyComplete) {
            settlement?.shuffle.progress = target
        } completion: {
            if settlement?.id == pending.id { completeShuffle(next) }
        }
    }

    private func completeShuffle(_ next: Int?) {
        withTransaction(Transaction(animation: nil)) {
            if let next { selectedIndex = next }
            settlement = nil
        }
    }

    private func originalsDeck(selection: Int, width: CGFloat, maximumHeight: CGFloat, backLayers: Int) -> some View {
        let height = min(420, maximumHeight, originalsHeights[brief.cards[selection].id] ?? 211)
        let next = shuffle.flatMap { adjacentIndex(from: selection, direction: $0.direction) }

        return ZStack(alignment: .top) {
            if backLayers > 0 {
                backingCard(width: width, height: height)
            }

            OriginalsPages(
                selection: selection, next: next, direction: shuffle?.direction ?? 1,
                width: width, height: height, progress: shuffle?.progress ?? 0,
                heightAnimation: reduceMotion ? nil : .easeOut(duration: 0.2)
            ) { index in
                let card = brief.cards[index]
                TodayOriginalsPanel(
                    sources: card.postIDs.compactMap { brief.sources[$0] },
                    referenceCount: card.postIDs.count,
                    width: width,
                    isCurrent: index == selection,
                    isLoadingSources: isLoadingSources,
                    retryReport: retryReport,
                    measure: { reportedHeight in
                        if showsOriginals, originalsHeights[card.id] != reportedHeight {
                            originalsHeights[card.id] = reportedHeight
                        }
                    }
                )
                .environment(\.preparedReadingMedia, brief.previews)
                .id(card.id)
            }
            .clipShape(shape)
            .modifier(CardSurface(shape: shape, width: width, shadowOpacity: 0.07))
            .overlay(alignment: .topTrailing) {
                Button { setOriginals(false) } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.top, 9)
                .padding(.trailing, TodayBriefStyle.horizontalInset)
                .accessibilityLabel("关闭阅读")
                .accessibilityIdentifier("today-close-originals")
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("today-originals-panel")
            .accessibilityAction(.escape) { setOriginals(false) }
            .accessibilityAction(named: Text("下一张")) { advance(1) }
            .accessibilityAction(named: Text("上一张")) { advance(-1) }
        }
        .offset(x: -CGFloat(backLayers) * 2)
    }

    private func backingCard(width: CGFloat, height: CGFloat) -> some View {
        Color.clear.frame(height: height)
            .modifier(CardSurface(shape: shape, width: width, shadowOpacity: 0.025, backingDepth: 1))
            .scaleEffect(0.988, anchor: .bottom)
            .rotationEffect(.degrees(0.7))
            .offset(x: 7, y: Self.layerSpacing)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private struct CardSurface: ViewModifier {
        let shape: RoundedRectangle
        let width: CGFloat
        let shadowOpacity: CGFloat
        var backingDepth: CGFloat = 0

        func body(content: Content) -> some View {
            content
                .frame(width: width)
                .background {
                    shape.fill(TodayBriefStyle.surface)
                        .overlay {
                            shape.fill(TodayBriefStyle.accent.opacity(0.025 * backingDepth))
                        }
                        .shadow(color: TodayBriefStyle.accent.opacity(shadowOpacity), radius: 8, x: 0, y: 3)
                }
                .overlay { shape.strokeBorder(TodayBriefStyle.surfaceOutline).allowsHitTesting(false) }
                .contentShape(shape)
        }
    }
}

private struct OriginalsPages<Page: View>: View, Animatable {
    let selection: Int
    let next: Int?
    let direction: Int
    let width: CGFloat
    let height: CGFloat
    var progress: CGFloat
    let heightAnimation: Animation?
    @ViewBuilder let page: (Int) -> Page

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        ZStack(alignment: .top) {
            ForEach([selection] + [next].compactMap { $0 }, id: \.self) { index in
                let isCurrent = index == selection
                page(index)
                    .animation(heightAnimation) { view in
                        view.frame(width: width, height: height, alignment: .top)
                    }
                    .offset(x: (isCurrent ? -progress : 1 - progress) * CGFloat(direction) * width)
                    .allowsHitTesting(isCurrent)
                    .accessibilityHidden(!isCurrent)
                    .transition(.identity)
            }
        }
    }
}

private struct TodayBriefDeckLayers<Layer: View>: View, Animatable {
    let selection: Int
    let cardCount: Int
    let cardWidth: CGFloat
    let viewportWidth: CGFloat
    let frontHeight: CGFloat
    let cardHeight: (Int) -> CGFloat?
    let direction: Int
    var progress: CGFloat
    @ViewBuilder let layer: (_ index: Int, _ height: CGFloat, _ contentOpacity: CGFloat, _ depth: CGFloat) -> Layer

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let stackSize = min(2, cardCount)
        let front = stack(from: selection, size: stackSize)
        let candidate = stack(from: selection + direction, size: stackSize)
        let destination = candidate.isEmpty ? front : candidate
        let visible = front + destination.filter { !front.contains($0) }
        let fraction = min(1, max(0, progress))
        let promotion = smoothProgress(fraction)
        let reveal = smoothProgress(fraction / 0.38)
        let destinationHeight = destination.first.flatMap(cardHeight) ?? frontHeight
        let promotedHeight = frontHeight + (destinationHeight - frontHeight) * promotion
        let stackInset = CGFloat(stackSize - 1) * 2
        let entryTravel = (viewportWidth + cardWidth) / 2 + 24

        ZStack(alignment: .top) {
            ForEach(visible, id: \.self) { index in
                let source = front.firstIndex(of: index)
                let target = destination.firstIndex(of: index)
                let sourceDepth = CGFloat(source ?? stackSize - 1)
                let targetDepth = CGFloat(target ?? stackSize - 1)
                let isEntering = target == 0 && source != 0
                let isReturning = direction < 0 && isEntering
                let depth = isReturning ? 0 : sourceDepth + (targetDepth - sourceDepth) * promotion
                let isLeaving = direction > 0 && index == selection
                let flight = isLeaving ? fraction : 0
                let approach = isReturning ? 1 - fraction : 0
                let rank = source ?? stackSize
                let rearOpacity = smoothProgress((fraction - 0.38) / 0.55)
                let outgoingOpacity = min(1, (1 - fraction) * 4)
                let shuffleOpacity = source == nil ? rearOpacity : target == nil ? outgoingOpacity : 1
                let cardOpacity = isReturning ? 1 : shuffleOpacity
                let textOpacity = contentOpacity(
                    source: source, target: target, isReturning: isReturning,
                    isLeaving: isLeaving, reveal: reveal, promotion: promotion
                )

                layer(index, isLeaving ? frontHeight : promotedHeight, textOpacity, depth)
                    .scaleEffect(1 - 0.012 * depth, anchor: .bottom)
                    .rotationEffect(.degrees(0.7 * depth - 13 * flight - 6 * approach))
                    .offset(
                        x: 7 * depth - stackInset - entryTravel * (flight + approach),
                        y: TodayBriefDeck.layerSpacing * depth - 18 * flight
                    )
                    .opacity(cardOpacity)
                    .zIndex(isReturning || isLeaving ? 1 : -Double(rank))
                    .transition(.identity)
            }
        }
    }

    private func smoothProgress(_ progress: CGFloat) -> CGFloat {
        let t = min(1, max(0, progress))
        return t * t * (3 - 2 * t)
    }

    private func contentOpacity(
        source: Int?, target: Int?, isReturning: Bool, isLeaving: Bool,
        reveal: CGFloat, promotion: CGFloat
    ) -> CGFloat {
        if isReturning || isLeaving { return 1 }
        if target == 0 { return reveal }
        return source == 0 ? 1 - promotion : 0
    }

    private func stack(from first: Int, size: Int) -> [Int] {
        guard (0..<cardCount).contains(first) else { return [] }
        return Array(first..<min(cardCount, first + size))
    }
}

private struct TodayBriefCardFace: View {
    @State private var identityHeight: CGFloat = 40
    @State private var followUpHeight: CGFloat = 0

    let card: TodayBriefProjection.Card
    let source: TodaySourcePresentation?
    let maximumHeight: CGFloat
    let openSource: () -> Void

    private var summary: String? {
        if let text = card.text, !text.isEmpty { return text }
        return card.followUps.isEmpty && !card.postIDs.isEmpty ? "暂无摘要" : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            identity
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { identityHeight = $0 }
            if let summary {
                TodaySummaryText(
                    text: summary,
                    maximumHeight: min(265, max(52, maximumHeight - identityHeight - followUpHeight - 64)),
                    openSource: openSource
                )
            }
            if !card.followUps.isEmpty {
                followUps
                    .contentShape(Rectangle())
                    .onTapGesture(perform: openSource)
                    .accessibilityAction { openSource() }
                    .accessibilityHint("打开阅读")
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { followUpHeight = $0 }
            }
        }
        .multilineTextAlignment(.leading)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
    }

    private var followUps: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("后续关注")
                .font(.caption.weight(.semibold))
                .foregroundStyle(TodayBriefStyle.accent)
            ForEach(card.followUps, id: \.self) { text in
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(TodayBriefStyle.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private var identity: some View {
        let size: CGFloat = 40
        return HStack(spacing: 10) {
            switch card.content {
            case let .event(event):
                if let logo = TodaySystemAvatar.Source(companySystemKey: event.companySystemKey) {
                    TodaySystemAvatar(source: logo, name: event.sourceLabel, size: size)
                } else if let source {
                    AvatarView(
                        url: source.avatarURL, name: source.author, size: size
                    )
                    .accessibilityHidden(true)
                } else {
                    Image(systemName: "newspaper")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: size, height: size)
                        .background(.background, in: Circle())
                        .accessibilityHidden(true)
                }
            case let .company(company):
                TodaySystemAvatar(source: company.avatar, name: company.name, size: size)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(card.sourceLabel.isEmpty ? source?.author ?? "简报" : card.sourceLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TodayBriefStyle.accent)
                Text(card.section)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}

private struct TodaySummaryText: View {
    @ScaledMetric(relativeTo: .body) private var textSize = 18.0
    @State private var textHeight: CGFloat?
    @State private var showsFade = false
    @State private var scrolledFromTop = false

    let text: String
    let maximumHeight: CGFloat
    let openSource: () -> Void

    var body: some View {
        let height = min(textHeight ?? maximumHeight, maximumHeight)
        ScrollView {
            Text(text)
                .font(.system(size: textSize))
                .foregroundStyle(TodayBriefStyle.ink)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(perform: openSource)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { openSource() }
                .accessibilityHint("打开阅读")
                .onGeometryChange(for: CGFloat.self, of: { ceil($0.size.height) }) { textHeight = $0 }
                .onGeometryChange(for: Bool.self, of: {
                    $0.frame(in: .named("today-summary-viewport")).maxY > height + 1
                }) { showsFade = $0 }
                .onGeometryChange(for: Bool.self, of: {
                    $0.frame(in: .named("today-summary-viewport")).minY < -1
                }) { scrolledFromTop = $0 }
        }
        .coordinateSpace(name: "today-summary-viewport")
        .frame(height: height)
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        .overlay(alignment: .top) {
            if scrolledFromTop {
                LinearGradient(colors: [TodayBriefStyle.surface, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 12)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .overlay(alignment: .bottom) {
            if showsFade && (textHeight ?? 0) > height {
                LinearGradient(
                    colors: [.clear, TodayBriefStyle.surface],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 18)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }
}

enum AliyunRecharge {
    static let url: URL = {
        var components = URLComponents(string: "alipays://platformapi/startapp")!
        components.queryItems = [
            URLQueryItem(name: "appId", value: "20000067"),
            URLQueryItem(name: "url", value: "https://m.console.aliyun.com/usercenter/recharge")
        ]
        return components.url!
    }()
}

struct TodayEditionNotice {
    let message: String?
    let isPartial: Bool
    let hasSubscriptionNotice: Bool
    let missingCount: Int?
    let reasons: [String]
    let publishedAt: String?
    let canRetry: Bool

    var label: String {
        if isPartial {
            if let missingCount { return "\(missingCount) 项缺失" }
            return "内容不完整"
        }
        return hasSubscriptionNotice ? "订阅专享" : "日报状态"
    }
}

struct TodayEditionStatusButton: View {
    let notice: TodayEditionNotice
    let isOpen: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                Text(notice.label)
                Image(systemName: isOpen ? "chevron.up" : "chevron.down").font(.caption2)
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 4)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color(uiColor: UIColor(red: 0.52, green: 0.32, blue: 0.13, alpha: 1)))
        .accessibilityLabel(notice.label)
        .accessibilityIdentifier("today-edition-status")
    }
}

struct TodayEditionStatusDetails: View {
    let notice: TodayEditionNotice
    let isRefreshing: Bool
    let retry: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if notice.isPartial || notice.hasSubscriptionNotice {
                Text(notice.label)
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("today-partial-edition")
                ForEach(notice.reasons, id: \.self) { reason in
                    Text(reason)
                }
            }
            if let message = notice.message {
                Text(message).accessibilityIdentifier("today-cached-edition")
            }
            if let publishedAt = notice.publishedAt {
                Text("本期发布于 \(publishedAt)").foregroundStyle(.secondary)
            }
            if notice.canRetry {
                TodayReportRetryButton(isRefreshing: isRefreshing, retry: retry)
            }
        }
        .font(.footnote)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 15))
    }
}

struct TodayToolsMenu<Heading: View, Report: View>: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var headingHeight: CGFloat = 63
    @State private var rechargeUnavailable = false
    @State private var updateUnavailable = false
    @AppStorage("focus.requestedUpdateRelease") private var requestedUpdateRelease = ""
    @State private var installerPresentation: InstallerPresentation?
    @State private var showsInstallOptions = false
    @State private var completedUpdateVersion: String?
    @State private var updateCheckAttempt = 0
    @State private var updateCheckState: UpdateCheckState = .idle
    @State private var availableUpdate: AvailableUpdate?

    private enum UpdateCheckState {
        case idle, checking, current, updateAvailable, failed
    }

    private enum InstallerPresentation: Equatable {
        case requesting, waitingForConfirmation
    }

    private struct AvailableUpdate {
        let version: String
        let build: Int
        let installURL: URL

        var releaseID: String { "\(version)+\(build)" }
    }

    private struct PublishedVersion: Decodable {
        let version: String
        let build: Int
        let package: String

        func installURL(in channel: URL) -> URL? {
            let prefix = "build-\(version)-\(build)-"
            let identifier = package.dropFirst(prefix.count)
            guard package.hasPrefix(prefix), identifier.utf8.count == 16,
                  identifier.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
                  var components = URLComponents(string: "itms-services://") else { return nil }
            let manifest = channel.appendingPathComponent(package, isDirectory: true).appendingPathComponent("manifest.plist")
            components.queryItems = [
                URLQueryItem(name: "action", value: "download-manifest"),
                URLQueryItem(name: "url", value: manifest.absoluteString)
            ]
            return components.url
        }
    }

    @Binding var waitingForRechargeReturn: Bool
    @Binding var showsTools: Bool
    let balance: AliyunAccountBalance?
    let dailyCosts: DisplaySnapshotCache.Entry<AIUsageDailyCosts>?
    let isLoading: Bool
    let needsRetry: Bool
    let retry: () async -> Void
    let viewport: CGSize
    @ViewBuilder let heading: () -> Heading
    @ViewBuilder let report: (CGFloat) -> Report

    var body: some View {
        let width = max(0, min(TodayBriefStyle.maximumCardWidth, viewport.width - TodayBriefStyle.horizontalInset * 2))
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 4) {
                heading()
                toolsButton
            }
            .frame(width: width)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { headingHeight = $0 }
            report(headingHeight)
                .allowsHitTesting(!showsTools)
                .accessibilityHidden(showsTools)
        }
        .frame(maxWidth: .infinity, minHeight: max(0, viewport.height), alignment: .top)
        .overlay(alignment: .top) {
            if showsTools {
                ZStack(alignment: .top) {
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { showsTools = false }
                        .accessibilityHidden(true)
                    toolsPanel
                        .frame(width: min(292, width))
                        .modifier(TodayMenuSurface())
                        .frame(width: width, alignment: .trailing)
                }
                .padding(.top, headingHeight + 5)
            }
        }
        .task(id: completedUpdateVersion) {
            guard completedUpdateVersion != nil else { return }
            do { try await Task.sleep(for: .seconds(6)) }
            catch { return }
            completedUpdateVersion = nil
        }
        .task(id: installerPresentation) {
            guard installerPresentation == .waitingForConfirmation else { return }
            do { try await Task.sleep(for: .seconds(15)) }
            catch { return }
            installerPresentation = nil
        }
        .task(id: scenePhase == .active ? updateCheckAttempt : nil, priority: .utility) {
            guard scenePhase == .active else {
                if updateCheckState == .checking { updateCheckState = .idle }
                return
            }
            while !Task.isCancelled {
                await checkForUpdate()
                do { try await Task.sleep(for: .seconds(300)) }
                catch { return }
            }
        }
    }

    private var toolsButton: some View {
        Button {
            showsTools.toggle()
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(TodayBriefStyle.accent)
                .frame(width: 44, height: 44)
                .background(TodayBriefStyle.accent.opacity(showsTools ? 0.08 : 0), in: Circle())
                .overlay(alignment: .topTrailing) {
                    if availableUpdate != nil {
                        Circle()
                            .fill(TodayBriefStyle.accent)
                            .frame(width: 7, height: 7)
                            .padding(4)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("今日选项")
        .accessibilityValue(availableUpdate == nil ? "" : "有可用更新")
        .accessibilityHint("查看余额、费用、充值和更新")
        .accessibilityIdentifier("today-tools")
    }

    private var toolsPanel: some View {
        ViewThatFits(in: .vertical) {
            toolsContent
            ScrollView { toolsContent }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: 320)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today-tools-panel")
        .onAppear(perform: showCompletedUpdate)
        .alert("无法打开支付宝", isPresented: $rechargeUnavailable) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("请在已安装支付宝的 iPhone 上点击「支付宝充值」，前往阿里云官方充值页。")
        }
        .alert("无法发起安装", isPresented: $updateUnavailable) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("无法打开 iOS 安装入口，请稍后重试。")
        }
        .alert("已发起安装", isPresented: $showsInstallOptions, presenting: availableUpdate) { update in
            Button("重新发起") { requestInstallation(update) }
            Button("关闭", role: .cancel) {}
        } message: { _ in
            Text("如果没有看到系统安装弹窗，可以重新发起。已确认安装时，请在主屏幕查看焦点图标的进度。")
        }
    }

    private var toolsContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            balanceControl.padding(.bottom, 6)
            billingDetails
            rechargeButton
            Divider()
            updateControl
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var installStatus: some View {
        if let completedUpdateVersion {
            Label("已更新至 \(completedUpdateVersion)", systemImage: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(TodayBriefStyle.accent)
                .accessibilityIdentifier("today-app-update-completed")
        } else if let update = availableUpdate, requestedUpdateRelease == update.releaseID,
                  installerPresentation != .requesting {
            Label("已请求安装 \(update.version)", systemImage: "arrow.down.to.line")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("today-app-update-handed-off")
        }
    }

    private var updateControl: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let availableUpdate { updateButton(availableUpdate) }
            Button { updateCheckAttempt += 1 } label: {
                HStack(spacing: 8) {
                    if updateCheckState == .checking {
                        ProgressView().controlSize(.small)
                        Text("正在检查更新…")
                    } else {
                        Label("检查更新", systemImage: "arrow.clockwise")
                    }
                    Spacer(minLength: 0)
                    if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                        Text(version).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .modifier(TodayToolActionLabel())
            }
            .buttonStyle(.plain)
            .disabled(updateCheckState == .checking)
            .accessibilityIdentifier("today-check-update")

            if updateCheckState == .failed {
                Text("暂时无法检查更新")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("today-update-check-failed")
            } else if updateCheckState == .current && completedUpdateVersion == nil {
                Text("已是最新版本")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            installStatus
        }
    }

    private var installEntryURL: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "FocusDirectInstallURL") as? String,
              let url = URL(string: value), url.scheme == "https", url.host != nil else { return nil }
        return url
    }

    private func numericVersion(_ version: String, build: Int) -> [Int]? {
        let fields = version.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(fields.count), build > 0,
              fields.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }) else { return nil }
        let numbers = fields.compactMap { Int($0) }
        guard numbers.count == fields.count else { return nil }
        return numbers + Array(repeating: 0, count: 3 - numbers.count) + [build]
    }

    private var installedRelease: (version: String, order: [Int])? {
        guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              let buildString = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
              let build = Int(buildString), let order = numericVersion(version, build: build) else { return nil }
        return (version, order)
    }

    private func showCompletedUpdate() {
        let parts = requestedUpdateRelease.split(separator: "+", omittingEmptySubsequences: false)
        guard parts.count == 2, let build = Int(parts[1]),
              let requested = numericVersion(String(parts[0]), build: build),
              let installed = installedRelease,
              !installed.order.lexicographicallyPrecedes(requested) else { return }
        requestedUpdateRelease = ""
        completedUpdateVersion = installed.version
    }

    @MainActor
    private func checkForUpdate() async {
        updateCheckState = .checking
        do {
            guard let entry = installEntryURL, let installed = installedRelease else {
                throw URLError(.badURL)
            }
            let channel = entry.deletingLastPathComponent()
            guard var components = URLComponents(url: channel.appendingPathComponent("latest.json"), resolvingAgainstBaseURL: false) else {
                throw URLError(.badURL)
            }
            components.queryItems = [.init(name: "check", value: UUID().uuidString)]
            guard let url = components.url else { throw URLError(.badURL) }
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 6)
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            let (data, response) = try await URLSession.shared.data(for: request)
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let published = try JSONDecoder().decode(PublishedVersion.self, from: data)
            guard let remote = numericVersion(published.version, build: published.build),
                  let installURL = published.installURL(in: channel) else {
                throw URLError(.cannotParseResponse)
            }
            if installed.order.lexicographicallyPrecedes(remote) {
                availableUpdate = AvailableUpdate(version: published.version, build: published.build, installURL: installURL)
                updateCheckState = .updateAvailable
            } else {
                availableUpdate = nil
                updateCheckState = .current
            }
        } catch {
            guard !Task.isCancelled else { return }
            updateCheckState = .failed
        }
    }

    private func requestInstallation(_ update: AvailableUpdate) {
        guard installerPresentation == nil else { return }
        installerPresentation = .requesting
        UIApplication.shared.open(update.installURL) { opened in
            if opened {
                requestedUpdateRelease = update.releaseID
                installerPresentation = .waitingForConfirmation
            } else {
                installerPresentation = nil
                updateUnavailable = true
            }
        }
    }

    private func updateButton(_ update: AvailableUpdate) -> some View {
        let alreadyRequested = requestedUpdateRelease == update.releaseID
        return Button {
            if alreadyRequested {
                showsInstallOptions = true
            } else {
                requestInstallation(update)
            }
        } label: {
            HStack(spacing: 4) {
                if let installerPresentation {
                    ProgressView().controlSize(.small)
                    Text(installerPresentation == .requesting ? "发起中" : "等待确认")
                } else if alreadyRequested {
                    Label("安装状态", systemImage: "info.circle")
                } else {
                    Label("更新", systemImage: "arrow.down.circle")
                }
            }
            .modifier(TodayToolActionLabel())
        }
        .buttonStyle(.plain)
        .disabled(installerPresentation != nil)
        .accessibilityIdentifier("today-app-update")
        .accessibilityValue(update.version)
        .accessibilityHint(alreadyRequested ? "查看安装说明" : "向 iOS 发起安装请求")
    }

    private var balanceControl: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text("阿里云余额").font(.subheadline.weight(.medium))
            Spacer(minLength: 8)
            Text(balance?.formattedAmount ?? (needsRetry ? "暂不可用" : "—"))
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(TodayBriefStyle.accent)
                .accessibilityIdentifier("today-aliyun-balance")
        }
    }

    private var billingDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("模型调用费用").font(.caption.weight(.semibold))
                if let dailyCosts {
                    Text("\(TodayBriefDate.timestamp(dailyCosts.savedAt)) 快照")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            billingCosts
            if isLoading {
                ProgressView("正在获取账务数据…").controlSize(.small).font(.caption)
            } else if needsRetry {
                Button("重新查询") { Task { await retry() } }
                    .font(.caption.weight(.medium))
                    .frame(minHeight: 44)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .foregroundStyle(TodayBriefStyle.accent)
        .background(TodayBriefStyle.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("today-billing-details")
    }

    private var billingCosts: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 20) {
                costItem("今日花费", amount: dailyCosts?.value.todayCostCNY, identifier: "today-model-cost")
                Spacer(minLength: 0)
                costItem("昨日花费", amount: dailyCosts?.value.yesterdayCostCNY, identifier: "yesterday-model-cost")
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 8) {
                costItem("今日花费", amount: dailyCosts?.value.todayCostCNY, identifier: "today-model-cost")
                costItem("昨日花费", amount: dailyCosts?.value.yesterdayCostCNY, identifier: "yesterday-model-cost")
            }
        }
    }

    private func costItem(_ title: String, amount: Double?, identifier: String) -> some View {
        billingMetric(
            label: Text(title),
            value: Text(AIUsageDailyCosts.formattedCost(amount) ?? (dailyCosts == nil && !needsRetry ? "—" : "暂不可用"))
                .accessibilityIdentifier(identifier)
                .accessibilityHint("AI Server 模型调用费用，按北京时间统计")
        )
    }

    private func billingMetric(label: some View, value: some View) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            label.font(.caption).foregroundStyle(TodayBriefStyle.secondary)
            value.font(.subheadline.weight(.semibold)).monospacedDigit()
        }
    }

    private var rechargeButton: some View {
        Button {
            waitingForRechargeReturn = true
            openURL(AliyunRecharge.url) { accepted in
                if !accepted {
                    waitingForRechargeReturn = false
                    rechargeUnavailable = true
                }
            }
        } label: {
            HStack(spacing: 8) {
                Label("支付宝充值", systemImage: "wallet.bifold")
                Spacer()
                Image(systemName: "arrow.up.right")
                    .accessibilityHidden(true)
            }
            .modifier(TodayToolActionLabel())
        }
        .buttonStyle(.plain)
        .foregroundStyle(TodayBriefStyle.accent)
        .accessibilityIdentifier("today-aliyun-recharge")
        .accessibilityHint("打开支付宝，前往阿里云官方充值页")
    }
}

func todayBriefSystemName(_ name: String) -> String {
    name.hasSuffix(" 系") ? String(name.dropLast(2)) : name
}

private struct TodayToolActionLabel: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.subheadline.weight(.medium))
            .foregroundStyle(TodayBriefStyle.accent)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
    }
}

private struct TodaySystemAvatar: View {
    enum Source: Sendable {
        case asset(String)
        case remote(URL?)

        init?(companySystemKey: String?) {
            guard let companySystemKey, let asset = TodaySystemAvatar.companyAssets[companySystemKey] else {
                return nil
            }
            self = .asset(asset)
        }

        init(_ system: TodayWorldFinalReportSystem) {
            self = Self(companySystemKey: system.systemKey)
                ?? .remote(system.sourceKeys.first.flatMap(todayWorldSourceAvatarURL))
        }
    }

    let source: Source
    let name: String
    let size: CGFloat

    nonisolated private static let companyAssets: [String: String] = [
        "altman": "TodayCompanyOpenAI",
        "musk": "TodayCompanyXAI",
        "nadella": "TodayCompanyMicrosoft",
        "pichai": "TodayCompanyGoogle",
        "amodei": "TodayCompanyAnthropic",
        "huang": "TodayCompanyNVIDIA",
        "apple": "TodayCompanyApple",
        "amazon": "TodayCompanyAWS",
        "cursor": "TodayCompanyCursor",
        "reflection": "TodayCompanyReflection",
        "cognition": "TodayCompanyCognition",
        "artificial-analysis": "TodayCompanyArtificialAnalysis",
        "zuckerberg": "TodayCompanyMeta",
        "ark-invest": "TodayCompanyARKInvest",
        "quiver-quantitative": "TodayCompanyQuiverQuantitative"
    ]

    var body: some View {
        switch source {
        case .asset(let asset):
            Image(asset)
                .resizable().scaledToFit()
                .foregroundStyle(.primary)
                .frame(width: size, height: size)
                .accessibilityLabel("\(name) 公司标识")
        case .remote(let url):
            AvatarView(url: url, name: name, size: size)
        }
    }
}
