import Charts
import SwiftUI

private struct IndustryStage: Identifiable {
    let id: String
    let title: String
    let level: String
    let description: String
    let icon: String
    let highlights: [String]
    let related: String
}

private struct IndustryCompany: Identifiable {
    let id: String
    let name: String
    let role: String
    let stageID: String?
    let ticker: String?

    init(id: String, name: String, role: String, stageID: String?, ticker: String? = nil) {
        self.id = id
        self.name = name
        self.role = role
        self.stageID = stageID
        self.ticker = ticker
    }
}

private struct IndustryHistoryPoint: Identifiable {
    let year: Int
    let value: Double
    let sourceURL: URL?

    var id: Int { year }
}

private struct IndustryStageGroup: Identifiable {
    let level: String
    let stages: [IndustryStage]
    let companies: [IndustryCompany]

    var id: String { level }
}

private struct IndustryFacts {
    let scaleValue: String
    let scaleMetric: String
    let period: String
    let source: String
    let sourceURL: URL?
    let history: [IndustryHistoryPoint]
    let companies: [IndustryCompany]

    init(
        scaleValue: String,
        scaleMetric: String,
        period: String,
        source: String,
        sourceURL: URL?,
        history: [IndustryHistoryPoint] = [],
        companies: [IndustryCompany]
    ) {
        self.scaleValue = scaleValue
        self.scaleMetric = scaleMetric
        self.period = period
        self.source = source
        self.sourceURL = sourceURL
        self.history = history
        self.companies = companies
    }
}

struct IndustryPanoramaResponse: Decodable {
    let success: Bool
    let data: IndustryPanoramaData
}

struct IndustryPanoramaData: Decodable {
    let version: String
    let industries: [IndustryFactPayload]
}

struct IndustryFactPayload: Decodable {
    struct Scale: Decodable {
        struct Source: Decodable {
            let name: String
            let url: URL?
        }

        let value: String
        let metric: String
        let period: String
        let source: Source
    }

    struct Company: Decodable {
        let id: String
        let name: String
        let role: String
        let stageID: String?
        let ticker: String?

        enum CodingKeys: String, CodingKey {
            case id, name, role, ticker
            case stageID = "stage_id"
        }
    }

    struct HistoryPoint: Decodable {
        let year: Int
        let value: Double
        let sourceURL: URL?

        enum CodingKeys: String, CodingKey {
            case year, value
            case sourceURL = "source_url"
        }
    }

    let id: String
    let scale: Scale
    let history: [HistoryPoint]?
    let companies: [Company]
}

private struct IndustryPanoramaService {
    let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = ServerConfiguration.currentURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func facts() async throws -> [String: IndustryFacts] {
        let url = baseURL.appending(path: "api/v1/industries/panorama")
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 8)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let payload = try JSONDecoder().decode(IndustryPanoramaResponse.self, from: data)
        guard payload.success else { throw URLError(.cannotParseResponse) }
        return Dictionary(uniqueKeysWithValues: payload.data.industries.map { industry in
            (
                industry.id,
                IndustryFacts(
                    scaleValue: industry.scale.value,
                    scaleMetric: industry.scale.metric,
                    period: industry.scale.period,
                    source: industry.scale.source.name,
                    sourceURL: industry.scale.source.url,
                    history: (industry.history ?? []).map {
                        IndustryHistoryPoint(year: $0.year, value: $0.value, sourceURL: $0.sourceURL)
                    },
                    companies: industry.companies.map {
                        IndustryCompany(
                            id: $0.id,
                            name: $0.name,
                            role: $0.role,
                            stageID: $0.stageID,
                            ticker: $0.ticker
                        )
                    }
                )
            )
        })
    }
}

private struct IndustryChain: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let stages: [IndustryStage]
    let related: [String]
    let facts: IndustryFacts
}

struct IndustryPanoramaView: View {
    @State private var selectedID = IndustryChain.samples[0].id
    @State private var remoteFacts: [String: IndustryFacts] = [:]

