import Charts
import Foundation
import SwiftUI

struct VolatilityResearchResponse: Decodable {
    let data: VolatilityResearchPayload
}

struct VolatilityResearchPayload: Decodable {
    let generatedAt: Date
    let lookbackDays: Int
    let summary: String
    let items: [VolatilityResearchInstrument]
    let isStale: Bool
}

struct VolatilityResearchInstrument: Decodable, Identifiable, Hashable {
    let id: String
    let market: String
    let name: String
    let shortName: String
    let value: Double
    let previousClose: Double
    let dailyChangePercent: Double
    let peakValue: Double
    let peakDate: String
    let drawdownFromPeakPercent: Double
    let asOf: String
    let regime: String
    let interpretation: String
    let history: [VolatilityResearchPoint]
    let source: VolatilityResearchSource
}

struct VolatilityResearchPoint: Decodable, Hashable, Identifiable {
    let date: String
    let value: Double

    var id: String { date }
}

struct VolatilityResearchSource: Decodable, Hashable {
    let title: String
    let url: URL
}

struct VolatilityResearchService {
    var baseURL: URL = ServerConfiguration.currentURL
    var session: URLSession = .shared

    func fetch() async throws -> VolatilityResearchPayload {
        let url = baseURL.appending(path: "api/ios/v1/market/volatility-research")
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(VolatilityResearchResponse.self, from: data).data
    }
}

@MainActor
final class VolatilityResearchStore: ObservableObject {
    @Published private(set) var payload: VolatilityResearchPayload?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let fetch: () async throws -> VolatilityResearchPayload

    init(service: VolatilityResearchService = VolatilityResearchService()) {
        fetch = { try await service.fetch() }
    }

    init(fetch: @escaping () async throws -> VolatilityResearchPayload) {
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
            errorMessage = "波动率数据暂时无法载入"
        }
    }
}

@MainActor
struct VolatilityResearchSection: View {
    @StateObject private var store = VolatilityResearchStore()
    @Environment(\.rootTabIsActive) private var rootTabIsActive

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .lastTextBaseline) {
                Text("波动观察")
                    .font(.system(size: 18, weight: .bold))
                Spacer()
                Text("服务端采集 · 官方数据")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 2)

            if let payload = store.payload, !payload.items.isEmpty {
                volatilityCard(payload)
            } else if store.isLoading {
                loadingCard
            } else if store.errorMessage != nil {
                retryCard
            }
        }
        .task(id: rootTabIsActive) {
            guard rootTabIsActive else { return }
            await store.load()
        }
    }

    private func volatilityCard(_ payload: VolatilityResearchPayload) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(InvestmentDesign.accent)
                    .frame(width: 28, height: 28)
                    .background(InvestmentDesign.accentSoft, in: RoundedRectangle(cornerRadius: 8))
                Text(payload.summary)
                    .font(.system(size: 13, weight: .medium))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }

            HStack(alignment: .top, spacing: 10) {
                ForEach(payload.items) { item in
                    instrumentCard(item, lookbackDays: payload.lookbackDays)
                }
            }

            HStack {
                if payload.isStale {
                    Label("当前展示最近一次成功采集", systemImage: "clock.arrow.circlepath")
                } else {
                    Label("最近更新 \(formatDate(payload.items.map(\.asOf).max() ?? ""))", systemImage: "checkmark.circle")
                }
                Spacer()
                Text("收盘日线")
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(InvestmentDesign.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(InvestmentDesign.divider, lineWidth: 0.8)
        }
    }

    private func instrumentCard(_ item: VolatilityResearchInstrument, lookbackDays: Int) -> some View {
        let tint = item.market == "日本" ? Color.orange : InvestmentDesign.accent
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Text(item.market)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tint)
                Spacer(minLength: 2)
                Text(item.regime)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(tint.opacity(0.11), in: Capsule())
            }

            Text(item.shortName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(item.value, format: .number.precision(.fractionLength(1)))
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(item.dailyChangePercent / 100, format: .percent.precision(.fractionLength(1)))
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(item.dailyChangePercent >= 0 ? InvestmentDesign.loss : InvestmentDesign.gain)
                    .monospacedDigit()
            }

            Chart(item.history) { point in
                AreaMark(
                    x: .value("日期", point.date),
                    y: .value("波动率", point.value)
                )
                .foregroundStyle(
                    LinearGradient(colors: [tint.opacity(0.25), tint.opacity(0.01)], startPoint: .top, endPoint: .bottom)
                )
                LineMark(
                    x: .value("日期", point.date),
                    y: .value("波动率", point.value)
                )
                .foregroundStyle(tint)
                .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 46)

            VStack(alignment: .leading, spacing: 2) {
                Text("距\(lookbackDays)日峰值")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                Text(item.drawdownFromPeakPercent / 100, format: .percent.precision(.fractionLength(1)))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(item.drawdownFromPeakPercent < 0 ? InvestmentDesign.gain : .secondary)
                    .monospacedDigit()
            }

            Link(destination: item.source.url) {
                HStack(spacing: 3) {
                    Text(item.source.title)
                        .lineLimit(1)
                    Image(systemName: "arrow.up.right")
                }
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(InvestmentDesign.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(InvestmentDesign.divider, lineWidth: 0.6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.name)，\(item.value, specifier: "%.1f")，较\(lookbackDays)日峰值\(item.drawdownFromPeakPercent, specifier: "%.1f")%")
    }

    private var loadingCard: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("正在整理美日波动率")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 92)
        .background(InvestmentDesign.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(InvestmentDesign.divider, lineWidth: 0.8)
        }
    }

    private var retryCard: some View {
        Button {
            Task { await store.load(force: true) }
        } label: {
            HStack {
                Label("波动率数据暂不可用", systemImage: "wifi.exclamationmark")
                Spacer()
                Text("重试")
                    .foregroundStyle(InvestmentDesign.accent)
            }
            .font(.system(size: 13, weight: .medium))
            .padding(14)
            .background(InvestmentDesign.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(InvestmentDesign.divider, lineWidth: 0.8)
            }
        }
        .buttonStyle(.plain)
    }

    private func formatDate(_ value: String) -> String {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return value }
        return "\(parts[1])月\(parts[2])日"
    }
}
