import SwiftUI

enum CityRegionLevel: String, Hashable {
    case country = "全国"
    case province = "省份"
    case city = "城市"
    case district = "区县"

    var childTitle: String? {
        switch self {
        case .country: "选择省份"
        case .province: "下辖城市"
        case .city: "下辖区县"
        case .district: nil
        }
    }
}

struct CityRegionNews: Identifiable, Hashable {
    let id: String
    let title: String
    let summary: String
    let source: String
    let relativeTime: String
    let symbol: String
}

struct CityRegion: Identifiable, Hashable {
    let id: String
    let adcode: Int
    let parentAdcode: Int?
    let name: String
    let level: CityRegionLevel
    let introduction: String
    let facts: [String]
    let news: [CityRegionNews]
    let children: [CityRegion]
}

struct CityRegionJourney: Equatable {
    private(set) var regionIDs: [String]

    init(path: [CityRegion] = []) {
        regionIDs = path.map(\.id)
    }

    var path: [CityRegion] { regionIDs.compactMap(CityNewsMockData.region(withID:)) }
    var current: CityRegion { path.last ?? CityNewsMockData.root }
    var trail: [CityRegion] { [CityNewsMockData.root] + path }
    var parent: CityRegion? { trail.dropLast().last }
    var canGoBack: Bool { !regionIDs.isEmpty }
    var mapScope: CityRegion { current.level == .district ? parent ?? current : current }
    var mapRegions: [CityRegion] { mapScope.children }
    var selectedMapRegionID: String? { current.id == mapScope.id ? nil : current.id }

    @discardableResult
    mutating func enter(_ region: CityRegion) -> Bool {
        guard current.children.contains(where: { $0.id == region.id }) else { return false }
        regionIDs.append(region.id)
        return true
    }

    @discardableResult
    mutating func selectPeer(_ region: CityRegion) -> Bool {
        guard region.id != current.id,
              let parent,
              parent.children.contains(where: { $0.id == region.id }),
              !regionIDs.isEmpty
        else { return false }
        regionIDs[regionIDs.count - 1] = region.id
        return true
    }

    @discardableResult
    mutating func returnTo(_ region: CityRegion) -> Bool {
        if region.id == CityNewsMockData.root.id {
            guard !regionIDs.isEmpty else { return false }
            regionIDs.removeAll()
            return true
        }

        guard let index = regionIDs.firstIndex(of: region.id), index < regionIDs.count - 1 else {
            return false
        }
        regionIDs = Array(regionIDs.prefix(through: index))
        return true
    }

    @discardableResult
    mutating func goBack() -> Bool {
        guard !regionIDs.isEmpty else { return false }
        regionIDs.removeLast()
        return true
    }
}

enum CityNewsMockData {
    static let root: CityRegion = {
        let guangdong = province(
            id: "guangdong",
            adcode: 440000,
            name: "广东省",
            introduction: "中国南部沿海省份，粤港澳大湾区核心区域。制造业、科技与外贸活跃。",
            facts: ["省会 广州", "21个地级市"],
            cities: [
                city(
                    "shenzhen", 440300, "深圳市",
                    "粤港澳大湾区核心城市，以科技创新、金融与现代服务业著称。",
                    ["常住人口 1,779万", "9个行政区"],
                    [(440305, "南山区"), (440304, "福田区"), (440303, "罗湖区"), (440306, "宝安区")]
                )
            ]
        )

        let zhejiang = province(
            id: "zhejiang",
            adcode: 330000,
            name: "浙江省",
            introduction: "中国东南沿海省份，数字经济、民营经济和港口贸易优势突出。",
            facts: ["省会 杭州", "11个地级市"],
            cities: [
                city(
                    "hangzhou", 330100, "杭州市",
                    "浙江省省会，数字经济和文化旅游产业发达。",
                    ["常住人口 1,262万", "13个区县"],
                    [(330106, "西湖区"), (330110, "余杭区"), (330108, "滨江区")]
                )
            ]
        )

        let sichuan = province(
            id: "sichuan",
            adcode: 510000,
            name: "四川省",
            introduction: "中国西部重要经济、人口和文化大省，电子信息、能源与文旅资源丰富。",
            facts: ["省会 成都", "21个市州"],
            cities: [city(
                "chengdu", 510100, "成都市",
                "成渝地区双城经济圈核心城市，电子信息和现代服务业发达。",
                ["国家中心城市", "23个区县"],
                [(510104, "锦江区"), (510107, "武侯区"), (510116, "双流区"), (510117, "郫都区")]
            )]
        )

        let shaanxi = province(
            id: "shaanxi",
            adcode: 610000,
            name: "陕西省",
            introduction: "连接中国东西部的重要省份，科教、航空航天、能源和历史文化资源突出。",
            facts: ["省会 西安", "10个地级市"],
            cities: [city(
                "xian", 610100, "西安市",
                "国家中心城市和重要科研教育基地，历史文化与硬科技产业并重。",
                ["常住人口 1,308万", "13个区县"],
                [(610113, "雁塔区"), (610103, "碑林区"), (610112, "未央区"), (610104, "莲湖区")]
            )]
        )

        return CityRegion(
            id: "china",
            adcode: 100000,
            parentAdcode: nil,
            name: "全国",
            level: .country,
            introduction: "这里按省份、城市和区县逐级查看地区概况与当天新闻，每一级都有独立内容。",
            facts: ["省级行政区", "三级地区新闻"],
            news: news(for: "全国", seed: "区域发展"),
            children: [guangdong, zhejiang, sichuan, shaanxi]
        )
    }()

