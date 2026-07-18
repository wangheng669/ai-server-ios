import SwiftUI

struct DeploymentStatusSnapshot: Equatable {
    enum Phase: Equatable {
        case running(progress: Double)
        case succeeded
        case failed
    }

    let phase: Phase
    let commit: String

    var title: String {
        switch phase {
        case .running: "自动更新"
        case .succeeded: "更新完成"
        case .failed: "更新失败"
        }
    }

    var detail: String {
        switch phase {
        case let .running(progress): "正在安装到 iPhone · \(Int(progress * 100))%"
        case .succeeded: "新版本已安装到此 iPhone"
        case .failed: "未能安装到此 iPhone"
        }
    }

    var progress: Double {
        switch phase {
        case let .running(progress): progress
        case .succeeded: 1
        case .failed: 0
        }
    }

    var tint: Color {
        switch phase {
        case .running: .blue
        case .succeeded: .green
        case .failed: .red
        }
    }
}

struct DeploymentStatusTip: View {
    let snapshot: DeploymentStatusSnapshot
    @State private var isExpanded: Bool

    init(snapshot: DeploymentStatusSnapshot, initiallyExpanded: Bool = false) {
        self.snapshot = snapshot
        _isExpanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 7) {
            Button {
                withAnimation(.snappy(duration: 0.24)) { isExpanded.toggle() }
            } label: {
                statusIndicator
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "收起自动更新状态" : "查看自动更新状态")

            if isExpanded {
                expandedTip
                    .transition(.scale(scale: 0.92, anchor: .topTrailing).combined(with: .opacity))
            }
        }
    }

    private var statusIndicator: some View {
        ZStack {
            Circle()
                .stroke(snapshot.tint.opacity(0.18), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: max(0.07, snapshot.progress))
                .stroke(snapshot.tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if case .succeeded = snapshot.phase {
                Image(systemName: "checkmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(snapshot.tint)
            }
            if case .failed = snapshot.phase {
                Image(systemName: "exclamationmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(snapshot.tint)
            }
        }
        .frame(width: 18, height: 18)
        .contentShape(Circle())
        .frame(width: 36, height: 36)
    }

    private var expandedTip: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text(snapshot.title)
                    .font(.system(size: 15, weight: .semibold))
                Spacer(minLength: 12)
                Button {
                    withAnimation(.snappy(duration: 0.2)) { isExpanded = false }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭")
            }

            Text(snapshot.detail)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            if case .running = snapshot.phase {
                ProgressView(value: snapshot.progress)
                    .tint(snapshot.tint)
            }

            Text(snapshot.commit)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(width: 230, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.24), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.10), radius: 14, y: 6)
        .accessibilityElement(children: .contain)
    }
}

