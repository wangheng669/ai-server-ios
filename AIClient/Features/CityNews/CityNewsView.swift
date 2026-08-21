import SwiftUI

enum CityRegionLevel: String, Hashable {
    case country = "全国", province = "省份", city = "城市", district = "区县"

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

    init(path: [CityRegion] = []) { regionIDs = path.map(\.id) }

    var path: [CityRegion] { regionIDs.compactMap(CityNewsMockData.region(withID:)) }
    var current: CityRegion { path.last ?? CityNewsMockData.root }
    var trail: [CityRegion] { [CityNewsMockData.root] + path }
    var parent: CityRegion? { trail.dropLast().last }
    var canGoBack: Bool { !regionIDs.isEmpty }
    var mapScope: CityRegion {
        if current.level == .district || (current.level == .city && current.children.isEmpty) {
            return parent ?? current
        }
        return current
    }
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
    private struct CitySeed {
        let id: String
        let adcode: Int
        let name: String
        let intro: String
        let facts: [String]
    }

    private static let guangdongSeeds: [CitySeed] = [
        .init(id: "guangzhou", adcode: 440100, name: "广州市", intro: "广东省省会，华南重要的商贸、交通与科技创新中心。", facts: ["省会城市", "国家中心城市", "综合门户"]),
        .init(id: "shaoguan", adcode: 440200, name: "韶关市", intro: "广东北部门户城市，生态资源与先进材料产业特色鲜明。", facts: ["粤北门户", "生态城市", "产业升级"]),
        .init(id: "shenzhen", adcode: 440300, name: "深圳市", intro: "科技创新与先进制造业中心，也是粤港澳大湾区核心城市。", facts: ["人口 1,756万", "GDP 3.46万亿", "高新技术产业发达"]),
        .init(id: "zhuhai", adcode: 440400, name: "珠海市", intro: "珠江口西岸核心城市，先进制造与滨海文旅协同发展。", facts: ["湾区城市", "滨海宜居", "先进制造"]),
        .init(id: "shantou", adcode: 440500, name: "汕头市", intro: "粤东中心城市和经济特区，港口经济与特色制造活跃。", facts: ["经济特区", "粤东中心", "港口城市"]),
        .init(id: "foshan", adcode: 440600, name: "佛山市", intro: "全国重要制造业城市，家电、装备与新材料产业基础深厚。", facts: ["制造业重镇", "广佛同城", "民营经济"]),
        .init(id: "jiangmen", adcode: 440700, name: "江门市", intro: "珠江西岸重要节点城市，先进制造与侨乡文化兼具。", facts: ["中国侨都", "湾区西翼", "先进制造"]),
        .init(id: "zhanjiang", adcode: 440800, name: "湛江市", intro: "粤西中心城市和沿海经济带重要增长极，临港产业突出。", facts: ["粤西中心", "临港产业", "海洋经济"]),
        .init(id: "maoming", adcode: 440900, name: "茂名市", intro: "广东重要能源与农业基地，石化与现代农业协同发展。", facts: ["能源基地", "现代农业", "滨海文旅"]),
        .init(id: "zhaoqing", adcode: 441200, name: "肇庆市", intro: "粤港澳大湾区西部门户，产业承接与生态文旅并进。", facts: ["湾区西门", "生态城市", "产业承接"]),
        .init(id: "huizhou", adcode: 441300, name: "惠州市", intro: "大湾区东部枢纽城市，电子信息、石化与新能源产业集聚。", facts: ["湾区东部", "电子信息", "新能源"]),
        .init(id: "meizhou", adcode: 441400, name: "梅州市", intro: "粤东北区域性中心城市，绿色产业与客家文化突出。", facts: ["世界客都", "绿色发展", "粤东北中心"]),
        .init(id: "shanwei", adcode: 441500, name: "汕尾市", intro: "沿海经济带重要节点，海上风电与滨海旅游加快发展。", facts: ["沿海节点", "海上风电", "滨海文旅"]),
        .init(id: "heyuan", adcode: 441600, name: "河源市", intro: "粤东北生态发展区重要城市，绿色产业与湾区协作并重。", facts: ["生态发展区", "绿色产业", "湾区腹地"]),
        .init(id: "yangjiang", adcode: 441700, name: "阳江市", intro: "沿海制造业城市，五金刀剪、海上风电与文旅具备优势。", facts: ["五金产业", "海上风电", "滨海城市"]),
        .init(id: "qingyuan", adcode: 441800, name: "清远市", intro: "广州都市圈北部节点，先进材料与生态旅游协同发展。", facts: ["广清一体化", "先进材料", "生态文旅"]),
        .init(id: "dongguan", adcode: 441900, name: "东莞市", intro: "大湾区先进制造业基地，电子信息与智能制造产业链完整。", facts: ["制造名城", "湾区节点", "外向经济"]),
        .init(id: "zhongshan", adcode: 442000, name: "中山市", intro: "珠江西岸制造业城市，装备制造与专业镇经济活跃。", facts: ["湾区城市", "专业镇经济", "先进制造"]),
        .init(id: "chaozhou", adcode: 445100, name: "潮州市", intro: "国家历史文化名城，陶瓷、食品与文化旅游特色突出。", facts: ["历史文化名城", "陶瓷产业", "潮州文化"]),
        .init(id: "jieyang", adcode: 445200, name: "揭阳市", intro: "粤东产业与交通节点，绿色石化和特色制造持续壮大。", facts: ["粤东节点", "绿色石化", "特色制造"]),
        .init(id: "yunfu", adcode: 445300, name: "云浮市", intro: "广东西部生态发展区城市，绿色建材与现代农业并进。", facts: ["生态发展区", "绿色建材", "现代农业"])
    ]

