import SwiftUI

struct YouTubeVideoDetailModel: Identifiable {
    let id: String
    let videoID: String
    let title: String
    let channelName: String
    let publishedLabel: String?
    let durationLabel: String?
    let description: String?
    let coverURL: URL?
    let avatarURL: URL?
    let originalURL: URL?
}

struct YouTubeSubtitleResult {
    let status: String
    let cues: [PersonVideoSubtitleCue]
}

struct YouTubeSubtitlesResponse: Decodable {
    let success: Bool
    let status: String
    let cues: [PersonVideoSubtitleCue]
}

actor YouTubePlaybackSourceCache {
    static let shared = YouTubePlaybackSourceCache()

    private struct Entry {
        let source: VideoPlaybackSource
        let savedAt: Date
    }

    private let timeToLive: TimeInterval = 25 * 60
    private var entries: [String: Entry] = [:]
    private var inFlight: [String: Task<VideoPlaybackSource, Error>] = [:]

    func source(url: URL, title: String, baseURL: URL) async throws -> VideoPlaybackSource {
        let key = "\(baseURL.absoluteString)|\(url.absoluteString)"
        if let entry = entries[key], Date().timeIntervalSince(entry.savedAt) < timeToLive {
            return entry.source
        }
        if let task = inFlight[key] {
            return try await task.value
        }

        let task = Task {
            try await APIClient(baseURL: baseURL).resolveYouTubePlayback(url: url, title: title)
        }
        inFlight[key] = task
        do {
            let source = try await task.value
            entries[key] = Entry(source: source, savedAt: Date())
            inFlight[key] = nil
            return source
        } catch {
            inFlight[key] = nil
            throw error
        }
    }

    func prewarm(url: URL, title: String, baseURL: URL) async {
        _ = try? await source(url: url, title: title, baseURL: baseURL)
    }
}

struct YouTubeVideoDetailView: View {
    typealias SubtitleLoader = @Sendable () async throws -> YouTubeSubtitleResult
    typealias PlaybackLoader = @Sendable () async throws -> VideoPlaybackSource

    let video: YouTubeVideoDetailModel
    var subtitleLoader: SubtitleLoader?
    var playbackLoader: PlaybackLoader?
    var presentedAsSheet = true
    var startsAutomatically = false

