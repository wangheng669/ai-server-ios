import Foundation
import SwiftUI

struct InstitutionResearchResponse: Decodable {
    let data: InstitutionResearchPayload
}

enum InstitutionResearchAge: String {
    case recent = "近期观点", historical = "历史观点", unverified = "日期待核验"
}

struct InstitutionResearchCoverage: Decodable, Identifiable {
    let institutionKey: String
    let institutionNameZh: String
    let officialResearchUrl: URL
    let isActive: Bool
    let lastCheckedAt: String?
    let latestPublishedOn: String?
    let activeReportCount: Int

    var id: String { institutionKey }
}

struct InstitutionResearchPayload: Decodable {
    let sources: [InstitutionResearchCoverage]
    let institutionsCount: Int
    let items: [InstitutionResearchItem]
    let updatedAt: Date?
    let institutionShortNames: [String]

    init(sources: [InstitutionResearchCoverage], institutionsCount: Int, items: [InstitutionResearchItem], updatedAt: Date?) {
        self.sources = sources.filter(\.isActive)
        self.institutionsCount = institutionsCount
        self.items = items.sorted { $0.publishedOn == $1.publishedOn ? $0.id < $1.id : $0.publishedOn > $1.publishedOn }
        self.updatedAt = updatedAt
        institutionShortNames = Array(Set(items.map(\.institutionShortName))).sorted()
    }
}

struct InstitutionResearchItem: Decodable, Identifiable, Hashable {
    let id: String
    let institution: String
    let institutionShortName: String
    let title: String
    let originalTitle: String
    let summary: String
    let publishedOn: String
    private let publicationDate: Date?
    let sourceType: String
    let categories: [String]
    let metrics: [InstitutionResearchMetric]
    let targetRevision: InstitutionResearchTargetRevision?
    let source: InstitutionResearchSource
    let isSystemSummary: Bool
    let presentation: InstitutionResearchPresentation
    var originalSummary: String? = nil
    var translationStatus: String? = nil

