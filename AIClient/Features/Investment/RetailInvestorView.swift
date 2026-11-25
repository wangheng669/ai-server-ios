import AVKit
import Observation
import SwiftUI
import UIKit

struct RetailInvestorView: View {
    let store: InvestorMoodStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedID: InvestorMoodItem.ID?
    @State private var playbackItem: InvestorMoodItem?

    private var items: [InvestorMoodItem] {
        store.investorMood?.items ?? []
    }

    private var selectedIndex: Int {
        items.firstIndex { $0.id == selectedID } ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            ResearchSheetHeading(title: "散户观点", onClose: dismiss.callAsFunction)
                .frame(maxWidth: TodayBriefStyle.maximumCardWidth)

            if items.count > 1 {
                pageProgress
                    .frame(maxWidth: TodayBriefStyle.maximumCardWidth)
                    .padding(.horizontal, ResearchDesign.inset)
            }

            if items.isEmpty {
                emptyState
            } else {
                pager
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(InvestmentDesign.surface)
        .task {
            await store.refreshInvestorMood(force: true)
        }
        .onChange(of: items.map(\.id)) { _, ids in
            if let selectedID, !ids.contains(selectedID) {
                self.selectedID = ids.first
            }
        }
        .appSheet(item: $playbackItem) { item in
            InvestorMoodVideoPlayerSheet(item: item)
        }
    }

    private var pageProgress: some View {
        HStack(spacing: 8) {
            Text("样本 \(selectedIndex + 1) / \(items.count)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(ResearchDesign.accent)
                .fixedSize()

            ProgressView(value: Double(selectedIndex + 1), total: Double(items.count))
                .tint(ResearchDesign.accent)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("散户观点进度")
        .accessibilityValue("第 \(selectedIndex + 1) 张，共 \(items.count) 张")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: advance(by: 1)
            case .decrement: advance(by: -1)
            @unknown default: break
            }
        }
    }

    private var pager: some View {
        GeometryReader { viewport in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(items) { item in
                        InvestorMoodVideoCard(item: item) { playbackItem = item }
                            .frame(maxWidth: TodayBriefStyle.maximumCardWidth)
                            .padding(.horizontal, TodayBriefStyle.horizontalInset)
                            .padding(.top, 10)
                            .padding(.bottom, 12)
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
        Group {
            if store.isLoadingInvestorMood {
                ProgressView("正在读取最新样本")
            } else {
                Text(store.investorMoodErrorMessage ?? "正在等待最新有效样本")
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(20)
    }

    private func advance(by offset: Int) {
        let destination = selectedIndex + offset
        guard items.indices.contains(destination) else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
            selectedID = items[destination].id
        }
    }
}

private struct InvestorMoodVideoCard: View {
    let item: InvestorMoodItem
    let onPlay: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showsDouyinOpenFailure = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                        .padding(14)
                        .researchPanel(fill: ResearchDesign.fill)
                    interpretation
                        .padding(.horizontal, 2)
                }
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)

            ResearchDesign.line.frame(height: 1)
            originalVideoButton
                .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("retail-investor-card-\(item.id)")
        .alert("无法打开抖音 App", isPresented: $showsDouyinOpenFailure) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("请确认抖音 App 已安装且可用。")
        }
    }

    private var header: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 14))

        return layout {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.nickname)
                        .font(.headline)
                    Text(publication)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                moodBadge

                if let description = item.description.nonEmpty {
                    Text(description)
                        .font(.body.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if item.directPlaybackURL != nil {
                Button(action: onPlay) {
                    thumbnail
                        .frame(width: 84, height: 112)
                        .clipped()
                        .overlay {
                            Image(systemName: "play.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(.black.opacity(0.54), in: Circle())
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("在焦点内播放视频")
            }
        }
    }

    @ViewBuilder
    private var interpretation: some View {
        if let analysis = item.analysis.nonEmpty, item.analysisSource.nonEmpty != nil {
            readingSection("AI 解读", text: analysis)
        } else if let transcript = item.transcript.nonEmpty {
            readingSection("视频字幕", text: transcript)
        } else {
            Text(item.analysis.nonEmpty ?? "当前视频暂无解读")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func readingSection(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ResearchDesign.accent)
                .accessibilityAddTraits(.isHeader)
            Text(text)
                .font(.body)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
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
            HStack(spacing: 8) {
                Image("TikTokMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)
                Text(url == nil ? "原视频暂不可用" : "打开抖音原视频")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                if url != nil {
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.semibold))
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(url == nil ? .secondary : ResearchDesign.accent)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(ResearchDesign.fill, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(url == nil)
        .accessibilityHint(url == nil ? "" : "在抖音 App 打开当前视频")
        .accessibilityIdentifier("retail-investor-open-douyin")
    }

    private var publication: String {
        let time = InvestorMoodFormat.compactRelativeTime(item.createdAt)
        return item.stale ? "\(time) · 旧样本" : time
    }

    private var thumbnail: some View {
        AsyncImage(url: item.directCoverURL) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else if phase.error != nil {
                proxyCoverImage
            } else {
                InvestmentDesign.secondarySurface
            }
        }
    }

    private var proxyCoverImage: some View {
        AsyncImage(url: item.coverPlaybackURL) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                InvestmentDesign.secondarySurface
            }
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
