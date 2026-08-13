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

    var completionIdentity: String {
        "\(commit)-\(stage ?? "installed")"
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
        case .failed:
            switch stage {
            case "merge-failed": "代码合并或合并验证未完成"
            case "build-failed": "App 构建未完成"
            case "install-failed": "未能安装到此 iPhone"
            default: "自动更新未完成"
            }
        }
    }

    var compactDetail: String {
        switch phase {
        case .running: runningStageTitle
        case .succeeded, .failed: detail
        }
    }

    private var runningStageTitle: String {
        switch stage {
        case "merging": "正在合并代码"
        case "merge-testing": "正在验证合并"
        case "publishing": "正在发布更新"
        case "testing": "正在运行测试"
        case "building": "正在构建 App"
        case "waiting-for-installer": "正在等待安装设备"
        case "waiting-for-device": "正在等待 iPhone 连接"
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
    private let defaults: UserDefaults
    private var realtimeClient: RealtimeFeedClient?
    private var snapshotTask: Task<Void, Never>?
    private var dismissalTask: Task<Void, Never>?
    private static let acknowledgedCompletionKey = "iosDeploymentAcknowledgedCompletion"
    static let acknowledgedFailureKey = "iosDeploymentAcknowledgedFailure"
    private static let successDisplayDuration: Duration = .seconds(3)

    init(
        baseURL: URL = ServerConfiguration.currentURL,
        session: URLSession = .shared,
        defaults: UserDefaults = .standard,
    ) {
        self.baseURL = baseURL
        self.session = session
        self.defaults = defaults
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
        dismissalTask?.cancel()
        dismissalTask = nil
        realtimeClient?.stop()
        realtimeClient = nil
    }

    func dismissFailure(_ value: DeploymentStatusSnapshot) {
        guard case .failed = value.phase else { return }
        defaults.set(value.identity, forKey: Self.acknowledgedFailureKey)
        if snapshot?.identity == value.identity {
            snapshot = nil
        }
    }

    private func loadSnapshot() async {
        let url = baseURL.appending(path: "api/ios/v1/system/ios-deployment")
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

    func apply(_ value: DeploymentStatusSnapshot) {
        dismissalTask?.cancel()
        dismissalTask = nil
        guard value.isVisible() else {
            snapshot = nil
            return
        }
        if case .succeeded = value.phase {
            if defaults.string(forKey: Self.acknowledgedCompletionKey) == value.completionIdentity {
                snapshot = nil
                return
            }
            defaults.set(value.completionIdentity, forKey: Self.acknowledgedCompletionKey)
            snapshot = value
            dismissalTask = Task { [weak self] in
                try? await Task.sleep(for: Self.successDisplayDuration)
                guard !Task.isCancelled else { return }
                self?.snapshot = nil
                self?.dismissalTask = nil
            }
            return
        }
        if case .failed = value.phase,
           defaults.string(forKey: Self.acknowledgedFailureKey) == value.identity {
            snapshot = nil
            return
        }
        snapshot = value
    }
}

struct DeploymentStatusTip: View {
    let snapshot: DeploymentStatusSnapshot
    let onDismiss: () -> Void
    @State private var isExpanded: Bool

    init(
        snapshot: DeploymentStatusSnapshot,
        initiallyExpanded: Bool = false,
        onDismiss: @escaping () -> Void = {},
    ) {
        self.snapshot = snapshot
        self.onDismiss = onDismiss
        _isExpanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        VStack(spacing: 8) {
            if isExpanded {
                expandedTip
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if case .succeeded = snapshot.phase {
                compactTip
                    .allowsHitTesting(false)
                    .accessibilityLabel(snapshot.detail)
            } else if case .failed = snapshot.phase {
                failedCompactTip
            } else {
                Button {
                    withAnimation(.snappy(duration: 0.24)) { isExpanded.toggle() }
                } label: {
                    compactTip
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "收起自动更新状态" : "查看自动更新状态，\(snapshot.detail)")
            }
        }
        .frame(maxWidth: 352)
    }

    private var failedCompactTip: some View {
        HStack(spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.24)) { isExpanded.toggle() }
            } label: {
                compactContent
                    .padding(.leading, 14)
                    .padding(.trailing, 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "收起自动更新状态" : "查看自动更新状态，\(snapshot.detail)")

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 48)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭更新失败提示")
        }
        .frame(height: 48)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(snapshot.tint.opacity(0.22), lineWidth: 0.75)
        }
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }

    private var compactTip: some View {
        compactContent
            .padding(.horizontal, 14)
            .frame(height: 48)
            .frame(maxWidth: .infinity)
            .background(.regularMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(snapshot.tint.opacity(0.22), lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }

    private var compactContent: some View {
        HStack(spacing: 10) {
            statusIndicator

            VStack(alignment: .leading, spacing: 1) {
                Text(snapshot.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(snapshot.compactDetail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if case .running = snapshot.phase {
                Text("\(Int(snapshot.progress * 100))%")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(snapshot.tint)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var statusIndicator: some View {
        ZStack {
            Circle()
                .stroke(snapshot.tint.opacity(0.18), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: max(0.07, snapshot.progress))
                .stroke(snapshot.tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: statusSymbol)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(snapshot.tint)
        }
        .frame(width: 22, height: 22)
    }

    private var statusSymbol: String {
        switch snapshot.phase {
        case .running: "arrow.down"
        case .succeeded: "checkmark"
        case .failed: "exclamationmark"
        }
    }

    private var expandedTip: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text(snapshot.title)
                    .font(.system(size: 15, weight: .semibold))
                Spacer(minLength: 12)
                Button {
                    if case .failed = snapshot.phase {
                        onDismiss()
                    } else {
                        withAnimation(.snappy(duration: 0.2)) { isExpanded = false }
                    }
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.24), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.10), radius: 14, y: 6)
        .accessibilityElement(children: .contain)
    }
}