    static func path(to regionID: String) -> [CityRegion] {
        findPath(in: root, targetID: regionID) ?? []
    }

    static func region(withID regionID: String) -> CityRegion? {
        regionIndex[regionID]
    }

    private static let regionIndex: [String: CityRegion] = {
        var result: [String: CityRegion] = [:]

        func collect(_ region: CityRegion) {
            result[region.id] = region
            region.children.forEach(collect)
        }

        collect(root)
        return result
    }()

    private static func findPath(in region: CityRegion, targetID: String) -> [CityRegion]? {
        for child in region.children {
            if child.id == targetID { return [child] }
            if let path = findPath(in: child, targetID: targetID) { return [child] + path }
        }
        return nil
    }

    private static func province(
        id: String,
        adcode: Int,
        name: String,
        introduction: String,
        facts: [String],
        cities: [CityRegion]
    ) -> CityRegion {
        CityRegion(
            id: id,
            adcode: adcode,
            parentAdcode: 100000,
            name: name,
            level: .province,
            introduction: introduction,
            facts: facts,
            news: news(for: name, seed: "区域协同"),
            children: cities
        )
    }

    private static func city(
        _ id: String,
        _ adcode: Int,
        _ name: String,
        _ introduction: String,
        _ facts: [String],
        _ districts: [(adcode: Int, name: String)]
    ) -> CityRegion {
        CityRegion(
            id: id,
            adcode: adcode,
            parentAdcode: adcode / 10000 * 10000,
            name: name,
            level: .city,
            introduction: introduction,
            facts: facts,
            news: news(for: name, seed: "产业创新"),
            children: districts.enumerated().map { index, entry in
                district(
                    id: "\(id)-\(entry.adcode)",
                    adcode: entry.adcode,
                    parentAdcode: adcode,
                    name: entry.name,
                    cityName: name,
                    index: index
                )
            }
        )
    }

    private static func district(
        id: String,
        adcode: Int,
        parentAdcode: Int,
        name: String,
        cityName: String,
        index: Int
    ) -> CityRegion {
        let featured = name == "南山区"
        return CityRegion(
            id: id,
            adcode: adcode,
            parentAdcode: parentAdcode,
            name: name,
            level: .district,
            introduction: featured
                ? "深圳科技创新核心区，聚集高新技术企业、高校与文化设施。"
                : "\(cityName)的重要城区，持续完善公共服务、产业空间与城市生活配套。",
            facts: featured ? ["面积 187平方公里", "常住人口 181万"] : ["区县级单位", "本地动态"],
            news: news(for: name, seed: index.isMultiple(of: 2) ? "城市更新" : "公共服务"),
            children: []
        )
    }

    private static func news(for place: String, seed: String) -> [CityRegionNews] {
        [
            CityRegionNews(
                id: "\(place)-lead",
                title: "\(place)发布新一轮\(seed)行动计划",
                summary: "聚焦重点项目和公共空间，推动区域高质量发展。",
                source: "本地发布",
                relativeTime: "1小时前",
                symbol: "building.2.crop.circle"
            ),
            CityRegionNews(
                id: "\(place)-industry",
                title: "\(place)重点项目建设取得新进展",
                summary: "多项民生与产业项目进入新阶段，进一步完善区域功能。",
                source: "区域新闻",
                relativeTime: "2小时前",
                symbol: "network"
            ),
            CityRegionNews(
                id: "\(place)-culture",
                title: "\(place)本周公共文化活动指南",
                summary: "图书馆、博物馆和文化场馆推出多项展览与活动。",
                source: "文旅资讯",
                relativeTime: "3小时前",
                symbol: "books.vertical.fill"
            )
        ]
    }
}

