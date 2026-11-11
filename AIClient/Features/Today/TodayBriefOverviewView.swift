import SwiftUI

private enum TodayBriefStyle {
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

    init?(payload: TodayWorldYesterdayReportPayload) {
        guard let report = payload.report.final, report.status == "succeeded" else { return nil }
        let systems = report.systems
        guard !systems.isEmpty else { return nil }
        date = payload.date
        postCount = payload.postCount
        sourceCount = payload.sourceCount
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
    let onRefresh: () async -> Void
    let onOpenHighlight: (TodayWorldFinalReportOverviewItem) -> Void
    let onOpenSystem: (TodayWorldFinalReportSystem) -> Void

    var body: some View {
        let section = brief.sections.first { $0.id == selectedSectionKey }
        let highlights = section?.highlights ?? brief.highlights
        let sections = section.map { [$0] } ?? brief.sections
        let watchItems = section?.watchItems ?? brief.watchItems
        VStack(spacing: 0) {
            masthead
            TodayBriefCategories(sections: brief.sections, selection: $selectedSectionKey)
                .padding(.horizontal, 20)
                .padding(.bottom, 14)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        Color.clear.frame(height: 0).id("today-reading-top")
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
                                            index: index,
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
                    .padding(.bottom, bottomInset + 20)
                }
                .scrollIndicators(.hidden)
                .refreshable { await onRefresh() }
                .accessibilityIdentifier("today-overview")
                .onChange(of: selectedSectionKey) { _, _ in
                    proxy.scrollTo("today-reading-top", anchor: .top)
                }
            }
        }
        .background(TodayBriefStyle.canvas)
    }

    private var masthead: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 5) {
                Text("今日").font(.system(size: 32, weight: .bold, design: .serif))
                Text("\(brief.postCount) 条动态 · \(brief.sourceCount) 个信息源")
                    .font(.caption).foregroundStyle(TodayBriefStyle.secondary)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 5) {
                Text(brief.displayDate).font(.subheadline.weight(.medium))
                Text("日报 · \(brief.systems.count) 组动向")
                    .font(.caption).foregroundStyle(TodayBriefStyle.secondary)
            }
        }
        .padding(.horizontal, 22).padding(.top, 10).padding(.bottom, 22)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("today-report-metadata")
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
                .padding(.horizontal, 17).padding(.vertical, 11)
                .background(selection == id ? TodayBriefStyle.accent : Color(uiColor: .tertiarySystemFill), in: Capsule())
                .contentShape(Capsule())
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
    let index: Int
    let isLead: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Text(String(format: "%02d", index + 1)).monospacedDigit()
                Text(isLead ? "焦点" : "要闻")
                Spacer()
                Text(source).foregroundStyle(TodayBriefStyle.secondary)
            }
            .font(.caption.weight(.medium)).foregroundStyle(TodayBriefStyle.accent)
            Text(title)
                .font(isLead ? .title2.weight(.bold) : .title3.weight(.semibold))
                .foregroundStyle(.primary).lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(paragraphs, id: \.self) { paragraph in
                Text(paragraph).font(.subheadline).lineSpacing(5)
                    .foregroundStyle(TodayBriefStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            articleFooter("查看事件与原文", count: sourceCount)
        }
        .multilineTextAlignment(.leading)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
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

struct TodayAliyunBalanceView: View {
    @Environment(\.openURL) private var openURL
    @State private var rechargeUnavailable = false
    @Binding var waitingForRechargeReturn: Bool
    let balance: AliyunAccountBalance?
    let isLoading: Bool

    var body: some View {
        VStack(spacing: 8) {
            rechargeButton
            HStack(spacing: 24) {
                costItem("今日花费", amount: balance?.usage.todayCostCNY, identifier: "today-model-cost")
                costItem("昨日花费", amount: balance?.usage.yesterdayCostCNY, identifier: "yesterday-model-cost")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 22)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
        .background(TodayBriefStyle.canvas)
        .alert("无法打开支付宝", isPresented: $rechargeUnavailable) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("请在已安装支付宝的 iPhone 上点击余额，前往阿里云官方充值页。")
        }
    }

    private func costItem(_ title: String, amount: Double?, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(TodayBriefStyle.secondary)
            Text(AIUsageDailyCosts.formattedCost(amount) ?? (isLoading ? "查询中…" : "暂不可用"))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .accessibilityIdentifier(identifier)
                .accessibilityHint("AI Server 模型调用费用，按北京时间统计")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text("阿里云余额")
                    .font(.body)
                    .foregroundStyle(TodayBriefStyle.secondary)
                Spacer(minLength: 0)
                Text(balance?.formattedAmount ?? (isLoading ? "查询中…" : "暂不可用"))
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                    .accessibilityIdentifier("today-aliyun-balance")
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TodayBriefStyle.secondary)
                    .accessibilityHidden(true)
            }
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
