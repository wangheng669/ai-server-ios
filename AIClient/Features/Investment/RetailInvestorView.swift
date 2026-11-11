import AVKit
import Observation
import SwiftUI

struct RetailInvestorView: View {
    private let store: InvestorMoodStore
    @State private var playbackItem: InvestorMoodItem?
    @Environment(\.rootTabIsActive) private var rootTabIsActive
    @Environment(\.dismiss) private var dismiss

    @MainActor
    init(store: InvestorMoodStore) {
        self.store = store
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                investorMoodContent
                    .background(InvestmentDesign.surface)
                    .padding(.bottom, 24)
            }
            .background(InvestmentDesign.surface)
            .task(id: rootTabIsActive) {
                guard rootTabIsActive else { return }
                await store.refreshInvestorMood(force: true)
            }
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .bottomTrailing) {
                DetailSheetCloseButton(
                    action: dismiss.callAsFunction,
                    accessibilityLabel: "关闭散户观点"
                )
                .padding(16)
            }
        }
        .appSheet(item: $playbackItem) { item in
            InvestorMoodVideoPlayerSheet(item: item)
        }
    }

    private var investorMoodContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("散户正在说")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Text("视频由后台自动解读")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            if store.investorMood?.items.isEmpty != false {
                placeholder(store.investorMoodErrorMessage ?? (store.isLoadingInvestorMood ? "正在读取最新样本" : "正在等待大曾子、王小雨等账号的最新有效样本"))
            } else if let items = store.investorMood?.items {
                investorMoodList(items)
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private func investorMoodList(_ items: [InvestorMoodItem]) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                InvestorMoodVideoCard(
                    item: item,
                    onPlay: { playbackItem = item }
                )
                if index < items.count - 1 {
                    Divider()
                        .overlay(InvestmentDesign.divider)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
    }
}

private struct InvestorMoodVideoCard: View {
    let item: InvestorMoodItem
    let onPlay: () -> Void

    var body: some View {
        Button(action: onPlay) {
            HStack(alignment: .top, spacing: 11) {
                thumbnail
                    .frame(width: 78, height: 104)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(alignment: .bottomTrailing) {
                        if item.createdAt != nil {
                            Text(InvestorMoodFormat.compactRelativeTime(item.createdAt))
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(.black.opacity(0.68), in: Capsule())
                                .padding(5)
                        }
                    }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 7) {
                        Text(item.nickname)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                        moodBadge
                        Spacer(minLength: 0)
                    }
                    Text(transcript)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .lineSpacing(2)
                }
            }
            .contentShape(Rectangle())
            .padding(.vertical, 9)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.nickname)，\(item.label)，\(InvestorMoodFormat.compactRelativeTime(item.createdAt))，\(transcript)")
        .accessibilityHint("播放散户观点视频")
    }

    @ViewBuilder
    private var thumbnail: some View {
        ZStack {
            Color.black
            AsyncImage(url: item.directCoverURL) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else if phase.error != nil {
                    proxyCoverImage
                } else {
                    coverPlaceholder
                }
            }
            Circle()
                .fill(.black.opacity(0.58))
                .frame(width: 32, height: 32)
            Image(systemName: "play.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .offset(x: 1)
        }
        .clipped()
    }

    private var transcript: String {
        item.transcript.nonEmpty ?? item.analysis.nonEmpty ?? item.description.nonEmpty ?? "当前视频暂无可用内容"
    }

    @ViewBuilder
    private var proxyCoverImage: some View {
        AsyncImage(url: item.coverPlaybackURL) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                coverPlaceholder
            }
        }
    }

    private var coverPlaceholder: some View {
        Color.black
            .overlay {
                Image(systemName: "video.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
            }
    }

    private var moodBadge: some View {
        let tint = InvestorMoodFormat.moodColor(item.label)
        return Text(item.stale ? "\(item.label) · 旧样本" : item.label)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.1), in: Capsule())
    }
}

private struct InvestorMoodVideoPlayerSheet: View {
    private static let playbackPreparationTimeout: Duration = .seconds(6)

