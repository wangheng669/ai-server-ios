import SwiftUI
import UIKit

enum TodayBriefStyle {
    static let horizontalInset: CGFloat = 22
    static let rule = Color(uiColor: .separator).opacity(0.28)
    static let secondary = Color(uiColor: .secondaryLabel)
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.67, green: 0.84, blue: 0.72, alpha: 1)
            : UIColor(red: 0.22, green: 0.36, blue: 0.27, alpha: 1)
    })
}

enum TodayOverviewSelection {
    static func supplementarySystems(
        in section: TodayWorldFinalReportSection,
        overview: TodayWorldFinalReportOverview
    ) -> [TodayWorldFinalReportSystem] {
        let highlights = overview.highlights.map { (item: $0, postIDs: Set($0.postIDs)) }
        return section.systems.filter { system in
            let matches = highlights.filter {
                $0.item.systemKeys.contains(system.systemKey) || !$0.postIDs.isDisjoint(with: system.postIDs)
            }.map(\.item)
            guard !matches.isEmpty, !system.postIDs.isEmpty else { return true }
            let covered = Set(matches.flatMap(\.postIDs))
            let displayed = matches.map(\.text)
            // Sharing one source does not mean the entire company report is covered.
            return !Set(system.postIDs).isSubset(of: covered)
                || !TodayReadingEvent.additionalDetails(system.facts.map(\.text), excluding: displayed).isEmpty
                || !(system.watchItem ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

struct TodayBriefProjection: Sendable {
    fileprivate struct CompanyCard: Sendable {
        let system: TodayWorldFinalReportSystem
        let name: String
        let avatar: TodaySystemAvatar.Source
        let paragraphs: [String]
        let watch: String?
        let postIDs: [Int]

        init(_ system: TodayWorldFinalReportSystem) {
            self.system = system
            name = todayBriefSystemName(system.systemName)
            avatar = TodaySystemAvatar.Source(system)
            paragraphs = TodayReadingEvent.additionalDetails(system.facts.map(\.text), excluding: [])
            watch = system.watchItem.flatMap { $0.isEmpty ? nil : "后续关注 · " + $0 }
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

        var text: String? {
            switch content {
            case let .event(event): event.text
            case let .company(company): company.paragraphs.first ?? company.watch
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
        let highlights = overview.highlights.map { TodayReadingEvent.highlight($0, systems: systems) }
        let watchItems = overview.watchItems.map { TodayReadingEvent.highlight($0, systems: systems) }
        var companyCards: [Card] = []
        for section in report.sections {
            let eligibleIDs = Set(TodayOverviewSelection.supplementarySystems(in: section, overview: overview).map(\.id))
            for group in section.groups {
                for system in group.systems where eligibleIDs.contains(system.id) {
                    let company = CompanyCard(system)
                    companyCards.append(Card(
                        id: "company-\(section.id)-\(group.id)-\(system.id)",
                        content: .company(company)
                    ))
                }
            }
        }
        cards = highlights.map { Card(id: "highlight-" + $0.id, content: .event($0)) }
            + companyCards
            + watchItems.map { Card(id: "watch-" + $0.id, content: .event($0)) }
        sourceIDs = Set(cards.flatMap(\.postIDs)).sorted()
    }
}

struct TodayBriefOverviewView: View {
    @State private var selectedCard: TodayBriefProjection.Card?

    let brief: TodayBriefProjection
    let cachedEditionMessage: String?
    let reportError: String?
    let isRefreshing: Bool
    let retryReport: () async -> Void

    var body: some View {
        VStack(spacing: 0) {
            editionStatus
            if brief.cards.isEmpty {
                ScrollView {
                    Text("本期暂无可阅读的简报")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(TodayBriefStyle.horizontalInset)
                }
            } else {
                TodayBriefDeck(brief: brief) { selectedCard = $0 }
            }
        }
        .scrollIndicators(.hidden)
        .clipped()
        .accessibilityIdentifier("today-overview")
        .appSheet(item: $selectedCard) { card in
            readingSheet(card)
                .appPresentationDetents([.large])
                .appPresentationCornerRadius(28)
                .appPresentationDragIndicator()
        }
    }

    private func readingSheet(_ card: TodayBriefProjection.Card) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                cardContent(card.content)
                if card.postIDs.isEmpty {
                    Text("暂无原文")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    cardSources(card.postIDs)
                }
            }
            .padding(.horizontal, TodayBriefStyle.horizontalInset)
            .padding(.top, 18)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .top, spacing: 0) {
            Button {
                selectedCard = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("关闭简报")
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal, 12)
            .background(Color(uiColor: .systemBackground))
        }
        .background(Color(uiColor: .systemBackground))
        .accessibilityIdentifier("today-brief-reading-sheet")
    }

    @ViewBuilder
    private var editionStatus: some View {
        let message = reportError ?? cachedEditionMessage
        if message != nil || brief.isPartial {
            VStack(alignment: .leading, spacing: 4) {
                if let message {
                    Label(message, systemImage: reportError == nil ? "clock" : "exclamationmark.circle")
                        .accessibilityIdentifier("today-cached-edition")
                }
                if brief.isPartial {
                    Label("本期内容尚不完整", systemImage: "info.circle")
                        .accessibilityIdentifier("today-partial-edition")
                }
                if reportError != nil {
                    retryButton
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, TodayBriefStyle.horizontalInset)
            .padding(.vertical, 8)
        }
    }

    private func cardSources(_ ids: [Int]) -> some View {
        let available = ids.compactMap { brief.sources[$0] }
        let missing = ids.count - available.count
        return LazyVStack(alignment: .leading, spacing: 0) {
            Text("原文")
                .font(.subheadline.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 4)
            ForEach(available) { source in
                TodayInlineSourceView(source: source)
                    .padding(.vertical, 12)
                    .overlay(alignment: .top) { TodayBriefStyle.rule.frame(height: 1) }
            }
            if missing > 0 {
                HStack {
                    Text("\(missing) 篇原文暂不可用").font(.footnote).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    retryButton
                }
            }
        }
    }

    @ViewBuilder
    private var retryButton: some View {
        if isRefreshing {
            ProgressView().controlSize(.small)
                .accessibilityLabel("正在刷新日报")
        } else {
            Button("重试") { Task { await retryReport() } }
                .font(.footnote.weight(.medium))
                .tint(TodayBriefStyle.accent)
                .frame(minHeight: 36)
        }
    }

    @ViewBuilder
    private func cardContent(_ content: TodayBriefProjection.Card.Content) -> some View {
        switch content {
        case let .event(event):
            TodayBriefEventContent(event: event)
        case let .company(card):
            TodayBriefCompanyRow(card: card)
        }
    }
}

private struct TodayBriefDeck: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visibleCardID: String?

    let brief: TodayBriefProjection
    let open: (TodayBriefProjection.Card) -> Void

    private let shape = RoundedRectangle(cornerRadius: 30)

    var body: some View {
        GeometryReader { geometry in
            let showsControls = brief.cards.count > 1 && geometry.size.height >= 320
            let deckPadding: CGFloat = 36
            let maximumCardHeight: CGFloat = 455
            let availableHeight = geometry.size.height - (showsControls ? 44 : 0)
            let deckHeight = min(max(0, availableHeight), maximumCardHeight + deckPadding)
            let cardWidth = min(max(0, geometry.size.width - 44), 480)
            let cardHeight = max(0, deckHeight - deckPadding)

            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    if brief.cards.count > 1 {
                        shape
                            .fill(Color(red: 0.91, green: 0.95, blue: 0.92))
                            .frame(width: cardWidth * 0.87, height: cardHeight)
                            .offset(y: 28)
                            .accessibilityHidden(true)
                        shape
                            .fill(Color(red: 0.95, green: 0.97, blue: 0.95))
                            .frame(width: cardWidth * 0.94, height: cardHeight)
                            .offset(y: 21)
                            .accessibilityHidden(true)
                    }

                    cards(
                        width: cardWidth,
                        height: cardHeight,
                        viewport: CGSize(width: geometry.size.width, height: deckHeight)
                    )
                }
                .frame(height: deckHeight)

                if showsControls {
                    pageControls
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    private func cards(width: CGFloat, height: CGFloat, viewport: CGSize) -> some View {
        let animatesCards = !reduceMotion
        return ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(brief.cards) { card in
                    Button { open(card) } label: {
                        TodayBriefCardFace(
                            card: card,
                            source: card.postIDs.lazy.compactMap { brief.sources[$0] }.first,
                            compact: height < 350
                        )
                        .frame(width: width, height: height)
                        .background {
                            shape.fill(.background)
                                .shadow(color: TodayBriefStyle.accent.opacity(0.13), radius: 10, x: 0, y: 5)
                        }
                        .overlay { shape.strokeBorder(TodayBriefStyle.accent.opacity(0.12)) }
                        .contentShape(shape)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("打开完整简报及原文")
                    .accessibilityIdentifier("today-card-\(card.id)")
                    .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                        content
                            .scaleEffect(animatesCards && !phase.isIdentity ? 0.95 : 1)
                            .rotationEffect(.degrees(animatesCards ? phase.value * 4 : 0), anchor: .bottom)
                    }
                    .padding(.top, 14)
                    .frame(width: viewport.width, height: viewport.height, alignment: .top)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $visibleCardID)
        .accessibilityIdentifier("today-card-pager")
    }

    private var pageControls: some View {
        let index = brief.cards.firstIndex { $0.id == visibleCardID } ?? 0
        return HStack(spacing: 12) {
            pageButton("上一条", icon: "chevron.left", target: index - 1)
            Text("\(index + 1) / \(brief.cards.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel("第 \(index + 1) 张，共 \(brief.cards.count) 张")
            pageButton("下一条", icon: "chevron.right", target: index + 1)
        }
    }

    private func pageButton(_ title: String, icon: String, target: Int) -> some View {
        let enabled = brief.cards.indices.contains(target)
        return Button {
            guard enabled else { return }
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.28)) {
                visibleCardID = brief.cards[target].id
            }
        } label: {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(enabled ? TodayBriefStyle.accent : Color.secondary.opacity(0.4))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(title)
    }
}

private struct TodayBriefCardFace: View {
    let card: TodayBriefProjection.Card
    let source: TodaySourcePresentation?
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 17) {
            identity

            if let text = card.text {
                Text(text)
                    .font(compact ? .body : .title3)
                    .foregroundStyle(.primary)
                    .lineSpacing(5)
                    .layoutPriority(1)
            }
        }
        .multilineTextAlignment(.leading)
        .padding(compact ? 15 : 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(alignment: .top) {
            LinearGradient(
                colors: [Color(red: 0.91, green: 0.96, blue: 0.92), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(maxHeight: compact ? 150 : 270)
        }
        .clipShape(RoundedRectangle(cornerRadius: 30))
        .accessibilityElement(children: .combine)
    }

    private var identity: some View {
        let size: CGFloat = compact ? 32 : 48
        return HStack(spacing: 10) {
            switch card.content {
            case let .event(event):
                if let source {
                    AvatarView(url: source.avatarURL, name: source.author, size: size)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "newspaper")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: size, height: size)
                        .background(.background, in: Circle())
                        .accessibilityHidden(true)
                }
                Text(event.sourceLabel.isEmpty ? source?.author ?? "简报" : event.sourceLabel)
            case let .company(company):
                TodaySystemAvatar(source: company.avatar, name: company.name, size: size)
                    .accessibilityHidden(true)
                Text(company.name)
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(TodayBriefStyle.accent)
        .lineLimit(1)
    }
}

private struct TodayBriefEventContent: View {
    let event: TodayReadingEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !event.sourceLabel.isEmpty {
                Text(event.sourceLabel).font(.footnote.weight(.semibold))
                    .foregroundStyle(TodayBriefStyle.accent)
            }
            Text(event.text).font(.body).lineSpacing(5)
            if !event.details.isEmpty {
                Text("具体进展").font(.subheadline.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 4)
                ForEach(event.details, id: \.self) { paragraph in
                    Text(paragraph).font(.subheadline).lineSpacing(5)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

private struct TodayBriefCompanyRow: View {
    let card: TodayBriefProjection.CompanyCard

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                TodaySystemAvatar(source: card.avatar, name: card.name, size: 24)
                Text(card.name).font(.subheadline.weight(.semibold)).foregroundStyle(TodayBriefStyle.accent)
            }
            ForEach(card.paragraphs, id: \.self) { fact in
                Text(fact).font(.body).lineSpacing(5)
            }
            if let watch = card.watch {
                Text(watch).font(.subheadline).foregroundStyle(TodayBriefStyle.accent)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("today-system-\(card.system.id)")
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

struct TodayHeaderView: View {
    @Environment(\.openURL) private var openURL
    @State private var rechargeUnavailable = false
    @State private var updateUnavailable = false
    @AppStorage("focus.requestedUpdateRelease") private var requestedUpdateRelease = ""
    @State private var installerPresentation: InstallerPresentation?
    @State private var showsInstallOptions = false
    @State private var completedUpdateVersion: String?
    @Environment(\.scenePhase) private var scenePhase
    @State private var updateCheckAttempt = 0
    @State private var updateCheckFailed = false
    @State private var availableUpdate: AvailableUpdate?
    @State private var showsUpdateCheckError = false
    @State private var showsBilling = false

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
    let balance: AliyunAccountBalance?
    let dailyCosts: DisplaySnapshotCache.Entry<AIUsageDailyCosts>?
    let isLoading: Bool
    let needsRetry: Bool
    let retry: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            headerActions
            installStatus
            if showsBilling {
                billingDetails
            }
        }
        .padding(.horizontal, TodayBriefStyle.horizontalInset)
        .padding(.bottom, 4)
        .alert("无法打开支付宝", isPresented: $rechargeUnavailable) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("请在已安装支付宝的 iPhone 上点击「充值」，前往阿里云官方充值页。")
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
        .alert("未能检查更新", isPresented: $showsUpdateCheckError) {
            Button("重试") { updateCheckAttempt += 1 }
            Button("取消", role: .cancel) {}
        } message: {
            Text("无法确认是否有新版本，请检查网络后重试。已确认可用的更新入口会继续保留。")
        }
        .onAppear(perform: showCompletedUpdate)
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
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await checkForUpdate()
                do { try await Task.sleep(for: .seconds(300)) }
                catch { return }
            }
        }
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

    @ViewBuilder
    private var updateControl: some View {
        if availableUpdate != nil || updateCheckFailed {
            HStack(spacing: 4) {
                if let availableUpdate { updateButton(availableUpdate) }
                if updateCheckFailed {
                    Button { showsUpdateCheckError = true } label: {
                        Label("检查更新", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("today-update-check-failed")
                }
            }
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
            } else {
                availableUpdate = nil
            }
            updateCheckFailed = false
        } catch {
            guard !Task.isCancelled else { return }
            // A failed request never turns a previously verified update into “up to date”.
            updateCheckFailed = true
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
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.1), in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
        .disabled(installerPresentation != nil)
        .accessibilityIdentifier("today-app-update")
        .accessibilityValue(update.version)
        .accessibilityHint(alreadyRequested ? "查看安装说明" : "向 iOS 发起安装请求")
    }

    private var headerActions: some View {
        HStack(spacing: 8) {
            Button {
                showsBilling.toggle()
            } label: {
                HStack(spacing: 5) {
                    Text("阿里云余额")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(balance?.formattedAmount ?? (needsRetry ? "暂不可用" : "—"))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .accessibilityIdentifier("today-aliyun-balance")
                    Image(systemName: showsBilling ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.semibold)).accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("today-billing-details")
            .accessibilityValue(showsBilling ? "已展开" : "已收起")
            Spacer(minLength: 0)
            updateControl
        }
    }

    private var billingDetails: some View {
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 20) {
                    billingCosts
                    Spacer(minLength: 0)
                    rechargeButton
                }
                VStack(alignment: .leading, spacing: 8) {
                    billingCosts
                    rechargeButton
                }
            }
            if needsRetry || isLoading {
                VStack(alignment: .leading, spacing: 4) {
                    if let dailyCosts {
                        Text("账务上次查询于 \(dailyCosts.savedAt, style: .time)")
                    } else if isLoading {
                        Text("正在获取账务数据…")
                    }
                    if needsRetry && !isLoading {
                        Button("重新查询") { Task { await retry() } }
                            .frame(minHeight: 44)
                    }
                }.font(.caption)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .background(TodayBriefStyle.accent.opacity(0.075), in: RoundedRectangle(cornerRadius: 12))
    }

    private var billingCosts: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 20) {
                costItem("今日花费", amount: dailyCosts?.value.todayCostCNY, identifier: "today-model-cost")
                costItem("昨日花费", amount: dailyCosts?.value.yesterdayCostCNY, identifier: "yesterday-model-cost")
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
            Label("充值", systemImage: "arrow.up.right")
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
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

/// Company-group identity is independent of whichever author supplied its first post.
private struct TodaySystemAvatar: View {
    enum Source: Sendable {
        case asset(String)
        case remote(URL?)

        init(_ system: TodayWorldFinalReportSystem) {
            if let asset = TodaySystemAvatar.companyAssets[system.systemKey] {
                self = .asset(asset)
            } else {
                self = .remote(system.sourceKeys.first.flatMap(todayWorldSourceAvatarURL))
            }
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