    static let root: CityRegion = {
        let guangdongCities = guangdongSeeds.map { seed in
            city(
                seed.id,
                seed.adcode,
                seed.name,
                seed.intro,
                seed.facts,
                seed.id == "shenzhen"
                    ? [(440305, "南山区"), (440304, "福田区"), (440303, "罗湖区"), (440306, "宝安区")]
                    : []
            )
        }
        let guangdong = province(
            "guangdong", 440000, "广东省",
            "华南沿海省份，粤港澳大湾区核心区域，制造业、科技与外贸活跃。",
            ["省会 广州", "21个地级市", "区域 华南"],
            guangdongCities
        )
        let zhejiang = province(
            "zhejiang", 330000, "浙江省",
            "中国东南沿海省份，数字经济、民营经济和港口贸易优势突出。",
            ["省会 杭州", "11个地级市"],
            [city("hangzhou", 330100, "杭州市", "浙江省省会，数字经济和文化旅游产业发达。", ["常住人口 1,262万", "13个区县"], [(330106, "西湖区"), (330110, "余杭区"), (330108, "滨江区")])]
        )
        let sichuan = province(
            "sichuan", 510000, "四川省",
            "中国西部重要经济、人口和文化大省，电子信息、能源与文旅资源丰富。",
            ["省会 成都", "21个市州"],
            [city("chengdu", 510100, "成都市", "成渝地区双城经济圈核心城市。", ["国家中心城市", "23个区县"], [(510104, "锦江区"), (510107, "武侯区"), (510116, "双流区"), (510117, "郫都区")])]
        )
        let shaanxi = province(
            "shaanxi", 610000, "陕西省",
            "连接中国东西部的重要省份，科教、航空航天和历史文化资源突出。",
            ["省会 西安", "10个地级市"],
            [city("xian", 610100, "西安市", "国家中心城市和重要科研教育基地。", ["常住人口 1,308万", "13个区县"], [(610113, "雁塔区"), (610103, "碑林区"), (610112, "未央区"), (610104, "莲湖区")])]
        )
        return CityRegion(
            id: "china", adcode: 100000, parentAdcode: nil, name: "全国", level: .country,
            introduction: "按省份、城市和区县逐级查看地区概况。",
            facts: ["省级行政区", "三级地区内容"],
            news: news("全国"), children: [guangdong, zhejiang, sichuan, shaanxi]
        )
    }()

    static func path(to regionID: String) -> [CityRegion] { findPath(root, regionID) ?? [] }
    static func region(withID regionID: String) -> CityRegion? { index[regionID] }

    private static let index: [String: CityRegion] = {
        var result: [String: CityRegion] = [:]
        func collect(_ region: CityRegion) {
            result[region.id] = region
            region.children.forEach(collect)
        }
        collect(root)
        return result
    }()