struct CityNewsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var journey: CityRegionJourney
    @State private var displayedRegion: CityRegion
    @State private var transitionIntent: CityRegionTransitionIntent?
    @State private var detailsOpacity = 1.0
    @State private var contentTask: Task<Void, Never>?

    init() {
        let initialJourney: CityRegionJourney
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--city-district-preview") {
            initialJourney = CityRegionJourney(path: CityNewsMockData.path(to: "shenzhen-440305"))
        } else if arguments.contains("--city-city-preview") {
            initialJourney = CityRegionJourney(path: CityNewsMockData.path(to: "shenzhen"))
        } else if arguments.contains("--city-province-preview") {
            initialJourney = CityRegionJourney(path: CityNewsMockData.path(to: "guangdong"))
        } else {
            initialJourney = CityRegionJourney()
        }
        #else
        initialJourney = CityRegionJourney()
        #endif
        _journey = State(initialValue: initialJourney)
        _displayedRegion = State(initialValue: initialJourney.current)
    }

    var body: some View {
        let region = journey.current
        let mapScope = journey.mapScope

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                CityRegionHeader(
                    region: region,
                    trail: journey.trail,
                    focusTitle: transitionIntent?.kind != .lateral,
                    canGoBack: journey.canGoBack,
                    parentName: journey.parent?.name,
                    onBack: goBack,
                    onSelectTrail: returnTo
                )
                .padding(.horizontal, 20)
                .padding(.top, 12)

                CityRegionMapStage(
                    scope: mapScope,
                    selectedRegionID: journey.selectedMapRegionID,
                    selectableRegions: journey.mapRegions,
                    transitionIntent: transitionIntent,
                    reduceMotion: reduceMotion,
                    onSelect: selectRegion
                )
                .padding(.horizontal, 16)
                .padding(.top, 12)

                if !journey.mapRegions.isEmpty {
                    CityRegionPicker(
                        scope: mapScope,
                        regions: journey.mapRegions,
                        selectedRegionID: journey.selectedMapRegionID,
                        onSelect: selectRegion
                    )
                    .padding(.top, 14)
                }

                CityRegionDetails(region: displayedRegion)
                    .opacity(detailsOpacity)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 72)
            }
        }
        .scrollIndicators(.hidden)
        .background(CityNewsDesign.canvas)
        .tint(CityNewsDesign.accent)
        .sensoryFeedback(.selection, trigger: region.id)
        .accessibilityIdentifier("city-region-screen")
        .onAppear { settleContentImmediately() }
        .onDisappear { settleContentImmediately() }
    }

    private func enter(_ region: CityRegion) {
        let sourceScope = journey.mapScope
        guard journey.enter(region) else { return }
        transitionIntent = CityRegionTransitionIntent(
            kind: .deeper,
            fromScope: sourceScope,
            toScope: journey.mapScope,
            focusAdcode: region.adcode
        )
        refreshContent(to: journey.current, after: reduceMotion ? 0 : 0.18)
    }

    private func selectRegion(_ region: CityRegion) {
        if journey.current.children.contains(where: { $0.id == region.id }) {
            enter(region)
            return
        }

        let sourceScope = journey.mapScope
        guard journey.selectPeer(region) else { return }
        transitionIntent = CityRegionTransitionIntent(
            kind: .lateral,
            fromScope: sourceScope,
            toScope: journey.mapScope,
            focusAdcode: region.adcode
        )
        refreshContent(to: journey.current, after: 0)
    }

    private func returnTo(_ region: CityRegion) {
        let sourceScope = journey.mapScope
        guard journey.returnTo(region) else { return }
        transitionIntent = CityRegionTransitionIntent(
            kind: .back,
            fromScope: sourceScope,
            toScope: journey.mapScope,
            focusAdcode: sourceScope.adcode
        )
        refreshContent(to: journey.current, after: reduceMotion ? 0 : 0.18)
    }

    private func goBack() {
        let sourceScope = journey.mapScope
        guard journey.goBack() else { return }
        transitionIntent = CityRegionTransitionIntent(
            kind: .back,
            fromScope: sourceScope,
            toScope: journey.mapScope,
            focusAdcode: sourceScope.adcode
        )
        refreshContent(to: journey.current, after: reduceMotion ? 0 : 0.18)
    }

    private func refreshContent(to region: CityRegion, after delay: TimeInterval) {
        contentTask?.cancel()
        let phaseDuration = reduceMotion ? 0.07 : 0.1

        contentTask = Task { @MainActor in
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
            }
            withAnimation(.easeOut(duration: phaseDuration)) {
                detailsOpacity = 0
            }
            try? await Task.sleep(for: .seconds(phaseDuration))
            guard !Task.isCancelled else { return }
            displayedRegion = region
            withAnimation(.easeIn(duration: reduceMotion ? 0.07 : 0.14)) {
                detailsOpacity = 1
            }
        }
    }

    private func settleContentImmediately() {
        contentTask?.cancel()
        contentTask = nil
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            displayedRegion = journey.current
            detailsOpacity = 1
        }
    }
}