    var displayTitle: String {
        let suffixes = [" | \(institution)", " | \(institutionChineseName(institutionShortName))"]
        for suffix in suffixes where title.hasSuffix(suffix) {
            return String(title.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
        }
        return title
    }

    var translationLabel: String {
        switch translationStatus {
        case "translated": "中文译文"
        case "pending": "待翻译 · 英文原文"
        case "failed": "翻译待重试 · 英文原文"
        default: sourceType
        }
    }

    func age(now: Date = Date()) -> InstitutionResearchAge {
        guard let publicationDate, publicationDate <= now else { return .unverified }
        return now.timeIntervalSince(publicationDate) > 30 * 86400 ? .historical : .recent
    }

    private static let publicationDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

extension InstitutionResearchPayload {
    private enum CodingKeys: String, CodingKey {
        case reports, updatedAt, sources
    }

    private struct ReportRecord: Decodable {
        let item: InstitutionResearchItem
        let isActive: Bool
        private enum CodingKeys: String, CodingKey { case isActive }
        init(from decoder: Decoder) throws {
            item = try InstitutionResearchItem(from: decoder)
            let values = try decoder.container(keyedBy: CodingKeys.self)
            isActive = try values.decode(Bool.self, forKey: .isActive)
        }
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let items = try values.decode([ReportRecord].self, forKey: .reports)
            .filter(\.isActive).map(\.item)
        let timestamp = try values.decodeIfPresent(String.self, forKey: .updatedAt)
        let sources = try values.decode([InstitutionResearchCoverage].self, forKey: .sources)
        let institutionsCount = sources.count(where: { $0.isActive && $0.activeReportCount > 0 })
        self.init(sources: sources, institutionsCount: institutionsCount, items: items, updatedAt: marketISODate(timestamp))
    }
}

extension InstitutionResearchItem {
    private enum CodingKeys: String, CodingKey {
        case id, institution, institutionShortName, title, originalTitle, summary, publishedOn
        case sourceType, categories, metrics, targetRevision, sourceTitle, sourceUrl
        case isSystemSummary, presentation, originalSummary, translationStatus
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        institution = try values.decode(String.self, forKey: .institution)
        institutionShortName = try values.decode(String.self, forKey: .institutionShortName)
        title = try values.decode(String.self, forKey: .title)
        originalTitle = try values.decode(String.self, forKey: .originalTitle)
        summary = try values.decode(String.self, forKey: .summary)
        publishedOn = try values.decode(String.self, forKey: .publishedOn)
        publicationDate = Self.publicationDateFormatter.date(from: publishedOn)
        sourceType = try values.decode(String.self, forKey: .sourceType)
        categories = try values.decode([String].self, forKey: .categories)
        metrics = try values.decode([InstitutionResearchMetric].self, forKey: .metrics)
        targetRevision = try values.decodeIfPresent(InstitutionResearchTargetRevision.self, forKey: .targetRevision)
        source = InstitutionResearchSource(
            title: try values.decode(String.self, forKey: .sourceTitle),
            url: try values.decode(URL.self, forKey: .sourceUrl)
        )
        isSystemSummary = try values.decode(Bool.self, forKey: .isSystemSummary)
        presentation = try values.decode(InstitutionResearchPresentation.self, forKey: .presentation)
        originalSummary = try values.decodeIfPresent(String.self, forKey: .originalSummary)
        translationStatus = try values.decodeIfPresent(String.self, forKey: .translationStatus)
    }
}

struct InstitutionResearchMetric: Decodable, Hashable, Identifiable {
    let label: String
    let value: String

    var id: String { label }
}

struct InstitutionResearchTargetRevision: Decodable, Hashable {
    let label: String
    let previousValue: String
    let currentValue: String
}

struct InstitutionResearchSource: Decodable, Hashable {
    let title: String
    let url: URL
}

enum InstitutionResearchPresentation: String, Decodable, Hashable {
    case lead
    case snapshot
    case revision
}

struct InstitutionResearchService {
    var baseURL: URL = ServerConfiguration.currentURL
    var session: URLSession = .shared

    func fetch(onCached: @escaping @MainActor (InstitutionResearchPayload) -> Void) async throws -> InstitutionResearchPayload {
        let url = baseURL.appending(path: "api/ios/v1/market/institution-research")
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        return try await loadDisplayPage(request: request, session: session, onCached: onCached) { data in
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(InstitutionResearchResponse.self, from: data).data
        }
    }
}

@MainActor
final class InstitutionResearchStore: ObservableObject {
    @Published private(set) var payload: InstitutionResearchPayload?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private var lastLoadedAt: Date?
    private let service: InstitutionResearchService

    init(service: InstitutionResearchService = InstitutionResearchService()) {
        self.service = service
    }

    func load(force: Bool = false) async {
        guard !isLoading else { return }
        if !force, let lastLoadedAt, Date().timeIntervalSince(lastLoadedAt) < 900 { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            payload = try await service.fetch { cached in
                if self.payload == nil { self.payload = cached }
            }
            lastLoadedAt = Date()
        } catch is CancellationError {
            return
        } catch {
            errorMessage = "机构研究暂时无法载入"
        }
    }
}

@MainActor
struct InstitutionResearchView: View {
    @StateObject private var store: InstitutionResearchStore
    @Environment(\.rootTabIsActive) private var rootTabIsActive
    @FocusState private var searchIsFocused: Bool
    @State private var selectedInstitution: String?
    @State private var scope = ResearchScope.all
    @State private var search = ""
    private let accent = ResearchDesign.accent

    private enum ResearchScope: String, CaseIterable {
        case all = "全部", recent = "近30天", history = "历史"
    }

    init(store: InstitutionResearchStore) {
        _store = StateObject(wrappedValue: store)
    }

    private func filteredItems(_ items: [InstitutionResearchItem]) -> [InstitutionResearchItem] {
        guard selectedInstitution != nil || scope != .all || !search.isEmpty else { return items }
        let now = Date()
        return items.filter { item in
            (selectedInstitution == nil || item.institutionShortName == selectedInstitution)
                && (scope == .all || item.age(now: now) == (scope == .recent ? .recent : .historical))
                && (search.isEmpty || "\(item.title) \(item.summary) \(item.originalTitle) \(item.institution)".localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        let items = store.payload?.items ?? []
        let filtered = filteredItems(items)
        VStack(spacing: 0) {
            filters
            if let payload = store.payload {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if let message = store.errorMessage {
                            Button {
                                Task { await store.load(force: true) }
                            } label: {
                                Label("\(message)，正在显示上次载入的报告", systemImage: "arrow.clockwise")
                                    .font(.caption)
                                    .foregroundStyle(accent)
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        HStack {
                            Text("\(filtered.count) 篇研究")
                            Spacer()
                            Text("按发布日期排序")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 11)
                        if filtered.isEmpty {
                            ContentUnavailableView(items.isEmpty ? "暂无公开研究" : "没有符合条件的报告", systemImage: "line.3.horizontal.decrease.circle")
                        }
                        ForEach(filtered) { item in
                            NavigationLink {
                                InstitutionResearchDetail(item: item)
                            } label: { row(item) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("institution-report-\(item.id)")
                            .padding(.bottom, 8)
                        }
                        Text("部分报告提供中文机器翻译。发表超过 30 天的报告标为历史观点。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 18)
                        coverage(payload)
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 64)
                }
            } else if store.isLoading {
                ContentLoadingPlaceholder(title: "正在载入研究报告")
                    .frame(maxHeight: .infinity, alignment: .top)
            } else {
                ContentUnavailableView {
                    Label(store.errorMessage ?? "暂无公开研究", systemImage: "doc.text.magnifyingglass")
                } actions: {
                    Button("重新加载") { Task { await store.load(force: true) } }
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
        .toolbar(.hidden, for: .navigationBar)
        .scrollDismissesKeyboard(.interactively)
        .tint(accent)
        .task(id: rootTabIsActive) {
            guard rootTabIsActive else { return }
            await store.load()
        }
        .onChange(of: rootTabIsActive) { _, active in
            if !active { searchIsFocused = false }
        }
    }

    private func coverage(_ payload: InstitutionResearchPayload) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(payload.sources) { source in
                    Link(destination: source.officialResearchUrl) {
                        HStack {
                            Text(source.institutionNameZh)
                            Spacer()
                            Text(coverageStatus(source)).foregroundStyle(.secondary)
                            Image(systemName: "arrow.up.right").font(.caption2)
                        }
                        .font(.caption)
                    }
                }
            }
            .padding(.top, 10)
        } label: {
            Text("已收录 \(payload.institutionsCount) / \(payload.sources.count) 家机构")
                .font(.caption.weight(.medium))
        }
        .padding(12)
        .researchPanel(fill: ResearchDesign.fill)
    }

    private func coverageStatus(_ source: InstitutionResearchCoverage) -> String {
        if source.activeReportCount > 0, let date = source.latestPublishedOn {
            return "\(source.activeReportCount) 篇 · 最新 \(date)"
        }
        if source.lastCheckedAt == nil { return "暂无采集记录" }
        return "已检查 · 暂无入库"
    }

    private var filters: some View {
        VStack(spacing: 4) {
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索观点、机构或关键词", text: $search)
                        .focused($searchIsFocused)
                        .font(.subheadline)
                        .submitLabel(.search)
                        .accessibilityIdentifier("institution-search")
                    if !search.isEmpty {
                        Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                            .accessibilityLabel("清除搜索")
                    }
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                Menu {
                    Picker("发布时间", selection: $scope) {
                        ForEach(ResearchScope.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                } label: {
                    Label(scope == .all ? "全部时间" : scope.rawValue, systemImage: "line.3.horizontal.decrease")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 44)
                        .background(ResearchDesign.selection, in: RoundedRectangle(cornerRadius: 10))
                }
                .accessibilityIdentifier("institution-time-filter")
            }
            .padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    institutionFilter(nil, title: "全部机构")
                    ForEach(store.payload?.institutionShortNames ?? [], id: \.self) { name in
                        institutionFilter(name, title: institutionChineseName(name))
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 4)
        .overlay(alignment: .bottom) { ResearchDesign.line.frame(height: 1) }
    }

    private func institutionFilter(_ value: String?, title: String) -> some View {
        Button { selectedInstitution = value } label: {
            Text(title)
                .font(.subheadline.weight(selectedInstitution == value ? .semibold : .regular))
                .foregroundStyle(selectedInstitution == value ? accent : .secondary)
                .padding(.horizontal, 13)
                .frame(minHeight: 32)
                .background(selectedInstitution == value ? accent.opacity(0.08) : Color(uiColor: .secondarySystemBackground), in: Capsule())
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectedInstitution == value ? .isSelected : [])
    }

    private func row(_ item: InstitutionResearchItem) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Text(institutionChineseName(item.institutionShortName))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
                Spacer()
                Text(item.publishedOn).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Text(item.displayTitle)
                .font(.headline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
            Text(item.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
            HStack(spacing: 8) {
                Text(item.age().rawValue)
                Text("·")
                Text(item.translationLabel)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .researchPanel()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct InstitutionResearchDetail: View {
    let item: InstitutionResearchItem
    @State private var showsOriginal = false
    private let accent = Color(red: 0.98, green: 0.36, blue: 0.12)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text(institutionChineseName(item.institutionShortName)).font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(item.publishedOn).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Text(item.displayTitle).font(.system(size: 25, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Text(item.age().rawValue)
                    Text("·")
                    Text(item.translationLabel)
                }
                .font(.caption).foregroundStyle(.secondary)
                Divider().opacity(0.45)
                Text("观点摘要").font(.headline)
                Text(item.summary).font(.system(size: 17)).lineSpacing(7).textSelection(.enabled)
                if let revision = item.targetRevision {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(revision.label).font(.subheadline).foregroundStyle(.secondary)
                        Text("\(revision.previousValue) → \(revision.currentValue)").font(.title3.monospacedDigit())
                    }
                }
                ForEach(item.metrics) { metric in
                    HStack { Text(metric.label).foregroundStyle(.secondary); Spacer(); Text(metric.value).monospacedDigit() }
                        .font(.subheadline)
                }
                if item.translationStatus == "translated" {
                    DisclosureGroup("英文对照", isExpanded: $showsOriginal) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(item.originalTitle).font(.headline)
                            if let original = item.originalSummary, !original.isEmpty {
                                Text(original).font(.system(size: 15)).lineSpacing(5)
                            }
                        }
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(.top, 12)
                    }
                }
                Divider().opacity(0.45)
                Link(destination: item.source.url) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("打开官方来源").font(.subheadline.weight(.semibold))
                            Text(item.source.url.host ?? item.institution).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }
                    .frame(minHeight: 44)
                }
                Text("译文由系统生成，保留原文的数字、条件和观点归属；请结合原文及发布日期阅读。")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(20)
            .padding(.bottom, 76)
        }
        .background(Color(uiColor: .systemBackground))
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .tint(accent)
    }
}

func institutionChineseName(_ short: String) -> String {
    switch short {
    case "GS": "高盛"
    case "MS": "摩根士丹利"
    case "JPM": "摩根大通"
    default: short
    }
}
