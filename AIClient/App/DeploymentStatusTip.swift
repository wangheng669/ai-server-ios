import Combine
import SwiftUI

struct DeploymentStatusSnapshot: Equatable {
    enum Phase: Equatable {
        case running(progress: Double)
        case succeeded
        case failed
    }

    let phase: Phase
    let commit: String
    let updatedAt: Date
    let stage: String?

    init(phase: Phase, commit: String, updatedAt: Date = Date(), stage: String? = nil) {
        self.phase = phase
        self.commit = commit
        self.updatedAt = updatedAt
        self.stage = stage
    }

    init?(message: DeploymentStatusMessage) {
        let date = Self.date(from: message.updatedAt) ?? Date()
        switch message.phase {
        case "running": phase = .running(progress: message.progress)
        case "succeeded": phase = .succeeded
        case "failed": phase = .failed
        default: return nil
        }
        commit = String(message.commit.prefix(7))
        updatedAt = date
        stage = message.stage
    }

    var identity: String {
        "\(commit)-\(updatedAt.timeIntervalSince1970)-\(stage ?? "")-\(title)"
    }

    func isVisible(at date: Date = Date()) -> Bool {
        let age = date.timeIntervalSince(updatedAt)
        guard age >= -60 else { return false }
        switch phase {
        case .running: return age <= 30 * 60
        case .succeeded, .failed: return age <= 10 * 60
        }
    }

    private static func date(from value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    var title: String {
        switch phase {
        case .running: "自动更新"
        case .succeeded: "更新完成"
        case .failed: "更新失败"
        }
    }

    var detail: String {
        switch phase {
        case let .running(progress): "\(runningStageTitle) · \(Int(progress * 100))%"
        case .succeeded: "新版本已安装到此 iPhone"
        case .failed: "未能安装到此 iPhone"
        }
    }

    private var runningStageTitle: String {
        switch stage {
        case "testing": "正在运行测试"
        case "building": "正在构建 App"
        case "waiting-for-installer": "正在等待安装设备"
        case "downloading": "正在下载安装包"
        case "signing": "正在签名"
        case "installing": "正在安装到 iPhone"
        default: "正在准备更新"
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

struct DeploymentStatusMessage: Decodable {
    let type: String
    let phase: String
    let stage: String?
    let progress: Double
    let commit: String
    let runId: String?
    let updatedAt: String
}

private struct DeploymentStatusResponse: Decodable {
    let success: Bool
    let data: DeploymentStatusMessage
}

@MainActor
final class DeploymentStatusStore: ObservableObject {
    @Published private(set) var snapshot: DeploymentStatusSnapshot?

    private let baseURL: URL
    private let session: URLSession
    private var realtimeClient: RealtimeFeedClient?
    private var snapshotTask: Task<Void, Never>?

    init(baseURL: URL = ServerConfiguration.currentURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func start() {
        guard realtimeClient == nil else { return }
        snapshotTask?.cancel()
        snapshotTask = Task { [weak self] in await self?.loadSnapshot() }

        let client = RealtimeFeedClient(baseURL: baseURL, session: session)
        client.onEvent = { [weak self] event in
            guard case .deploymentStatus(let snapshot) = event else { return }
            self?.apply(snapshot)
        }
        realtimeClient = client
        client.start()
    }

    func stop() {
        snapshotTask?.cancel()
        snapshotTask = nil
        realtimeClient?.stop()
        realtimeClient = nil
    }

    private func loadSnapshot() async {
        let url = baseURL.appending(path: "api/v1/system/ios-deployment")
        do {
            let (data, response) = try await session.data(from: url)
            guard !Task.isCancelled,
                  let http = response as? HTTPURLResponse,
                  http.statusCode == 200,
                  let payload = try? JSONDecoder().decode(DeploymentStatusResponse.self, from: data),
                  payload.success,
                  let snapshot = DeploymentStatusSnapshot(message: payload.data) else { return }
            apply(snapshot)
        } catch {
            // WebSocket remains the primary live path; the initial request is best-effort.
        }
    }

    private func apply(_ value: DeploymentStatusSnapshot) {
        snapshot = value.isVisible() ? value : nil
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