private enum CityNewsDesign {
    static let accent = InvestmentDesign.accent
    static let accentSoft = accent.opacity(0.09)
    static let canvas = Color(uiColor: .systemBackground)
    static let secondarySurface = Color(uiColor: .secondarySystemBackground)
    static let divider = Color(uiColor: .separator).opacity(0.24)
    static let mapGradient = LinearGradient(
        colors: [
            Color(uiColor: .secondarySystemBackground),
            accent.opacity(0.075)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

private struct CityPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private enum CityRegionTransitionKind {
    case deeper
    case back
    case lateral
}

private struct CityRegionTransitionIntent: Equatable {
    let id = UUID()
    let kind: CityRegionTransitionKind
    let fromScope: CityRegion
    let toScope: CityRegion
    let focusAdcode: Int
}

private struct CityRegionHeader: View {
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @AccessibilityFocusState private var isCurrentTitleFocused: Bool

    let region: CityRegion
    let trail: [CityRegion]
    let focusTitle: Bool
    let canGoBack: Bool
    let parentName: String?
    let onBack: () -> Void
    let onSelectTrail: (CityRegion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Label("城市观察", systemImage: "location.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CityNewsDesign.accent)
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                Spacer()

                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 34, height: 34)
                        .background(CityNewsDesign.secondarySurface, in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(CityPressStyle())
                .opacity(canGoBack ? 1 : 0)
                .allowsHitTesting(canGoBack)
                .accessibilityHidden(!canGoBack)
                .accessibilityLabel(parentName.map { "返回\($0)" } ?? "返回上一级地区")
                .accessibilityHint("在当前页面展开上一级内容")
            }
            .frame(height: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(region.name)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(.primary)
                    .contentTransition(.opacity)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($isCurrentTitleFocused)
                    .accessibilityIdentifier("city-current-title")
                Text(([region.level.rawValue] + region.facts).joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
            }
            .frame(minHeight: 66, alignment: .topLeading)
            .task(id: region.id) {
                guard voiceOverEnabled, focusTitle else { return }
                await Task.yield()
                isCurrentTitleFocused = true
            }

            Group {
                if trail.count > 1 {
                    CityRegionBreadcrumb(trail: trail, onSelect: onSelectTrail)
                } else {
                    Text("轻点地图或地区名称逐级浏览")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 7)
                }
            }
            .frame(minHeight: 32, alignment: .leading)
        }
    }
}

private struct CityRegionBreadcrumb: View {
    let trail: [CityRegion]
    let onSelect: (CityRegion) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 7) {
                ForEach(Array(trail.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.tertiary)
                    }

                    if item.id == trail.last?.id {
                        Text(item.name)
                            .foregroundStyle(.primary)
                            .fontWeight(.semibold)
                            .padding(.vertical, 7)
                    } else {
                        Button {
                            onSelect(item)
                        } label: {
                            Text(item.name)
                                .padding(.vertical, 7)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(CityPressStyle())
                        .foregroundStyle(.secondary)
                        .accessibilityHint("在当前页面返回到\(item.name)")
                        .accessibilityIdentifier("city-breadcrumb-\(item.id)")
                    }
                }
            }
            .font(.caption)
        }
        .scrollIndicators(.hidden)
    }
}

private struct CityRegionMapStage: View {
    let scope: CityRegion
    let selectedRegionID: String?
    let selectableRegions: [CityRegion]
    let transitionIntent: CityRegionTransitionIntent?
    let reduceMotion: Bool
    let onSelect: (CityRegion) -> Void

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(CityNewsDesign.mapGradient)

            Circle()
                .fill(CityNewsDesign.accent.opacity(0.055))
                .frame(width: 170, height: 170)
                .offset(x: 62, y: 74)
                .allowsHitTesting(false)

