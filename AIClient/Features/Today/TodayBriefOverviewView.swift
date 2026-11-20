import SwiftUI
import UIKit

enum TodayBriefStyle {
    static let ink = Color(red: 0.10, green: 0.23, blue: 0.19)
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
            let displayed = matches.flatMap { [$0.title ?? "", $0.text] }
            // Sharing one source does not mean the entire company report is covered.
            return !Set(system.postIDs).isSubset(of: covered)
                || !TodayReadingEvent.additionalDetails([system.headline] + system.facts.map(\.text), excluding: displayed).isEmpty
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
        let sources: String
        let postIDs: [Int]

        init(_ system: TodayWorldFinalReportSystem) {
            self.system = system
            name = todayBriefSystemName(system.systemName)
            avatar = TodaySystemAvatar.Source(system)
            paragraphs = TodayReadingEvent.additionalDetails(system.facts.map(\.text), excluding: [system.headline])
            watch = system.watchItem.flatMap { $0.isEmpty ? nil : "后续关注 · " + $0 }
            sources = system.sourceNames.joined(separator: " · ")
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

        var sourceNames: String {
            guard case let .company(company) = content else { return "" }
            return company.sources
        }

        var postIDs: [Int] {
            switch content {
            case let .event(event): event.postIDs
            case let .company(company): company.postIDs
            }
        }
    }

    let date: String
    let postCount: Int
    let sourceCount: Int
    let isPartial: Bool
    let overviewHeadline: String?
    fileprivate let cards: [Card]
    let sourceIDs: [Int]
    private(set) var sources: [Int: TodaySourcePresentation] = [:]

    var missingSourceCount: Int {
        sourceIDs.count - sources.count
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
        postCount = edition.postCount
        sourceCount = edition.sourceCount
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
        let headline = overview.headline
        let canonicalHeadline = TodayReadingEvent.canonical(headline)
        overviewHeadline = headline.isEmpty || highlights.contains {
            TodayReadingEvent.canonical($0.title) == canonicalHeadline
        } ? nil : headline
    }
}

struct TodayBriefOverviewView: View {
    let brief: TodayBriefProjection
    let cachedEditionMessage: String?
    let reportError: String?
    let isRefreshing: Bool
    let retryReport: () async -> Void

    var body: some View {
        Group {
            if brief.cards.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        editionStatus
                        if let headline = brief.overviewHeadline {
                            Text(headline).font(.subheadline).lineSpacing(4)
                        }
                        editionCounts
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }
            } else {
                cardPager
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .accessibilityIdentifier("today-overview")
    }

    private var cardPager: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(brief.cards) { card in
                        ScrollView(.vertical) {
                            LazyVStack(alignment: .leading, spacing: 12) {
                                let isFirstCard = card.id == brief.cards.first?.id
                                if isFirstCard {
                                    editionStatus
                                    if let headline = brief.overviewHeadline {
                                        Text(headline).font(.subheadline).lineSpacing(4)
                                            .foregroundStyle(TodayBriefStyle.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Divider()
                                    }
                                }
                                cardContent(card.content)
                                let sources = card.postIDs.compactMap { brief.sources[$0] }
                                sourcesHeading(card, availableCount: sources.count)
                                ForEach(sources) { source in
                                    TodayInlineSourceView(source: source)
                                }
                                if isFirstCard { editionCounts }
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
                        .frame(height: geometry.size.height)
                        .containerRelativeFrame(.horizontal)
                        .id(card.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden, axes: .horizontal)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .scrollTargetBehavior(.paging)
            .accessibilityIdentifier("today-card-pager")
        }
    }

    @ViewBuilder
    private var editionStatus: some View {
        if let reportError {
            Label("已显示缓存日报 · \(reportError)", systemImage: "exclamationmark.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else if let cachedEditionMessage {
            Text(cachedEditionMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("today-cached-edition")
        }
        if brief.isPartial {
            Label("部分发布 · 本期内容尚不完整", systemImage: "exclamationmark.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("today-partial-edition")
        }
        if brief.missingSourceCount > 0 {
            Text("\(brief.missingSourceCount) 篇原文暂不可用")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        if reportError != nil || brief.missingSourceCount > 0 {
            if isRefreshing {
                ProgressView().controlSize(.small)
            } else {
                Button("重试") { Task { await retryReport() } }
                    .font(.subheadline)
            }
        }
    }

    private var editionCounts: some View {
        Text("\(brief.postCount) 条动态 · \(brief.sourceCount) 个信息源")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("today-report-metadata")
    }

    private func sourcesHeading(_ card: TodayBriefProjection.Card, availableCount: Int) -> some View {
        let count = card.postIDs.count
        return VStack(alignment: .leading, spacing: 5) {
            Divider().padding(.bottom, 5)
            Text(count == 0 ? "消息来源" : "消息来源 · \(count) 篇原文")
                .font(.subheadline.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            if !card.sourceNames.isEmpty {
                Text(card.sourceNames).font(.caption).foregroundStyle(.secondary)
            }
            if count == 0 {
                Text("本条简报暂未提供原文引用").font(.caption).foregroundStyle(.secondary)
            } else if availableCount < count {
                Text("\(count - availableCount) 篇原文暂不可用").font(.caption).foregroundStyle(.secondary)
            }
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

private struct TodayBriefEventContent: View {
    let event: TodayReadingEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !event.sourceLabel.isEmpty {
                Text(event.sourceLabel).font(.caption.weight(.semibold))
                    .foregroundStyle(TodayBriefStyle.accent)
            }
            Text(event.title)
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
                .textSelection(.enabled)
            if !event.summary.isEmpty {
                Text(event.summary).font(.body).lineSpacing(4).textSelection(.enabled)
            }
            if !event.details.isEmpty {
                Text("具体进展").font(.subheadline.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 4)
                ForEach(event.details, id: \.self) { paragraph in
                    Text(paragraph).font(.subheadline).lineSpacing(4).textSelection(.enabled)
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
            Text(card.system.headline).font(.headline).lineSpacing(4)
                .accessibilityAddTraits(.isHeader)
            ForEach(card.paragraphs, id: \.self) { fact in
                Text(fact).font(.subheadline).foregroundStyle(.secondary).lineSpacing(4)
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
        VStack(alignment: .leading, spacing: 5) {
            headerActions
            installStatus
            if showsBilling {
                billingDetails
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
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
            VStack(alignment: .leading, spacing: 4) {
                Label("已向 iOS 发起 \(update.version) 安装", systemImage: "arrow.down.to.line")
                    .font(.subheadline.weight(.medium))
                Text("在系统弹窗确认安装后，可在主屏幕的焦点图标上查看进度。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
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
                        Label("检查失败", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
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
                    billingMetric(
                        label: Text("阿里云余额"),
                        value: Text(balance?.formattedAmount ?? (needsRetry ? "暂不可用" : "—"))
                            .accessibilityIdentifier("today-aliyun-balance")
                    )
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

private func todayBriefSystemName(_ name: String) -> String {
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
