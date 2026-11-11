import SwiftUI

/// Static placeholders reserve the content layout without a perpetual animation.
struct ContentLoadingPlaceholder: View {
    enum Layout { case list, cards, article, chart }

    var title = "正在载入内容"
    var layout: Layout = .list
    var rowCount = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            switch layout {
            case .list:
                ForEach(0..<rowCount, id: \.self) { _ in
                    HStack(alignment: .top, spacing: 12) {
                        block(height: 40).frame(width: 40)
                        lines
                    }
                }
            case .cards:
                LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 14) {
                    ForEach(0..<4, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 14) {
                            block(height: 32).frame(width: 32)
                            lines
                        }
                        .padding(14)
                        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 14))
                    }
                }
            case .article:
                block(height: 22).padding(.trailing, 70)
                ForEach(0..<rowCount, id: \.self) { _ in lines }
            case .chart:
                HStack(spacing: 14) {
                    block(height: 24)
                    block(height: 24)
                    block(height: 24)
                }
                block(height: 140)
            }
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }

    private var lines: some View {
        VStack(alignment: .leading, spacing: 10) {
            block(height: 14).padding(.trailing, 24)
            block(height: 10)
            block(height: 10).padding(.trailing, 58)
        }
    }

    private func block(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: min(height / 3, 10))
            .fill(Color.primary.opacity(0.055))
            .frame(height: height)
    }
}

struct InlineActionNotice: View {
    let message: String
    let retry: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .accessibilityHidden(true)
            Text(message)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("重试", action: retry)
                .fontWeight(.semibold)
                .foregroundStyle(Color.accentColor)
                .frame(minHeight: 44)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("收起提示")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .buttonStyle(.plain)
        .padding(.leading, 12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
    }
}