            CityMapCamera(
                scope: scope,
                selectedRegionID: selectedRegionID,
                selectableRegions: selectableRegions,
                transitionIntent: transitionIntent,
                reduceMotion: reduceMotion,
                onSelect: onSelect
            )
            .padding(12)

            Image(systemName: selectedRegionID == nil ? "hand.tap.fill" : "mappin.circle.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .background(.ultraThinMaterial, in: Circle())
                .padding(12)
                .accessibilityHidden(true)
        }
        .frame(height: 232)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 0.7)
        }
    }
}

struct CityMapFeatureCollection: Decodable {
    let features: [CityMapFeature]
}

struct CityMapFeature: Decodable, Identifiable {
    struct Properties: Decodable {
        struct Parent: Decodable { let adcode: Int }

        let adcode: Int
        let name: String
        let level: String
        let parent: Parent?
        let center: [Double]?
        let centroid: [Double]?
    }

    struct Geometry: Decodable {
        let polygons: [[[[Double]]]]

        private enum CodingKeys: String, CodingKey { case type, coordinates }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)
            if type == "Polygon" {
                polygons = [try container.decode([[[Double]]].self, forKey: .coordinates)]
            } else {
                polygons = try container.decode([[[[Double]]]].self, forKey: .coordinates)
            }
        }
    }

    let properties: Properties
    let geometry: Geometry

    var id: Int { properties.adcode }
    var parentAdcode: Int? { properties.parent?.adcode }
    var allCoordinates: [[Double]] { geometry.polygons.flatMap { $0.flatMap { $0 } } }

    var labelCoordinate: [Double]? {
        properties.centroid ?? properties.center ?? allCoordinates.first
    }
}

struct CityMapRepository {
    static let shared = CityMapRepository()

    let features: [CityMapFeature]

    init(bundle: Bundle = .main) {
        guard
            let url = bundle.url(forResource: "CityMapRegions", withExtension: "geojson"),
            let data = try? Data(contentsOf: url),
            let collection = try? JSONDecoder().decode(CityMapFeatureCollection.self, from: data)
        else {
            features = []
            return
        }
        features = collection.features
    }

    func features(for region: CityRegion) -> [CityMapFeature] {
        switch region.level {
        case .country:
            features.filter { $0.properties.level == "province" }
        case .province:
            features.filter { $0.properties.level == "city" && $0.parentAdcode == region.adcode }
        case .city:
            features.filter { $0.properties.level == "district" && $0.parentAdcode == region.adcode }
        case .district:
            features.filter { $0.properties.level == "district" && $0.parentAdcode == region.parentAdcode }
        }
    }

    func feature(adcode: Int) -> CityMapFeature? {
        features.first { $0.id == adcode }
    }
}

private struct CityMapCamera: View {
    let scope: CityRegion
    let selectedRegionID: String?
    let selectableRegions: [CityRegion]
    let transitionIntent: CityRegionTransitionIntent?
    let reduceMotion: Bool
    let onSelect: (CityRegion) -> Void

    @State private var renderedScope: CityRegion
    @State private var previousScope: CityRegion?
    @State private var cameraAnchor: UnitPoint = .center
    @State private var incomingScale: CGFloat = 1
    @State private var outgoingScale: CGFloat = 1
    @State private var incomingOpacity: Double = 1
    @State private var outgoingOpacity: Double = 0
    @State private var transitionTask: Task<Void, Never>?