    private var selectedChain: IndustryChain {
        let chain = IndustryChain.samples.first(where: { $0.id == selectedID }) ?? IndustryChain.samples[0]
        guard let facts = remoteFacts[chain.id] else { return chain }
        return chain.replacingFacts(with: facts)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                industryPicker
                chainOverview(selectedChain)
            }
            .padding(.top, 8)
            .padding(.bottom, 104)
        }
        .scrollIndicators(.hidden)
        .background(Color(red: 0.975, green: 0.972, blue: 0.958))
        .task {
            guard let facts = try? await IndustryPanoramaService().facts(), !facts.isEmpty else { return }
            remoteFacts = facts
        }
    }

    private var industryPicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(IndustryChain.samples) { chain in
                    industryPickerButton(chain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
    }

    private func industryPickerButton(_ chain: IndustryChain) -> some View {
        let isSelected = selectedID == chain.id

        return Button {
            withAnimation(.easeOut(duration: 0.2)) {
                selectedID = chain.id
            }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: chain.icon)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(isSelected ? chain.color : Color.secondary)
                    .frame(width: 42, height: 42)
                    .background(
                        isSelected ? chain.color.opacity(0.12) : Color(uiColor: .tertiarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 13)
                    )

                Text(chain.title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? chain.color : Color.primary)
                    .lineLimit(1)
            }
            .frame(width: 68, height: 76)
            .padding(.vertical, 6)
            .background(
                isSelected ? chain.color.opacity(0.07) : Color.clear,
                in: RoundedRectangle(cornerRadius: 16)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(chain.title)，\(chain.subtitle)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func chainOverview(_ chain: IndustryChain) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            scaleSection(chain)

            VStack(spacing: 0) {
                ForEach(Array(stageGroups(for: chain).enumerated()), id: \.element.id) { index, group in
                    stageGroupRow(
                        group,
                        color: chain.color,
                        isFirst: index == 0,
                        isLast: index == stageGroups(for: chain).count - 1
                    )
                }
            }

            companyTickerStrip(chain)
                .padding(.top, 12)
        }
        .padding(.horizontal, 16)
        .animation(.easeOut(duration: 0.18), value: selectedID)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(chain.title)产业链全景")
    }

    private func scaleSection(_ chain: IndustryChain) -> some View {
        let parts = scaleValueParts(chain.facts.scaleValue)

        return VStack(alignment: .leading, spacing: 14) {
            Text("\(chain.facts.period) 产业规模")
                .font(.system(size: 17, weight: .semibold))

            HStack(alignment: .bottom, spacing: 18) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(parts.value)
                        .font(.system(size: 56, weight: .medium, design: .serif))
                        .foregroundStyle(chain.color)
                        .minimumScaleFactor(0.68)
                        .lineLimit(1)

                    Text(parts.unit)
                        .font(.system(size: 15, weight: .medium))
                }
                .frame(width: 145, alignment: .leading)

                if chain.facts.history.count >= 2 {
                    historyChart(chain.facts.history, color: chain.color)
                        .frame(maxWidth: .infinity)
                        .frame(height: 112)
                }
            }

            HStack(alignment: .firstTextBaseline) {
                Text(chain.facts.scaleMetric)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                sourceLink(chain.facts)
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 26)
        .overlay(alignment: .bottomLeading) {
            Capsule()
                .fill(Color.orange.opacity(0.8))
                .frame(width: 30, height: 3)
        }
    }

    private func historyChart(_ history: [IndustryHistoryPoint], color: Color) -> some View {
        Chart(history) { point in
            AreaMark(
                x: .value("年份", String(point.year)),
                y: .value("规模", point.value)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [color.opacity(0.18), color.opacity(0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            LineMark(
                x: .value("年份", String(point.year)),
                y: .value("规模", point.value)
            )
            .foregroundStyle(color)
            .lineStyle(StrokeStyle(lineWidth: 1.5))

            PointMark(
                x: .value("年份", String(point.year)),
                y: .value("规模", point.value)
            )
            .foregroundStyle(color)
            .symbolSize(24)
        }
        .chartXAxis {
            AxisMarks(values: history.map { String($0.year) }) { value in
                AxisValueLabel {
                    if let year = value.as(String.self) {
                        Text(year)
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartYScale(domain: 200...1_400)
        .chartYAxis {
            AxisMarks(position: .leading, values: [200, 600, 1_000, 1_400]) {
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2]))
                    .foregroundStyle(Color.secondary.opacity(0.18))
                AxisValueLabel()
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("历年\(history.first?.year ?? 0)至\(history.last?.year ?? 0)产业规模趋势")
    }

    private func scaleValueParts(_ value: String) -> (value: String, unit: String) {
        let units = ["万亿元", "亿元", "亿块", "万辆", "万家", "家"]
        for unit in units where value.hasSuffix(unit) {
            return (String(value.dropLast(unit.count)), unit)
        }
        return (value, "")
    }

    @ViewBuilder
    private func sourceLink(_ facts: IndustryFacts) -> some View {
        if let sourceURL = facts.sourceURL {
            Link(destination: sourceURL) {
                HStack(spacing: 4) {
                    Text("来源：\(facts.source)")
                    Image(systemName: "arrow.up.right")
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }
        } else {
            Text("来源：\(facts.source)")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private func companies(for stage: IndustryStage, in chain: IndustryChain) -> [IndustryCompany] {
        let exact = chain.facts.companies.filter { $0.stageID == stage.id }
        if !exact.isEmpty { return exact }
        guard chain.facts.companies.allSatisfy({ $0.stageID == nil }),
              let stageIndex = chain.stages.firstIndex(where: { $0.id == stage.id })
        else { return [] }
        return chain.facts.companies.enumerated().compactMap { companyIndex, company in
            let matchedIndex = chain.stages.firstIndex { candidate in
                company.role.contains(candidate.title)
                    || candidate.highlights.contains(where: { company.role.contains($0) || $0.contains(company.role) })
            }
            return (matchedIndex ?? min(companyIndex, chain.stages.count - 1)) == stageIndex ? company : nil
        }
    }

    private func stageGroups(for chain: IndustryChain) -> [IndustryStageGroup] {
        var levels: [String] = []
        var grouped: [String: [IndustryStage]] = [:]
        for stage in chain.stages {
            if grouped[stage.level] == nil { levels.append(stage.level) }
            grouped[stage.level, default: []].append(stage)
        }
        return levels.map { level in
            let stages = grouped[level] ?? []
            return IndustryStageGroup(
                level: level,
                stages: stages,
                companies: stages.flatMap { companies(for: $0, in: chain) }
            )
        }
    }

    private func stageGroupRow(
        _ group: IndustryStageGroup,
        color: Color,
        isFirst: Bool,
        isLast: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(isFirst ? Color.clear : color.opacity(0.7))
                    .frame(width: 2, height: 13)
                Circle()
                    .fill(Color(red: 0.975, green: 0.972, blue: 0.958))
                    .frame(width: 13, height: 13)
                    .overlay(Circle().stroke(color, lineWidth: 2))
                Rectangle()
                    .fill(isLast ? Color.clear : color.opacity(0.7))
                    .frame(width: 2, height: group.companies.isEmpty ? 124 : 172)
            }
            .frame(width: 16)

            HStack(alignment: .top, spacing: 12) {
                Text(group.level)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(color, in: Circle())

                VStack(alignment: .leading, spacing: 9) {
                    Text(group.stages.map(\.title).joined(separator: " · "))
                        .font(.system(size: 16, weight: .bold))

                    Text(group.stages.map(\.description).joined(separator: "；"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)

                    HStack(spacing: 5) {
                        ForEach(Array(Set(group.stages.flatMap(\.highlights))).sorted(), id: \.self) { highlight in
                            Text(highlight)
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(color)
                                .padding(.horizontal, 8)
                                .frame(height: 23)
                                .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
                        }
                    }

                    if !group.companies.isEmpty {
                        HStack(spacing: 12) {
                            ForEach(group.companies) { company in
                                companyAnchor(company, color: color)
                            }
                        }
                        .padding(.top, 5)
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, isLast ? 6 : 16)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(group.level)，\(group.stages.map(\.title).joined(separator: "、"))"
        )
    }

    private func companyTickerStrip(_ chain: IndustryChain) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                ForEach(chain.facts.companies) { company in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 5) {
                            Text(companyMonogram(company.name))
                                .foregroundStyle(chain.color)
                            Text(company.name)
                        }
                        .font(.system(size: 13, weight: .bold))

                        Text(company.ticker ?? company.role)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .frame(minWidth: 112, alignment: .leading)
                    .padding(.horizontal, 12)

                    if company.id != chain.facts.companies.last?.id {
                        Divider()
                            .frame(height: 36)
                    }
                }
            }
            .padding(.vertical, 13)
        }
        .scrollIndicators(.hidden)
        .background(Color.white.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func companyAnchor(_ company: IndustryCompany, color: Color) -> some View {
        HStack(spacing: 8) {
            Text(companyMonogram(company.name))
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(color.opacity(0.24)))

            VStack(alignment: .leading, spacing: 2) {
                Text(company.name)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Text(company.role)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func companyMonogram(_ name: String) -> String {
        let latin: [String: String] = [
            "比亚迪": "BYD", "宁德时代": "CATL", "上汽集团": "SAIC", "蔚来": "NIO"
        ]
        return latin[name] ?? String(name.prefix(2))
    }
}

private extension IndustryChain {
    static let samples: [IndustryChain] = [
        chain(
            id: "new-energy", title: "新能源汽车", subtitle: "电池 · 整车 · 补能",
            icon: "car.side.fill", color: HoldingsPalette.green,
            names: ["锂矿", "动力电池", "整车", "充换电"],
            icons: ["hammer.fill", "battery.100percent", "car.side.fill", "bolt.car.fill"],
            descriptions: ["矿产开采与提炼，为电池提供关键原材料", "电芯与电池系统制造，决定续航与安全表现", "整车研发制造，集成电动化与智能化技术", "充换电基础设施，支撑车辆运营与能源补给"],
            highlights: [["锂矿开采", "材料提纯"], ["正负极", "电芯制造"], ["三电系统", "整车制造"], ["充电桩", "换电站"]],
            stageRelated: ["有色金属 · 化工", "隔膜 · 设备制造", "芯片 · 智能驾驶", "电网 · 储能"],
            related: ["储能", "智能驾驶"]
        ),
        chain(
            id: "semiconductor", title: "半导体", subtitle: "设备 · 芯片 · 终端",
            icon: "cpu.fill", color: HoldingsPalette.indigo,
            names: ["材料设备", "芯片设计", "制造封测", "智能终端"],
            icons: ["gearshape.2.fill", "cpu", "square.stack.3d.up.fill", "iphone"],
            descriptions: ["提供晶圆、光刻胶与核心制造设备", "定义芯片架构、功能与计算能力", "完成晶圆制造、测试与产品封装", "芯片进入手机、汽车与智能设备"],
            highlights: [["硅片", "光刻设备"], ["EDA", "芯片架构"], ["晶圆制造", "先进封装"], ["消费电子", "汽车电子"]],
            stageRelated: ["新材料 · 精密仪器", "AI · 通信", "自动化 · 检测", "软件 · 消费电子"],
            related: ["AI", "通信"]
        ),
        chain(
            id: "ai", title: "人工智能", subtitle: "算力 · 模型 · 应用",
            icon: "sparkles", color: HoldingsPalette.purple,
            names: ["算力芯片", "数据中心", "大模型", "行业应用"],
            icons: ["cpu.fill", "server.rack", "brain.head.profile", "square.grid.2x2.fill"],
            descriptions: ["为训练与推理提供高性能计算底座", "组织服务器、网络与能源基础设施", "训练通用与垂直领域智能模型", "将模型能力嵌入生产与生活场景"],
            highlights: [["GPU", "加速芯片"], ["服务器", "高速网络"], ["训练", "推理"], ["智能助手", "工业智能"]],
            stageRelated: ["半导体 · 存储", "云计算 · 电力", "数据服务 · 软件", "机器人 · 自动驾驶"],
            related: ["机器人", "云计算"]
        ),
        chain(
            id: "solar", title: "光伏储能", subtitle: "硅料 · 组件 · 电站",
            icon: "sun.max.fill", color: HoldingsPalette.orange,
            names: ["硅料", "电池片", "组件", "电站储能"],
            icons: ["cube.fill", "circle.grid.cross.fill", "square.grid.3x3.fill", "bolt.fill"],
            descriptions: ["生产高纯硅与光伏制造基础材料", "将硅片制成实现光电转换的核心部件", "封装电池片形成可安装的光伏组件", "建设电站并通过储能调节电力输出"],
            highlights: [["多晶硅", "硅片"], ["电池技术", "转换效率"], ["封装", "逆变器"], ["电站", "储能系统"]],
            stageRelated: ["化工 · 能源", "设备 · 材料", "玻璃 · 电气", "电网 · 运维"],
            related: ["电网", "新能源"]
        ),
        chain(
            id: "robot", title: "机器人", subtitle: "零部件 · 本体 · 场景",
            icon: "figure.walk.motion", color: HoldingsPalette.blue,
            names: ["核心部件", "机器人本体", "系统集成", "场景应用"],
            icons: ["gearshape.fill", "figure.walk.motion", "point.3.connected.trianglepath.dotted", "building.2.fill"],
            descriptions: ["提供减速器、伺服系统与控制器", "完成结构设计、装配与运动控制", "将机器人接入产线和业务系统", "在工业、服务与家庭场景中落地"],
            highlights: [["减速器", "伺服"], ["结构设计", "控制"], ["产线集成", "调试"], ["制造", "服务"]],
            stageRelated: ["精密制造 · 电机", "传感器 · 软件", "自动化 · 工业软件", "AI · 消费电子"],
            related: ["AI", "高端装备"]
        ),
        chain(
            id: "biomedicine", title: "医药健康", subtitle: "研发 · 制造 · 医疗",
            icon: "cross.case.fill", color: HoldingsPalette.red,
            names: ["原料研发", "药械制造", "流通服务", "医疗健康"],
            icons: ["flask.fill", "cross.case.fill", "shippingbox.fill", "stethoscope"],
            descriptions: ["开展基础研究、药物发现与原料供应", "生产药品、器械与诊断产品", "连接生产企业、医院与零售终端", "为患者提供诊疗和健康管理服务"],
            highlights: [["药物发现", "原料药"], ["制药", "医疗器械"], ["医药商业", "零售"], ["诊疗", "健康管理"]],
            stageRelated: ["科研 · 化工", "制造 · 包装", "物流 · 零售", "保险 · 养老"],
            related: ["生物科技", "养老"]
        ),
        chain(
            id: "aerospace", title: "航空航天", subtitle: "材料 · 制造 · 服务",
            icon: "airplane", color: HoldingsPalette.teal,
            names: ["特种材料", "核心部件", "整机制造", "运营服务"],
            icons: ["hexagon.fill", "gearshape.fill", "airplane", "antenna.radiowaves.left.and.right"],
            descriptions: ["提供轻量化、高温与高强度材料", "制造发动机、航电与关键结构件", "完成飞机、火箭与卫星总装", "提供飞行、通信与遥感等服务"],
            highlights: [["合金", "复合材料"], ["发动机", "航电"], ["飞机", "卫星"], ["运营", "遥感"]],
            stageRelated: ["新材料 · 化工", "精密制造 · 芯片", "高端装备 · 软件", "通信 · 交通"],
            related: ["低空经济", "卫星"]
        ),
        chain(
            id: "equipment", title: "高端装备", subtitle: "母机 · 自动化 · 工程",
            icon: "gearshape.2.fill", color: HoldingsPalette.pink,
            names: ["工业母机", "核心零件", "装备制造", "工业服务"],
            icons: ["gearshape.2.fill", "wrench.and.screwdriver.fill", "building.2.fill", "person.2.fill"],
            descriptions: ["提供制造复杂零件的基础加工能力", "生产轴承、液压件与控制系统", "集成零部件形成专业生产设备", "提供安装、运维与改造服务"],
            highlights: [["机床", "数控系统"], ["轴承", "液压"], ["专用设备", "产线"], ["运维", "改造"]],
            stageRelated: ["钢铁 · 软件", "材料 · 电气", "自动化 · 工程", "检测 · 咨询"],
            related: ["机器人", "船舶"]
        ),
        chain(
            id: "consumer", title: "消费制造", subtitle: "原料 · 品牌 · 零售",
            icon: "shippingbox.fill", color: .brown,
            names: ["原料", "生产加工", "品牌渠道", "消费服务"],
            icons: ["leaf.fill", "building.2.fill", "megaphone.fill", "storefront.fill"],
            descriptions: ["提供农产品、化工与包装等基础材料", "将原料转化为标准化消费产品", "建立品牌并连接线上线下渠道", "围绕消费者提供零售与生活服务"],
            highlights: [["农产品", "包装"], ["食品", "家电"], ["品牌", "电商"], ["零售", "本地生活"]],
            stageRelated: ["农业 · 化工", "设备 · 物流", "广告 · 互联网", "支付 · 服务业"],
            related: ["食品", "家电"]
        )
    ]

    static func chain(
        id: String,
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        names: [String],
        icons: [String],
        descriptions: [String],
        highlights: [[String]],
        stageRelated: [String],
        related: [String]
    ) -> IndustryChain {
        let levels = id == "new-energy"
            ? ["上游", "上游", "中游", "下游"]
            : ["上游", "中游", "中游", "下游"]
        let stages = names.indices.map { index in
            IndustryStage(
                id: "\(id)-\(index)",
                title: names[index],
                level: levels[index],
                description: descriptions[index],
                icon: icons[index],
                highlights: highlights[index],
                related: stageRelated[index]
            )
        }

        return IndustryChain(
            id: id,
            title: title,
            subtitle: subtitle,
            icon: icon,
            color: color,
            stages: stages,
            related: related,
            facts: facts[id] ?? facts["new-energy"]!
        )
    }

    static let facts: [String: IndustryFacts] = [
        "new-energy": IndustryFacts(
            scaleValue: "1,286.6万辆",
            scaleMetric: "新能源汽车销量",
            period: "2024年",
            source: "工业和信息化部",
            sourceURL: URL(string: "https://www.miit.gov.cn/xwfb/bldhd/art/2025/art_303017acc5f44c95bf4c035c3345fb99.html"),
            history: [
                IndustryHistoryPoint(
                    year: 2021,
                    value: 352.1,
                    sourceURL: URL(string: "https://english.www.gov.cn/archive/statistics/202201/12/content_WS61ded71ec6d09c94e48a38a5.html")
                ),
                IndustryHistoryPoint(
                    year: 2022,
                    value: 688.7,
                    sourceURL: URL(string: "https://www.ndrc.gov.cn/fgsj/tjsj/cyfz/zzyfz/202301/t20230131_1348148.html")
                ),
                IndustryHistoryPoint(
                    year: 2023,
                    value: 949.5,
                    sourceURL: URL(string: "https://www.miit.gov.cn/ztzl/rdzt/xxgyhqk/tjyd/zjlt/art/2025/art_3cfeca22303f408ebd82978701e71ff9.html")
                ),
                IndustryHistoryPoint(
                    year: 2024,
                    value: 1_286.6,
                    sourceURL: URL(string: "https://www.miit.gov.cn/xwfb/bldhd/art/2025/art_303017acc5f44c95bf4c035c3345fb99.html")
                )
            ],
            companies: companies([
                ("比亚迪", "整车与电池"),
                ("宁德时代", "动力电池"),
                ("上汽集团", "整车制造"),
                ("蔚来", "整车与换电")
            ])
        ),
        "semiconductor": IndustryFacts(
            scaleValue: "4,514亿块",
            scaleMetric: "集成电路产量",
            period: "2024年",
            source: "国家统计局",
            sourceURL: URL(string: "https://www.miit.gov.cn/jgsj/yxj/xxfb/art/2025/art_805e7edc1e5444e9b2008354600487aa.html"),
            companies: companies([
                ("中芯国际", "晶圆制造"),
                ("海思", "芯片设计"),
                ("北方华创", "半导体设备"),
                ("长电科技", "封装测试")
            ])
        ),
        "ai": IndustryFacts(
            scaleValue: "近6,000亿元",
            scaleMetric: "人工智能核心产业",
            period: "2024年",
            source: "中国互联网络信息中心",
            sourceURL: URL(string: "https://www.miit.gov.cn/xwfb/mtbd/twbd/art/2025/art_e444c1d5f3df472f9824c777c41d89ae.html"),
            companies: companies([
                ("百度", "大模型与应用"),
                ("阿里云", "云算力与模型"),
                ("华为", "算力与大模型"),
                ("科大讯飞", "语音与行业应用")
            ])
        ),
        "solar": IndustryFacts(
            scaleValue: "万亿元级",
            scaleMetric: "光伏制造业产值",
            period: "2024年",
            source: "工业和信息化部",
            sourceURL: URL(string: "https://www.miit.gov.cn/gyhxxhb/jgsj/dzxxs/dzjc/art/2025/art_da51f7f47c75477ea1fa6732155536db.html"),
            companies: companies([
                ("隆基绿能", "硅片与组件"),
                ("通威股份", "硅料与电池片"),
                ("阳光电源", "逆变器与储能"),
                ("天合光能", "组件与系统")
            ])
        ),
        "robot": IndustryFacts(
            scaleValue: "2,379亿元",
            scaleMetric: "机器人行业营收",
            period: "2024年",
            source: "商务部服务贸易指南",
            sourceURL: URL(string: "https://tradeinservices.mofcom.gov.cn/article/lingyu/jsmyi/202510/179713.html"),
            companies: companies([
                ("新松机器人", "工业机器人"),
                ("埃斯顿", "本体与伺服"),
                ("汇川技术", "控制与驱动"),
                ("优必选", "人形机器人")
            ])
        ),
        "biomedicine": IndustryFacts(
            scaleValue: "2.5万亿元",
            scaleMetric: "医药制造业营收",
            period: "2024年",
            source: "国家统计局",
            sourceURL: URL(string: "https://filedownload-ytb.stats.gov.cn/attachment/10-2024%E5%B9%B4%E5%8C%96%E5%AD%A6%E5%88%B6%E8%8D%AF%E8%A1%8C%E4%B8%9A%E7%BB%8F%E6%B5%8E%E8%BF%90%E8%A1%8C%E6%8A%A5%E5%91%8A.pdf"),
            companies: companies([
                ("恒瑞医药", "创新药"),
                ("迈瑞医疗", "医疗器械"),
                ("药明康德", "研发服务"),
                ("国药集团", "流通与健康")
            ])
        ),
        "aerospace": IndustryFacts(
            scaleValue: "约1,200家",
            scaleMetric: "规上航空航天企业",
            period: "2023年末",
            source: "第五次全国经济普查",
            sourceURL: URL(string: "https://www.stats.gov.cn/sj/tjgb/jjpcgb/qgjpgb/202605/t20260508_1963635.html"),
            companies: companies([
                ("中国航天科技", "火箭与卫星"),
                ("中国航空工业", "航空装备"),
                ("中国商飞", "民用飞机"),
                ("银河航天", "商业卫星")
            ])
        ),
        "equipment": IndustryFacts(
            scaleValue: "约1.45万家",
            scaleMetric: "规上高端装备企业",
            period: "2023年末",
            source: "第五次全国经济普查",
            sourceURL: URL(string: "https://www.stats.gov.cn/sj/tjgb/jjpcgb/qgjpgb/202605/t20260508_1963635.html"),
            companies: companies([
                ("三一重工", "工程机械"),
                ("中国中车", "轨道装备"),
                ("海天精工", "工业母机"),
                ("汇川技术", "工业自动化")
            ])
        ),
        "consumer": IndustryFacts(
            scaleValue: "2.19万亿元",
            scaleMetric: "规上食品制造业营收",
            period: "2024年",
            source: "国家统计局",
            sourceURL: URL(string: "https://www.stats.gov.cn/sj/zxfb/202501/t20250127_1958485.html"),
            companies: companies([
                ("美的集团", "家电制造"),
                ("海尔智家", "家电与渠道"),
                ("伊利股份", "食品制造"),
                ("安踏体育", "品牌与零售")
            ])
        )
    ]

    static func companies(_ values: [(String, String)]) -> [IndustryCompany] {
        values.map { name, role in
            IndustryCompany(id: name, name: name, role: role, stageID: nil)
        }
    }

    func replacingFacts(with facts: IndustryFacts) -> IndustryChain {
        IndustryChain(
            id: id,
            title: title,
            subtitle: subtitle,
            icon: icon,
            color: color,
            stages: stages,
            related: related,
            facts: facts
        )
    }
}

#Preview {
    IndustryPanoramaView()
}
