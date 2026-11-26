import AVKit
import Observation
import SwiftUI
import UIKit

struct RetailInvestorView: View {
    fileprivate static let closeClearance: CGFloat = 60
    private static let estimatedSourceHeight: CGFloat = 44
    private static let estimatedHeaderHeight: CGFloat = 80
    private static let estimatedEmptyHeight: CGFloat = 130

    let store: InvestorMoodStore
    let onClose: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedID: InvestorMoodAuthor.ID?
    @State private var destination: RetailInvestorDestination?
    @State private var sourceHeight: CGFloat?
    @State private var headerHeight: CGFloat?
    @State private var emptyHeight: CGFloat?
    @State private var listHeights: [InvestorMoodAuthor.ID: CGFloat] = [:]

    static func initialContentHeight(for author: InvestorMoodAuthor?) -> CGFloat {
        guard let author else { return estimatedSourceHeight + estimatedEmptyHeight }
        return estimatedSourceHeight + estimatedHeaderHeight
            + CGFloat(author.videos.count) * InvestorMoodVideoRow.minimumHeight + closeClearance
    }

    private var selectedIndex: Int {
        store.authors.firstIndex { $0.id == selectedID } ?? 0
    }

    var body: some View {
        let authors = store.authors
        let author = authors.isEmpty ? nil : authors[selectedIndex]
        VStack(spacing: 0) {
            sourceLink
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height.rounded(.up) }) {
                    sourceHeight = $0
                }
            if let author {
                authorHeader(author)
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height.rounded(.up) }) {
                        headerHeight = $0
                    }
                pager
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .appPresentationContentHeight(contentHeight(for: author))
        .background(InvestmentDesign.surface)
        .floatingSheetClose("关闭散户观点", action: onClose)
        .accessibilityAction(.escape) { onClose() }
        .task {
            await store.refreshInvestorMood(force: true)
        }
        .onChange(of: store.authors.map(\.id)) { _, ids in
            if let selectedID, !ids.contains(selectedID) {
                self.selectedID = ids.first
            }
        }
        .appSheet(item: $destination) { destination in
            switch destination {
            case .video(let item):
                InvestorMoodVideoDetailSheet(item: item)
            case .xiaohongshu:
                XiaohongshuMoodSheet(load: store.xiaohongshuMood)
                    .readingSheetPresentation()
                    .appPresentationBackground(InvestmentDesign.surface)
            }
        }
    }

    private var sourceLink: some View {
        Button {
            destination = .xiaohongshu
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "bubble.left.and.bubble.right")
                Text("小红书")
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(ResearchDesign.accent)
            .frame(minHeight: Self.estimatedSourceHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("retail-investor-xiaohongshu")
        .frame(maxWidth: TodayBriefStyle.maximumCardWidth, alignment: .trailing)
        .padding(.horizontal, TodayBriefStyle.horizontalInset)
        .frame(maxWidth: .infinity)
    }

    private func contentHeight(for author: InvestorMoodAuthor?) -> CGFloat {
        let source = sourceHeight ?? Self.estimatedSourceHeight
        guard let author else { return source + (emptyHeight ?? Self.estimatedEmptyHeight) }
        let listHeight = listHeights[author.id] ?? CGFloat(author.videos.count) * InvestorMoodVideoRow.minimumHeight
            + Self.closeClearance
        return source + (headerHeight ?? Self.estimatedHeaderHeight) + listHeight
    }

    private func authorHeader(_ author: InvestorMoodAuthor) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(author.nickname)
                    .font(.title2.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text("今日 \(author.videos.count) 条视频")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if store.authors.count > 1 {
                HStack(spacing: 0) {
                    authorButton("chevron.backward", label: "上一位博主", offset: -1)
                    authorButton("chevron.forward", label: "下一位博主", offset: 1)
                }
            }
        }
        .frame(maxWidth: TodayBriefStyle.maximumCardWidth)
        .padding(.horizontal, TodayBriefStyle.horizontalInset)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    private func authorButton(_ symbol: String, label: String, offset: Int) -> some View {
        Button {
            advance(by: offset)
        } label: {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(!store.authors.indices.contains(selectedIndex + offset))
        .accessibilityLabel(label)
    }

    private var pager: some View {
        GeometryReader { viewport in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(store.authors) { author in
                        InvestorMoodAuthorPage(author: author) {
                            destination = .video($0)
                        } onHeightChange: {
                            listHeights[author.id] = $0
                        }
                        .containerRelativeFrame(.horizontal)
                        .frame(height: viewport.size.height)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $selectedID, anchor: .center)
            .scrollBounceBehavior(.basedOnSize)
        }
        .accessibilityIdentifier("retail-investor-pager")
    }

    private var emptyState: some View {
        ScrollView {
            Group {
                if store.isLoadingInvestorMood {
                    ProgressView("正在读取今日视频")
                } else {
                    Text(store.investorMoodErrorMessage ?? "暂无今日视频")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(20)
            .padding(.bottom, Self.closeClearance)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height.rounded(.up) }) {
                emptyHeight = $0
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func advance(by offset: Int) {
        let destination = selectedIndex + offset
        guard store.authors.indices.contains(destination) else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
            selectedID = store.authors[destination].id
        }
    }
}

private enum RetailInvestorDestination: Identifiable {
    case video(InvestorMoodItem)
    case xiaohongshu

    var id: String {
        switch self {
        case .video(let item): "video-\(item.id)"
        case .xiaohongshu: "xiaohongshu"
        }
    }
}

struct InvestorMoodAuthor: Identifiable {
    let id: String
    let nickname: String
    let videos: [InvestorMoodItem]
}

private struct InvestorMoodAuthorPage: View {
    let author: InvestorMoodAuthor
    let onSelect: (InvestorMoodItem) -> Void
    let onHeightChange: (CGFloat) -> Void

    var body: some View {
        ScrollView {
            // Measure the full list so paging and scrolling cannot change its fitted height.
            VStack(spacing: 0) {
                ForEach(author.videos) { video in
                    InvestorMoodVideoRow(item: video) { onSelect(video) }
                    if video.id != author.videos.last?.id {
                        Divider()
                            .accessibilityHidden(true)
                    }
                }
            }
            .frame(maxWidth: TodayBriefStyle.maximumCardWidth)
            .padding(.horizontal, TodayBriefStyle.horizontalInset)
            .frame(maxWidth: .infinity)
            .padding(.bottom, RetailInvestorView.closeClearance)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height.rounded(.up) }, action: onHeightChange)
        }
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityIdentifier("retail-investor-author-\(author.id)")
    }
}

private struct InvestorMoodVideoRow: View {
    private static let coverHeight: CGFloat = 72
    private static let verticalPadding: CGFloat = 10
    static let minimumHeight = coverHeight + verticalPadding * 2

    let item: InvestorMoodItem
    let onSelect: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showsDouyinOpenFailure = false

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onSelect) {
                HStack(spacing: 12) {
                    thumbnail
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.description.nonEmpty ?? "抖音视频")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("\(InvestorMoodFormat.compactRelativeTime(item.createdAt)) · \(item.label)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(item.directPlaybackURL == nil ? "查看视频信息和解读" : "播放视频并查看解读")

            originalVideoButton
        }
        .padding(.vertical, Self.verticalPadding)
        .accessibilityIdentifier("retail-investor-card-\(item.id)")
        .alert("无法打开抖音 App", isPresented: $showsDouyinOpenFailure) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("请确认抖音 App 已安装且可用。")
        }
    }

    private var thumbnail: some View {
        AsyncImage(url: item.coverPlaybackURL) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                InvestmentDesign.secondarySurface
            }
        }
        .frame(width: 56, height: Self.coverHeight)
        .clipped()
        .overlay {
            if item.directPlaybackURL != nil {
                Image(systemName: "play.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(.black.opacity(0.55), in: Circle())
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var originalVideoButton: some View {
        let url = item.douyinAppVideoURL
        return Button {
            guard let url else { return }
            Task {
                let opened = await UIApplication.shared.open(url, options: [:])
                showsDouyinOpenFailure = !opened
            }
        } label: {
            Image("TikTokMark")
                .resizable()
                .scaledToFit()
                .frame(width: 19, height: 19)
                .opacity(url == nil ? 0.35 : 1)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(url == nil)
        .accessibilityLabel(url == nil ? "抖音原视频暂不可用" : "打开抖音原视频")
        .accessibilityIdentifier("retail-investor-open-douyin")
    }
}

private struct InvestorMoodVideoDetailSheet: View {
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
                    if item.directPlaybackURL != nil {
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
                    }

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
                DetailSheetCloseButton(action: dismiss.callAsFunction, accessibilityLabel: "关闭视频详情")
                    .padding(16)
            }
        }
        .task(id: "\(item.id)-\(playbackAttempt)") {
            guard item.directPlaybackURL != nil else { return }
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
    private(set) var investorMoodErrorMessage: String?
    private(set) var isLoadingInvestorMood = false
    private var investorMood: InvestorMoodBoard?
    private var loadedAuthors: [InvestorMoodAuthor] = []
    private var investorMoodLoadedAt: Date?
    private let investorMoodLoader: () async throws -> InvestorMoodBoard
    private let service: MarketService

    var authors: [InvestorMoodAuthor] {
        guard let investorMood, InvestorMoodFormat.isToday(investorMood.generatedAt) else { return [] }
        return loadedAuthors
    }

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
           !authors.isEmpty {
            return
        }
        isLoadingInvestorMood = true
        defer { isLoadingInvestorMood = false }
        do {
            let mood = try await investorMoodLoader()
            guard !Task.isCancelled else { return }
            let previousIDs = Set(investorMood?.items.map(\.id) ?? [])
            var videosByAuthor = Dictionary(grouping: mood.items, by: \.authorId)
            loadedAuthors = mood.items.compactMap { video in
                videosByAuthor.removeValue(forKey: video.authorId).map { videos in
                    InvestorMoodAuthor(id: video.authorId, nickname: video.nickname, videos: videos)
                }
            }
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

    func xiaohongshuMood() async throws -> XiaohongshuMoodBoard {
        try await service.xiaohongshuMood()
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private enum InvestorMoodFormat {
    static func isToday(_ value: String) -> Bool {
        guard let date = isoDate(value) else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar.isDateInToday(date)
    }

    static func relativeTime(_ value: String) -> String {
        guard let date = isoDate(value) else { return "时间未知" }
        return date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
    }

    static func compactRelativeTime(_ value: String) -> String {
        guard let date = isoDate(value) else { return "时间未知" }
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