    init(
        scope: CityRegion,
        selectedRegionID: String?,
        selectableRegions: [CityRegion],
        transitionIntent: CityRegionTransitionIntent?,
        reduceMotion: Bool,
        onSelect: @escaping (CityRegion) -> Void
    ) {
        self.scope = scope
        self.selectedRegionID = selectedRegionID
        self.selectableRegions = selectableRegions
        self.transitionIntent = transitionIntent
        self.reduceMotion = reduceMotion
        self.onSelect = onSelect
        _renderedScope = State(initialValue: scope)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let previousScope {
                    CityAdministrativeMap(
                        scope: previousScope,
                        selectedRegionID: nil,
                        selectableRegions: [],
                        allowsSelection: false,
                        onSelect: onSelect
                    )
                    .scaleEffect(outgoingScale, anchor: cameraAnchor)
                    .opacity(outgoingOpacity)
                    .allowsHitTesting(false)
                }

                CityAdministrativeMap(
                    scope: renderedScope,
                    selectedRegionID: selectedRegionID,
                    selectableRegions: selectableRegions,
                    allowsSelection: previousScope == nil,
                    onSelect: onSelect
                )
                .scaleEffect(incomingScale, anchor: cameraAnchor)
                .opacity(incomingOpacity)
                .animation(.easeInOut(duration: 0.2), value: selectedRegionID)
            }
            .animation(
                reduceMotion ? .linear(duration: 0.14) : .smooth(duration: 0.4, extraBounce: 0),
                value: incomingScale
            )
            .animation(
                reduceMotion ? .linear(duration: 0.14) : .smooth(duration: 0.4, extraBounce: 0),
                value: outgoingScale
            )
            .animation(
                reduceMotion ? .linear(duration: 0.14) : .easeInOut(duration: 0.22).delay(0.06),
                value: incomingOpacity
            )
            .animation(.easeInOut(duration: reduceMotion ? 0.14 : 0.24), value: outgoingOpacity)
            .onChange(of: transitionIntent?.id) { _, _ in
                guard let transitionIntent else { return }
                runTransition(transitionIntent, size: geometry.size)
            }
        }
        .onAppear { settleCamera() }
        .onDisappear { settleCamera() }
    }

    private func runTransition(_ intent: CityRegionTransitionIntent, size: CGSize) {
        transitionTask?.cancel()

        guard intent.fromScope.id != intent.toScope.id else {
            withoutAnimation {
                renderedScope = scope
                previousScope = nil
                incomingScale = 1
                outgoingScale = 1
                incomingOpacity = 1
                outgoingOpacity = 0
            }
            return
        }

        let anchorScope = intent.kind == .back ? intent.toScope : intent.fromScope
        withoutAnimation {
            cameraAnchor = mapAnchor(adcode: intent.focusAdcode, in: anchorScope, size: size)
            previousScope = intent.fromScope
            renderedScope = intent.toScope
            outgoingScale = 1
            incomingScale = reduceMotion ? 1 : (intent.kind == .deeper ? 0.965 : 1.045)
            outgoingOpacity = 1
            incomingOpacity = 0
        }

        transitionTask = Task { @MainActor in
            await Task.yield()
            outgoingScale = reduceMotion ? 1 : (intent.kind == .deeper ? 1.075 : 0.955)
            incomingScale = 1
            outgoingOpacity = 0
            incomingOpacity = 1
            try? await Task.sleep(for: .seconds(reduceMotion ? 0.15 : 0.42))
            guard !Task.isCancelled else { return }
            previousScope = nil
        }
    }

    private func withoutAnimation(_ changes: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, changes)
    }

    private func settleCamera() {
        transitionTask?.cancel()
        transitionTask = nil
        withoutAnimation {
            renderedScope = scope
            previousScope = nil
            incomingScale = 1
            outgoingScale = 1
            incomingOpacity = 1
            outgoingOpacity = 0
        }
    }

    private func mapAnchor(adcode: Int, in scope: CityRegion, size: CGSize) -> UnitPoint {
        let features = CityMapRepository.shared.features(for: scope)
        guard let feature = features.first(where: { $0.id == adcode }),
              let coordinate = feature.labelCoordinate,
              size.width > 0,
              size.height > 0
        else { return .center }
        let point = CityMapProjection(features: features, size: size).point(for: coordinate)
        return UnitPoint(
            x: min(max(point.x / size.width, 0), 1),
            y: min(max(point.y / size.height, 0), 1)
        )
    }
}

private struct CityAdministrativeMap: View {
    let scope: CityRegion
    let selectedRegionID: String?
    let selectableRegions: [CityRegion]
    let allowsSelection: Bool
    let onSelect: (CityRegion) -> Void

    private var features: [CityMapFeature] { CityMapRepository.shared.features(for: scope) }
    private var regionByAdcode: [Int: CityRegion] {
        Dictionary(uniqueKeysWithValues: selectableRegions.map { ($0.adcode, $0) })
    }
    private var availableAdcodes: Set<Int> { Set(selectableRegions.map(\.adcode)) }
    private var selectedAdcode: Int? {
        selectedRegionID.flatMap(CityNewsMockData.region(withID:))?.adcode
    }