    private static func findPath(_ region: CityRegion, _ target: String) -> [CityRegion]? {
        for child in region.children {
            if child.id == target { return [child] }
            if let suffix = findPath(child, target) { return [child] + suffix }
        }
        return nil
    }

    private static func province(
        _ id: String, _ adcode: Int, _ name: String, _ intro: String,
        _ facts: [String], _ cities: [CityRegion]
    ) -> CityRegion {
        CityRegion(
            id: id, adcode: adcode, parentAdcode: 100000, name: name, level: .province,
            introduction: intro, facts: facts, news: news(name), children: cities
        )
    }

    private static func city(
        _ id: String, _ adcode: Int, _ name: String, _ intro: String,
        _ facts: [String], _ districts: [(Int, String)]
    ) -> CityRegion {
        CityRegion(
            id: id, adcode: adcode, parentAdcode: adcode / 10_000 * 10_000,
            name: name, level: .city, introduction: intro, facts: facts, news: news(name),
            children: districts.enumerated().map { index, entry in
                CityRegion(
                    id: "\(id)-\(entry.0)", adcode: entry.0, parentAdcode: adcode,
                    name: entry.1, level: .district,
                    introduction: entry.1 == "南山区"
                        ? "深圳科技创新核心区，聚集高新技术企业、高校与文化设施。"
                        : "\(name)的重要城区，持续完善产业空间与城市生活配套。",
                    facts: entry.1 == "南山区"
                        ? ["面积 187平方公里", "常住人口 181万"]
                        : ["区县级单位", "本地动态"],
                    news: news(entry.1, seed: index.isMultiple(of: 2) ? "城市更新" : "公共服务"),
                    children: []
                )
            }
        )
    }

    private static func news(_ place: String, seed: String = "产业创新") -> [CityRegionNews] {
        [
            .init(id: "\(place)-1", title: "\(place)发布新一轮\(seed)行动计划", summary: "聚焦重点项目和公共空间。", source: "本地发布", relativeTime: "1小时前", symbol: "building.2.crop.circle"),
            .init(id: "\(place)-2", title: "\(place)重点项目建设取得新进展", summary: "多项民生与产业项目进入新阶段。", source: "区域新闻", relativeTime: "2小时前", symbol: "network")
        ]
    }
}

private enum CityDashboardTab: String, CaseIterable, Identifiable {
    case overview = "概览", cities = "城市", data = "数据", industry = "产业", transport = "交通", culture = "文旅"
    var id: String { rawValue }
}

private struct CityMetric: Identifiable {
    let id: String
    let title: String
    let value: String
    let unit: String
    let note: String
    let symbol: String
}

struct CityNewsView: View {
    @Environment(\.rootBottomChromeHeight) private var bottomChromeHeight
    @State private var journey: CityRegionJourney
    @State private var selectedID: String?
    @State private var selectedTab: CityDashboardTab = .overview
    @State private var showsList = false
    @State private var showsMap = false

