import SwiftUI
import Observation

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
    let gdpPerCapitaUSD: Double?
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
        case gdpPerCapitaUSD = "gdp_per_capita_usd"
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

    func ranking(onCached: @escaping @MainActor (CountryGDPRanking) -> Void) async throws -> CountryGDPRanking {
        let url = baseURL.appending(path: "api/ios/v1/economy/gdp-ranking")
        var request = URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 10)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await loadDisplayPage(request: request, session: session, onCached: onCached) { data in
            let payload = try JSONDecoder().decode(CountryGDPRankingResponse.self, from: data)
            guard payload.success, !payload.data.countries.isEmpty else {
                throw URLError(.cannotParseResponse)
            }
            return payload.data
        }
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
    let iconURL: String

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

    func ranking(onCached: @escaping @MainActor (GlobalAssetsRanking) -> Void) async throws -> GlobalAssetsRanking {
        let url = baseURL.appending(path: "api/ios/v1/economy/global-assets")
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        return try await loadDisplayPage(request: request, session: session, onCached: onCached) { data in
            let payload = try JSONDecoder().decode(GlobalAssetsRankingResponse.self, from: data)
            guard payload.success, !payload.data.assets.isEmpty else {
                throw URLError(.cannotParseResponse)
            }
            return payload.data
        }
    }
}

@MainActor
@Observable
final class GlobalRankingStore {
    private(set) var countryGDP: CountryGDPRanking?
    private(set) var globalAssets: GlobalAssetsRanking?
    private(set) var isLoadingCountryGDP = false
    private(set) var isLoadingGlobalAssets = false
    private(set) var countryGDPLoadFailed = false
    private(set) var globalAssetsLoadFailed = false
    private var globalAssetsLoadedAt: Date?

    private let countryGDPService: CountryGDPService
    private let globalAssetsService: GlobalAssetsService

    init(baseURL: URL = ServerConfiguration.currentURL, session: URLSession = .shared) {
        countryGDPService = CountryGDPService(baseURL: baseURL, session: session)
        globalAssetsService = GlobalAssetsService(baseURL: baseURL, session: session)
    }

    func loadCountryGDP() async {
        guard !isLoadingCountryGDP else { return }
        isLoadingCountryGDP = true
        countryGDPLoadFailed = false
        defer { isLoadingCountryGDP = false }
        do {
            countryGDP = try await countryGDPService.ranking { cached in
                if self.countryGDP == nil { self.countryGDP = cached }
            }
        } catch is CancellationError {
            return
        } catch {
            if countryGDP == nil { countryGDPLoadFailed = true }
        }
    }

    func loadGlobalAssets(force: Bool = false) async {
        guard !isLoadingGlobalAssets else { return }
        if !force, let globalAssetsLoadedAt, Date().timeIntervalSince(globalAssetsLoadedAt) < 60 { return }
        isLoadingGlobalAssets = true
        globalAssetsLoadFailed = false
        defer { isLoadingGlobalAssets = false }
        do {
            globalAssets = try await globalAssetsService.ranking { cached in
                if self.globalAssets == nil { self.globalAssets = cached }
            }
            globalAssetsLoadedAt = Date()
        } catch is CancellationError {
            return
        } catch {
            globalAssetsLoadFailed = true
        }
    }
}

struct CountryGDPRankingView: View {
    @Environment(\.rootTabIsActive) private var rootTabIsActive
    let store: GlobalRankingStore
    let onClose: () -> Void
    @State private var category: GlobalRankingCategory
    @State private var selectedCountry: CountryGDPRoute?

