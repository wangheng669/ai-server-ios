import AVKit
import SwiftUI

struct XiaohongshuMoodView: View {
    private enum Destination: Identifiable {
        case note(XiaohongshuMoodNote)
        case history

        var id: String {
            switch self {
            case .note(let note): note.id
            case .history: "capture-history"
            }
        }
    }

    let isActive: Bool
    let load: () async throws -> XiaohongshuMoodBoard
    let loadNote: (String) async throws -> XiaohongshuNoteDetail
    let onHeightChange: (CGFloat) -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var board: XiaohongshuMoodBoard?
    @State private var errorMessage: String?
    @State private var retry = 0
    @State private var destination: Destination?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let errorMessage {
                    retryRow(errorMessage)
                }
                if let board {
                    summary(board)
                    if board.notes.isEmpty {
                        Text("暂无已入库笔记")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 24)
                    }
                    ForEach(XiaohongshuNoteDay.grouped(board.notes)) { day in
                        dayHeading(day)
                        ForEach(day.notes) { note in
                            noteRow(note)
                            Divider()
                        }
                    }
                } else if errorMessage == nil {
                    ProgressView("正在读取小红书样本")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                }
            }
            .frame(maxWidth: TodayBriefStyle.maximumCardWidth, alignment: .leading)
            .padding(.horizontal, TodayBriefStyle.horizontalInset)
            .padding(.top, 6)
            .padding(.bottom, RetailInvestorView.closeClearance)
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height.rounded(.up) }, action: onHeightChange)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityIdentifier("xiaohongshu-mood-content")
        .appSheet(item: $destination) { selected in
            switch selected {
            case .note(let note):
                XiaohongshuNoteReader(note: note, load: { try await loadNote(note.id) }) {
                    destination = nil
                }
                .readingSheetPresentation()
            case .history:
                if let board {
                    XiaohongshuCaptureHistory(board: board) {
                        destination = nil
                    }
                }
            }
        }
        .task(id: LoadTrigger(isActive: isActive, phase: scenePhase, retry: retry)) {
            guard isActive, scenePhase == .active else { return }
            await refreshWhileVisible()
        }
    }

    private func summary(_ board: XiaohongshuMoodBoard) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                sampleStatus(board)
                Spacer(minLength: 0)
                historyButton
            }
            VStack(alignment: .leading, spacing: 2) {
                sampleStatus(board)
                historyButton
            }
        }
        .padding(.bottom, 2)
    }

    private func sampleStatus(_ board: XiaohongshuMoodBoard) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(board.notes.count.formatted()) 篇笔记 · \(board.authors.formatted()) 位作者")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
            if let notice = board.captureNotice {
                Label(notice, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var historyButton: some View {
        Button {
            destination = .history
        } label: {
            Label("采集记录", systemImage: "clock")
                .font(.caption.weight(.medium))
                .foregroundStyle(ResearchDesign.accent)
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("xiaohongshu-capture-history")
    }

    private func dayHeading(_ day: XiaohongshuNoteDay) -> some View {
        Text(XiaohongshuMoodTime.dayLabel(day.date))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 12)
            .padding(.bottom, 5)
            .accessibilityAddTraits(.isHeader)
    }

    private func noteRow(_ note: XiaohongshuMoodNote) -> some View {
        Button {
            destination = .note(note)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(XiaohongshuMoodTime.clock(note.publishedAt))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
                VStack(alignment: .leading, spacing: 5) {
                    Text(note.title.isEmpty ? "无标题笔记" : note.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle = note.listSubtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 11)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("xiaohongshu-note-\(note.id)")
    }

    private func retryRow(_ message: String) -> some View {
        Button {
            retry += 1
        } label: {
            Label("\(message) · 重试", systemImage: "arrow.clockwise")
                .font(.footnote)
                .foregroundStyle(ResearchDesign.accent)
                .frame(minHeight: 44, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private func refreshWhileVisible() async {
        while !Task.isCancelled {
            do {
                let result = try await load()
                try Task.checkCancellation()
                board = result
                errorMessage = nil
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = NetworkErrorPresentation.message(for: error)
            }
            do { try await Task.sleep(for: .seconds(60)) }
            catch { return }
        }
    }

    private struct LoadTrigger: Equatable {
        let isActive: Bool
        let phase: ScenePhase
        let retry: Int
    }
}

private extension XiaohongshuMoodBoard {
    var captureNotice: String? {
        switch state {
        case .waiting, .running, .paused, .failed, .coverageGap:
            state.title(reason: reason)
        default:
            stale ? "采集状态超过两小时未更新" : nil
        }
    }
}

private extension XiaohongshuMoodNote {
    var listSubtitle: String? {
        if repeated { return "同作者重复内容" }
        if onlyTopics { return "仅话题标签" }
        if excerpt.isEmpty { return "无正文" }
        guard hasTitle else { return nil }
        let snippet = excerpt
            .replacingOccurrences(of: "#[^#\\n]+\\[话题\\]#", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return snippet.isEmpty ? nil : snippet
    }
}

private struct XiaohongshuNoteDay: Identifiable {
    let date: Date
    let notes: [XiaohongshuMoodNote]
    var id: Date { date }

    static func grouped(_ notes: [XiaohongshuMoodNote]) -> [Self] {
        Dictionary(grouping: notes) { XiaohongshuMoodTime.day(for: $0.publishedAt) }
            .sorted { $0.key > $1.key }
            .map { Self(date: $0.key, notes: $0.value) }
    }
}

private struct XiaohongshuCaptureHistory: View {
    let board: XiaohongshuMoodBoard
    let onClose: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("采集记录")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                if let updatedAt = board.updatedAt {
                    Text("最近入库 \(XiaohongshuMoodTime.label(updatedAt, .dateAndTime)) · 北京时间")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 5)
                }
                if let notice = board.captureNotice {
                    Label(notice, systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
                let withText = board.notes.count - board.onlyTopics - board.notes.count { $0.excerpt.isEmpty }
                Text("\(withText) 篇含正文 · \(board.notes.count - withText) 篇仅标签或无正文")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 10)
                Divider()
                if board.runs.isEmpty {
                    Text("暂无采集记录")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 16)
                }
                ForEach(CaptureRunGroup.grouped(board.runs)) { group in
                    if let oldest = group.earlierFailures.last {
                        failureGroup(group, oldest: oldest)
                    } else {
                        runRow(group.latest)
                    }
                    Divider()
                }
            }
            .frame(maxWidth: TodayBriefStyle.maximumCardWidth, alignment: .leading)
            .padding(.horizontal, TodayBriefStyle.horizontalInset)
            .padding(.top, 22)
            .padding(.bottom, RetailInvestorView.closeClearance)
            .frame(maxWidth: .infinity)
            .measureReadingSheetContent(when: true)
        }
        .background(InvestmentDesign.surface)
        .floatingSheetClose("关闭采集记录", action: onClose)
        .accessibilityAction(.escape) { onClose() }
        .readingSheetPresentation()
    }

    private func runRow(_ run: XiaohongshuCapture) -> some View {
        HStack(alignment: .top, spacing: 10) {
            rowTime(run.at)
            VStack(alignment: .leading, spacing: 3) {
                Text(run.backfill ? "补采 · \(run.state.title(reason: run.reason))" : run.state.title(reason: run.reason))
                    .font(.subheadline.weight(.semibold))
                if run.newNotes > 0 || run.refreshed > 0 {
                    let counts = [
                        run.newNotes > 0 ? "新增 \(run.newNotes) 篇" : nil,
                        run.refreshed > 0 ? "补齐详情 \(run.refreshed) 篇" : nil
                    ].compactMap { $0 }
                    Text(counts.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                } else if run.state == .overlapReached {
                    Text("本轮无新增").font(.caption).foregroundStyle(.secondary)
                }
                if run.state == .coverageGap, let oldestAt = run.oldestAt {
                    Text("最早采到 \(XiaohongshuMoodTime.label(oldestAt, .dateAndTime))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
    }

    private func failureGroup(_ group: CaptureRunGroup, oldest: XiaohongshuCapture) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 0) {
                ForEach([group.latest] + group.earlierFailures) { run in
                    HStack(spacing: 8) {
                        rowTime(run.at)
                        if run.newNotes > 0 {
                            Text("已入库 \(run.newNotes) 篇")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text("连续失败 \(group.earlierFailures.count + 1) 次")
                    .font(.subheadline.weight(.semibold))
                Text(XiaohongshuMoodTime.range(from: oldest.at, to: group.latest.at))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 10)
        }
        .tint(ResearchDesign.accent)
        .accessibilityIdentifier("xiaohongshu-failed-run-group")
    }

    private func rowTime(_ value: String) -> some View {
        Text(XiaohongshuMoodTime.label(value, .row))
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: true, vertical: false)
    }
}

private struct XiaohongshuNoteReader: View {
    let note: XiaohongshuMoodNote
    let load: () async throws -> XiaohongshuNoteDetail
    let onClose: () -> Void

    @State private var detail: XiaohongshuNoteDetail?
    @State private var failed = false
    @State private var openFailed = false
    @State private var retry = 0
    @State private var contentHeight: CGFloat = 230

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if note.hasTitle {
                    Text(note.title)
                        .font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                }
                if let detail {
                    article(detail)
                } else if failed {
                    Button {
                        failed = false
                        retry += 1
                    } label: {
                        Label("详情加载失败，重试", systemImage: "arrow.clockwise")
                            .font(.subheadline)
                            .frame(minHeight: 44)
                    }
                } else {
                    ProgressView("正在读取笔记详情")
                        .font(.subheadline)
                }
            }
            .frame(maxWidth: TodayBriefStyle.maximumCardWidth, alignment: .leading)
            .padding(.horizontal, TodayBriefStyle.horizontalInset)
            .padding(.top, 24)
            .padding(.bottom, 80)
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height.rounded(.up) }) { height in
                contentHeight = max(230, height)
            }
        }
        .background(InvestmentDesign.surface)
        .appPresentationContentHeight(contentHeight)
        .overlay(alignment: .bottom) { controls }
        .accessibilityAction(.escape) { onClose() }
        .alert("无法打开小红书原帖", isPresented: $openFailed) {
            Button("好", role: .cancel) {}
        } message: {
            Text("请确认已安装小红书 App。")
        }
        .task(id: retry) {
            do {
                let result = try await load()
                try Task.checkCancellation()
                detail = result
            } catch is CancellationError {
                return
            } catch {
                failed = !Task.isCancelled
            }
        }
    }

    private func article(_ detail: XiaohongshuNoteDetail) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            let published = XiaohongshuMoodTime.label(note.publishedAt, .dateAndTime)
            Text(detail.details?.authorName.map { "\($0) · \(published)" } ?? published)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let media = detail.details, media.kind == "video" {
                if let url = media.videoURL {
                    XiaohongshuNoteVideo(url: url, cover: media.images.first?.url)
                } else {
                    Label("视频暂不可播放", systemImage: "play.slash")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if !detail.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(verbatim: detail.text)
                    .font(.body)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("xiaohongshu-note-full-text")
            }
            if let media = detail.details {
                let images = media.videoURL != nil ? Array(media.images.dropFirst()) : media.images
                if !images.isEmpty {
                    XiaohongshuNotePhotos(images: images)
                }
                XiaohongshuNoteEngagement(media: media)
            } else {
                Text("图片、视频和互动信息待补采")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("采集于 \(XiaohongshuMoodTime.label(note.collectedAt, .dateAndTime))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            if let detail {
                Button {
                    Task {
                        let opened = await UIApplication.shared.open(detail.url, options: [.universalLinksOnly: true])
                        openFailed = !opened
                    }
                } label: {
                    Label("打开小红书原帖", systemImage: "arrow.up.right")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(ResearchDesign.accent)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(.regularMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("xiaohongshu-note-open-original")
            }
            Spacer(minLength: 0)
            DetailSheetCloseButton(action: onClose, accessibilityLabel: "关闭笔记")
                .accessibilityIdentifier("xiaohongshu-note-close")
        }
        .padding(16)
    }
}

private struct XiaohongshuNotePhotos: View {
    let images: [XiaohongshuNoteImage]
    @State private var selection: ImageGallerySelection?

    var body: some View {
        Group {
            if images.count == 1, let image = images.first {
                photo(image, at: 0)
                    .frame(maxWidth: .infinity)
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 8) {
                        ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                            photo(image, at: index)
                                .frame(width: imageWidth(image))
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .imageGallery(item: $selection)
    }

    private func photo(_ image: XiaohongshuNoteImage, at index: Int) -> some View {
        Button {
            selection = ImageGallerySelection(urls: images.map(\.url), initialIndex: index)
        } label: {
            AsyncImage(url: image.url) { phase in
                switch phase {
                case .success(let photo):
                    photo.resizable().scaledToFit()
                case .failure:
                    Label("图片暂不可用", systemImage: "photo")
                        .font(.caption)
                default:
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: images.count == 1 ? 254 : 184)
            .background(InvestmentDesign.secondarySurface, in: RoundedRectangle(cornerRadius: 12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("查看笔记图片 \(index + 1)")
    }

    private func imageWidth(_ image: XiaohongshuNoteImage) -> CGFloat {
        guard image.width > 0, image.height > 0 else { return 184 }
        return min(276, max(120, 184 * CGFloat(image.width) / CGFloat(image.height)))
    }
}

private struct XiaohongshuNoteEngagement: View {
    let media: XiaohongshuNoteMedia

    var body: some View {
        let counts = [
            media.interaction.likes.map { "赞 \($0)" },
            media.interaction.saves.map { "收藏 \($0)" },
            media.interaction.comments.map { "评论 \($0)" },
            media.interaction.shares.map { "分享 \($0)" }
        ].compactMap { $0 }
        if !counts.isEmpty || media.comments?.isEmpty == false {
            VStack(alignment: .leading, spacing: 8) {
                Divider()
                if !counts.isEmpty {
                    Text(counts.joined(separator: " · "))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if let comments = media.comments, !comments.isEmpty {
                    DisclosureGroup("已采集评论（\(comments.count) 条）") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(comments.enumerated()), id: \.offset) { _, comment in
                                Text(verbatim: comment)
                                    .font(.footnote)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.top, 6)
                    }
                    .font(.footnote)
                }
                Text("互动采集于 \(XiaohongshuMoodTime.label(media.capturedAt, .dateAndTime))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct XiaohongshuNoteVideo: View {
    let url: URL
    let cover: URL?
    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
            } else {
                Button {
                    let video = AVPlayer(url: url)
                    player = video
                    video.play()
                } label: {
                    ZStack {
                        Color.black
                        AsyncImage(url: cover) { image in
                            image.resizable().scaledToFit()
                        } placeholder: {
                            Color.clear
                        }
                        Image(systemName: "play.fill")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 54, height: 54)
                            .background(.black.opacity(0.72), in: Circle())
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("播放视频")
                .accessibilityIdentifier("xiaohongshu-note-play-video")
            }
        }
        .aspectRatio(4.0 / 3.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onDisappear { player?.pause() }
    }
}

private struct CaptureRunGroup: Identifiable {
    let latest: XiaohongshuCapture
    var earlierFailures: [XiaohongshuCapture] = []

    var id: String { latest.id }

    static func grouped(_ runs: [XiaohongshuCapture]) -> [Self] {
        var groups: [Self] = []
        for run in runs {
            if run.state == .failed, groups.last?.latest.state == .failed {
                groups[groups.count - 1].earlierFailures.append(run)
            } else {
                groups.append(Self(latest: run))
            }
        }
        return groups
    }
}

private enum XiaohongshuMoodTime {
    enum Style {
        case row, dateAndTime
    }

    static func day(for value: String) -> Date {
        marketISODate(value).map { calendar.startOfDay(for: $0) } ?? .distantPast
    }

    static func dayLabel(_ date: Date) -> String {
        if date == .distantPast { return "时间未知" }
        if calendar.isDateInToday(date) { return "今天" }
        if calendar.isDateInYesterday(date) { return "昨天" }
        let format = calendar.isDate(date, equalTo: Date(), toGranularity: .year) ? dayOnly : dayWithYear
        return format.string(from: date)
    }

    static func clock(_ value: String) -> String {
        marketISODate(value).map { time.string(from: $0) } ?? "—"
    }

    static func label(_ value: String, _ style: Style) -> String {
        guard let date = marketISODate(value) else { return "时间未知" }
        return (style == .row && calendar.isDateInToday(date) ? time : dateAndTime).string(from: date)
    }

    static func range(from earliest: String, to latest: String) -> String {
        guard let start = marketISODate(earliest), let end = marketISODate(latest) else { return "时间未知" }
        let sameDay = calendar.isDate(start, inSameDayAs: end)
        let startFormat = sameDay && calendar.isDateInToday(start) ? time : dateAndTime
        let endFormat = sameDay ? time : dateAndTime
        return "\(startFormat.string(from: start))–\(endFormat.string(from: end))"
    }

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }()

    private static let time = formatter("HH:mm")
    private static let dayOnly = formatter("M月d日")
    private static let dayWithYear = formatter("yyyy年M月d日")
    private static let dateAndTime = formatter("MM/dd HH:mm")

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter
    }
}