    var body: some View {
        GeometryReader { geometry in
            if features.isEmpty {
                ContentUnavailableView("地图数据不可用", systemImage: "map")
            } else {
                let projection = CityMapProjection(features: features, size: geometry.size)
                ZStack {
                    Canvas { context, _ in
                        for feature in features {
                            let path = projection.path(for: feature)
                            context.fill(
                                path,
                                with: .color(fillColor(for: feature)),
                                style: FillStyle(eoFill: true)
                            )
                            context.stroke(path, with: .color(.white.opacity(0.85)), lineWidth: 0.65)
                        }
                    }

                    if allowsSelection {
                        Color.clear
                            .contentShape(Rectangle())
                            .gesture(
                                SpatialTapGesture()
                                    .onEnded { value in
                                        selectFeature(at: value.location, projection: projection)
                                    }
                            )
                            .accessibilityHidden(true)
                    }

                    ForEach(markerFeatures) { feature in
                        if let coordinate = feature.labelCoordinate {
                            if let selectableRegion = regionByAdcode[feature.id] {
                                if selectableRegion.id == selectedRegionID {
                                    mapLabel(feature.properties.name, selected: true)
                                        .position(projection.point(for: coordinate))
                                        .accessibilityLabel("\(selectableRegion.name)，当前区域")
                                        .accessibilityAddTraits([.isButton, .isSelected])
                                        .accessibilityAction { onSelect(selectableRegion) }
                                } else {
                                    mapLabel(feature.properties.name, selected: false)
                                        .frame(minWidth: 44, minHeight: 44)
                                        .position(projection.point(for: coordinate))
                                        .accessibilityLabel(selectableRegion.name)
                                        .accessibilityHint("在当前页面展开\(selectableRegion.name)")
                                        .accessibilityIdentifier("city-region-\(selectableRegion.id)")
                                        .accessibilityAddTraits(.isButton)
                                        .accessibilityAction { onSelect(selectableRegion) }
                                }
                            } else {
                                mapLabel(feature.properties.name, selected: true)
                                    .position(projection.point(for: coordinate))
                            }
                        }
                    }

                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text("行政边界")
                                .font(.system(size: 8))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(8)
                    .allowsHitTesting(false)
                }
                .padding(8)
            }
        }
    }

    private var markerFeatures: [CityMapFeature] {
        if selectableRegions.isEmpty {
            return selectedAdcode.map { selected in features.filter { $0.id == selected } } ?? []
        }
        return features.filter { availableAdcodes.contains($0.id) }
    }

    private func fillColor(for feature: CityMapFeature) -> Color {
        if feature.id == selectedAdcode { return CityNewsDesign.accent.opacity(0.78) }
        if availableAdcodes.contains(feature.id) { return CityNewsDesign.accent.opacity(0.42) }
        return Color.secondary.opacity(0.11)
    }

    private func selectFeature(at point: CGPoint, projection: CityMapProjection) {
        guard allowsSelection else { return }
        if let feature = features.reversed().first(where: {
            availableAdcodes.contains($0.id) && projection.path(for: $0).contains(point, eoFill: true)
        }), let region = regionByAdcode[feature.id] {
            onSelect(region)
            return
        }

        let nearest = markerFeatures
            .compactMap { feature -> (CityMapFeature, CGFloat)? in
                guard let coordinate = feature.labelCoordinate else { return nil }
                let location = projection.point(for: coordinate)
                return (feature, hypot(location.x - point.x, location.y - point.y))
            }
            .filter { $0.1 <= 28 }
            .min { $0.1 < $1.1 }
        if let feature = nearest?.0, let region = regionByAdcode[feature.id] {
            onSelect(region)
        }
    }

    private func mapLabel(_ text: String, selected: Bool) -> some View {
        Text(text.replacingOccurrences(of: "省", with: "").replacingOccurrences(of: "市", with: ""))
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(selected ? .white : CityNewsDesign.accent)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(
                selected ? CityNewsDesign.accent : CityNewsDesign.secondarySurface.opacity(0.96),
                in: Capsule()
            )
            .overlay { Capsule().stroke(CityNewsDesign.accent.opacity(0.24), lineWidth: 0.6) }
            .shadow(color: .black.opacity(selected ? 0 : 0.06), radius: 4, y: 2)
            .allowsHitTesting(false)
    }
}

private struct CityMapProjection {
    private let minX: Double
    private let maxY: Double
    private let scale: Double
    private let offsetX: Double
    private let offsetY: Double

    init(features: [CityMapFeature], size: CGSize) {
        let coordinates = features.flatMap(\.allCoordinates)
        let xs = coordinates.compactMap { $0.first }
        let ys = coordinates.compactMap { $0.count > 1 ? $0[1] : nil }
        let sourceMinX = xs.min() ?? 0
        let sourceMaxX = xs.max() ?? 1
        let sourceMinY = ys.min() ?? 0
        let sourceMaxY = ys.max() ?? 1
        let padding = 8.0
        let sourceWidth = max(sourceMaxX - sourceMinX, 0.001)
        let sourceHeight = max(sourceMaxY - sourceMinY, 0.001)
        let fittedScale = min(
            max(Double(size.width) - padding * 2, 1) / sourceWidth,
            max(Double(size.height) - padding * 2, 1) / sourceHeight
        )
        let renderedWidth = sourceWidth * fittedScale
        let renderedHeight = sourceHeight * fittedScale

        minX = sourceMinX
        maxY = sourceMaxY
        scale = fittedScale
        offsetX = (Double(size.width) - renderedWidth) / 2
        offsetY = (Double(size.height) - renderedHeight) / 2
    }

