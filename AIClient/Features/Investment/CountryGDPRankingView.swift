import SwiftUI

struct CountryGDPRankingResponse: Decodable {
    let success: Bool
    let data: CountryGDPRanking
}

struct CountryGDPRanking: Decodable {
    let year: Int
    let previousYear: Int?
    let metric: String
    let unit: String
    let sourceName: String
    let sourceURL: URL
    let updatedAt: String
    let countries: [CountryGDP]

    enum CodingKeys: String, CodingKey {
        case year, metric, unit, countries
        case previousYear = "previous_year"
        case sourceName = "source_name"
        case sourceURL = "source_url"
        case updatedAt = "updated_at"
    }
}

struct CountryGDP: Decodable, Identifiable {
    let rank: Int
    let previousRank: Int?
    let rankChange: Int?
    let countryCode: String
    let iso2Code: String
    let countryName: String
    let gdpCurrentUSD: Double
    let previousGDPCurrentUSD: Double?
    let gdpGrowthPercent: Double?

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
        case previousRank = "previous_rank"
        case rankChange = "rank_change"
        case countryCode = "country_code"
        case iso2Code = "iso2_code"
        case countryName = "country_name"
        case gdpCurrentUSD = "gdp_current_usd"
        case previousGDPCurrentUSD = "previous_gdp_current_usd"
        case gdpGrowthPercent = "gdp_growth_percent"
    }
}

struct CountryGDPService {
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

    func history(countryCode: String) async throws -> CountryGDPHistory {
        var components = URLComponents(
            url: baseURL.appending(path: "api/v1/economy/gdp-ranking/country"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "code", value: countryCode)]
        guard let url = components?.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 10)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let payload = try JSONDecoder().decode(CountryGDPHistoryResponse.self, from: data)
        guard payload.success, !payload.data.points.isEmpty else {
            throw URLError(.cannotParseResponse)
        }
        return payload.data
    }
}

struct CountryGDPRankingView: View {
    @Binding var showsDetail: Bool
    @State private var ranking: CountryGDPRanking?
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var searchText = ""
    @State private var selectedCountry: CountryGDPRoute?

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
        NavigationStack {
            Group {
                if let ranking {
                    List {
                        Section {
                        overview(ranking)
                        }

                        Section {
                            if visibleCountries.isEmpty {
                                ContentUnavailableView("没有匹配的国家", systemImage: "magnifyingglass")
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 180)
                                    .listRowBackground(Color.clear)
                            } else {
                                ForEach(visibleCountries) { country in
                                    Button {
                                        selectedCountry = CountryGDPRoute(country: country)
                                    } label: {
                                        HStack(spacing: 8) {
                                            countryRow(country)
                                            Image(systemName: "chevron.right")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        } header: {
                            HStack {
                                Text("国家排名")
                                Spacer()
                                Text(searchText.isEmpty ? "\(ranking.countries.count) 个经济体" : "\(visibleCountries.count) 个结果")
                                    .textCase(nil)
                            }
                        }

                        Section {
                            sourceFooter(ranking)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .searchable(text: $searchText, placement: .automatic, prompt: "国家或三位代码")
                    .scrollDismissesKeyboard(.interactively)
                } else if isLoading {
                    loadingState
                } else {
                    errorState
                }
            }
            .background(InvestmentDesign.canvas)
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(item: $selectedCountry) { route in
            CountryGDPDetailView(route: route)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(24)
                .presentationBackground(InvestmentDesign.canvas)
        }
        .task { await load() }
        .refreshable { await load() }
        .onAppear { showsDetail = false }
        .onDisappear { showsDetail = false }
    }

    private func overview(_ ranking: CountryGDPRanking) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: "globe.asia.australia.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(InvestmentDesign.accent)
                    .frame(width: 52, height: 52)
                    .background(InvestmentDesign.accentSoft, in: RoundedRectangle(cornerRadius: 13))

                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: "\(ranking.year) 全球 GDP")
                        .font(.title3.bold())
                    Text("名义值 · 现价美元")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            if let leader = ranking.countries.first {
                LabeledContent {
                    Text(CountryGDPFormat.compact(leader.gdpCurrentUSD))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                } label: {
                    Label("最大经济体 \(leader.flag) \(leader.localizedName)", systemImage: "chart.bar.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func countryRow(_ country: CountryGDP) -> some View {
        HStack(spacing: 10) {
            Text("\(country.rank)")
                .font(.system(size: 13, weight: country.rank <= 3 ? .bold : .regular, design: .rounded))
                .foregroundStyle(country.rank <= 3 ? InvestmentDesign.accent : .secondary)
                .frame(width: 24)

            Text(country.flag)
                .font(.system(size: 25))
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(country.localizedName)
                    .font(.body.weight(.medium))
                Text(country.countryCode)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(CountryGDPFormat.compact(country.gdpCurrentUSD))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)
                changeSummary(country)
            }
        }
        .frame(minHeight: 48)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(country))
    }

    @ViewBuilder
    private func changeSummary(_ country: CountryGDP) -> some View {
        HStack(spacing: 4) {
            if let change = country.rankChange {
                if change != 0 {
                    Text("\(change > 0 ? "↑" : "↓")\(abs(change))")
                        .foregroundStyle(change > 0 ? InvestmentDesign.gain : InvestmentDesign.loss)
                }
            }
            if let growth = country.gdpGrowthPercent {
                Text("\(growth >= 0 ? "+" : "")\(growth, specifier: "%.1f")%")
                    .foregroundStyle(growth >= 0 ? InvestmentDesign.gain : InvestmentDesign.loss)
            }
        }
        .font(.caption2.weight(.medium))
    }

    private func accessibilityLabel(_ country: CountryGDP) -> String {
        var text = "第 \(country.rank) 名，\(country.localizedName)，\(CountryGDPFormat.accessible(country.gdpCurrentUSD))"
        if let growth = country.gdpGrowthPercent {
            text += "，同比\(growth >= 0 ? "增长" : "下降")\(abs(growth).formatted(.number.precision(.fractionLength(1))))%"
        }
        return text
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
            #if DEBUG
            if selectedCountry == nil,
               let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--gdp-detail-preview=") }),
               let country = ranking?.countries.first(where: {
                   $0.countryCode == String(argument.dropFirst("--gdp-detail-preview=".count)).uppercased()
               }) {
                selectedCountry = CountryGDPRoute(country: country)
            }
            #endif
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
