import SwiftUI
import UIKit

enum TodayBriefStyle {
    static let ink = Color(red: 0.10, green: 0.23, blue: 0.19)
    static let canvas = Color(uiColor: .systemBackground)
    static let secondary = Color(uiColor: .secondaryLabel)
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.67, green: 0.84, blue: 0.72, alpha: 1)
            : UIColor(red: 0.22, green: 0.36, blue: 0.27, alpha: 1)
    })
    static let rule = Color(uiColor: .separator).opacity(0.25)
}

/// Taps open details; scrolling never activates an article.
private struct TodayBriefButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onTapGesture { configuration.trigger() }
            .accessibilityAction { configuration.trigger() }
    }
}

enum TodayOverviewSelection {
    static func highlights(
        in section: TodayWorldFinalReportSection?,
        overview: TodayWorldFinalReportOverview
    ) -> [TodayWorldFinalReportOverviewItem] {
        items(overview.highlights, in: section)
    }

    static func items(
        _ items: [TodayWorldFinalReportOverviewItem],
        in section: TodayWorldFinalReportSection?
    ) -> [TodayWorldFinalReportOverviewItem] {
        guard let section else { return items }
        let systems = section.systems
        let keys = Set(systems.map(\.systemKey))
        let ids = Set(systems.flatMap(\.postIDs))
        return items.filter {
            !keys.isDisjoint(with: $0.systemKeys) || !ids.isDisjoint(with: $0.postIDs)
        }
    }

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

struct TodayBriefProjection {
    struct Section: Identifiable {
        let id: String
        let name: String
        let groups: [TodayWorldFinalReportGroup]
        let highlights: [TodayWorldFinalReportOverviewItem]
        let watchItems: [TodayWorldFinalReportOverviewItem]
        let supplementarySystems: [TodayWorldFinalReportSystem]
        let supplementarySystemIDs: Set<String>

        init(_ section: TodayWorldFinalReportSection, overview: TodayWorldFinalReportOverview) {
            id = section.id
            name = section.sectionName
            groups = section.groups
            highlights = TodayOverviewSelection.highlights(in: section, overview: overview)
            watchItems = TodayOverviewSelection.items(overview.watchItems, in: section)
            supplementarySystems = TodayOverviewSelection.supplementarySystems(in: section, overview: overview)
            supplementarySystemIDs = Set(supplementarySystems.map(\.id))
        }
    }

    let date: String
    let postCount: Int
    let sourceCount: Int
    let highlights: [TodayWorldFinalReportOverviewItem]
    let watchItems: [TodayWorldFinalReportOverviewItem]
    let sections: [Section]
    let systems: [TodayWorldFinalReportSystem]
    let displayDate: String
    let overviewHeadline: String?
    private let highlightPostIDs: [Int]

    init?(edition: TodayPublishedEdition) {
        let report = edition.report
        let systems = report.systems
        guard !systems.isEmpty else { return nil }
        date = edition.date
        postCount = edition.postCount
        sourceCount = edition.sourceCount
        let highlights = report.overview.highlights
        self.highlights = highlights
        watchItems = report.overview.watchItems
        self.systems = systems
        sections = report.sections.map { Section($0, overview: report.overview) }
        highlightPostIDs = highlights.flatMap(\.postIDs)
        let headline = report.overview.headline
        let canonicalHeadline = TodayReadingEvent.canonical(headline)
        overviewHeadline = headline.isEmpty || highlights.contains {
            TodayReadingEvent.canonical($0.title ?? "") == canonicalHeadline
        } ? nil : headline

        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        if let date = parser.date(from: date) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = "M月d日 EEEE"
            displayDate = formatter.string(from: date)
        } else {
            displayDate = date
        }
    }

    func preparationIDs(sectionKey: String?) -> [Int] {
        let selectedSections = sectionKey.map { key in sections.filter { $0.id == key } } ?? sections
        let visiblePostIDs = selectedSections.lazy.flatMap(\.supplementarySystems).prefix(4).flatMap(\.postIDs)
        return TodayChinesePreparation.prioritizedIDs(highlights: highlightPostIDs, visible: Array(visiblePostIDs))
    }
}

