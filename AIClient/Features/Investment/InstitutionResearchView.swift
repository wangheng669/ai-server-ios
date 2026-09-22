import Foundation
import SwiftUI

struct InstitutionResearchResponse: Decodable {
    let data: InstitutionResearchPayload
}

struct InstitutionResearchPayload: Decodable {
    let institutionsCount: Int
    let items: [InstitutionResearchItem]
    let updatedAt: Date?

    var chronologicalItems: [InstitutionResearchItem] {
        items.sorted { $0.publishedOn == $1.publishedOn ? $0.id < $1.id : $0.publishedOn > $1.publishedOn }
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
}

extension InstitutionResearchPayload {
    private enum CodingKeys: String, CodingKey {
        case institutionsCount, items, sources, reports, updatedAt
    }

    private struct ReportRecord: Decodable {
        let item: InstitutionResearchItem
        let isActive: Bool
        private enum CodingKeys: String, CodingKey { case isActive }
        init(from decoder: Decoder) throws {
            item = try InstitutionResearchItem(from: decoder)
            let values = try decoder.container(keyedBy: CodingKeys.self)
            isActive = try values.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        }
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if values.contains(.items) {
            items = try values.decode([InstitutionResearchItem].self, forKey: .items)
        } else {
            items = try values.decode([ReportRecord].self, forKey: .reports)
                .filter(\.isActive).map(\.item)
        }
        institutionsCount = try values.decodeIfPresent(Int.self, forKey: .institutionsCount)
            ?? Set(items.map(\.institution)).count
        let timestamp = try values.decodeIfPresent(String.self, forKey: .updatedAt)
        updatedAt = marketISODate(timestamp)
    }
}

extension InstitutionResearchItem {
    private enum CodingKeys: String, CodingKey {
        case id, institution, institutionShortName, title, originalTitle, summary, publishedOn
        case sourceType, categories, metrics, targetRevision, source, sourceTitle, sourceUrl
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
        sourceType = try values.decode(String.self, forKey: .sourceType)
        categories = try values.decode([String].self, forKey: .categories)
        metrics = try values.decode([InstitutionResearchMetric].self, forKey: .metrics)
        targetRevision = try values.decodeIfPresent(InstitutionResearchTargetRevision.self, forKey: .targetRevision)
        if let nested = try values.decodeIfPresent(InstitutionResearchSource.self, forKey: .source) {
            source = nested
        } else {
            source = InstitutionResearchSource(
                title: try values.decode(String.self, forKey: .sourceTitle),
                url: try values.decode(URL.self, forKey: .sourceUrl)
            )
        }
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

    func fetch() async throws -> InstitutionResearchPayload {
        let url = baseURL.appending(path: "api/ios/v1/market/institution-research")
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(InstitutionResearchResponse.self, from: data).data
    }
}

@MainActor
final class InstitutionResearchStore: ObservableObject {
    @Published private(set) var payload: InstitutionResearchPayload?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private var lastLoadedAt: Date?
    private let fetch: () async throws -> InstitutionResearchPayload

    init(service: InstitutionResearchService = InstitutionResearchService()) {
        fetch = { try await service.fetch() }
    }

    init(fetch: @escaping () async throws -> InstitutionResearchPayload) {
        self.fetch = fetch
    }

