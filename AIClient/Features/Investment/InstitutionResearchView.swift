import Foundation
import SwiftUI

struct InstitutionResearchResponse: Decodable {
    let data: InstitutionResearchPayload
}

struct InstitutionResearchPayload: Decodable {
    let institutionsCount: Int
    let items: [InstitutionResearchItem]
    let updatedAt: Date?
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

    private let fetch: () async throws -> InstitutionResearchPayload

    init(service: InstitutionResearchService = InstitutionResearchService()) {
        fetch = { try await service.fetch() }
    }

    init(fetch: @escaping () async throws -> InstitutionResearchPayload) {
        self.fetch = fetch
    }

    func load(force: Bool = false) async {
        guard !isLoading, force || payload == nil else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            payload = try await fetch()
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

    init() {
        _store = StateObject(wrappedValue: InstitutionResearchStore())
    }

    init(store: InstitutionResearchStore) {
        _store = StateObject(wrappedValue: store)
    }

    var body: some View {
        Group {
            if let payload = store.payload, !payload.items.isEmpty {
                content(payload)
            } else if store.isLoading {
                ProgressView("正在载入机构研究")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(InvestmentDesign.surface)
            } else if let message = store.errorMessage {
                ContentUnavailableView {
                    Label(message, systemImage: "wifi.exclamationmark")
                } description: {
                    Text("请稍后重试")
                } actions: {
                    Button("重新载入") { Task { await store.load(force: true) } }
                }
            } else {
                ContentUnavailableView("暂无公开研究", systemImage: "doc.text.magnifyingglass")
            }
        }
        .background(store.isLoading ? InvestmentDesign.surface : InvestmentDesign.canvas)
        .task(id: rootTabIsActive) {
            guard rootTabIsActive else { return }
            await store.load()
        }
    }

    private func content(_ payload: InstitutionResearchPayload) -> some View {
        ScrollView {
            LazyVStack(spacing: InvestmentDesign.sectionSpacing) {
                trustBanner(payload.institutionsCount)

                if let lead = payload.items.first(where: { $0.presentation == .lead }) {
                    leadCard(lead)
                }

                ForEach(payload.items.filter { $0.presentation != .lead }) { item in
                    researchCard(item)
                }

                latestResearchList(payload.items)
                disclosure
            }
            .padding(.horizontal, InvestmentDesign.pageInset)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
    }

    private func trustBanner(_ institutionsCount: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(InvestmentDesign.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text("公开机构研究")
                    .font(.system(size: 15, weight: .semibold))
                Text("仅收录官方公开内容 · 每条可查看原文")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text("\(institutionsCount) 家机构")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(InvestmentDesign.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(InvestmentDesign.accentSoft, in: Capsule())
        }
        .padding(14)
        .institutionCard()
    }

    private func leadCard(_ item: InstitutionResearchItem) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                institutionBadge(item.institutionShortName)
                Text("最新公开观点")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatDate(item.publishedOn))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Text(item.title)
                .font(.system(size: 21, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            Text(item.summary)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            categoryRow(item.categories)
            sourceLink(item)
        }
        .padding(16)
        .institutionCard()
    }

    private func researchCard(_ item: InstitutionResearchItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                institutionBadge(item.institutionShortName)
                Text(item.title)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(2)
                Spacer(minLength: 8)
            }

            if let revision = item.targetRevision {
                VStack(alignment: .leading, spacing: 8) {
                    Text(revision.label)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Text(revision.previousValue)
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .strikethrough()
                        Image(systemName: "arrow.right")
                            .foregroundStyle(InvestmentDesign.accent)
                        Text(revision.currentValue)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(InvestmentDesign.accent)
                    }
                }
            }

            if !item.metrics.isEmpty {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(item.metrics.enumerated()), id: \.element.id) { index, metric in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(metric.value)
                                .font(.system(size: 21, weight: .bold, design: .rounded))
                                .minimumScaleFactor(0.75)
                            Text(metric.label)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if index < item.metrics.count - 1 {
                            Divider().padding(.horizontal, 8)
                        }
                    }
                }
            }

            Text(item.summary)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            sourceLink(item)
        }
        .padding(16)
        .institutionCard()
    }

    private func latestResearchList(_ items: [InstitutionResearchItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("最新公开研究")
                .font(.system(size: 17, weight: .bold))
                .padding(.bottom, 8)
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                Link(destination: item.source.url) {
                    HStack(spacing: 12) {
                        Text(item.institutionShortName)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(InvestmentDesign.accent)
                            .frame(width: 34, height: 34)
                            .background(InvestmentDesign.accentSoft, in: RoundedRectangle(cornerRadius: 9))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            Text(item.sourceType)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Text(formatDate(item.publishedOn))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 11)
                }
                if index < items.count - 1 { Divider().padding(.leading, 46) }
            }
        }
        .padding(16)
        .institutionCard()
    }

    private var disclosure: some View {
        Label("中文标题与摘要由系统整理 · 数字来自原始来源", systemImage: "info.circle")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.top, 4)
    }

    private func institutionBadge(_ name: String) -> some View {
        Text(name)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(InvestmentDesign.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(InvestmentDesign.accentSoft, in: Capsule())
    }

    private func categoryRow(_ categories: [String]) -> some View {
        HStack(spacing: 7) {
            ForEach(categories, id: \.self) { category in
                Text(category)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(InvestmentDesign.secondarySurface, in: Capsule())
            }
        }
    }

    private func sourceLink(_ item: InstitutionResearchItem) -> some View {
        Link(destination: item.source.url) {
            HStack(spacing: 6) {
                Text(item.sourceType)
                Spacer()
                Text("查看原文")
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(InvestmentDesign.accent)
        }
        .padding(.top, 2)
    }

    private func formatDate(_ value: String) -> String {
        guard let date = DateFormatter.institutionAPIDate.date(from: value) else { return value }
        return DateFormatter.institutionDisplayDate.string(from: date)
    }
}

private extension View {
    func institutionCard() -> some View {
        background(InvestmentDesign.surface, in: RoundedRectangle(cornerRadius: InvestmentDesign.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: InvestmentDesign.cornerRadius, style: .continuous)
                    .stroke(InvestmentDesign.divider, lineWidth: 0.5)
            }
    }
}

private extension DateFormatter {
    static let institutionAPIDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let institutionDisplayDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "M月d日"
        return formatter
    }()
}