    init() {
        let journey: CityRegionJourney
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--city-district-preview") {
            journey = CityRegionJourney(path: CityNewsMockData.path(to: "shenzhen-440305"))
        } else if arguments.contains("--city-city-preview") {
            journey = CityRegionJourney(path: CityNewsMockData.path(to: "shenzhen"))
        } else {
            journey = CityRegionJourney(path: CityNewsMockData.path(to: "guangdong"))
        }
        #else
        journey = CityRegionJourney(path: CityNewsMockData.path(to: "guangdong"))
        #endif
        _journey = State(initialValue: journey)
        _selectedID = State(initialValue: Self.defaultSelection(for: journey))
    }

    var body: some View {
        let region = journey.current
        let regions = journey.mapRegions
        let selected = selectedRegion(in: regions)

        VStack(spacing: 0) {
            topBar

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    header(region)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    tabBar
                        .padding(.top, 8)

                    mapSection(scope: journey.mapScope, regions: regions, selected: selected)
                        .padding(.horizontal, 20)
                        .padding(.top, 10)

                    metricSection(region)
                        .padding(.horizontal, 20)
                        .padding(.top, 12)

                    exploreSection
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, max(bottomChromeHeight, 78) + 20)
                }
            }
            .scrollIndicators(.hidden)
        }
        .background(CityDesign.canvas.ignoresSafeArea())
        .tint(CityDesign.accent)
        .accessibilityIdentifier("city-region-screen")
        .sheet(isPresented: $showsList) {
            CityRegionList(
                title: journey.mapScope.level.childTitle ?? "区域列表",
                regions: journey.mapRegions,
                selection: selectedID,
                onSelect: { region in selectedID = region.id; showsList = false }
            )
        }
        .fullScreenCover(isPresented: $showsMap) {
            CityFullScreenMap(
                scope: journey.mapScope,
                regions: journey.mapRegions,
                selection: $selectedID
            )
        }
    }

    private var topBar: some View {
        ZStack {
            Text("城市观察")
                .font(.headline.weight(.bold))

            HStack {
                Button {
                    guard journey.goBack() else { return }
                    selectedID = Self.defaultSelection(for: journey)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 19, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(CityPressStyle())
                .accessibilityLabel("返回上一级地区")

                Spacer()

                ShareLink(
                    item: "\(journey.current.name)城市观察",
                    subject: Text(journey.current.name),
                    message: Text(journey.current.introduction)
                ) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(CityPressStyle())
                .accessibilityLabel("分享城市观察")
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 48)
        .background(CityDesign.canvas)
        .overlay(alignment: .bottom) {
            Rectangle().fill(CityDesign.divider).frame(height: 0.5)
        }
    }

    private static func defaultSelection(for journey: CityRegionJourney) -> String? {
        if journey.current.id == "guangdong" {
            return journey.current.children.first(where: { $0.id == "shenzhen" })?.id
        }
        return journey.selectedMapRegionID ?? journey.current.children.first?.id
    }

    private func selectedRegion(in regions: [CityRegion]) -> CityRegion? {
        if let selectedID, let region = regions.first(where: { $0.id == selectedID }) { return region }
        if let current = regions.first(where: { $0.id == journey.current.id }) { return current }
        return regions.first
    }

    @ViewBuilder
    private func header(_ region: CityRegion) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if journey.regionIDs.count > 1 {
                Button {
                    let leaving = journey.current
                    guard journey.goBack() else { return }
                    selectedID = journey.mapRegions.first(where: { $0.id == leaving.id })?.id
                        ?? Self.defaultSelection(for: journey)
                } label: {
                    Label(journey.parent?.name ?? "广东省", systemImage: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                }
                .buttonStyle(CityPressStyle())
                .padding(.bottom, 2)
            }

            Text(eyebrow(region))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CityDesign.accent)

            Text(region.name)
                .font(.system(size: 23, weight: .bold, design: .rounded))
                .padding(.top, 5)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("city-current-title")

            Text(compactIntro(region))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .padding(.top, 3)

            factCard(region)
                .padding(.top, 9)
        }
    }

    private func eyebrow(_ region: CityRegion) -> String {
        switch region.level {
        case .province: region.id == "guangdong" ? "中国 · 华南 · 省级行政区" : "中国 · 省级行政区"
        case .city: "\(journey.parent?.name ?? "广东省") · 地级市"
        case .district: "\(journey.parent?.name ?? "城市") · 区县"
        case .country: "中国 · 城市观察"
        }
    }

    private func compactIntro(_ region: CityRegion) -> String {
        if region.id == "guangdong" { return "华南沿海省份，湾区核心，制造业与科技活跃" }
        return region.introduction
    }

    private func headerFacts(_ region: CityRegion) -> [(String, String, String)] {
        if region.id == "guangdong" {
            return [("省会", "广州", "building.2.fill"), ("地级市", "21个", "square.3.layers.3d"), ("区域", "华南", "mappin.and.ellipse")]
        }
        if region.level == .city {
            return [("所属", journey.parent?.name ?? "广东省", "map.fill"), ("级别", "地级市", "building.2.fill"), ("下辖", region.children.isEmpty ? "城市概览" : "\(region.children.count)个区县", "square.3.layers.3d")]
        }
        return [("级别", region.level.rawValue, "map.fill"), ("内容", "区域观察", "scope"), ("动态", "\(region.news.count)条", "newspaper.fill")]
    }

    private func factCard(_ region: CityRegion) -> some View {
        let facts = headerFacts(region)
        return HStack(spacing: 0) {
            ForEach(Array(facts.enumerated()), id: \.offset) { index, item in
                HStack(spacing: 9) {
                    Image(systemName: item.2)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CityDesign.accent)
                        .frame(width: 27, height: 27)
                        .background(CityDesign.accentSoft, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.0).font(.system(size: 10)).foregroundStyle(.secondary)
                        Text(item.1).font(.system(size: 14, weight: .bold)).lineLimit(1).minimumScaleFactor(0.72)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity)
                if index < facts.count - 1 {
                    Rectangle().fill(CityDesign.divider).frame(width: 1, height: 25).padding(.horizontal, 5)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(CityDesign.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 15).stroke(Color.primary.opacity(0.04), lineWidth: 0.7) }
        .shadow(color: .black.opacity(0.035), radius: 8, y: 4)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(CityDashboardTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 5) {
                        Text(tab.rawValue)
                            .font(.system(size: 13, weight: selectedTab == tab ? .bold : .medium))
                            .foregroundStyle(selectedTab == tab ? CityDesign.accent : .secondary)
                        Capsule().fill(selectedTab == tab ? CityDesign.accent : .clear).frame(width: 34, height: 2.5)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(CityPressStyle())
            }
        }
        .padding(.horizontal, 18)
        .overlay(alignment: .bottom) { Rectangle().fill(CityDesign.divider).frame(height: 0.5) }
    }

    private func mapSection(
        scope: CityRegion,
        regions: [CityRegion],
        selected: CityRegion?
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(scope.level.childTitle ?? "区域地图").font(.system(size: 17, weight: .bold))
                Spacer()
                if !regions.isEmpty {
                    Button { showsList = true } label: {
                        HStack(spacing: 5) {
                            Text("查看全部 \(regions.count)个")
                            Image(systemName: "chevron.right").font(.caption.weight(.bold))
                        }
                        .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(CityPressStyle())
                }
            }

            VStack(spacing: 0) {
                ZStack(alignment: .bottomTrailing) {
                    CityDesign.mapGradient
                    Circle().fill(.white.opacity(0.45)).frame(width: 240, height: 240).blur(radius: 10).offset(x: 100, y: -120)
                    CityAdministrativeMap(
                        scope: scope,
                        selectedRegionID: selected?.id,
                        selectableRegions: regions,
                        onSelect: { selectedID = $0.id }
                    )
                    .padding(.horizontal, 7)
                    .padding(.vertical, 8)
                    Button { showsMap = true } label: {
                        Label("全屏地图", systemImage: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 7)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .buttonStyle(CityPressStyle())
                    .padding(9)
                }
                .frame(height: 190)

                if let selected {
                    selectedCard(selected)
                }
            }
            .background(CityDesign.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.04), lineWidth: 0.7) }
            .shadow(color: CityDesign.accent.opacity(0.075), radius: 11, y: 5)
        }
    }

    private func selectedCard(_ region: CityRegion) -> some View {
        HStack(spacing: 9) {
            Group {
                if region.id == "shenzhen" {
                    Image("ShenzhenSkyline")
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        LinearGradient(colors: [CityDesign.accent.opacity(0.85), .cyan.opacity(0.50)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        Image(systemName: region.level == .district ? "building.columns.fill" : "building.2.fill")
                            .font(.system(size: 27, weight: .medium))
                            .foregroundStyle(.white)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
            .frame(width: 65, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(region.name).font(.system(size: 16, weight: .bold)).lineLimit(1)
                    Text(region.id == journey.current.id ? "当前城市" : "当前选择")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(CityDesign.accent)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(CityDesign.accentSoft, in: Capsule())
                }
                Text(cardSubtitle(region)).font(.system(size: 9.5)).foregroundStyle(.secondary).lineLimit(1)
                Text(cardIntroduction(region)).font(.system(size: 10, weight: .medium)).lineLimit(1)
                ScrollView(.horizontal) {
                    HStack(spacing: 5) {
                        ForEach(region.facts.prefix(3), id: \.self) { fact in
                            Text(fact).font(.system(size: 8)).foregroundStyle(.secondary)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(CityDesign.secondarySurface, in: Capsule())
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if region.id != journey.current.id {
                Button {
                    if journey.current.children.contains(where: { $0.id == region.id }) {
                        guard journey.enter(region) else { return }
                    } else {
                        guard journey.selectPeer(region) else { return }
                    }
                    selectedID = Self.defaultSelection(for: journey)
                } label: {
                    HStack(spacing: 4) {
                        Text("进入城市")
                        Image(systemName: "chevron.right")
                    }
                    .font(.system(size: 10, weight: .bold))
                    .fixedSize()
                    .frame(minWidth: 50, minHeight: 36)
                }
                .buttonStyle(CityPressStyle())
                .accessibilityLabel("进入\(region.name)")
            }
        }
        .padding(8)
        .background(CityDesign.surface)
        .overlay(alignment: .top) { Rectangle().fill(CityDesign.divider).frame(height: 0.5) }
    }

    private func cardSubtitle(_ region: CityRegion) -> String {
        if region.id == "shenzhen" { return "广东省副省级市 · 经济特区" }
        return region.level == .district ? "区县级行政单位" : "广东省地级市"
    }

    private func cardIntroduction(_ region: CityRegion) -> String {
        if region.id == "shenzhen" { return "科技创新与先进制造业中心" }
        return region.introduction
    }

    private func metrics(_ region: CityRegion) -> [CityMetric] {
        if region.id == "guangdong" {
            return [
                .init(id: "population", title: "常住人口", value: "1.27", unit: "亿", note: "全国第1", symbol: "person.2.fill"),
                .init(id: "gdp", title: "GDP（2023）", value: "13.57", unit: "万亿", note: "全国第1", symbol: "yensign.circle.fill"),
                .init(id: "industry", title: "规模以上工业", value: "4.68", unit: "万亿", note: "全国第1", symbol: "building.2.fill"),
                .init(id: "trade", title: "外贸进出口", value: "8.35", unit: "万亿", note: "全国第1", symbol: "shippingbox.fill")
            ]
        }
        return [
            .init(id: "profile", title: "区域概况", value: region.level.rawValue, unit: "", note: region.facts.first ?? "城市观察", symbol: "map.fill"),
            .init(id: "focus", title: "发展重点", value: "产业", unit: "", note: "创新与协同", symbol: "chart.line.uptrend.xyaxis"),
            .init(id: "service", title: "公共服务", value: "持续", unit: "", note: "完善城市功能", symbol: "building.columns.fill"),
            .init(id: "updates", title: "今日动态", value: "\(region.news.count)", unit: "条", note: "原型内容", symbol: "newspaper.fill")
        ]
    }

    private func metricSection(_ region: CityRegion) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text("城市名片").font(.system(size: 17, weight: .bold))
                Text("快速了解\(region.name)").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Text("更多数据  ›").font(.system(size: 10, weight: .medium)).foregroundStyle(CityDesign.accent)
            }
            HStack(spacing: 8) {
                ForEach(metrics(region)) { metric in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: metric.symbol)
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(CityDesign.accent)
                                .frame(width: 20, height: 20)
                                .background(CityDesign.accentSoft, in: Circle())
                            Text(metric.title).font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 1) {
                            Text(metric.value).font(.system(size: 16, weight: .bold, design: .rounded)).minimumScaleFactor(0.68)
                            Text(metric.unit).font(.system(size: 8, weight: .semibold))
                        }
                        .lineLimit(1)
                        Text(metric.note).font(.system(size: 8)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
                    .padding(6)
                    .background(CityDesign.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.04), lineWidth: 0.7) }
                }
            }
        }
    }

    private var exploreSection: some View {
        let items = [
            ("景点地图", "探索旅游景点", "building.columns.fill"),
            ("城市对比", "多维度对比分析", "chart.bar.xaxis"),
            ("区域排行榜", "城市发展排名", "trophy.fill"),
            ("产业分布", "产业格局分析", "chart.pie.fill")
        ]
        let colors: [Color] = [.teal, CityDesign.accent, .orange, .indigo]
        return VStack(alignment: .leading, spacing: 7) {
            Text("探索广东").font(.system(size: 17, weight: .bold))
            HStack(spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.0).font(.system(size: 9.5, weight: .bold)).lineLimit(1)
                        Text(item.1).font(.system(size: 7.5)).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        HStack {
                            Spacer()
                            Image(systemName: item.2)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(colors[index].opacity(0.72))
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 37, alignment: .topLeading)
                    .padding(6)
                    .background(colors[index].opacity(0.065), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 11).stroke(colors[index].opacity(0.12), lineWidth: 0.7) }
                }
            }
        }
    }
}

