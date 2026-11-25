import AVKit
import Observation
import SwiftUI

struct RetailInvestorView: View {
    private let store: InvestorMoodStore
    @State private var playbackItem: InvestorMoodItem?
    @Environment(\.dismiss) private var dismiss

    @MainActor
    init(store: InvestorMoodStore) {
        self.store = store
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                investorMoodContent
                    .padding(.horizontal, InvestmentDesign.pageInset)
                    .padding(.top, 20)
                    .padding(.bottom, 64)
            }
            .background(InvestmentDesign.canvas)
            .task {
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
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("散户观点")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                Text("视频观点由 AI 自动解读")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 2)

            if let items = store.investorMood?.items, !items.isEmpty {
                LazyVStack(spacing: 10) {
                    ForEach(items) { item in
                        InvestorMoodVideoCard(item: item, onPlay: { playbackItem = item })
                    }
                }
            } else {
                emptyState
            }
        }
    }

    private var emptyState: some View {
        Group {
            if store.isLoadingInvestorMood {
                ProgressView("正在读取最新样本")
            } else {
                Text(store.investorMoodErrorMessage ?? "正在等待最新有效样本")
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(InvestmentDesign.surface, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct InvestorMoodVideoCard: View {
    let item: InvestorMoodItem
    let onPlay: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let contentLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 14))
        let shape = RoundedRectangle(cornerRadius: 16)

        Button(action: onPlay) {
            VStack(alignment: .leading, spacing: 12) {
                header
                contentLayout {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .lineSpacing(3)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 4)
                            .fixedSize(horizontal: false, vertical: true)

                        Label("播放原视频", systemImage: "play.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    thumbnail
                        .frame(width: 76, height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .accessibilityHidden(true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(InvestmentDesign.surface, in: shape)
            .overlay {
                shape.strokeBorder(InvestmentDesign.divider, lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.nickname)，\(item.label)，\(publication)")
        .accessibilityValue(summary)
        .accessibilityHint("播放原视频")
    }

    private var header: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 8))

        return layout {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.nickname)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(publication)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            moodBadge
        }
    }

    private var publication: String {
        let time = InvestorMoodFormat.compactRelativeTime(item.createdAt)
        return item.stale ? "\(time) · 旧样本" : time
    }

    private var summary: String {
        item.analysis.nonEmpty ?? item.transcript.nonEmpty ?? item.description.nonEmpty ?? "当前视频暂无可用内容"
    }

    private var thumbnail: some View {
        AsyncImage(url: item.directCoverURL) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else if phase.error != nil {
                proxyCoverImage
            } else {
                coverPlaceholder
            }
        }
    }

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
        InvestmentDesign.secondarySurface
            .overlay {
                Image(systemName: "video")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
    }

    private var moodBadge: some View {
        let tint = InvestorMoodFormat.moodColor(item.label)
        return Text(item.label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
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

                    if let analysis = item.analysis.nonEmpty {
                        readingSection(item.analysisSource.nonEmpty == nil ? "解读状态" : "AI 解读", text: analysis)
                    }
                    readingSection("视频字幕", text: item.transcript.nonEmpty ?? "当前视频暂无可用字幕")
                }
                .padding(16)
                .padding(.bottom, 48)
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

    private func readingSection(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text(text)
                .font(.body)
                .lineSpacing(5)
                .textSelection(.enabled)
        }
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
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private enum InvestorMoodFormat {
    static func relativeTime(_ value: String?) -> String {
        guard let value, let date = isoDate(value) else { return "时间未知" }
        return date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
    }

    static func compactRelativeTime(_ value: String?) -> String {
        guard let value, let date = isoDate(value) else { return "时间未知" }
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
        switch label {
        case "悲观", "恐慌":
            return Color(red: 0.12, green: 0.39, blue: 0.27)
        case "乐观", "亢奋":
            return Color(red: 0.65, green: 0.20, blue: 0.24)
        default:
            return .secondary
        }
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
