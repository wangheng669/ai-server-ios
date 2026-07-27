import SwiftUI

private struct IndustryChain: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let stages: [String]
    let related: [String]
}

struct IndustryPanoramaView: View {
    @State private var selectedID = IndustryChain.samples[0].id

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    private var selectedChain: IndustryChain {
        IndustryChain.samples.first(where: { $0.id == selectedID }) ?? IndustryChain.samples[0]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                overviewHeader
                chainFlow(selectedChain)
                industryGrid
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 104)
        }
        .scrollIndicators(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var overviewHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("中国产业全景")
                        .font(.system(size: 25, weight: .bold))
                    Text("从资源到应用，快速看懂产业之间的连接")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(HoldingsPalette.indigo)
                    .frame(width: 48, height: 48)
                    .background(HoldingsPalette.indigo.opacity(0.10), in: RoundedRectangle(cornerRadius: 15))
            }

            HStack(spacing: 0) {
                summaryValue("9", label: "重点产业")
                summaryDivider
                summaryValue("36", label: "关键环节")
                summaryDivider
                summaryValue("上·中·下游", label: "链路视角")
            }
            .padding(.vertical, 14)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private func summaryValue(_ value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: value.count > 4 ? 14 : 20, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var summaryDivider: some View {
        Rectangle()
            .fill(HoldingsPalette.divider)
            .frame(width: 1, height: 30)
    }

    private func chainFlow(_ chain: IndustryChain) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("产业链路")
                        .font(.system(size: 17, weight: .bold))
                    Text(chain.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(chain.color)
                }
                Spacer()
                Text("上游 → 下游")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 5) {
                ForEach(Array(chain.stages.enumerated()), id: \.offset) { index, stage in
                    VStack(spacing: 7) {
                        Text(stage)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                        Text(stageLabel(index))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 62)
                    .background(chain.color.opacity(0.09), in: RoundedRectangle(cornerRadius: 13))

                    if index < chain.stages.count - 1 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(chain.color.opacity(0.65))
                    }
                }
            }

            HStack(spacing: 7) {
                Text("关联")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                ForEach(chain.related, id: \.self) { item in
                    Text(item)
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: Capsule())
                }
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
        .animation(.easeOut(duration: 0.18), value: selectedID)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(chain.title)产业链路")
    }

    private var industryGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("重点产业")
                    .font(.system(size: 19, weight: .bold))
                Spacer()
                Text("点击切换链路")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(IndustryChain.samples) { chain in
                    industryButton(chain)
                }
            }
        }
    }

    private func industryButton(_ chain: IndustryChain) -> some View {
        let isSelected = selectedID == chain.id
        return Button {
            withAnimation(.easeOut(duration: 0.18)) {
                selectedID = chain.id
            }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: chain.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(chain.color)
                    .frame(width: 36, height: 36)
                    .background(chain.color.opacity(0.11), in: RoundedRectangle(cornerRadius: 11))

                VStack(alignment: .leading, spacing: 4) {
                    Text(chain.title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(chain.subtitle)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity, minHeight: 62)
            .background(
                isSelected ? chain.color.opacity(0.10) : Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 16)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? chain.color.opacity(0.50) : .clear, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(chain.title)，\(chain.subtitle)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func stageLabel(_ index: Int) -> String {
        switch index {
        case 0: "上游"
        case 1, 2: "中游"
        default: "下游"
        }
    }
}

private extension IndustryChain {
    static let samples: [IndustryChain] = [
        IndustryChain(id: "new-energy", title: "新能源汽车", subtitle: "电池 · 整车 · 补能", icon: "car.side.fill", color: HoldingsPalette.green, stages: ["锂矿", "动力电池", "整车", "充换电"], related: ["储能", "智能驾驶"]),
        IndustryChain(id: "semiconductor", title: "半导体", subtitle: "设备 · 芯片 · 终端", icon: "cpu.fill", color: HoldingsPalette.indigo, stages: ["材料设备", "芯片设计", "制造封测", "智能终端"], related: ["AI", "通信"]),
        IndustryChain(id: "ai", title: "人工智能", subtitle: "算力 · 模型 · 应用", icon: "sparkles", color: HoldingsPalette.purple, stages: ["算力芯片", "数据中心", "大模型", "行业应用"], related: ["机器人", "云计算"]),
        IndustryChain(id: "solar", title: "光伏储能", subtitle: "硅料 · 组件 · 电站", icon: "sun.max.fill", color: HoldingsPalette.orange, stages: ["硅料", "电池片", "组件", "电站储能"], related: ["电网", "新能源"]),
        IndustryChain(id: "robot", title: "机器人", subtitle: "零部件 · 本体 · 场景", icon: "figure.walk.motion", color: HoldingsPalette.blue, stages: ["核心部件", "机器人本体", "系统集成", "场景应用"], related: ["AI", "高端装备"]),
        IndustryChain(id: "biomedicine", title: "医药健康", subtitle: "研发 · 制造 · 医疗", icon: "cross.case.fill", color: HoldingsPalette.red, stages: ["原料研发", "药械制造", "流通服务", "医疗健康"], related: ["生物科技", "养老"]),
        IndustryChain(id: "aerospace", title: "航空航天", subtitle: "材料 · 制造 · 服务", icon: "airplane", color: HoldingsPalette.teal, stages: ["特种材料", "核心部件", "整机制造", "运营服务"], related: ["低空经济", "卫星"]),
        IndustryChain(id: "equipment", title: "高端装备", subtitle: "母机 · 自动化 · 工程", icon: "gearshape.2.fill", color: HoldingsPalette.pink, stages: ["工业母机", "核心零件", "装备制造", "工业服务"], related: ["机器人", "船舶"]),
        IndustryChain(id: "consumer", title: "消费制造", subtitle: "原料 · 品牌 · 零售", icon: "shippingbox.fill", color: .brown, stages: ["原料", "生产加工", "品牌渠道", "消费服务"], related: ["食品", "家电"])
    ]
}

#Preview {
    IndustryPanoramaView()
}