private enum CityDesign {
    static let accent = Color(red: 0.04, green: 0.43, blue: 0.97)
    static let accentSoft = accent.opacity(0.10)
    static let canvas = Color(red: 0.982, green: 0.987, blue: 0.997)
    static let surface = Color(uiColor: .systemBackground)
    static let secondarySurface = Color(uiColor: .secondarySystemBackground)
    static let divider = Color(uiColor: .separator).opacity(0.18)
    static let mapFill = Color(red: 0.36, green: 0.63, blue: 0.94)
    static let mapGradient = LinearGradient(
        colors: [Color(red: 0.91, green: 0.96, blue: 1), Color(red: 0.85, green: 0.94, blue: 0.99), Color(red: 0.93, green: 0.98, blue: 1)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

private struct CityPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct CityRegionList: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let regions: [CityRegion]
    let selection: String?
    let onSelect: (CityRegion) -> Void

    var body: some View {
        NavigationStack {
            List(regions) { region in
                Button { onSelect(region) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "mappin.circle.fill").foregroundStyle(CityDesign.accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(region.name).font(.body.weight(.semibold)).foregroundStyle(.primary)
                            Text(region.introduction).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        if region.id == selection { Image(systemName: "checkmark.circle.fill").foregroundStyle(CityDesign.accent) }
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
    }
}

private struct CityFullScreenMap: View {
    @Environment(\.dismiss) private var dismiss
    let scope: CityRegion
    let regions: [CityRegion]
    @Binding var selection: String?

    var body: some View {
        NavigationStack {
            ZStack {
                CityDesign.mapGradient.ignoresSafeArea()
                CityAdministrativeMap(scope: scope, selectedRegionID: selection, selectableRegions: regions) { selection = $0.id }
                    .padding(18)
            }
            .navigationTitle(scope.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
    }
}

struct CityMapFeatureCollection: Decodable { let features: [CityMapFeature] }

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
            if try container.decode(String.self, forKey: .type) == "Polygon" {
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
    var labelCoordinate: [Double]? { properties.centroid ?? properties.center ?? allCoordinates.first }
}

struct CityMapRepository {
    static let shared = CityMapRepository()
    let features: [CityMapFeature]

    init(bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: "CityMapRegions", withExtension: "geojson"),
              let data = try? Data(contentsOf: url),
              let collection = try? JSONDecoder().decode(CityMapFeatureCollection.self, from: data)
        else { features = []; return }
        features = collection.features
    }

    func features(for region: CityRegion) -> [CityMapFeature] {
        switch region.level {
        case .country:
            features.filter { $0.properties.level == "province" }
        case .province:
            features.filter { $0.properties.level == "city" && $0.parentAdcode == region.adcode }
        case .city:
            {
                let districts = features.filter { $0.properties.level == "district" && $0.parentAdcode == region.adcode }
                if !districts.isEmpty { return districts }
                return features.filter { $0.properties.level == "city" && $0.parentAdcode == region.parentAdcode }
            }()
        case .district:
            features.filter { $0.properties.level == "district" && $0.parentAdcode == region.parentAdcode }
        }
    }

    func feature(adcode: Int) -> CityMapFeature? { features.first { $0.id == adcode } }
}

private struct CityAdministrativeMap: View {
    @ScaledMetric(relativeTo: .caption2) private var labelSize: CGFloat = 9
    let scope: CityRegion
    let selectedRegionID: String?
    let selectableRegions: [CityRegion]
    let onSelect: (CityRegion) -> Void

    private var features: [CityMapFeature] { CityMapRepository.shared.features(for: scope) }
    private var regionByAdcode: [Int: CityRegion] { Dictionary(uniqueKeysWithValues: selectableRegions.map { ($0.adcode, $0) }) }
    private var available: Set<Int> { Set(selectableRegions.map(\.adcode)) }
    private var selectedAdcode: Int? { selectedRegionID.flatMap(CityNewsMockData.region(withID:))?.adcode }

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
                            context.fill(path, with: .color(fill(feature)), style: FillStyle(eoFill: true))
                            context.stroke(path, with: .color(.white.opacity(0.92)), lineWidth: 0.85)
                        }
                    }
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(SpatialTapGesture().onEnded { select(at: $0.location, projection: projection) })
                        .accessibilityHidden(true)
                    ForEach(features.filter { available.contains($0.id) }) { feature in
                        if let coordinate = feature.labelCoordinate, let region = regionByAdcode[feature.id] {
                            mapLabel(feature.properties.name, selected: region.id == selectedRegionID)
                                .frame(minWidth: region.id == selectedRegionID ? 68 : 36, minHeight: 30)
                                .position(projection.point(for: coordinate))
                                .accessibilityLabel(region.id == selectedRegionID ? "\(region.name)，当前选择" : region.name)
                                .accessibilityHint("选择\(region.name)")
                                .accessibilityAddTraits(.isButton)
                                .accessibilityAction { onSelect(region) }
                        }
                    }
                }
            }
        }
    }