    @State private var cues: [PersonVideoSubtitleCue] = []
    @State private var subtitleStatus = "loading"
    @State private var subtitleError: String?
    @State private var currentMS: Int64 = 0
    @State private var isFullscreen = false
    @State private var isPlaying = false
    @State private var playbackFailed = false
    @State private var playbackSource: VideoPlaybackSource?
    @State private var isResolvingPlayback = false
    @State private var activePlayerInstance: String?
    @State private var playbackGeneration = 0
    @State private var isDescriptionExpanded = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            player(instanceID: "youtube-detail-inline")
                .aspectRatio(16 / 9, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .background(Color.black)
                .clipped()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    metadata
                    Divider().opacity(0.55)
                    channelRow
                    actionRow
                    if let description = normalizedDescription {
                        descriptionCard(description)
                    }
                    if subtitleLoader != nil {
                        subtitleSection
                    }
                    Color.clear.frame(height: 32)
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
        .overlay(alignment: .bottomTrailing) {
            if presentedAsSheet {
                DetailSheetCloseButton(action: dismiss.callAsFunction, accessibilityLabel: "关闭视频详情")
                    .padding(16)
            }
        }
        .navigationTitle(presentedAsSheet ? "" : "视频详情")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            if !presentedAsSheet {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel("返回")
                }
            }
        }
        .task(id: video.id) {
            if startsAutomatically {
                await startPlayback(instanceID: "youtube-detail-inline")
            }
            await loadSubtitles()
        }
        .fullScreenCover(isPresented: $isFullscreen) {
            fullscreenPlayer
        }
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(video.title)
                .font(.system(size: 20, weight: .bold))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Text([video.publishedLabel, video.durationLabel, "YouTube"]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " · "))
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 15)
    }

    private var channelRow: some View {
        HStack(spacing: 11) {
            AvatarView(url: video.avatarURL, name: video.channelName, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(video.channelName).font(.system(size: 15.5, weight: .semibold)).lineLimit(1)
                Text("频道").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("YouTube 打开") { openOriginal() }
                .font(.system(size: 13, weight: .semibold))
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(video.originalURL == nil)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var actionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                if let url = video.originalURL {
                    ShareLink(item: url) { actionLabel("分享", symbol: "square.and.arrow.up") }
                        .buttonStyle(.plain)
                }
                Button { openOriginal() } label: { actionLabel("原视频", symbol: "arrow.up.right.square") }
                    .buttonStyle(.plain)
                    .disabled(video.originalURL == nil)
                if isPlaying {
                    Button { Task { await startPlayback(instanceID: "youtube-detail-inline") } } label: {
                        actionLabel("重新播放", symbol: "arrow.counterclockwise")
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 14)
    }

    private func actionLabel(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 15)
            .frame(height: 38)
            .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
    }

    private func descriptionCard(_ description: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("简介").font(.system(size: 15, weight: .bold))
            Text(description)
                .font(.system(size: 14.5))
                .lineSpacing(4)
                .lineLimit(isDescriptionExpanded ? nil : 3)
                .textSelection(.enabled)
            if description.count > 90 {
                Button(isDescriptionExpanded ? "收起" : "展开") {
                    withAnimation(.easeInOut(duration: 0.2)) { isDescriptionExpanded.toggle() }
                }
                .font(.system(size: 13, weight: .semibold))
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 13))
        .padding(.horizontal, 16)
    }

    @ViewBuilder private var subtitleSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("中文字幕")
                .font(.system(size: 20, weight: .bold))
            if isSubtitlePending {
                ProgressView(subtitleStatus == "loading" ? "正在载入字幕…" : "首次提取约需 10 秒…")
            } else if let subtitleError {
                ContentUnavailableView("字幕载入失败", systemImage: "captions.bubble", description: Text(subtitleError))
            } else if cues.isEmpty {
                ContentUnavailableView("暂无可用字幕", systemImage: "captions.bubble")
            } else if let activeCue {
                Section {
                    subtitleRows(excluding: activeCue.id)
                } header: {
                    currentSubtitleCard(activeCue)
                        .padding(.vertical, 8)
                        .background(Color(uiColor: .systemBackground))
                }
            } else {
                subtitleRows(excluding: nil)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 24)
    }

    private func player(instanceID: String, showsFullscreenButton: Bool = true) -> some View {
        ZStack(alignment: .topTrailing) {
            if activePlayerInstance == instanceID, let playbackSource {
                NativeVideoPlayer(
                    source: playbackSource,
                    startsAt: Double(currentMS) / 1_000,
                    onReady: { isPlaying = true; playbackFailed = false },
                    onFailed: { playbackFailed = true; isPlaying = false },
                    onTime: { seconds in
                    let isFullPlayer = instanceID == "youtube-detail-full"
                    guard isFullPlayer == isFullscreen else { return }
                    updatePlaybackTime(seconds)
                    }
                )
                .id("\(instanceID)-\(playbackGeneration)")
            }
            if activePlayerInstance != instanceID || playbackSource == nil || !isPlaying {
                videoPoster(instanceID: instanceID)
            }
            if showsFullscreenButton {
                Button { enterFullscreen() } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.black.opacity(0.62), in: Circle())
                }
                .accessibilityLabel("横屏全屏播放")
                .padding(10)
            }
        }
    }

    private func videoPoster(instanceID: String) -> some View {
        ZStack {
            AsyncImage(url: video.coverURL) { phase in
                if let image = phase.image { image.resizable().scaledToFill() } else { Color.black }
            }
            LinearGradient(colors: [.black.opacity(0.08), .black.opacity(0.42)], startPoint: .top, endPoint: .bottom)
            Button { Task { await startPlayback(instanceID: instanceID) } } label: {
                if isResolvingPlayback, activePlayerInstance == instanceID {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: playbackFailed ? "arrow.clockwise" : "play.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                }
            }
                    .frame(width: 62, height: 62)
                    .background(.black.opacity(0.68), in: Circle())
            .buttonStyle(.plain)
            .accessibilityLabel(playbackFailed ? "重新加载视频" : "播放视频")
        }
        .clipped()
    }

    private var fullscreenPlayer: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            player(instanceID: "youtube-detail-full", showsFullscreenButton: false).ignoresSafeArea()
            if let cue = activeCue {
                Text(cue.text)
                    .font(.system(size: 22, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 34)
                    .padding(.bottom, 34)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            Button { exitFullscreen() } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(.black.opacity(0.55), in: Circle())
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .onAppear { AppOrientationController.shared.setVideoFullscreen(true) }
        .onDisappear { AppOrientationController.shared.setVideoFullscreen(false) }
    }

    @ViewBuilder private func subtitleRows(excluding cueID: PersonVideoSubtitleCue.ID?) -> some View {
        ForEach(cues.filter { $0.id != cueID }) { cue in
            Button { seek(to: cue) } label: {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(timeLabel(for: cue.startMS))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 46, alignment: .leading)
                    Text(cue.text)
                        .font(.system(size: 16))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("跳转到 \(timeLabel(for: cue.startMS))，\(cue.text)")
            Divider()
        }
    }

    private func currentSubtitleCard(_ cue: PersonVideoSubtitleCue) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("正在播放 · \(timeLabel(for: cue.startMS))")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(Color.accentColor)
            Text(cue.text)
                .font(.system(size: 16, weight: .medium))
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var activeCue: PersonVideoSubtitleCue? { cue(at: currentMS) }
    private var isSubtitlePending: Bool { ["loading", "pending", "processing", "extracting", "queued"].contains(subtitleStatus) }
    private var normalizedDescription: String? {
        guard let value = video.description?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty, value != video.title else { return nil }
        return value
    }

    private func cue(at timestamp: Int64) -> PersonVideoSubtitleCue? {
        guard !cues.isEmpty else { return nil }
        var lower = 0
        var upper = cues.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if cues[middle].startMS <= timestamp { lower = middle + 1 } else { upper = middle }
        }
        guard lower > 0 else { return nil }
        let cue = cues[lower - 1]
        return timestamp < cue.endMS ? cue : nil
    }

    private func updatePlaybackTime(_ seconds: Double) {
        let nextMS = Int64(seconds * 1_000)
        guard cue(at: nextMS)?.id != activeCue?.id else { return }
        currentMS = nextMS
    }

    private func seek(to cue: PersonVideoSubtitleCue) {
        currentMS = cue.startMS
        playbackGeneration += 1
    }

    private func startPlayback(instanceID: String) async {
        playbackFailed = false
        activePlayerInstance = instanceID
        guard playbackSource == nil else {
            playbackGeneration += 1
            return
        }
        guard let playbackLoader else {
            playbackFailed = true
            return
        }
        isResolvingPlayback = true
        defer { isResolvingPlayback = false }
        do {
            playbackSource = try await playbackLoader()
            playbackGeneration += 1
        } catch {
            playbackFailed = true
        }
    }

    private func enterFullscreen() {
        AppOrientationController.shared.setVideoFullscreen(true)
        isPlaying = false
        isFullscreen = true
        activePlayerInstance = "youtube-detail-full"
        playbackGeneration += 1
    }

    private func exitFullscreen() {
        AppOrientationController.shared.setVideoFullscreen(false)
        isPlaying = false
        isFullscreen = false
        activePlayerInstance = "youtube-detail-inline"
        playbackGeneration += 1
    }

    private func openOriginal() {
        if let url = video.originalURL { openURL(url) }
    }

    private func timeLabel(for milliseconds: Int64) -> String {
        let totalSeconds = max(0, milliseconds / 1_000)
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, seconds) : String(format: "%02d:%02d", minutes, seconds)
    }

    private func loadSubtitles() async {
        guard let subtitleLoader else { return }
        subtitleStatus = "loading"
        subtitleError = nil
        for attempt in 0..<5 {
            do {
                let payload = try await subtitleLoader()
                guard !Task.isCancelled else { return }
                cues = payload.cues.sorted { $0.startMS < $1.startMS }
                subtitleStatus = payload.status
                if !payload.cues.isEmpty || payload.status == "ready" || payload.status == "unavailable" { return }
                guard attempt < 4 else { return }
                try await Task.sleep(for: .seconds(2))
            } catch is CancellationError {
                return
            } catch {
                subtitleStatus = "failed"
                subtitleError = error.localizedDescription
                return
            }
        }
    }
}
