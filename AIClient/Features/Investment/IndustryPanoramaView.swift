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
}

private struct IndustryFacts {
    let scaleValue: String
    let scaleMetric: String
    let period: String
    let source: String
    let sourceURL: URL?
    let companies: [IndustryCompany]
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

        enum CodingKeys: String, CodingKey {
            case id, name, role
            case stageID = "stage_id"
        }
    }

    let id: String
    let scale: Scale
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
                    companies: industry.companies.map {
                        IndustryCompany(id: $0.id, name: $0.name, role: $0.role)
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
            VStack(alignment: .leading, spacing: 14) {
                industryPicker
                chainOverview(selectedChain)
            }
            .padding(.top, 4)
            .padding(.bottom, 104)
        }
        .scrollIndicators(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
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
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(chain.title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(chain.color)
                Text("产业链全景")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                Text("上游 → 下游")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 15)

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("产业规模")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(chain.facts.scaleValue)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(chain.color)
                        Text(chain.facts.scaleMetric)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let sourceURL = chain.facts.sourceURL {
                        Link(destination: sourceURL) {
                            HStack(spacing: 3) {
                                Text("\(chain.facts.period) · \(chain.facts.source)")
                                Image(systemName: "arrow.up.right")
                            }
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                        }
                    } else {
                        Text("\(chain.facts.period) · \(chain.facts.source)")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 6)
                overviewMetric(value: "\(chain.stages.count)", label: "核心环节", icon: "square.grid.2x2.fill", color: chain.color)
                    .frame(width: 86)
            }
            .padding(.bottom, 12)

            Rectangle()
                .fill(HoldingsPalette.divider)
                .frame(height: 1)

            VStack(spacing: 0) {
                ForEach(Array(chain.stages.enumerated()), id: \.element.id) { index, stage in
                    stageRow(
                        stage,
                        color: chain.color,
                        isFirst: index == 0,
                        isLast: index == chain.stages.count - 1
                    )
                }
            }

            HStack(spacing: 7) {
                Text("关联")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                ForEach(chain.related, id: \.self) { item in
                    Text(item)
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(chain.color.opacity(0.08), in: Capsule())
                }
            }
            .padding(.top, 12)

            companySection(chain)
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
        .padding(.horizontal, 16)
        .animation(.easeOut(duration: 0.18), value: selectedID)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(chain.title)产业链全景")
    }

    private func overviewMetric(value: String, label: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 15, weight: .bold))
                Text(label)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var overviewDivider: some View {
        Rectangle()
            .fill(HoldingsPalette.divider)
            .frame(width: 1, height: 28)
    }

    private func companySection(_ chain: IndustryChain) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("知名企业")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Text("按产业链代表性展示")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ],
                spacing: 8
            ) {
                ForEach(chain.facts.companies) { company in
                    HStack(spacing: 9) {
                        Image(systemName: "building.2.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(chain.color)
                            .frame(width: 30, height: 30)
                            .background(chain.color.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(company.name)
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                            Text(company.role)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 9)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(.top, 16)
    }

    private func stageRow(
        _ stage: IndustryStage,
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
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    .frame(width: 13, height: 13)
                    .overlay(Circle().stroke(color, lineWidth: 2))
                Rectangle()
                    .fill(isLast ? Color.clear : color.opacity(0.7))
                    .frame(width: 2, height: 82)
            }
            .frame(width: 16)

            Image(systemName: stage.icon)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 48, height: 48)
                .background(color.opacity(0.10), in: Circle())
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(stage.title)
                        .font(.system(size: 16, weight: .bold))
                    Spacer()
                    Text(stage.level)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(color)
                        .padding(.horizontal, 7)
                        .frame(height: 22)
                        .background(color.opacity(0.08), in: Capsule())
                }

                Text(stage.description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 5) {
                    ForEach(stage.highlights, id: \.self) { highlight in
                        Text(highlight)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(color)
                            .padding(.horizontal, 7)
                            .frame(height: 22)
                            .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
                    }
                }

                Text("关联：\(stage.related)")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, 8)
            .padding(.bottom, isLast ? 2 : 8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(stage.level)，\(stage.title)，\(stage.description)")
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
        let levels = ["上游", "中游", "中游", "下游"]
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
            IndustryCompany(id: name, name: name, role: role)
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
