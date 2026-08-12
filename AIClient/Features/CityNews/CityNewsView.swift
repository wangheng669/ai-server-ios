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

    var introductionTitle: String { "\(name)简介" }
    var newsTitle: String { "\(name) · 今日新闻" }
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
    @State private var path: [CityRegion]
    private let directlyPresentedPreviewRegion: CityRegion?

    init() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--city-district-preview") {
            _path = State(initialValue: CityNewsMockData.path(to: "shenzhen-440305"))
            directlyPresentedPreviewRegion = nil
        } else if arguments.contains("--city-city-preview") {
            _path = State(initialValue: CityNewsMockData.path(to: "shenzhen"))
            directlyPresentedPreviewRegion = nil
        } else if arguments.contains("--city-province-preview") {
            _path = State(initialValue: [])
            directlyPresentedPreviewRegion = CityNewsMockData.path(to: "guangdong").last
        } else {
            _path = State(initialValue: [])
            directlyPresentedPreviewRegion = nil
        }
        #else
        _path = State(initialValue: [])
        directlyPresentedPreviewRegion = nil
        #endif
    }

    var body: some View {
        Group {
            if let directlyPresentedPreviewRegion {
                NavigationStack {
                    CityRegionPage(region: directlyPresentedPreviewRegion)
                }
            } else {
                NavigationStack(path: $path) {
                    CityRegionPage(region: CityNewsMockData.root)
                        .navigationDestination(for: CityRegion.self) { region in
                            CityRegionPage(region: region)
                        }
                }
            }
        }
        .tint(CityNewsDesign.accent)
    }
}

private enum CityNewsDesign {
    static let accent = Color(red: 0.83, green: 0.26, blue: 0.18)
    static let accentSoft = accent.opacity(0.10)
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .systemBackground)
    static let divider = Color(uiColor: .separator).opacity(0.35)
}

private struct CityRegionPage: View {
    let region: CityRegion

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                CityRegionBreadcrumb(region: region)
                CityRegionMapCard(region: region)
                CityRegionIntroductionCard(region: region)

                if !region.children.isEmpty {
                    CityRegionChildrenSection(region: region)
                }

                CityRegionNewsSection(region: region)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(CityNewsDesign.canvas)
        .navigationTitle(region.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct CityRegionBreadcrumb: View {
    let region: CityRegion

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "location.fill")
                .font(.caption2)
                .foregroundStyle(CityNewsDesign.accent)
            Text(region.level.rawValue)
            Text("/")
            Text(region.name)
                .foregroundStyle(.primary)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}

private struct CityRegionMapCard: View {
    let region: CityRegion

    var body: some View {
        CityAdministrativeMap(region: region)
        .frame(height: region.level == .country ? 226 : 206)
        .frame(maxWidth: .infinity)
        .background(CityNewsDesign.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(CityNewsDesign.divider, lineWidth: 0.6)
        }
        .accessibilityLabel("\(region.name)行政区地图")
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
}

private struct CityAdministrativeMap: View {
    let region: CityRegion

    private var features: [CityMapFeature] { CityMapRepository.shared.features(for: region) }
    private var childByAdcode: [Int: CityRegion] { Dictionary(uniqueKeysWithValues: region.children.map { ($0.adcode, $0) }) }
    private var availableAdcodes: Set<Int> { Set(region.children.map(\.adcode)) }

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

                    ForEach(markerFeatures) { feature in
                        if let coordinate = feature.labelCoordinate {
                            if let child = childByAdcode[feature.id] {
                                NavigationLink(value: child) {
                                    mapLabel(feature.properties.name, selected: false)
                                }
                                .buttonStyle(.plain)
                                .position(projection.point(for: coordinate))
                                .accessibilityHint("进入并查看\(child.name)简介和新闻")
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
                            Text("行政区边界 · 原型数据")
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
        if region.children.isEmpty {
            return features.filter { $0.id == region.adcode }
        }
        return features.filter { availableAdcodes.contains($0.id) }
    }

    private func fillColor(for feature: CityMapFeature) -> Color {
        if feature.id == region.adcode { return CityNewsDesign.accent.opacity(0.78) }
        if availableAdcodes.contains(feature.id) { return CityNewsDesign.accent.opacity(0.32) }
        return Color.secondary.opacity(0.13)
    }

    private func mapLabel(_ text: String, selected: Bool) -> some View {
        Text(text.replacingOccurrences(of: "省", with: "").replacingOccurrences(of: "市", with: ""))
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(selected ? .white : CityNewsDesign.accent)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(selected ? CityNewsDesign.accent : Color.white.opacity(0.94), in: Capsule())
            .overlay { Capsule().stroke(CityNewsDesign.accent.opacity(0.35), lineWidth: 0.5) }
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

private struct CityRegionIntroductionCard: View {
    let region: CityRegion

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(region.introductionTitle, systemImage: "info.circle.fill")
                .font(.headline)
                .foregroundStyle(.primary)

            Text(region.introduction)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            HStack(spacing: 8) {
                ForEach(region.facts, id: \.self) { fact in
                    Text(fact)
                    if fact != region.facts.last {
                        Circle().fill(.tertiary).frame(width: 3, height: 3)
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(CityNewsDesign.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(CityNewsDesign.divider, lineWidth: 0.6)
        }
    }
}

private struct CityRegionChildrenSection: View {
    let region: CityRegion

    private let columns = [GridItem(.adaptive(minimum: 102), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(region.level.childTitle ?? "")
                .font(.headline)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(region.children) { child in
                    NavigationLink(value: child) {
                        HStack(spacing: 5) {
                            Text(child.name)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.bold))
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 11)
                        .frame(height: 40)
                        .background(CityNewsDesign.surface, in: RoundedRectangle(cornerRadius: 11))
                        .overlay {
                            RoundedRectangle(cornerRadius: 11)
                                .stroke(CityNewsDesign.divider, lineWidth: 0.6)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("进入并查看\(child.name)简介和新闻")
                }
            }
        }
    }
}

private struct CityRegionNewsSection: View {
    let region: CityRegion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(region.newsTitle)
                    .font(.title3.weight(.bold))
                Spacer()
                Text("\(region.news.count)条更新")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                ForEach(Array(region.news.enumerated()), id: \.element.id) { index, item in
                    CityRegionNewsRow(item: item, isLead: index == 0)
                    if index < region.news.count - 1 {
                        Divider().padding(.leading, index == 0 ? 94 : 0)
                    }
                }
            }
            .padding(14)
            .background(CityNewsDesign.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(CityNewsDesign.divider, lineWidth: 0.6)
            }
        }
    }
}

private struct CityRegionNewsRow: View {
    let item: CityRegionNews
    let isLead: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if isLead {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            LinearGradient(
                                colors: [CityNewsDesign.accentSoft, Color.blue.opacity(0.12)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: item.symbol)
                        .font(.system(size: 27))
                        .foregroundStyle(CityNewsDesign.accent)
                }
                .frame(width: 82, height: 76)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text("\(item.source)  ·  \(item.relativeTime)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }
}
