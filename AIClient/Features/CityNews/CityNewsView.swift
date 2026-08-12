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
            name: "广东省",
            introduction: "中国南部沿海省份，粤港澳大湾区核心区域。制造业、科技与外贸活跃。",
            facts: ["省会 广州", "21个地级市"],
            cities: [
                city("shenzhen", "深圳市", "粤港澳大湾区核心城市，以科技创新、金融与现代服务业著称。", ["常住人口 1,779万", "9个行政区"], ["南山区", "福田区", "罗湖区", "宝安区", "龙岗区"]),
                city("guangzhou", "广州市", "广东省省会和国家中心城市，是华南地区重要的商贸、交通与文化中心。", ["常住人口 1,898万", "11个行政区"], ["天河区", "越秀区", "海珠区", "白云区"]),
                city("foshan", "佛山市", "珠江三角洲重要制造业城市，以装备制造、家电和陶瓷产业见长。", ["常住人口 961万", "5个行政区"], ["禅城区", "南海区", "顺德区"]),
                city("dongguan", "东莞市", "粤港澳大湾区制造业基地，电子信息和先进制造产业集聚。", ["常住人口 1,050万", "4个片区"], ["南城街道", "松山湖", "虎门镇"])
            ]
        )

        let beijing = province(
            id: "beijing",
            name: "北京市",
            introduction: "中华人民共和国首都，全国政治、文化、国际交往和科技创新中心。",
            facts: ["直辖市", "16个行政区"],
            cities: [city("beijing-city", "北京城区", "首都功能核心区域，汇集公共文化、科技创新与现代服务资源。", ["国家中心城市", "16个行政区"], ["海淀区", "朝阳区", "东城区", "西城区"])]
        )

        let shanghai = province(
            id: "shanghai",
            name: "上海市",
            introduction: "中国重要的国际经济、金融、贸易、航运和科技创新中心。",
            facts: ["直辖市", "16个行政区"],
            cities: [city("shanghai-city", "上海城区", "长江三角洲核心城市，现代服务业、先进制造业和国际贸易高度集聚。", ["国际金融中心", "16个行政区"], ["浦东新区", "黄浦区", "徐汇区", "静安区"])]
        )

        let zhejiang = province(
            id: "zhejiang",
            name: "浙江省",
            introduction: "中国东南沿海省份，数字经济、民营经济和港口贸易优势突出。",
            facts: ["省会 杭州", "11个地级市"],
            cities: [
                city("hangzhou", "杭州市", "浙江省省会，数字经济和文化旅游产业发达。", ["常住人口 1,262万", "13个区县"], ["西湖区", "余杭区", "滨江区"]),
                city("ningbo", "宁波市", "长三角南翼经济中心和国际港口城市。", ["副省级城市", "10个区县"], ["鄞州区", "海曙区", "北仑区"])
            ]
        )

        let sichuan = province(
            id: "sichuan",
            name: "四川省",
            introduction: "中国西部重要经济、人口和文化大省，电子信息、能源与文旅资源丰富。",
            facts: ["省会 成都", "21个市州"],
            cities: [city("chengdu", "成都市", "成渝地区双城经济圈核心城市，电子信息和现代服务业发达。", ["国家中心城市", "23个区县"], ["高新区", "锦江区", "武侯区", "天府新区"])]
        )

        let shaanxi = province(
            id: "shaanxi",
            name: "陕西省",
            introduction: "连接中国东西部的重要省份，科教、航空航天、能源和历史文化资源突出。",
            facts: ["省会 西安", "10个地级市"],
            cities: [city("xian", "西安市", "国家中心城市和重要科研教育基地，历史文化与硬科技产业并重。", ["常住人口 1,308万", "13个区县"], ["雁塔区", "碑林区", "未央区", "高新区"])]
        )

        return CityRegion(
            id: "china",
            name: "全国",
            level: .country,
            introduction: "这里按省份、城市和区县逐级查看地区概况与当天新闻，每一级都有独立内容。",
            facts: ["省级行政区", "三级地区新闻"],
            news: news(for: "全国", seed: "区域发展"),
            children: [guangdong, beijing, shanghai, zhejiang, sichuan, shaanxi]
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
        name: String,
        introduction: String,
        facts: [String],
        cities: [CityRegion]
    ) -> CityRegion {
        CityRegion(
            id: id,
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
        _ name: String,
        _ introduction: String,
        _ facts: [String],
        _ districtNames: [String]
    ) -> CityRegion {
        CityRegion(
            id: id,
            name: name,
            level: .city,
            introduction: introduction,
            facts: facts,
            news: news(for: name, seed: "产业创新"),
            children: districtNames.enumerated().map { index, districtName in
                district(
                    id: "\(id)-\(index)",
                    name: districtName,
                    cityName: name,
                    index: index
                )
            }
        )
    }

    private static func district(id: String, name: String, cityName: String, index: Int) -> CityRegion {
        let featured = name == "南山区"
        return CityRegion(
            id: id,
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
            _path = State(initialValue: CityNewsMockData.path(to: "shenzhen-0"))
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
        ZStack {
            CityRegionMapShape(level: region.level)
                .fill(CityNewsDesign.accentSoft)
                .overlay {
                    CityRegionMapShape(level: region.level)
                        .stroke(CityNewsDesign.accent.opacity(0.45), lineWidth: 1)
                }
                .padding(.horizontal, 34)
                .padding(.vertical, 12)

            VStack(spacing: 5) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(CityNewsDesign.accent)
                Text(region.name)
                    .font(.subheadline.weight(.semibold))
            }
        }
        .frame(height: 146)
        .frame(maxWidth: .infinity)
        .background(CityNewsDesign.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(CityNewsDesign.divider, lineWidth: 0.6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(region.name)地图示意")
    }
}

private struct CityRegionMapShape: Shape {
    let level: CityRegionLevel

    func path(in rect: CGRect) -> Path {
        let points: [CGPoint]
        switch level {
        case .country:
            points = [
                .init(x: 0.05, y: 0.38), .init(x: 0.17, y: 0.20), .init(x: 0.36, y: 0.29),
                .init(x: 0.48, y: 0.14), .init(x: 0.66, y: 0.21), .init(x: 0.76, y: 0.34),
                .init(x: 0.94, y: 0.30), .init(x: 0.88, y: 0.53), .init(x: 0.73, y: 0.60),
                .init(x: 0.66, y: 0.82), .init(x: 0.48, y: 0.72), .init(x: 0.30, y: 0.77),
                .init(x: 0.18, y: 0.61), .init(x: 0.08, y: 0.58)
            ]
        case .province:
            points = [
                .init(x: 0.06, y: 0.45), .init(x: 0.17, y: 0.23), .init(x: 0.38, y: 0.30),
                .init(x: 0.55, y: 0.18), .init(x: 0.76, y: 0.26), .init(x: 0.93, y: 0.47),
                .init(x: 0.81, y: 0.68), .init(x: 0.59, y: 0.71), .init(x: 0.43, y: 0.85),
                .init(x: 0.25, y: 0.69), .init(x: 0.11, y: 0.65)
            ]
        case .city:
            points = [
                .init(x: 0.10, y: 0.29), .init(x: 0.29, y: 0.16), .init(x: 0.48, y: 0.28),
                .init(x: 0.68, y: 0.19), .init(x: 0.91, y: 0.39), .init(x: 0.83, y: 0.69),
                .init(x: 0.62, y: 0.76), .init(x: 0.44, y: 0.68), .init(x: 0.24, y: 0.83),
                .init(x: 0.07, y: 0.59)
            ]
        case .district:
            points = [
                .init(x: 0.19, y: 0.18), .init(x: 0.49, y: 0.10), .init(x: 0.79, y: 0.24),
                .init(x: 0.91, y: 0.52), .init(x: 0.72, y: 0.82), .init(x: 0.42, y: 0.75),
                .init(x: 0.14, y: 0.88), .init(x: 0.06, y: 0.48)
            ]
        }

        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: CGPoint(x: rect.minX + first.x * rect.width, y: rect.minY + first.y * rect.height))
        for point in points.dropFirst() {
            path.addLine(to: CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height))
        }
        path.closeSubpath()
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
