import SwiftUI

struct CountryGDPRankingResponse: Decodable {
    let success: Bool
    let data: CountryGDPRanking
}

struct CountryGDPRanking: Decodable {
    let year: Int
    let metric: String
    let unit: String
    let sourceName: String
    let sourceURL: URL
    let updatedAt: String
    let countries: [CountryGDP]

    enum CodingKeys: String, CodingKey {
        case year, metric, unit, countries
        case sourceName = "source_name"
        case sourceURL = "source_url"
        case updatedAt = "updated_at"
    }
}

struct CountryGDP: Decodable, Identifiable {
    let rank: Int
    let countryCode: String
    let iso2Code: String
    let countryName: String
    let gdpCurrentUSD: Double

    var id: String { "\(countryCode)-\(rank)" }

    var localizedName: String {
        if iso2Code == "CN" { return "中国" }
        return Locale(identifier: "zh-Hans_CN").localizedString(forRegionCode: iso2Code) ?? countryName
    }

    var flag: String {
        iso2Code.uppercased().unicodeScalars.compactMap { scalar in
            UnicodeScalar(127397 + scalar.value).map(String.init)
        }.joined()
    }

    enum CodingKeys: String, CodingKey {
        case rank
        case countryCode = "country_code"
        case iso2Code = "iso2_code"
        case countryName = "country_name"
        case gdpCurrentUSD = "gdp_current_usd"
    }
}

private struct CountryGDPService {
    let baseURL: URL
    let session: URLSession

    init(baseURL: URL = ServerConfiguration.currentURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func ranking() async throws -> CountryGDPRanking {
        let url = baseURL.appending(path: "api/v1/economy/gdp-ranking")
        var request = URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 10)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let payload = try JSONDecoder().decode(CountryGDPRankingResponse.self, from: data)
        guard payload.success, !payload.data.countries.isEmpty else {
            throw URLError(.cannotParseResponse)
        }
        return payload.data
    }
}

struct CountryGDPRankingView: View {
    @State private var ranking: CountryGDPRanking?
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var searchText = ""

    private var visibleCountries: [CountryGDP] {
        guard let countries = ranking?.countries else { return [] }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return countries }
        return countries.filter {
            $0.localizedName.localizedCaseInsensitiveContains(query) ||
            $0.countryName.localizedCaseInsensitiveContains(query) ||
            $0.countryCode.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if let ranking {
                    overview(ranking)
                    searchField
                    rankingList(ranking)
                    sourceFooter(ranking)
                } else if isLoading {
                    loadingState
                } else {
                    errorState
                }
            }
            .padding(.horizontal, InvestmentDesign.pageInset)
            .padding(.top, 14)
            .padding(.bottom, 112)
        }
        .scrollIndicators(.hidden)
        .background(InvestmentDesign.canvas)
        .task { await load() }
        .refreshable { await load() }
    }

    private func overview(_ ranking: CountryGDPRanking) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("全球经济体量")
                        .font(.system(size: 23, weight: .bold))
                    Text("\(ranking.year) 年 · 名义 GDP · 现价美元")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "globe.americas.fill")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(InvestmentDesign.accent)
                    .padding(10)
                    .background(InvestmentDesign.accentSoft, in: Circle())
            }

            HStack(spacing: 8) {
                ForEach(Array(ranking.countries.prefix(3))) { country in
                    VStack(alignment: .leading, spacing: 5) {
                        Text("#\(country.rank)  \(country.flag)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(country.localizedName)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                        Text(CountryGDPFormat.compact(country.gdpCurrentUSD))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(InvestmentDesign.accent)
                            .minimumScaleFactor(0.78)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(11)
                    .background(InvestmentDesign.secondarySurface, in: RoundedRectangle(cornerRadius: 11))
                }
            }
        }
        .padding(16)
        .background(InvestmentDesign.surface, in: RoundedRectangle(cornerRadius: InvestmentDesign.cornerRadius))
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索国家或代码", text: $searchText)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.system(size: 14))
        .padding(.horizontal, 13)
        .frame(height: 42)
        .background(InvestmentDesign.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private func rankingList(_ ranking: CountryGDPRanking) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("国家排名")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Text(searchText.isEmpty ? "\(ranking.countries.count) 个国家和经济体" : "\(visibleCountries.count) 个结果")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 14)

            Divider().padding(.leading, 15)

            if visibleCountries.isEmpty {
                ContentUnavailableView("没有匹配的国家", systemImage: "magnifyingglass")
                    .frame(height: 180)
            } else {
                ForEach(visibleCountries) { country in
                    countryRow(country, leaderGDP: ranking.countries.first?.gdpCurrentUSD ?? 1)
                    if country.id != visibleCountries.last?.id {
                        Divider().padding(.leading, 63)
                    }
                }
            }
        }
        .background(InvestmentDesign.surface, in: RoundedRectangle(cornerRadius: InvestmentDesign.cornerRadius))
    }

    private func countryRow(_ country: CountryGDP, leaderGDP: Double) -> some View {
        HStack(spacing: 11) {
            Text("\(country.rank)")
                .font(.system(size: 13, weight: country.rank <= 3 ? .bold : .semibold, design: .rounded))
                .foregroundStyle(country.rank <= 3 ? InvestmentDesign.accent : Color.secondary)
                .frame(width: 28)

            Text(country.flag)
                .font(.system(size: 25))
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(country.localizedName)
                            .font(.system(size: 15, weight: .semibold))
                        Text("\(country.countryName) · \(country.countryCode)")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text(CountryGDPFormat.compact(country.gdpCurrentUSD))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.8)
                        .lineLimit(1)
                }
                GeometryReader { geometry in
                    Capsule()
                        .fill(InvestmentDesign.accent.opacity(country.rank <= 3 ? 0.82 : 0.38))
                        .frame(width: max(4, geometry.size.width * country.gdpCurrentUSD / max(leaderGDP, 1)), height: 3)
                }
                .frame(height: 3)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("第 \(country.rank) 名，\(country.localizedName)，\(CountryGDPFormat.accessible(country.gdpCurrentUSD))")
    }

    private func sourceFooter(_ ranking: CountryGDPRanking) -> some View {
        Link(destination: ranking.sourceURL) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(InvestmentDesign.accent)
                Text("数据来自世界银行 \(ranking.metric)，按数据库中的 \(ranking.year) 年现价美元值排序。点击查看原始口径。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(13)
            .background(InvestmentDesign.surface, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("正在读取 GDP 排名")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 320)
    }

    private var errorState: some View {
        ContentUnavailableView {
            Label("GDP 排名暂不可用", systemImage: "chart.bar.xaxis")
        } description: {
            Text("服务器未返回可用的排名数据")
        } actions: {
            Button("重新加载") {
                Task { await load() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(minHeight: 320)
    }

    @MainActor
    private func load() async {
        if ranking == nil { isLoading = true }
        loadFailed = false
        defer { isLoading = false }
        do {
            ranking = try await CountryGDPService().ranking()
        } catch {
            if ranking == nil { loadFailed = true }
        }
    }
}

enum CountryGDPFormat {
    static func compact(_ value: Double) -> String {
        if value >= 1_000_000_000_000 {
            return String(format: "%.2f 万亿美元", value / 1_000_000_000_000)
        }
        if value >= 100_000_000 {
            return String(format: "%.0f 亿美元", value / 100_000_000)
        }
        return value.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }

    static func accessible(_ value: Double) -> String {
        compact(value)
    }
}