    let item: InvestorMoodItem
    @Environment(\.dismiss) private var dismiss
    @State private var player = AVPlayer()
    @State private var isPlaybackReady = false
    @State private var playbackFailed = false
    @State private var playbackAttempt = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ZStack {
                        VideoPlayer(player: player)

                        if !isPlaybackReady {
                            loadingCover
                                .transition(.opacity)
                        }
                    }
                    .aspectRatio(9 / 16, contentMode: .fit)
                    .frame(maxWidth: 240)
                    .background(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .frame(maxWidth: .infinity, alignment: .center)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(item.nickname)
                                .font(.headline)
                            Spacer()
                            Text(InvestorMoodFormat.relativeTime(item.createdAt))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        Text(item.description.nonEmpty ?? "散户观点视频")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Text(item.transcript.nonEmpty ?? "当前视频暂无可用字幕")
                        .font(.body)
                        .lineSpacing(5)
                        .textSelection(.enabled)
                }
                .padding(16)
            }
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .bottomTrailing) {
                DetailSheetCloseButton(action: dismiss.callAsFunction, accessibilityLabel: "关闭原视频")
                    .padding(16)
            }
        }
        .task(id: "\(item.id)-\(playbackAttempt)") {
            await startPlayback()
        }
        .onDisappear { player.pause() }
    }

    private var loadingCover: some View {
        ZStack {
            Color.black
            AsyncImage(url: item.directCoverURL) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else if phase.error != nil {
                    proxyLoadingCover
                }
            }
            .clipped()

            LinearGradient(
                colors: [.black.opacity(0.05), .black.opacity(0.5)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 10) {
                if playbackFailed {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 28, weight: .medium))
                    Text("视频暂时无法加载")
                        .font(.system(size: 13, weight: .semibold))
                    Button("重试") {
                        playbackAttempt += 1
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white.opacity(0.22))
                } else {
                    ProgressView()
                        .tint(.white)
                    Text("视频加载中")
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .foregroundStyle(.white)
        }
    }

    private var proxyLoadingCover: some View {
        AsyncImage(url: item.coverPlaybackURL) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            }
        }
        .clipped()
    }

    @MainActor
    private func startPlayback() async {
        let playbackURLs = [item.playbackURL, item.directPlaybackURL]
            .compactMap { $0 }
            .reduce(into: [URL]()) { result, url in
                if !result.contains(url) { result.append(url) }
            }
        guard !playbackURLs.isEmpty else {
            playbackFailed = true
            return
        }

        isPlaybackReady = false
        playbackFailed = false
        for url in playbackURLs {
            if await preparePlayback(from: url) {
                return
            }
            guard !Task.isCancelled else { return }
        }
        playbackFailed = true
    }

    @MainActor
    private func preparePlayback(from url: URL) async -> Bool {
        let playerItem = AVPlayerItem(url: url)
        playerItem.preferredForwardBufferDuration = 1
        player.automaticallyWaitsToMinimizeStalling = true
        player.replaceCurrentItem(with: playerItem)
        player.play()

        let deadline = ContinuousClock.now.advanced(by: Self.playbackPreparationTimeout)
        while !Task.isCancelled, ContinuousClock.now < deadline {
            if playerItem.status == .failed {
                return false
            }
            if playerItem.status == .readyToPlay {
                withAnimation(.easeOut(duration: 0.18)) {
                    isPlaybackReady = true
                }
                return true
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }
}

@MainActor
@Observable
final class InvestorMoodStore {
    private(set) var investorMood: InvestorMoodBoard?
    private(set) var investorMoodErrorMessage: String?
    private(set) var isLoadingInvestorMood = false
    private var investorMoodLoadedAt: Date?
    private let investorMoodLoader: () async throws -> InvestorMoodBoard
    private let service: MarketService

    init(
        baseURL: URL = ServerConfiguration.currentURL,
        investorMoodLoader: (() async throws -> InvestorMoodBoard)? = nil
    ) {
        let service = MarketService(baseURL: baseURL)
        self.service = service
        self.investorMoodLoader = investorMoodLoader ?? { try await service.investorMood(refresh: true) }
    }

    func refreshInvestorMood(force: Bool = false) async {
        guard !isLoadingInvestorMood else { return }
        if !force, let investorMoodLoadedAt,
           Date().timeIntervalSince(investorMoodLoadedAt) < 60,
           investorMood?.items.contains(where: { !$0.stale }) == true {
            return
        }
        isLoadingInvestorMood = true
        defer { isLoadingInvestorMood = false }
        do {
            let mood = try await investorMoodLoader()
            guard !Task.isCancelled else { return }
            let previousIDs = Set(investorMood?.items.map(\.id) ?? [])
            investorMood = mood
            investorMoodLoadedAt = Date()
            investorMoodErrorMessage = nil
            Task { await service.prewarmInvestorMoodVideos(mood.items.filter { !previousIDs.contains($0.id) }) }
        } catch is CancellationError {
            return
        } catch {
            investorMoodErrorMessage = NetworkErrorPresentation.message(for: error)
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

private enum InvestorMoodFormat {
    static func relativeTime(_ value: String?) -> String {
        guard let value, let date = isoDate(value) else { return "时间未知" }
        return date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
    }

    static func compactRelativeTime(_ value: String?) -> String {
        guard let value, let date = isoDate(value) else { return "刚刚" }
        let seconds = max(Int(Date().timeIntervalSince(date)), 0)
        switch seconds {
        case ..<60:
            return "刚刚"
        case ..<3_600:
            return "\(seconds / 60) 分钟前"
        case ..<86_400:
            return "\(seconds / 3_600) 小时前"
        default:
            return "\(seconds / 86_400) 天前"
        }
    }

    static func moodColor(_ label: String) -> Color {
        if label.contains("悲观") || label.contains("恐慌") || label.contains("看空") { return .green }
        if label.contains("乐观") || label.contains("兴奋") || label.contains("看多") { return .red }
        return InvestmentDesign.accent
    }

    private static func isoDate(_ value: String) -> Date? {
        fractionalISO.date(from: value) ?? standardISO.date(from: value)
    }

    private static let fractionalISO: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let standardISO = ISO8601DateFormatter()
}