struct TodayBriefOverviewView: View {
    let brief: TodayBriefProjection
    let bottomInset: CGFloat
    @Binding var selectedSectionKey: String?
    let onOpenHighlight: (TodayWorldFinalReportOverviewItem) -> Void
    let onOpenSystem: (TodayWorldFinalReportSystem) -> Void

    var body: some View {
        let section = brief.sections.first { $0.id == selectedSectionKey }
        let highlights = section?.highlights ?? brief.highlights
        let sections = section.map { [$0] } ?? brief.sections
        let watchItems = section?.watchItems ?? brief.watchItems
        VStack(spacing: 0) {
            TodayBriefCategories(sections: brief.sections, selection: $selectedSectionKey)
                .padding(.horizontal, 22)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        Text("\(brief.postCount) 条动态 · \(brief.sourceCount) 个信息源 · \(brief.systems.count) 组动向")
                            .font(.caption).foregroundStyle(.secondary)
                            .accessibilityIdentifier("today-report-metadata")
                        if selectedSectionKey == nil, let headline = brief.overviewHeadline {
                            Text(headline)
                                .font(.title3.weight(.medium)).lineSpacing(5)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if !highlights.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                sectionHeading("今日要闻", count: highlights.count)
                                    .padding(.bottom, 6)
                                ForEach(Array(highlights.enumerated()), id: \.element.id) { index, item in
                                    Button { onOpenHighlight(item) } label: {
                                        TodayBriefArticle(
                                            title: item.title ?? "",
                                            paragraphs: TodayReadingEvent.additionalDetails([item.text], excluding: [item.title ?? ""]),
                                            source: sourceLabel(for: item),
                                            sourceCount: Set(item.postIDs).count,
                                            isLead: index == 0
                                        )
                                    }
                                    .buttonStyle(TodayBriefButtonStyle())
                                    .accessibilityIdentifier("today-highlight-\(index)")
                                    if index < highlights.count - 1 {
                                        TodayBriefStyle.rule.frame(height: 0.5)
                                    }
                                }
                            }
                        }
                        ForEach(sections) { section in
                            if !section.supplementarySystems.isEmpty {
                                VStack(alignment: .leading, spacing: 0) {
                                    sectionHeading(section.name + "动态", count: section.supplementarySystems.count)
                                        .padding(.bottom, 16)
                                    ForEach(section.groups) { group in
                                        let visible = group.systems.filter { section.supplementarySystemIDs.contains($0.id) }
                                        if !visible.isEmpty {
                                            Text(group.groupName)
                                                .font(.caption.weight(.medium))
                                                .foregroundStyle(TodayBriefStyle.secondary)
                                                .padding(.top, 8)
                                            ForEach(visible) { system in
                                                TodayBriefCompanyRow(system: system) { onOpenSystem(system) }
                                                TodayBriefStyle.rule.frame(height: 0.5)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        if !watchItems.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                sectionHeading("持续观察", count: watchItems.count)
                                ForEach(watchItems) { item in
                                    watchItem(item)
                                }
                            }
                        }
                        Text("本期内容已全部展示")
                            .font(.caption).foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .accessibilityIdentifier("today-reading-end")
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 8)
                    .padding(.bottom, bottomInset + 20)
                    .id("today-reading-top")
                }
                .scrollIndicators(.hidden)
                .accessibilityIdentifier("today-overview")
                .onChange(of: selectedSectionKey) { _, _ in
                    proxy.scrollTo("today-reading-top", anchor: .top)
                }
            }
        }
        .background(TodayBriefStyle.canvas)
    }

    private func sourceLabel(for item: TodayWorldFinalReportOverviewItem) -> String {
        let ids = Set(item.postIDs)
        let systems = brief.systems.filter {
            item.systemKeys.contains($0.systemKey) || !ids.isDisjoint(with: $0.postIDs)
        }
        return TodayReadingEvent.unique(systems.map { todayBriefSystemName($0.systemName) }).joined(separator: " · ")
    }

