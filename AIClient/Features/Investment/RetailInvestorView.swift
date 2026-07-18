import SwiftUI

struct RetailInvestorView: View {
    private let topics = [
        RetailTopic(name: "AI算力", symbol: "brain.head.profile", heat: 86, change: 2.45, trend: [18, 24, 21, 29, 26, 34, 31, 38, 44, 40, 43, 51]),
        RetailTopic(name: "黄金", symbol: "shippingbox.fill", heat: 72, change: 0.83, trend: [20, 25, 22, 27, 24, 30, 35, 39, 34, 41, 45, 53]),
        RetailTopic(name: "港股创新药", symbol: "pills.fill", heat: 65, change: -1.32, trend: [54, 47, 39, 43, 36, 41, 34, 28, 31, 23, 18, 15])
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sentimentCard
                breadthCard
                attentionSection
                riskReminder
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 26)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var sentimentCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Label("散户情绪", systemImage: "info.circle")
                    .font(.system(size: 22, weight: .bold))
                Spacer()
                Text("更新于 7月17日 23:39")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 20) {
                Gauge(value: 68, in: 0...100) {
                    Text("散户情绪")
                } currentValueLabel: {
                    VStack(spacing: 0) {
                        Text("68")
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                        Text("偏乐观")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(Color.green)
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(AngularGradient(colors: [.red, .orange, .yellow, .green], center: .center))
                .frame(width: 150, height: 150)

                Divider().frame(height: 92)

                VStack(spacing: 7) {
                    Text("今日变化")
                        .font(.system(size: 15, weight: .medium))
                    Text("+6")
                        .font(.system(size: 38, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.green)
                    Text("较昨日 +8")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.16)) }
    }

    private var breadthCard: some View {
        HStack(spacing: 0) {
            breadthMetric("上涨", value: "2,356", change: "较昨日 +312", color: .red)
            Divider().frame(height: 58)
            breadthMetric("下跌", value: "1,285", change: "较昨日 −198", color: .green)
            Divider().frame(height: 58)
            breadthMetric("涨停", value: "76", change: "较昨日 +12", color: .red)
        }
        .padding(.vertical, 15)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.16)) }
    }

    private func breadthMetric(_ title: String, value: String, change: String, color: Color) -> some View {
        VStack(spacing: 5) {
            Text(title).font(.system(size: 14, weight: .medium))
            Text(value)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
            Text(change)
                .font(.system(size: 11.5))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
    }

    private var attentionSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("大家在关注")
                    .font(.system(size: 23, weight: .bold))
                Spacer()
                Label("更多", systemImage: "chevron.right")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 2)
            .padding(.bottom, 8)

            VStack(spacing: 0) {
                ForEach(Array(topics.enumerated()), id: \.element.id) { index, topic in
                    topicRow(topic)
                    if index < topics.count - 1 { Divider().padding(.leading, 54) }
                }
            }
            .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private func topicRow(_ topic: RetailTopic) -> some View {
        HStack(spacing: 12) {
            Image(systemName: topic.symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(topic.color)
                .frame(width: 42, height: 42)
                .background(topic.color.opacity(0.1), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(topic.name)
                    .font(.system(size: 16.5, weight: .semibold))
                Text("讨论热度  \(topic.heat)")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 3) {
                Text(topic.change.formatted(.number.sign(strategy: .always()).precision(.fractionLength(2))) + "%")
                    .font(.system(size: 15.5, weight: .medium, design: .rounded))
                    .foregroundStyle(topic.color)
                Text("今日涨跌")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }

            RetailSparkline(values: topic.trend, color: topic.color)
                .frame(width: 76, height: 38)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    private var riskReminder: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("今日风险提醒", systemImage: "exclamationmark.shield.fill")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(.primary)
            Label("情绪偏乐观，注意追高风险，避免冲动下单。", systemImage: "circle.fill")
            Label("市场分化加剧，控制仓位，关注高位回落信号。", systemImage: "circle.fill")
        }
        .font(.system(size: 14.5))
        .symbolRenderingMode(.monochrome)
        .foregroundStyle(.primary)
        .tint(.red)
        .padding(16)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(Color.red.opacity(0.16)) }
    }
}

private struct RetailTopic: Identifiable {
    let name: String
    let symbol: String
    let heat: Int
    let change: Double
    let trend: [Double]

    var id: String { name }
    var color: Color { change >= 0 ? .red : .green }
}

private struct RetailSparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        Canvas { context, size in
            guard let minimum = values.min(), let maximum = values.max(), values.count > 1 else { return }
            let range = max(maximum - minimum, 1)
            var path = Path()
            for (index, value) in values.enumerated() {
                let x = size.width * CGFloat(index) / CGFloat(values.count - 1)
                let y = size.height * (1 - CGFloat((value - minimum) / range))
                if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(path, with: .color(color), lineWidth: 2)
        }
        .accessibilityHidden(true)
    }
}