    private func fill(_ feature: CityMapFeature) -> Color {
        if feature.id == selectedAdcode { return CityDesign.accent.opacity(0.72) }
        if available.contains(feature.id) { return CityDesign.mapFill.opacity(0.34) }
        return CityDesign.mapFill.opacity(0.14)
    }

    private func select(at point: CGPoint, projection: CityMapProjection) {
        if let feature = features.reversed().first(where: { available.contains($0.id) && projection.path(for: $0).contains(point, eoFill: true) }),
           let region = regionByAdcode[feature.id] {
            onSelect(region)
            return
        }
        let nearest = features.filter { available.contains($0.id) }.compactMap { feature -> (CityMapFeature, CGFloat)? in
            guard let coordinate = feature.labelCoordinate else { return nil }
            let location = projection.point(for: coordinate)
            return (feature, hypot(location.x - point.x, location.y - point.y))
        }.filter { $0.1 <= 30 }.min { $0.1 < $1.1 }
        if let feature = nearest?.0, let region = regionByAdcode[feature.id] { onSelect(region) }
    }

    @ViewBuilder
    private func mapLabel(_ text: String, selected: Bool) -> some View {
        let value = text.replacingOccurrences(of: "省", with: "").replacingOccurrences(of: "市", with: "")
        if selected {
            Label(value, systemImage: "mappin.circle.fill")
                .font(.system(size: min(max(labelSize + 1, 10), 14), weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(CityDesign.accent, in: Capsule())
                .shadow(color: CityDesign.accent.opacity(0.25), radius: 6, y: 3)
                .allowsHitTesting(false)
        } else {
            HStack(spacing: 3) {
                Circle().fill(CityDesign.accent.opacity(0.76)).frame(width: 4, height: 4)
                Text(value).font(.system(size: min(max(labelSize, 8), 12), weight: .semibold)).foregroundStyle(Color.primary.opacity(0.78))
            }
            .padding(.horizontal, 3).padding(.vertical, 2)
            .background(.white.opacity(0.22), in: Capsule())
            .allowsHitTesting(false)
        }
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
        let padding = 12.0
        let width = max(sourceMaxX - sourceMinX, 0.001)
        let height = max(sourceMaxY - sourceMinY, 0.001)
        let fitted = min(max(Double(size.width) - padding * 2, 1) / width, max(Double(size.height) - padding * 2, 1) / height)
        minX = sourceMinX
        maxY = sourceMaxY
        scale = fitted
        offsetX = (Double(size.width) - width * fitted) / 2
        offsetY = (Double(size.height) - height * fitted) / 2
    }

    func point(for coordinate: [Double]) -> CGPoint {
        guard coordinate.count >= 2 else { return .zero }
        return CGPoint(x: (coordinate[0] - minX) * scale + offsetX, y: (maxY - coordinate[1]) * scale + offsetY)
    }

    func path(for feature: CityMapFeature) -> Path {
        var path = Path()
        for polygon in feature.geometry.polygons {
            for ring in polygon {
                guard let first = ring.first else { continue }
                path.move(to: point(for: first))
                for coordinate in ring.dropFirst() { path.addLine(to: point(for: coordinate)) }
                path.closeSubpath()
            }
        }
        return path
    }
}
