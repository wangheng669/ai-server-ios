import SwiftUI

struct GlobalAssetsRankingView: View {
    @State private var ranking: GlobalAssetsRanking?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let ranking {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        overview(ranking)
                        HStack {
                            Text("资产市值排名").font(.headline)
                            Spacer()
                            Text("\(ranking.assets.count) 项资产")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, InvestmentDesign.pageInset)
                        .padding(.top, 18)
                        .padding(.bottom, 10)

                        ForEach(Array(ranking.assets.enumerated()), id: \.element.id) { index, asset in
                            assetRow(asset)
                            if index < ranking.assets.count - 1 {
                                Divider()
                                    .overlay(InvestmentDesign.divider)
                                    .padding(.leading, 62)
                            }
                        }

                        Link(destination: ranking.sourceURL) {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "externaldrive.connected.to.line.below")
                                    .foregroundStyle(InvestmentDesign.accent)
                                Text("数据由服务器定时采集自 \(ranking.sourceName) 并存入数据库；当前页面仅读取服务器接口。")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, InvestmentDesign.pageInset)
                        .padding(.vertical, 22)
                    }
                }
                .scrollIndicators(.hidden)
                .refreshable { await load() }
            } else if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("正在读取全球资产排名")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 320)
            } else {
                ContentUnavailableView {
                    Label("全球资产排名暂不可用", systemImage: "chart.bar.xaxis")
                } description: {
                    Text("服务器数据库尚未返回可用数据")
                } actions: {
                    Button("重新加载") { Task { await load() } }
                        .buttonStyle(.borderedProminent)
                }
                .frame(minHeight: 320)
            }
        }
        .background(GDPDesign.porcelain)
        .task {
            if ranking == nil { await load() }
        }
    }

    private func overview(_ ranking: GlobalAssetsRanking) -> some View {
        ZStack(alignment: .trailing) {
            LinearGradient(
                colors: [GDPDesign.midnight, GDPDesign.midnightLight],
                startPoint: .leading,
                endPoint: .trailing
            )
            Image(systemName: "chart.pie.fill")
                .font(.system(size: 126, weight: .thin))
                .foregroundStyle(.white.opacity(0.045))
                .offset(x: 28, y: 20)
            VStack(alignment: .leading, spacing: 10) {
                if let leader = ranking.assets.first {
                    Text("市值最高")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                    HStack(spacing: 10) {
                        assetIcon(leader, size: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(leader.name).font(.title3.weight(.semibold))
                            Text(leader.symbol)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.65))
                        }
                        Spacer()
                        Text(GlobalAssetsFormat.marketCap(leader.marketCapUSD))
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, InvestmentDesign.pageInset)
            .padding(.top, 20)
            .padding(.bottom, 22)
        }
    }

    private func assetRow(_ asset: GlobalAsset) -> some View {
        HStack(spacing: 10) {
            Text("\(asset.rank)")
                .font(.caption.monospacedDigit().weight(asset.rank <= 3 ? .semibold : .regular))
                .foregroundStyle(asset.rank <= 3 ? .primary : .secondary)
                .frame(width: 25)
            assetIcon(asset, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(asset.name).font(.body.weight(.semibold)).lineLimit(1)
                Text(asset.symbol).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(GlobalAssetsFormat.marketCap(asset.marketCapUSD))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                HStack(spacing: 6) {
                    change(asset.change24HPercent, label: "24h")
                    change(asset.change7DPercent, label: "7d")
                }
            }
        }
        .padding(.horizontal, InvestmentDesign.pageInset)
        .frame(minHeight: 62)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("第 \(asset.rank) 名，\(asset.name)，市值 \(GlobalAssetsFormat.marketCap(asset.marketCapUSD))")
    }

    private func assetIcon(_ asset: GlobalAsset, size: CGFloat) -> some View {
        AsyncImage(url: asset.iconURL) { phase in
            if case let .success(image) = phase {
                image.resizable().scaledToFit()
            } else {
                ZStack {
                    Circle().fill(GDPDesign.search)
                    Text(String(asset.symbol.prefix(1)))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private func change(_ value: Double, label: String) -> some View {
        Text("\(label) \(value >= 0 ? "+" : "")\(value, specifier: "%.2f")%")
            .font(.caption2.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(value >= 0 ? InvestmentDesign.gain : InvestmentDesign.loss)
    }

    @MainActor
    private func load() async {
        if ranking == nil { isLoading = true }
        defer { isLoading = false }
        do {
            ranking = try await GlobalAssetsService().ranking()
        } catch {
            // Preserve the last valid database snapshot during transient failures.
        }
    }
}

enum GlobalAssetsFormat {
    static func marketCap(_ value: Double) -> String {
        if value >= 1_000_000_000_000 {
            return String(format: "$%.2f 万亿", value / 1_000_000_000_000)
        }
        if value >= 100_000_000 {
            return String(format: "$%.0f 亿", value / 100_000_000)
        }
        return value.formatted(.currency(code: "USD").precision(.fractionLength(0...2)))
    }
}