    init(store: GlobalRankingStore, initialCategory: GlobalRankingCategory, onClose: @escaping () -> Void) {
        self.store = store
        self.onClose = onClose
        #if DEBUG
        _category = State(
            initialValue: ProcessInfo.processInfo.arguments.contains("--global-assets-preview")
                ? .globalAssets
                : initialCategory
        )
        #else
        _category = State(initialValue: initialCategory)
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            categoryPicker
                .padding(.top, 12)

            switch category {
            case .countryGDP:
                Group {
                    if let ranking = store.countryGDP {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                overview(ranking)
                                rankingSection(ranking)
                                sourceFooter(ranking)
                            }
                            .padding(.bottom, 64)
                        }
                        .background(InvestmentDesign.surface)
                        .scrollIndicators(.hidden)
                    } else if store.isLoadingCountryGDP || !store.countryGDPLoadFailed {
                        loadingState
                    } else {
                        errorState
                    }
                }
                .background(InvestmentDesign.surface)
            case .globalAssets:
                GlobalAssetsRankingView(store: store)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(InvestmentDesign.surface)
        .floatingSheetClose("关闭资产排行", action: onClose)
        .accessibilityAction(.escape) { onClose() }
        .appSheet(item: $selectedCountry) { route in
            CountryGDPDetailView(route: route)
                .appPresentationDetents([.large])
                .appPresentationCornerRadius(28)
                .appPresentationBackground(InvestmentDesign.surface)
        }
        .task(id: "\(rootTabIsActive):\(category.rawValue)") {
            if rootTabIsActive, category == .countryGDP, store.countryGDP == nil {
                await store.loadCountryGDP()
            }
            #if DEBUG
            if rootTabIsActive,
               selectedCountry == nil,
               let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--gdp-detail-preview=") }),
               let country = store.countryGDP?.countries.first(where: {
                   $0.countryCode == String(argument.dropFirst("--gdp-detail-preview=".count)).uppercased()
               }) {
                selectedCountry = CountryGDPRoute(country: country)
            }
            #endif
        }
    }

    private var categoryPicker: some View {
        HStack(spacing: 4) {
            ForEach(GlobalRankingCategory.allCases) { item in
                let selected = category == item
                Button {
                    category = item
                } label: {
                    Label(item.rawValue, systemImage: item.icon)
                        .font(.subheadline.weight(selected ? .semibold : .medium))
                        .foregroundStyle(selected ? ResearchDesign.accent : .secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(selected ? ResearchDesign.selection : .clear, in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(ResearchDesign.fill, in: RoundedRectangle(cornerRadius: 11))
        .padding(.horizontal, ResearchDesign.inset)
        .padding(.bottom, 6)
        .accessibilityIdentifier("global-ranking-category-picker")
    }

    private func rankingSection(_ ranking: CountryGDPRanking) -> some View {
        VStack(spacing: 0) {
            rankingHeader(ranking)
            Divider().overlay(InvestmentDesign.divider)
            countries(ranking)
        }
    }

    @ViewBuilder
    private func countries(_ ranking: CountryGDPRanking) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(ranking.countries.enumerated()), id: \.element.id) { index, country in
                Button {
                    selectedCountry = CountryGDPRoute(country: country)
                } label: {
                    countryRow(country)
                }
                .buttonStyle(.plain)

                if index < ranking.countries.count - 1 {
                    Divider()
                        .overlay(InvestmentDesign.divider)
                        .padding(.leading, 58)
                }
            }
        }
    }

    private func overview(_ ranking: CountryGDPRanking) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Text("按现价美元 GDP 排名")
                    .font(.subheadline.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text(verbatim: "\(ranking.year)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if let leader = ranking.countries.first {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("规模最大的经济体")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            FlatCountryFlag(iso2Code: leader.iso2Code, width: 34, height: 23)
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
                        if let perCapita = leader.gdpPerCapitaUSD {
                            Text("人均 \(CountryGDPFormat.perCapita(perCapita))")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .researchPanel(fill: ResearchDesign.fill)
        .padding(.horizontal, ResearchDesign.inset)
        .padding(.top, 10)
    }

    private func rankingHeader(_ ranking: CountryGDPRanking) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("国家与地区")
                .font(.headline)
            Spacer()
            Text("\(ranking.countries.count) 个经济体")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, InvestmentDesign.pageInset)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    private func countryRow(_ country: CountryGDP) -> some View {
        HStack(spacing: 10) {
            FlatCountryFlag(iso2Code: country.iso2Code, width: 32, height: 22)

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
                HStack(spacing: 6) {
                    if let perCapita = country.gdpPerCapitaUSD {
                        Text("人均 \(CountryGDPFormat.perCapita(perCapita))")
                            .foregroundStyle(.secondary)
                    }
                    changeSummary(country)
                }
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
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
        if let perCapita = country.gdpPerCapitaUSD {
            text += "，人均 GDP \(CountryGDPFormat.perCapita(perCapita))"
        }
        return text
    }

    private func sourceFooter(_ ranking: CountryGDPRanking) -> some View {
        Link(destination: ranking.sourceURL) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(InvestmentDesign.accent)
                Text("数据来自世界银行，按 \(ranking.year) 年现价美元 GDP 总量排序。点按查看原始口径。")
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
        ContentLoadingPlaceholder(title: "正在读取 GDP 排名")
    }

    private var errorState: some View {
        ContentUnavailableView {
            Label("GDP 排名暂不可用", systemImage: "chart.bar.xaxis")
        } description: {
            Text("排名数据暂不可用，请稍后重试")
        } actions: {
            Button("重新加载") {
                Task { await store.loadCountryGDP() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(minHeight: 320)
    }

}

struct FlatCountryFlag: View {
    let iso2Code: String
    let width: CGFloat
    let height: CGFloat

    private var imageURL: URL? {
        let code = iso2Code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard code.count == 2 else { return nil }
        return MediaURL.image("https://flagcdn.com/w80/\(code).png")
    }

    var body: some View {
        ZStack {
            Color(uiColor: .secondarySystemBackground)

            AsyncImage(url: imageURL) { phase in
                if case let .success(image) = phase {
                    image
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "flag.fill")
                        .font(.system(size: min(width, height) * 0.42, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 2.5, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .stroke(InvestmentDesign.divider, lineWidth: 0.5)
        }
        .accessibilityHidden(true)
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

    static func perCapita(_ value: Double) -> String {
        "$" + value.formatted(.number.grouping(.automatic).precision(.fractionLength(0)))
    }

    static func accessible(_ value: Double) -> String {
        compact(value)
    }
}