    func load(force: Bool = false) async {
        guard !isLoading else { return }
        if !force, let lastLoadedAt, Date().timeIntervalSince(lastLoadedAt) < 900 { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            payload = try await fetch()
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
    @Environment(\.dismiss) private var dismiss
    @State private var selectedInstitution: String?
    @State private var scope = ResearchScope.all
    @State private var search = ""
    private let accent = Color(red: 0.98, green: 0.36, blue: 0.12)

    private enum ResearchScope: String, CaseIterable {
        case all = "全部", recent = "近30天", history = "历史"
    }

    init() { _store = StateObject(wrappedValue: InstitutionResearchStore()) }
    init(store: InstitutionResearchStore) { _store = StateObject(wrappedValue: store) }

    private var items: [InstitutionResearchItem] { store.payload?.chronologicalItems ?? [] }
    private var institutions: [String] { Array(Set(items.map(\.institutionShortName))).sorted() }
    private var filtered: [InstitutionResearchItem] {
        items.filter { item in
            let age = institutionResearchAgeLabel(item.publishedOn)
            return (selectedInstitution == nil || item.institutionShortName == selectedInstitution)
                && (scope == .all || (scope == .recent ? age == "近期观点" : age == "历史观点"))
                && (search.isEmpty || "\(item.title) \(item.summary) \(item.originalTitle) \(item.institution)".localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            filters
            if !items.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("\(filtered.count) 篇研究")
                            Spacer()
                            Text("按发布日期排序")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 14)
                        if filtered.isEmpty {
                            ContentUnavailableView("没有符合条件的报告", systemImage: "line.3.horizontal.decrease.circle")
                        }
                        ForEach(filtered) { item in
                            NavigationLink {
                                InstitutionResearchDetail(item: item)
                            } label: { row(item) }
                            .buttonStyle(.plain)
                            Divider().opacity(0.45)
                        }
                        Text("中文为机器翻译，英文原文可对照。报告发布日期超过30天标为历史观点。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 18)
                        if let message = store.errorMessage {
                            Text("\(message)，正在显示上次载入的报告")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 18)
                }
                .refreshable { await store.load(force: true) }
            } else if store.isLoading {
                Spacer(); ProgressView("正在加载研究"); Spacer()
            } else {
                ContentUnavailableView {
                    Label(store.errorMessage ?? "暂无公开研究", systemImage: "doc.text.magnifyingglass")
                } actions: {
                    Button("重新加载") { Task { await store.load(force: true) } }
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle("机构观点")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("关闭", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
            }
        }
        .searchable(text: $search, prompt: "搜索观点、机构或关键词")
        .tint(accent)
        .task { await store.load() }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    institutionFilter(nil, title: "全部机构")
                    ForEach(institutions, id: \.self) { name in
                        institutionFilter(name, title: institutionChineseName(name))
                    }
                }
            }
            .scrollIndicators(.hidden)
            HStack(spacing: 22) {
                ForEach(ResearchScope.allCases, id: \.self) { option in
                    Button { scope = option } label: {
                        VStack(spacing: 6) {
                            Text(option.rawValue)
                                .font(.subheadline.weight(scope == option ? .semibold : .regular))
                                .foregroundStyle(scope == option ? .primary : .secondary)
                            Rectangle().fill(scope == option ? accent : .clear).frame(height: 2)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(scope == option ? .isSelected : [])
                }
                Spacer()
                Text("官方来源").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .overlay(alignment: .bottom) { Divider().opacity(0.5) }
    }

    private func institutionFilter(_ value: String?, title: String) -> some View {
        Button { selectedInstitution = value } label: {
            Text(title)
                .font(.subheadline.weight(selectedInstitution == value ? .semibold : .regular))
                .foregroundStyle(selectedInstitution == value ? accent : .secondary)
                .padding(.horizontal, 13)
                .frame(minHeight: 44)
                .background(selectedInstitution == value ? accent.opacity(0.08) : Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectedInstitution == value ? .isSelected : [])
    }

    private func row(_ item: InstitutionResearchItem) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Text(item.institutionShortName)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 4)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 4))
                Text(institutionChineseName(item.institutionShortName))
                    .font(.caption.weight(.medium))
                Spacer()
                Text(item.publishedOn).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Text(item.displayTitle)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
            Text(item.summary)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
            HStack(spacing: 8) {
                Text(institutionResearchAgeLabel(item.publishedOn))
                Text("·")
                Text(item.translationLabel)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 17)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct InstitutionResearchDetail: View {
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
                    Text(institutionResearchAgeLabel(item.publishedOn))
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
                            Text("阅读官方原文").font(.subheadline.weight(.semibold))
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
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle("研究详情")
        .navigationBarTitleDisplayMode(.inline)
        .tint(accent)
    }
}

private func institutionChineseName(_ short: String) -> String {
    switch short {
    case "GS": "高盛"
    case "MS": "摩根士丹利"
    case "JPM": "摩根大通"
    default: short
    }
}

func institutionResearchAgeLabel(_ publishedOn: String, now: Date = Date()) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    guard let date = formatter.date(from: publishedOn), date <= now else { return "日期待核验" }
    return now.timeIntervalSince(date) > 30 * 86400 ? "历史观点" : "近期观点"
}
