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
    @State private var path: [CountryGDPRoute] = []

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
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
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
                .padding(.top, 16)
                .padding(.bottom, 112)
            }
            .scrollIndicators(.hidden)
            .background(InvestmentDesign.canvas)
            .navigationDestination(for: CountryGDPRoute.self) { route in
                CountryGDPDetailView(route: route)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .task { await load() }
        .refreshable { await load() }
        .onChange(of: path) { _, value in showsDetail = !value.isEmpty }
        .onAppear { showsDetail = !path.isEmpty }
        .onDisappear { showsDetail = false }
    }

    private func overview(_ ranking: CountryGDPRanking) -> some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.24, blue: 0.60),
                    Color(red: 0.10, green: 0.40, blue: 0.96)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .stroke(Color.white.opacity(0.10), lineWidth: 22)
                .frame(width: 150, height: 150)
                .offset(x: 48, y: -56)

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("全球经济体量")
                            .font(.system(size: 25, weight: .bold))
                        HStack(spacing: 6) {
                            Text("\(ranking.year)")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.16), in: Capsule())
                            Text("名义 GDP · 现价美元")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.72))
                        }
                    }
                    Spacer()
                    Image(systemName: "globe.asia.australia.fill")
                        .font(.system(size: 27, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.88))
                        .padding(9)
                        .background(Color.white.opacity(0.12), in: Circle())
                }

                HStack(spacing: 8) {
                    ForEach(Array(ranking.countries.prefix(3))) { country in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(country.flag)
                                    .font(.system(size: 20))
                                Spacer()
                                Text("#\(country.rank)")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color.white.opacity(0.70))
                            }
                            Text(country.localizedName)
                                .font(.system(size: 14, weight: .semibold))
                                .lineLimit(1)
                            Text(CountryGDPFormat.compact(country.gdpCurrentUSD))
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .minimumScaleFactor(0.72)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(11)
                        .background(Color.white.opacity(country.rank == 1 ? 0.20 : 0.12), in: RoundedRectangle(cornerRadius: 13))
                        .overlay {
                            RoundedRectangle(cornerRadius: 13)
                                .stroke(Color.white.opacity(country.rank == 1 ? 0.24 : 0.10), lineWidth: 0.7)
                        }
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(18)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: InvestmentDesign.accent.opacity(0.16), radius: 14, y: 7)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(InvestmentDesign.accent)
            TextField("搜索国家或三位代码", text: $searchText)
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
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(InvestmentDesign.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(InvestmentDesign.divider, lineWidth: 0.6)
        }
        .shadow(color: Color.black.opacity(0.035), radius: 8, y: 3)
    }

    private func rankingList(_ ranking: CountryGDPRanking) -> some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("国家排名")
                        .font(.system(size: 17, weight: .bold))
                    Text("点击国家查看历年走势")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(searchText.isEmpty ? "\(ranking.countries.count) 个国家和经济体" : "\(visibleCountries.count) 个结果")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 14)

            Divider().padding(.horizontal, 15)

            if visibleCountries.isEmpty {
                ContentUnavailableView("没有匹配的国家", systemImage: "magnifyingglass")
                    .frame(height: 180)
            } else {
                ForEach(visibleCountries) { country in
                    NavigationLink(value: CountryGDPRoute(country: country)) {
                        countryRow(country, leaderGDP: ranking.countries.first?.gdpCurrentUSD ?? 1)
                    }
                    .buttonStyle(.plain)
                    if country.id != visibleCountries.last?.id {
                        Divider().padding(.leading, 73)
                    }
                }
            }
        }
        .background(InvestmentDesign.surface, in: RoundedRectangle(cornerRadius: InvestmentDesign.cornerRadius))
    }

    private func countryRow(_ country: CountryGDP, leaderGDP: Double) -> some View {
        HStack(spacing: 10) {
            Text("\(country.rank)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(country.rank <= 3 ? Color.white : Color.secondary)
                .frame(width: 28, height: 28)
                .background(
                    country.rank <= 3 ? InvestmentDesign.accent : InvestmentDesign.secondarySurface,
                    in: RoundedRectangle(cornerRadius: 9)
                )

            Text(country.flag)
                .font(.system(size: 24))
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(country.localizedName)
                            .font(.system(size: 15, weight: .semibold))
                        Text("\(country.countryName) · \(country.countryCode)")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 5) {
                        Text(CountryGDPFormat.compact(country.gdpCurrentUSD))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .minimumScaleFactor(0.72)
                            .lineLimit(1)
                        changeSummary(country)
                    }
                }
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(InvestmentDesign.accentSoft)
                        Capsule()
                            .fill(InvestmentDesign.accent.opacity(country.rank <= 3 ? 0.88 : 0.48))
                            .frame(width: max(5, geometry.size.width * country.gdpCurrentUSD / max(leaderGDP, 1)))
                    }
                }
                .frame(height: 4)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(country))
    }

    @ViewBuilder
    private func changeSummary(_ country: CountryGDP) -> some View {
        HStack(spacing: 5) {
            if let change = country.rankChange {
                if change == 0 {
                    Text("持平").foregroundStyle(.secondary)
                } else {
                    Label("\(abs(change))", systemImage: change > 0 ? "arrow.up" : "arrow.down")
                        .foregroundStyle(change > 0 ? InvestmentDesign.gain : InvestmentDesign.loss)
                }
            }
            if let growth = country.gdpGrowthPercent {
                Text("\(growth >= 0 ? "+" : "")\(growth, specifier: "%.1f")%")
                    .foregroundStyle(growth >= 0 ? InvestmentDesign.gain : InvestmentDesign.loss)
            }
        }
        .font(.system(size: 10, weight: .semibold, design: .rounded))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(InvestmentDesign.secondarySurface, in: Capsule())
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
            #if DEBUG
            if path.isEmpty,
               let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--gdp-detail-preview=") }),
               let country = ranking?.countries.first(where: {
                   $0.countryCode == String(argument.dropFirst("--gdp-detail-preview=".count)).uppercased()
               }) {
                path.append(CountryGDPRoute(country: country))
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
