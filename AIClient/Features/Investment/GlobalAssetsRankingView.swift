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
                        rankingSection(ranking)
                        sourceFooter(ranking)
                    }
                    .padding(.bottom, 28)
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
        .background(InvestmentDesign.surface)
        .task {
            if ranking == nil { await load() }
        }
    }

    private func overview(_ ranking: GlobalAssetsRanking) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 9) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(InvestmentDesign.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("全球资产")
                        .font(.system(size: 16, weight: .bold))
                        .lineLimit(1)
                    Text("按实时总市值排名")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .layoutPriority(1)
                Spacer()
                Text("\(ranking.assets.count) 项")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            if let leader = ranking.assets.first {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("当前市值最高")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            assetIcon(leader, size: 28)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(leader.name)
                                    .font(.system(size: 20, weight: .bold))
                                    .lineLimit(1)
                                Text(leader.symbol).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .layoutPriority(1)
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(GlobalAssetsFormat.marketCap(leader.marketCapUSD))
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .minimumScaleFactor(0.62)
                            .lineLimit(1)
                        change(leader.change24HPercent, label: "24h")
                    }
                }
            }
        }
        .padding(.horizontal, InvestmentDesign.pageInset)
        .padding(.top, 20)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Divider().overlay(InvestmentDesign.divider)
        }
    }

    private func rankingSection(_ ranking: GlobalAssetsRanking) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("资产市值排名").font(.headline)
                Spacer()
                Text("24h / 7d 涨跌")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, InvestmentDesign.pageInset)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider().overlay(InvestmentDesign.divider)

            ForEach(Array(ranking.assets.enumerated()), id: \.element.id) { index, asset in
                assetRow(asset)
                if index < ranking.assets.count - 1 {
                    Divider()
                        .overlay(InvestmentDesign.divider)
                        .padding(.leading, 52)
                }
            }
        }
    }

    private func sourceFooter(_ ranking: GlobalAssetsRanking) -> some View {
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
        .padding(.top, 18)
        .overlay(alignment: .top) {
            Divider().overlay(InvestmentDesign.divider)
        }
    }

    private func assetRow(_ asset: GlobalAsset) -> some View {
        HStack(spacing: 10) {
            rankBadge(asset.rank)
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
                    .minimumScaleFactor(0.72)
                    .lineLimit(1)
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

    private func rankBadge(_ rank: Int) -> some View {
        Text("\(rank)")
            .font(.system(size: 13, weight: rank <= 3 ? .bold : .regular, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(rank <= 3 ? InvestmentDesign.accent : Color.secondary)
            .frame(width: 26)
    }

    private func assetIcon(_ asset: GlobalAsset, size: CGFloat) -> some View {
        AsyncImage(url: asset.iconURL.flatMap { MediaURL.image($0.absoluteString) ?? $0 }) { phase in
            if case let .success(image) = phase {
                image.resizable().scaledToFit()
            } else {
                ZStack {
                    Circle().fill(InvestmentDesign.secondarySurface)
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
