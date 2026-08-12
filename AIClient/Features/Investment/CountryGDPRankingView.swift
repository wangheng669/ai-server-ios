import SwiftUI

enum GDPDesign {
    static let porcelain = InvestmentDesign.surface
}

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
        let url = baseURL.appending(path: "api/ios/v1/economy/gdp-ranking")
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
            url: baseURL.appending(path: "api/ios/v1/economy/gdp-ranking/country"),
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

struct GlobalAssetsRankingResponse: Decodable {
    let success: Bool
    let data: GlobalAssetsRanking
}

struct GlobalAssetsRanking: Decodable {
    let sourceName: String
    let sourceURL: URL
    let unit: String
    let fetchedAt: String
    let assets: [GlobalAsset]

    enum CodingKeys: String, CodingKey {
        case unit, assets
        case sourceName = "source_name"
        case sourceURL = "source_url"
        case fetchedAt = "fetched_at"
    }
}

struct GlobalAsset: Decodable, Identifiable {
    let rank: Int
    let symbol: String
    let name: String
    let marketCapUSD: Double
    let priceUSD: Double
    let change24HPercent: Double
    let change7DPercent: Double
    let iconURL: URL?

    var id: String { symbol }

    enum CodingKeys: String, CodingKey {
        case rank, symbol, name
        case marketCapUSD = "market_cap_usd"
        case priceUSD = "price_usd"
        case change24HPercent = "change_24h_percent"
        case change7DPercent = "change_7d_percent"
        case iconURL = "icon_url"
    }
}

struct GlobalAssetsService {
    let baseURL: URL
    let session: URLSession

    init(baseURL: URL = ServerConfiguration.currentURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func ranking() async throws -> GlobalAssetsRanking {
        let url = baseURL.appending(path: "api/ios/v1/economy/global-assets")
        var request = URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 10)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let payload = try JSONDecoder().decode(GlobalAssetsRankingResponse.self, from: data)
        guard payload.success, !payload.data.assets.isEmpty else {
            throw URLError(.cannotParseResponse)
        }
        return payload.data
    }
}

struct CountryGDPRankingView: View {
    @Binding var showsDetail: Bool
    @State private var category: GlobalRankingCategory
    @State private var ranking: CountryGDPRanking?
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var searchText = ""
    @State private var selectedCountry: CountryGDPRoute?