    private func watchItem(_ item: TodayWorldFinalReportOverviewItem) -> some View {
        Button { onOpenHighlight(item) } label: {
            VStack(alignment: .leading, spacing: 10) {
                Label("待跟进", systemImage: "binoculars")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(TodayBriefStyle.accent)
                Text(item.title ?? item.text)
                    .font(.headline)
                    .foregroundStyle(.primary)
                if let context = item.context, !context.isEmpty {
                    Text(context)
                        .font(.subheadline)
                        .foregroundStyle(TodayBriefStyle.secondary)
                        .lineSpacing(4)
                }
                if item.title != nil {
                    Text(item.text)
                        .font(.subheadline)
                        .foregroundStyle(TodayBriefStyle.secondary)
                        .lineSpacing(4)
                }
                articleFooter(sourceLabel(for: item), count: Set(item.postIDs).count)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(TodayBriefStyle.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
            .multilineTextAlignment(.leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(TodayBriefButtonStyle())
        .accessibilityIdentifier("today-watch-\(item.id)")
    }

    private func sectionHeading(_ title: String, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.title3.weight(.bold)).foregroundStyle(.primary)
            Text(String(format: "%02d", count))
                .font(.caption.monospacedDigit()).foregroundStyle(TodayBriefStyle.secondary)
            Spacer()
        }
        .accessibilityAddTraits(.isHeader)
    }
}

private struct TodayBriefCategories: View {
    let sections: [TodayBriefProjection.Section]
    @Binding var selection: String?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                category("全部", id: nil)
                ForEach(sections) { section in
                    category(section.name, id: section.id)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func category(_ title: String, id: String?) -> some View {
        Button { selection = id } label: {
            Text(title)
                .font(.subheadline.weight(selection == id ? .semibold : .regular))
                .foregroundStyle(selection == id ? TodayBriefStyle.canvas : TodayBriefStyle.secondary)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(selection == id ? TodayBriefStyle.accent : Color(uiColor: .tertiarySystemFill), in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(TodayBriefButtonStyle())
        .accessibilityIdentifier("today-category-\(id ?? "all")")
        .accessibilityAddTraits(selection == id ? .isSelected : [])
    }
}

private struct TodayBriefArticle: View {
    let title: String
    let paragraphs: [String]
    let source: String
    let sourceCount: Int
    let isLead: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if !source.isEmpty {
                Text(source).font(.caption.weight(.semibold))
                    .foregroundStyle(isLead ? Color.white.opacity(0.82) : TodayBriefStyle.accent)
            }
            if !title.isEmpty {
                Text(title)
                    .font(isLead ? .system(.title2, design: .serif, weight: .bold) : .headline)
                    .lineSpacing(3)
            }
            if let summary = paragraphs.first {
                Text(summary).font(.subheadline).lineSpacing(3).lineLimit(3)
                    .foregroundStyle(isLead ? Color.white.opacity(0.86) : TodayBriefStyle.secondary)
            }
            Label("\(sourceCount) 篇原文", systemImage: "doc.on.doc")
                .font(.caption).opacity(0.8)
        }
        .foregroundStyle(isLead ? Color.white : Color.primary)
        .multilineTextAlignment(.leading)
        .padding(.horizontal, isLead ? 18 : 0)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isLead ? TodayBriefStyle.ink : Color.clear, in: RoundedRectangle(cornerRadius: 16))
        .contentShape(Rectangle())
    }
}

private struct TodayBriefCompanyRow: View {
    let system: TodayWorldFinalReportSystem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 9) {
                    TodaySystemAvatar(system: system, size: 24)
                    Text(todayBriefSystemName(system.systemName))
                        .font(.subheadline.weight(.medium)).foregroundStyle(TodayBriefStyle.accent)
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.up.right").font(.caption)
                        .foregroundStyle(TodayBriefStyle.secondary)
                }
                Text(system.headline)
                    .font(.headline).foregroundStyle(.primary).lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(TodayReadingEvent.additionalDetails(system.facts.map(\.text), excluding: [system.headline]), id: \.self) { fact in
                    Text(fact).font(.subheadline).lineSpacing(5)
                        .foregroundStyle(TodayBriefStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let watch = system.watchItem, !watch.isEmpty {
                    Text("后续关注 · " + watch).font(.subheadline).lineSpacing(4)
                        .foregroundStyle(TodayBriefStyle.accent)
                }
                articleFooter(system.sourceNames.joined(separator: " · "), count: Set(system.postIDs).count)
            }
            .multilineTextAlignment(.leading)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(TodayBriefButtonStyle())
        .accessibilityIdentifier("today-system-\(system.id)")
    }
}

private func articleFooter(_ text: String, count: Int) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
        Text(text)
        Spacer(minLength: 0)
        HStack(spacing: 4) {
            Image(systemName: "text.document")
            Text("\(count) 篇原文").monospacedDigit()
        }
        .fixedSize(horizontal: true, vertical: false)
    }
    .font(.caption).foregroundStyle(TodayBriefStyle.secondary)
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
    @State private var installRequestedAt: Date?
    @State private var installerAccepted = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var updateCheckAttempt = 0
    @State private var updateCheckFailed = false
    @State private var availableUpdate: AvailableUpdate?
    @State private var showsUpdateCheckError = false
    private struct AvailableUpdate {
        let version: String
        let installURL: URL
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

    let reportDate: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center, spacing: 10) {
                Text("今日").font(.system(.largeTitle, design: .serif, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if let reportDate {
                    Text("日报 · " + reportDate).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                updateControl
            }
            ViewThatFits(in: .horizontal) {
                HStack {
                    rechargeButton
                    Spacer(minLength: 12)
                    costs
                }
                VStack(alignment: .leading) {
                    rechargeButton
                    costItem("今日花费", amount: dailyCosts?.value.todayCostCNY, identifier: "today-model-cost")
                    costItem("昨日花费", amount: dailyCosts?.value.yesterdayCostCNY, identifier: "yesterday-model-cost")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 2)
            .background(TodayBriefStyle.accent.opacity(0.075), in: RoundedRectangle(cornerRadius: 12))
            if needsRetry || isLoading {
                HStack {
                    if let dailyCosts {
                        Text("账务上次查询于 \(dailyCosts.savedAt, style: .time)")
                    } else if isLoading {
                        Text("正在获取账务数据…")
                    }
                    if needsRetry && !isLoading {
                        Button("重新查询") { Task { await retry() } }
                    }
                }
                .font(.caption)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .alert("无法打开支付宝", isPresented: $rechargeUnavailable) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("请在已安装支付宝的 iPhone 上点击余额，前往阿里云官方充值页。")
        }
        .alert("无法发起安装", isPresented: $updateUnavailable) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("iOS 没有接受安装请求。请稍后再点「更新」。")
        }
        .alert("未能检查更新", isPresented: $showsUpdateCheckError) {
            Button("重试") { updateCheckAttempt += 1 }
            Button("取消", role: .cancel) {}
        } message: {
            Text("无法确认是否有新版本，请检查网络后重试。已确认可用的更新入口会继续保留。")
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

    @MainActor
    private func checkForUpdate() async {
        do {
            guard let entry = installEntryURL,
                  let localVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                  let localBuildString = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
                  let localBuild = Int(localBuildString),
                  let local = numericVersion(localVersion, build: localBuild) else {
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
            if local.lexicographicallyPrecedes(remote) {
                availableUpdate = AvailableUpdate(version: published.version, installURL: installURL)
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

    private func updateButton(_ update: AvailableUpdate) -> some View {
        Button {
            guard installRequestedAt == nil else { return }
            let requestedAt = Date()
            installerAccepted = false
            installRequestedAt = requestedAt
            UIApplication.shared.open(update.installURL) { accepted in
                guard installRequestedAt == requestedAt else { return }
                if accepted {
                    installerAccepted = true
                } else {
                    installRequestedAt = nil
                    updateUnavailable = true
                }
            }
        } label: {
            HStack(spacing: 4) {
                if installRequestedAt == nil {
                    Label("更新", systemImage: "arrow.down.circle")
                } else if installerAccepted {
                    Label("已请求安装", systemImage: "checkmark.circle")
                } else {
                    ProgressView().controlSize(.small)
                    Text("请求安装中")
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
        .disabled(installRequestedAt != nil)
        .task(id: installRequestedAt) {
            guard let started = installRequestedAt else { return }
            do {
                try await Task.sleep(for: .seconds(max(0, started.addingTimeInterval(60).timeIntervalSinceNow)))
            } catch { return }
            if installRequestedAt == started { installRequestedAt = nil }
        }
        .accessibilityIdentifier("today-app-update")
        .accessibilityValue(update.version)
        .accessibilityHint("向 iOS 发起安装请求")
    }

    private var costs: some View {
        HStack(spacing: 20) {
            costItem("今日花费", amount: dailyCosts?.value.todayCostCNY, identifier: "today-model-cost")
            costItem("昨日花费", amount: dailyCosts?.value.yesterdayCostCNY, identifier: "yesterday-model-cost")
        }
        .fixedSize(horizontal: true, vertical: false)
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
            billingMetric(
                label: HStack(spacing: 4) {
                    Text("阿里云余额")
                    Image(systemName: "arrow.up.right")
                        .font(.caption2.weight(.semibold))
                        .accessibilityHidden(true)
                },
                value: Text(balance?.formattedAmount ?? (dailyCosts == nil && !needsRetry ? "—" : "暂不可用"))
                    .accessibilityIdentifier("today-aliyun-balance")
            )
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("today-aliyun-recharge")
        .accessibilityHint("打开支付宝，前往阿里云官方充值页")
    }
}

private func todayBriefSystemName(_ name: String) -> String {
    name.hasSuffix(" 系") ? String(name.dropLast(2)) : name
}

/// Company-group identity is independent of whichever author supplied its first post.
struct TodaySystemAvatar: View {
    let system: TodayWorldFinalReportSystem
    let size: CGFloat

    private static let companyAssets: [String: String] = [
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
        if let asset = Self.companyAssets[system.systemKey] {
            Image(asset)
                .resizable().scaledToFit()
                .foregroundStyle(.primary)
                .frame(width: size, height: size)
                .accessibilityLabel("\(todayBriefSystemName(system.systemName)) 公司标识")
        } else {
            AvatarView(
                url: system.sourceKeys.first.flatMap(todayWorldSourceAvatarURL),
                name: system.systemName,
                size: size
            )
        }
    }
}

/// Today details have no push navigation; keep their chrome lightweight.
struct TodayDetailSheet<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    private let content: Content
    private let detents: Set<PresentationDetent>

    init(title: String = "事件详情", detents: Set<PresentationDetent> = [.large], @ViewBuilder content: () -> Content) {
        _title = State(initialValue: title)
        self.detents = detents
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .bottomTrailing) {
            Button(action: dismiss.callAsFunction) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .background(.regularMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭")
            .accessibilityIdentifier("today-detail-close")
            .padding(12)
        }
        .background(Color(uiColor: .systemBackground))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today-detail-\(title)")
        .onPreferenceChange(TodayDetailTitleKey.self) { value in
            if let value { title = value }
        }
        .environment(\.rootBottomChromeHeight, 0)
        .presentationDetents(detents)
        .presentationCornerRadius(24)
    }
}

private struct TodayDetailTitleKey: PreferenceKey {
    static let defaultValue: String? = nil
    static func reduce(value: inout String?, nextValue: () -> String?) {
        if let next = nextValue() { value = next }
    }
}

extension View {
    func todayDetailTitle(_ title: String) -> some View {
        preference(key: TodayDetailTitleKey.self, value: title)
    }
}
