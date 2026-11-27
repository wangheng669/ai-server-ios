import SwiftUI

struct XiaohongshuMoodView: View {
    private enum Section: String, CaseIterable {
        case notes = "采集笔记"
        case runs = "采集记录"
    }

    let isActive: Bool
    let load: () async throws -> XiaohongshuMoodBoard
    let onHeightChange: (CGFloat) -> Void
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var board: XiaohongshuMoodBoard?
    @State private var errorMessage: String?
    @State private var retry = 0
    @State private var section: Section = .notes
    @State private var expandedNote: XiaohongshuMoodNote.ID?
    @State private var showAll = false

    private static let previewCount = 4

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let errorMessage {
                    retryRow(errorMessage)
                }
                if let board {
                    overview(board)
                    if let status = notice(board) {
                        Label(status, systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    sectionPicker
                    switch section {
                    case .notes: notesList(board.notes)
                    case .runs: runsList(board.runs)
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
            .padding(.top, 16)
            .padding(.bottom, RetailInvestorView.closeClearance)
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height.rounded(.up) }, action: onHeightChange)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityIdentifier("xiaohongshu-mood-content")
        .task(id: LoadTrigger(isActive: isActive, phase: scenePhase, retry: retry)) {
            guard isActive, scenePhase == .active else { return }
            await refreshWhileVisible()
        }
    }

    private func overview(_ board: XiaohongshuMoodBoard) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 10))

        return VStack(alignment: .leading, spacing: 13) {
            layout {
                VStack(alignment: .leading, spacing: 4) {
                    Text("A 股散户情绪")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(ResearchDesign.accent)
                        .accessibilityAddTraits(.isHeader)
                    Text("样本积累中")
                        .font(.title2.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Label("过热信号待计算", systemImage: "circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            layout {
                metric("采集笔记", value: board.notes.count, unit: "篇")
                metric("不同作者", value: board.authors, unit: "位")
            }
            if !board.notes.isEmpty {
                composition(board)
            }
            if let updatedAt = board.updatedAt {
                Text("\(XiaohongshuMoodTime.label(updatedAt, .dateAndTime)) 入库")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .researchPanel(fill: ResearchDesign.selection.opacity(0.45))
    }

    private func metric(_ title: String, value: Int, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value.formatted())
                    .font(.title2.weight(.semibold).monospacedDigit())
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func composition(_ board: XiaohongshuMoodBoard) -> some View {
        let empty = board.notes.count { $0.excerpt.isEmpty }
        let total = board.notes.count
        let withoutText = board.onlyTopics + empty
        let otherText = total - withoutText
        let label = empty == 0 ? "仅标签" : "仅标签或空正文"
        return VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geometry in
                Capsule()
                    .fill(ResearchDesign.accent.opacity(0.16))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(ResearchDesign.accent.opacity(0.72))
                            .frame(width: geometry.size.width * CGFloat(otherText) / CGFloat(total))
                    }
            }
            .frame(height: 6)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    legend("含其他文字", count: otherText, strength: 0.72)
                    Spacer(minLength: 4)
                    legend(label, count: withoutText, strength: 0.16)
                }
                VStack(alignment: .leading, spacing: 5) {
                    legend("含其他文字", count: otherText, strength: 0.72)
                    legend(label, count: withoutText, strength: 0.16)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("含其他文字 \(otherText) 篇，\(label) \(withoutText) 篇")
    }

    private func legend(_ title: String, count: Int, strength: Double) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2)
                .fill(ResearchDesign.accent.opacity(strength))
                .frame(width: 7, height: 7)
            Text(title).foregroundStyle(.secondary)
            Text(count.formatted()).fontWeight(.semibold)
        }
        .font(.caption)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var sectionPicker: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(Section.allCases, id: \.self) { item in
                    let selected = section == item
                    Button {
                        section = item
                    } label: {
                        Text(item.rawValue)
                            .font(.subheadline.weight(selected ? .semibold : .medium))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .foregroundStyle(selected ? ResearchDesign.accent : .secondary)
                            .background(selected ? ResearchDesign.selection : .clear, in: RoundedRectangle(cornerRadius: 10))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            Divider()
        }
    }

    private func notesList(_ notes: [XiaohongshuMoodNote]) -> some View {
        let visible = showAll ? notes[...] : notes.prefix(Self.previewCount)
        return VStack(alignment: .leading, spacing: 0) {
            listCaption("最近样本", detail: "按发布时间")
            if notes.isEmpty {
                Text("暂无已入库笔记").foregroundStyle(.secondary).padding(.vertical, 16)
            }
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(visible, id: \.id) { note in
                    noteRow(note)
                    Divider()
                }
            }
            if notes.count > Self.previewCount {
                Button {
                    showAll.toggle()
                    if !showAll, !notes.prefix(Self.previewCount).contains(where: { $0.id == expandedNote }) {
                        expandedNote = nil
                    }
                } label: {
                    Label(showAll ? "收起笔记" : "查看全部 \(notes.count) 篇",
                          systemImage: showAll ? "chevron.up" : "chevron.down")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(ResearchDesign.accent)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("xiaohongshu-mood-show-all")
            }
        }
    }

    private func noteRow(_ note: XiaohongshuMoodNote) -> some View {
        let expanded = expandedNote == note.id
        let title = note.title.isEmpty ? "无标题笔记" : note.title
        let labels = [
            note.excerpt.isEmpty ? "无正文" : (note.onlyTopics ? "仅标签" : "含其他文字"),
            note.hasTitle ? nil : "原帖无标题",
            note.repeated ? "同作者重复内容" : nil
        ].compactMap { $0 }

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                expandedNote = expanded ? nil : note.id
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    rowTime(note.publishedAt)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(.subheadline.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(labels.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                        .accessibilityHidden(true)
                }
                .padding(.vertical, 9)
                .frame(minHeight: 48, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(expanded ? "已展开" : "已收起")
            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    if !note.excerpt.isEmpty {
                        Text(note.excerpt)
                            .font(.subheadline)
                            .textSelection(.enabled)
                    }
                    Text("采集于 \(XiaohongshuMoodTime.label(note.collectedAt, .dateAndTime))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 12)
            }
        }
    }

    private func runsList(_ runs: [XiaohongshuCapture]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            listCaption("近期采集", detail: "北京时间")
            if runs.isEmpty {
                Text("暂无采集记录").foregroundStyle(.secondary).padding(.vertical, 16)
            }
            ForEach(runs) { run in
                HStack(alignment: .top, spacing: 10) {
                    rowTime(run.at)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(run.state.title(reason: run.reason)).font(.subheadline.weight(.semibold))
                        if run.newNotes > 0 {
                            Text("新增 \(run.newNotes) 篇").font(.caption).foregroundStyle(.secondary)
                        } else if run.state == .overlapReached {
                            Text("本轮无新增").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 10)
                Divider()
            }
        }
    }

    private func listCaption(_ title: String, detail: String) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 8)
            Text(detail)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.bottom, 4)
    }

    private func rowTime(_ value: String) -> some View {
        Text(XiaohongshuMoodTime.label(value, .row))
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: true, vertical: false)
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

    private func notice(_ board: XiaohongshuMoodBoard) -> String? {
        switch board.state {
        case .waiting, .paused, .failed, .coverageGap:
            board.state.title(reason: board.reason)
        default:
            board.stale ? "采集状态超过两小时未更新" : nil
        }
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

private enum XiaohongshuMoodTime {
    enum Style {
        case row, dateAndTime
    }

    static func label(_ value: String, _ style: Style) -> String {
        guard let date = marketISODate(value) else { return "时间未知" }
        return (style == .row && calendar.isDateInToday(date) ? time : dateAndTime).string(from: date)
    }

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }()

    private static let time = formatter("HH:mm")
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