    init(showsDetail: Binding<Bool>) {
        _showsDetail = showsDetail
        #if DEBUG
        _category = State(
            initialValue: ProcessInfo.processInfo.arguments.contains("--global-assets-preview")
                ? .globalAssets
                : .countryGDP
        )
        #else
        _category = State(initialValue: .countryGDP)
        #endif
    }

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
        VStack(spacing: 0) {
            categoryPicker

            switch category {
            case .countryGDP:
                NavigationStack {
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
                            .background(InvestmentDesign.surface)
                            .scrollIndicators(.hidden)
                            .scrollDismissesKeyboard(.interactively)
                            .refreshable { await load() }
                        } else if isLoading {
                            loadingState
                        } else {
                            errorState
                        }
                    }
                    .background(InvestmentDesign.surface)
                    .toolbar(.hidden, for: .navigationBar)
                }
            case .globalAssets:
                GlobalAssetsRankingView()
            }
        }
        .background(InvestmentDesign.surface)
        .sheet(item: $selectedCountry) { route in
            CountryGDPDetailView(route: route)
                .presentationDetents([.fraction(0.72), .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
                .presentationBackground(GDPDesign.porcelain)
        }
        .task(id: category) {
            if category == .countryGDP, ranking == nil {
                await load()
            }
        }
        .onAppear { showsDetail = false }
        .onDisappear { showsDetail = false }
    }

    private var categoryPicker: some View {
        HStack(spacing: 28) {
            ForEach(GlobalRankingCategory.allCases) { item in
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { category = item }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: item.icon)
                            .font(.system(size: 12, weight: .semibold))
                        Text(item.rawValue)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(category == item ? InvestmentDesign.accent : Color.secondary)
                    .frame(height: 40)
                    .overlay(alignment: .bottom) {
                        Capsule()
                            .fill(category == item ? InvestmentDesign.accent : Color.clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(category == item ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, InvestmentDesign.pageInset)
        .background(InvestmentDesign.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(InvestmentDesign.divider).frame(height: 0.5)
        }
        .accessibilityIdentifier("global-ranking-category-picker")
    }

    private func rankingSection(_ ranking: CountryGDPRanking) -> some View {
        VStack(spacing: 0) {
            rankingHeader(ranking)
            searchField
                .padding(.horizontal, InvestmentDesign.pageInset)
                .padding(.bottom, 14)
            Divider().overlay(InvestmentDesign.divider)
            countries(ranking)
        }
    }

    @ViewBuilder
    private func countries(_ ranking: CountryGDPRanking) -> some View {
        if visibleCountries.isEmpty {
            ContentUnavailableView("没有匹配的国家", systemImage: "magnifyingglass")
                .frame(maxWidth: .infinity)
                .frame(height: 220)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(visibleCountries.enumerated()), id: \.element.id) { index, country in
                    Button {
                        selectedCountry = CountryGDPRoute(country: country)
                    } label: {
                        countryRow(country)
                    }
                    .buttonStyle(.plain)

                    if index < visibleCountries.count - 1 {
                        Divider()
                            .overlay(InvestmentDesign.divider)
                            .padding(.leading, 52)
                    }
                }
            }
        }
    }

    private func overview(_ ranking: CountryGDPRanking) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 9) {
                Image(systemName: "globe.asia.australia.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(InvestmentDesign.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("全球经济体")
                        .font(.system(size: 16, weight: .bold))
                    Text("按现价美元 GDP 排名")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(verbatim: "\(ranking.year)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            if let leader = ranking.countries.first {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("规模最大的经济体")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            Text(leader.flag).font(.system(size: 24))
                            Text(leader.localizedName)
                                .font(.system(size: 20, weight: .bold))
                        }
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(CountryGDPFormat.compact(leader.gdpCurrentUSD))
                            .font(.system(size: 21, weight: .bold, design: .rounded))
                            .minimumScaleFactor(0.68)
                            .lineLimit(1)
                        if let growth = leader.gdpGrowthPercent {
                            Text("同比 \(growth >= 0 ? "+" : "")\(growth, specifier: "%.1f")%")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(growth >= 0 ? InvestmentDesign.gain : InvestmentDesign.loss)
                        }
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

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索国家或地区", text: $searchText)
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
        .font(.subheadline)
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(InvestmentDesign.secondarySurface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func rankingHeader(_ ranking: CountryGDPRanking) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("国家与地区")
                .font(.headline)
            Spacer()
            Text(searchText.isEmpty ? "\(ranking.countries.count) 个经济体" : "\(visibleCountries.count) 个结果")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, InvestmentDesign.pageInset)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    private func countryRow(_ country: CountryGDP) -> some View {
        HStack(spacing: 10) {
            rankBadge(country.rank)

            Text(country.flag)
                .font(.system(size: 22))
                .frame(width: 30)

            Text(country.localizedName)
                .font(.body.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 2) {
                Text(CountryGDPFormat.ranking(country.gdpCurrentUSD))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)
                changeSummary(country)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal, InvestmentDesign.pageInset)
        .frame(minHeight: 58)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(country))
    }

    private func rankBadge(_ rank: Int) -> some View {
        Text("\(rank)")
            .font(.system(size: 13, weight: rank <= 3 ? .bold : .regular, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(rank <= 3 ? InvestmentDesign.accent : Color.secondary)
            .frame(width: 26)
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
        .font(.caption2.weight(.semibold))
        .monospacedDigit()
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
        .padding(.horizontal, InvestmentDesign.pageInset)
        .padding(.top, 18)
        .overlay(alignment: .top) {
            Divider().overlay(InvestmentDesign.divider)
        }
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

enum GlobalRankingCategory: String, CaseIterable, Identifiable {
    case countryGDP = "国家 GDP"
    case globalAssets = "全球资产"

    var id: Self { self }

    var icon: String {
        switch self {
        case .countryGDP: "globe.asia.australia.fill"
        case .globalAssets: "chart.bar.fill"
        }
    }
}

enum CountryGDPFormat {
    static func ranking(_ value: Double) -> String {
        if value >= 1_000_000_000_000 {
            return String(format: "%.2f 万亿", value / 1_000_000_000_000)
        }
        if value >= 100_000_000 {
            return String(format: "%.0f 亿", value / 100_000_000)
        }
        return value.formatted(.number.notation(.compactName))
    }

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