    func point(for coordinate: [Double]) -> CGPoint {
        guard coordinate.count >= 2 else { return .zero }
        return CGPoint(
            x: (coordinate[0] - minX) * scale + offsetX,
            y: (maxY - coordinate[1]) * scale + offsetY
        )
    }

    func path(for feature: CityMapFeature) -> Path {
        var path = Path()
        for polygon in feature.geometry.polygons {
            for ring in polygon {
                guard let first = ring.first else { continue }
                path.move(to: point(for: first))
                for coordinate in ring.dropFirst() {
                    path.addLine(to: point(for: coordinate))
                }
                path.closeSubpath()
            }
        }
        return path
    }
}

private struct CityRegionDetails: View {
    let region: CityRegion

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 12) {
                Text("城市速写")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(CityNewsDesign.accent)
                    .tracking(0.8)

                Text(region.introduction)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        ForEach(region.facts, id: \.self) { fact in
                            factLabel(fact)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(region.facts, id: \.self) { fact in
                            factLabel(fact)
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Rectangle()
                    .fill(CityNewsDesign.divider)
                    .frame(height: 0.5)
            }
            VStack(alignment: .leading, spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) {
                        newsHeading
                        Spacer()
                        regionLabel
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        newsHeading
                        regionLabel
                    }
                }

                VStack(spacing: 0) {
                    ForEach(Array(region.news.enumerated()), id: \.element.id) { index, item in
                        CityRegionNewsRow(item: item)
                        if index < region.news.count - 1 {
                            Rectangle()
                                .fill(CityNewsDesign.divider)
                                .frame(height: 0.5)
                                .padding(.leading, 50)
                        }
                    }
                }
            }
        }
    }

    private func factLabel(_ fact: String) -> some View {
        Text(fact)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minHeight: 28)
            .background(CityNewsDesign.secondarySurface, in: Capsule())
    }

    private var newsHeading: some View {
        Text("今日动态")
            .font(.title3.weight(.bold))
    }

    private var regionLabel: some View {
        Text(region.name)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

private struct CityRegionPicker: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionNamespace
    @State private var centeredRegionID: String?

    let scope: CityRegion
    let regions: [CityRegion]
    let selectedRegionID: String?
    let onSelect: (CityRegion) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 8) {
                ForEach(regions) { region in
                    let isSelected = region.id == selectedRegionID
                    Button {
                        onSelect(region)
                    } label: {
                        Text(region.name)
                            .font(.subheadline.weight(isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? CityNewsDesign.accent : .primary)
                            .lineLimit(1)
                            .padding(.horizontal, 15)
                            .frame(minHeight: 44)
                            .background {
                                if isSelected {
                                    Capsule()
                                        .fill(CityNewsDesign.accentSoft)
                                        .matchedGeometryEffect(id: "city-region-selection", in: selectionNamespace)
                                } else {
                                    Capsule().fill(CityNewsDesign.secondarySurface)
                                }
                            }
                    }
                    .buttonStyle(CityPressStyle())
                    .accessibilityHint(isSelected ? "当前区域" : "在当前页面查看\(region.name)")
                    .accessibilityIdentifier("city-region-list-\(region.id)")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $centeredRegionID, anchor: .center)
        .animation(
            reduceMotion ? nil : .smooth(duration: 0.22, extraBounce: 0),
            value: selectedRegionID
        )
        .onAppear { centeredRegionID = selectedRegionID }
        .onChange(of: selectedRegionID) { _, selectedRegionID in
            guard let selectedRegionID else { return }
            if reduceMotion {
                centeredRegionID = selectedRegionID
            } else {
                withAnimation(.smooth(duration: 0.22, extraBounce: 0)) {
                    centeredRegionID = selectedRegionID
                }
            }
        }
        .accessibilityLabel(scope.level.childTitle ?? "同城区域")
    }
}

private struct CityRegionNewsRow: View {
    let item: CityRegionNews

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(CityNewsDesign.accent)
                .frame(width: 38, height: 38)
                .background(CityNewsDesign.accentSoft, in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text("\(item.source)  ·  \(item.relativeTime)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}
