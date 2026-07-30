import AVKit
import Observation
import SwiftUI

struct LearningDetailView: View {
    let topic: LearningTopic
    let repository: LearningContentRepository
    let progressStore: LearningProgressStore
    var lessonTitle: String?
    var lessonNumber: Int?
    var lessonCount: Int?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            detailBar
            if hasLessonPosition {
                progressRule
            }

            if let loaded = repository.topic(id: topic.id), let detail = loaded.detail {
                LearningArticleView(
                    topic: loaded,
                    detail: detail,
                    isCompleted: progressStore.isCompleted(topic.id),
                    onComplete: completeLesson
                )
            } else if let errorMessage = repository.errorMessages[topic.id] {
                ContentUnavailableView {
                    Label("内容载入失败", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("重试") { Task { await repository.load(id: topic.id) } }
                    Button("查看来源") { openURL(topic.url) }
                }
                .frame(maxHeight: .infinity)
            } else {
                LearningDetailPlaceholder(topic: topic)
            }
        }
        .background(LearningDetailPalette.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .background(InteractivePopGestureEnabler())
        .simultaneousGesture(edgeBackGesture)
        .task { await repository.load(id: topic.id) }
    }

    private var detailBar: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 40)
                    .background(LearningDetailPalette.surface, in: Circle())
                    .overlay {
                        Circle().stroke(LearningDetailPalette.stroke, lineWidth: 0.8)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回学习路径")

            VStack(alignment: .leading, spacing: 2) {
                Text("股票入门路径")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(lessonPositionText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button { openURL(topic.url) } label: {
                Image(systemName: "safari")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 40)
                    .background(LearningDetailPalette.surface, in: Circle())
                    .overlay {
                        Circle().stroke(LearningDetailPalette.stroke, lineWidth: 0.8)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("查看内容来源")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var progressRule: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle().fill(LearningDetailPalette.stroke)
                Rectangle()
                    .fill(LearningDetailPalette.accent)
                    .frame(width: geometry.size.width * lessonProgress)
            }
        }
        .frame(height: 2)
        .accessibilityHidden(true)
    }

    private var hasLessonPosition: Bool {
        lessonNumber != nil && lessonCount != nil
    }

    private var lessonProgress: CGFloat {
        guard let lessonNumber, let lessonCount, lessonCount > 0 else { return 0 }
        return CGFloat(min(max(lessonNumber, 0), lessonCount)) / CGFloat(lessonCount)
    }

    private var lessonPositionText: String {
        guard let lessonNumber, let lessonCount else { return "延伸阅读" }
        if let lessonTitle, !lessonTitle.isEmpty {
            return "第 \(lessonNumber)/\(lessonCount) 节 · \(lessonTitle)"
        }
        return "第 \(lessonNumber)/\(lessonCount) 节"
    }

    private func completeLesson() {
        progressStore.markCompleted(topic.id)
        dismiss()
    }

    private var edgeBackGesture: some Gesture {
        DragGesture(minimumDistance: 18)
            .onEnded { value in
                let horizontalDistance = value.translation.width
                guard value.startLocation.x <= 28,
                      horizontalDistance >= 72,
                      abs(horizontalDistance) > abs(value.translation.height) else {
                    return
                }
                dismiss()
            }
    }
}

private enum LearningDetailPalette {
    static let accent = Color(red: 0.76, green: 0.29, blue: 0.12)
    static let sage = Color(red: 0.40, green: 0.48, blue: 0.39)
    static let canvas = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.systemBackground
                : UIColor(red: 0.98, green: 0.965, blue: 0.94, alpha: 1)
        }
    )
    static let surface = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.secondarySystemBackground
                : UIColor(red: 0.995, green: 0.985, blue: 0.965, alpha: 1)
        }
    )
    static let stroke = Color.primary.opacity(0.10)
}

private struct LearningDetailPlaceholder: View {
    let topic: LearningTopic

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                lessonLabel

                Text(topic.title)
                    .font(.system(size: 32, weight: .bold, design: .serif))
                    .tracking(-0.35)
                    .padding(.top, 13)
                    .padding(.bottom, 10)

                if !topic.summary.isEmpty {
                    Text(topic.summary)
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .lineSpacing(5)
                        .padding(.bottom, 22)
                }

                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LearningDetailPalette.surface)
                    .frame(height: 104)
                    .overlay {
                        ProgressView("正在载入本节内容")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(LearningDetailPalette.stroke, lineWidth: 0.8)
                    }

                ForEach(0..<4, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.secondary.opacity(0.11))
                        .frame(height: index == 0 ? 25 : 17)
                        .frame(maxWidth: index.isMultiple(of: 2) ? .infinity : 260)
                        .padding(.top, index == 0 ? 30 : 16)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .accessibilityLabel("正在读取课程内容")
    }

    private var lessonLabel: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(LearningDetailPalette.accent)
                .frame(width: 7, height: 7)
            Text(topic.category)
            Text("·")
            Text("正在载入")
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(LearningDetailPalette.accent)
    }
}

private struct LearningArticleView: View {
    let topic: LearningTopic
    let detail: LearningDetail
    let isCompleted: Bool
    let onComplete: () -> Void
    @State private var player: AVPlayer?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                lessonLabel

                Text(detail.title)
                    .font(.system(size: 32, weight: .bold, design: .serif))
                    .tracking(-0.35)
                    .lineSpacing(2)
                    .padding(.top, 13)
                    .padding(.bottom, 11)

                if !detail.subtitle.isEmpty {
                    Text(detail.subtitle)
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .lineSpacing(5)
                        .padding(.bottom, 15)
                }

                metadata

                lessonObjective
                    .padding(.top, 22)
                    .padding(.bottom, 26)

                if let examples = detail.companyExamples, !examples.isEmpty {
                    LearningCompanyExamplesView(examples: examples)
                        .padding(.bottom, 28)
                }

                if let references = detail.videoReferences, !references.isEmpty {
                    LearningExternalVideoSection(reference: references[0])
                        .padding(.bottom, 28)
                }

                if let videoURL = topic.mediaURL(detail.videoURLValue) {
                    video(url: videoURL)
                        .padding(.bottom, 28)
                }

                ForEach(Array(detail.blocks.enumerated()), id: \.element.id) { index, block in
                    LearningBlockView(
                        topic: topic,
                        block: block,
                        headingNumber: headingNumber(at: index)
                    )
                }

                finishSection
                    .padding(.top, 18)

                Text("内容来源：富途学习中心")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 18)
                    .padding(.bottom, 42)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
        }
        .scrollIndicators(.hidden)
        .onDisappear {
            player?.pause()
            player = nil
        }
    }

    private var lessonLabel: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(LearningDetailPalette.accent)
                .frame(width: 7, height: 7)
            Text(topic.category)
            Text("·")
            Text(durationText)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(LearningDetailPalette.accent)
    }

    private var metadata: some View {
        HStack(spacing: 7) {
            if !detail.viewsText.isEmpty {
                Image(systemName: "person.2")
                    .font(.system(size: 11, weight: .medium))
                Text("\(detail.viewsText) 人学过")
            }
            if !displayDate.isEmpty {
                Text("·")
                Text(displayDate)
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
    }

    private var lessonObjective: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: "scope")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(LearningDetailPalette.accent)
                .frame(width: 34, height: 34)
                .background(LearningDetailPalette.accent.opacity(0.10), in: Circle())

            VStack(alignment: .leading, spacing: 6) {
                Text("本节目标")
                    .font(.system(size: 14, weight: .semibold))
                Text(objectiveText)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
            }

            Spacer(minLength: 0)
        }
        .padding(15)
        .background(LearningDetailPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(LearningDetailPalette.stroke, lineWidth: 0.8)
        }
    }

    private var finishSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isCompleted ? "本节已完成" : "读完了吗？")
                        .font(.system(size: 16, weight: .semibold))
                    Text(
                        isCompleted
                            ? "完成记录已保存，可以继续学习下一节"
                            : "确认完成后才会计入真实学习进度"
                    )
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(LearningDetailPalette.sage, in: Circle())
            }

            Button {
                onComplete()
            } label: {
                HStack {
                    Text(isCompleted ? "返回学习路径" : "完成本节")
                    Spacer()
                    Image(systemName: isCompleted ? "arrow.right" : "checkmark")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(height: 48)
                .background(
                    LearningDetailPalette.accent,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(LearningDetailPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(LearningDetailPalette.stroke, lineWidth: 0.8)
        }
    }

    private var objectiveText: String {
        if !topic.summary.isEmpty { return topic.summary }
        if !detail.subtitle.isEmpty { return detail.subtitle }
        return "理解这一概念的含义、适用场景与常见误区。"
    }

    private var durationText: String {
        guard let seconds = detail.videoDuration, seconds > 0 else { return "图文课程" }
        let minutes = max(1, Int(ceil(Double(seconds) / 60)))
        return "\(minutes) 分钟"
    }

    private var displayDate: String {
        if let seconds = TimeInterval(detail.updatedAt), seconds > 1_000_000_000 {
            return Date(timeIntervalSince1970: seconds)
                .formatted(.dateTime.year().month().day())
        }
        return detail.updatedAt
    }

    private func headingNumber(at blockIndex: Int) -> Int? {
        guard detail.blocks[blockIndex].type == "heading" else { return nil }
        return detail.blocks[..<blockIndex].filter { $0.type == "heading" }.count + 1
    }

    @ViewBuilder
    private func video(url: URL) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black)
            if let player {
                VideoPlayer(player: player)
            } else {
                AsyncImage(url: topic.mediaURL(detail.videoPosterURLValue)) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Color.black
                    }
                }
                Button {
                    let newPlayer = AVPlayer(url: url)
                    player = newPlayer
                    newPlayer.play()
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 23, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 58, height: 58)
                        .background(LearningDetailPalette.accent.opacity(0.92), in: Circle())
                        .shadow(color: .black.opacity(0.22), radius: 8, y: 4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("播放课程视频")
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .topLeading) {
            Text("课程视频")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(.black.opacity(0.55), in: Capsule())
                .padding(10)
        }
    }
}

private struct LearningExternalVideoSection: View {
    let reference: LearningVideoReference
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Rectangle()
                    .fill(LearningDetailPalette.accent)
                    .frame(width: 28, height: 2)
                Text("换一种方式理解")
                    .font(.system(size: 18, weight: .bold, design: .serif))
                Spacer(minLength: 0)
            }

            Button {
                if let url = reference.watchURL {
                    openURL(url)
                }
            } label: {
                HStack(spacing: 0) {
                    videoCover
                        .frame(width: 132, height: 132)
                        .clipped()

                    VStack(alignment: .leading, spacing: 8) {
                        Text(reference.creator)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(LearningDetailPalette.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(LearningDetailPalette.accent.opacity(0.10), in: Capsule())

                        Text(reference.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        Text("相关片段 · \(reference.clipDurationText)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        Spacer(minLength: 0)

                        HStack(spacing: 4) {
                            Text(reference.platform == "bilibili" ? "B站观看" : "观看视频")
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(LearningDetailPalette.accent)
                    }
                    .padding(13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 132)
                .background(LearningDetailPalette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(LearningDetailPalette.accent.opacity(0.22), lineWidth: 0.9)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("在B站观看\(reference.creator)的视频：\(reference.title)")

            if !reference.recommendationItems.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    Text("看视频时重点关注")
                        .font(.system(size: 13, weight: .semibold))
                    ForEach(reference.recommendationItems, id: \.self) { item in
                        HStack(alignment: .top, spacing: 9) {
                            Circle()
                                .fill(LearningDetailPalette.accent)
                                .frame(width: 5, height: 5)
                                .padding(.top, 6)
                            Text(item)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .lineSpacing(3)
                        }
                    }
                }
                .padding(.horizontal, 3)
            }
        }
    }

    private var videoCover: some View {
        AsyncImage(url: reference.coverURL) { phase in
            if let image = phase.image {
                image
                    .resizable()
                    .scaledToFill()
                    .overlay {
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.20)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
            } else {
                LearningDetailPalette.accent.opacity(0.10)
            }
        }
        .overlay {
            Image(systemName: "play.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(.black.opacity(0.62), in: Circle())
                .overlay {
                    Circle().stroke(.white.opacity(0.72), lineWidth: 1)
                }
        }
    }
}

private struct LearningCompanyExamplesView: View {
    let examples: [LearningCompanyExample]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Rectangle()
                    .fill(LearningDetailPalette.accent)
                    .frame(width: 28, height: 2)
                Text("公司案例")
                    .font(.system(size: 18, weight: .bold, design: .serif))
                Text("把概念放进经营现场")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            ForEach(examples) { example in
                VStack(alignment: .leading, spacing: 15) {
                    HStack(spacing: 11) {
                        Text(monogram(for: example.company))
                            .font(.system(size: 14, weight: .bold, design: .serif))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(LearningDetailPalette.accent, in: Circle())

                        VStack(alignment: .leading, spacing: 3) {
                            Text(example.company)
                                .font(.system(size: 16, weight: .semibold))
                            if let ticker = example.ticker, !ticker.isEmpty {
                                Text(ticker)
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(LearningDetailPalette.accent)
                            }
                        }
                    }

                    exampleSection(title: "公司情况", text: example.situation)

                    Divider().opacity(0.55)

                    exampleSection(title: "理解关键", text: example.connection)

                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 12, weight: .medium))
                            .padding(.top, 1)
                        Text(example.caution)
                            .font(.system(size: 11))
                            .lineSpacing(3)
                    }
                    .foregroundStyle(.secondary)
                }
                .padding(16)
                .background(LearningDetailPalette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(LearningDetailPalette.accent.opacity(0.24), lineWidth: 0.9)
                }
            }
        }
    }

    private func exampleSection(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(LearningDetailPalette.accent)
            Text(text)
                .font(.system(size: 15))
                .lineSpacing(5)
                .foregroundStyle(.primary)
        }
    }

    private func monogram(for company: String) -> String {
        String(company.prefix(1))
    }
}

private struct LearningBlockView: View {
    let topic: LearningTopic
    let block: LearningBlock
    let headingNumber: Int?

    var body: some View {
        switch block.type {
        case "heading":
            HStack(alignment: .firstTextBaseline, spacing: 11) {
                if let headingNumber {
                    Text(String(format: "%02d", headingNumber))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(LearningDetailPalette.accent)
                }
                Text(block.text ?? "")
                    .font(.system(
                        size: block.level == 1 ? 24 : 22,
                        weight: .bold,
                        design: .serif
                    ))
                    .foregroundStyle(.primary)
            }
            .padding(.top, 22)
            .padding(.bottom, 14)

        case "paragraph":
            Text(block.text ?? "")
                .font(.system(size: 17))
                .lineSpacing(8)
                .foregroundStyle(.primary)
                .padding(.bottom, 18)

        case "list":
            VStack(alignment: .leading, spacing: 13) {
                ForEach(block.items ?? [], id: \.self) { item in
                    HStack(alignment: .top, spacing: 11) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(LearningDetailPalette.accent)
                            .frame(width: 21, height: 21)
                            .background(LearningDetailPalette.accent.opacity(0.10), in: Circle())
                        Text(item)
                            .font(.system(size: 16))
                            .lineSpacing(6)
                    }
                }
            }
            .padding(15)
            .background(LearningDetailPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(LearningDetailPalette.stroke, lineWidth: 0.8)
            }
            .padding(.bottom, 20)

        case "image":
            AsyncImage(url: topic.mediaURL(block.imageURLValue)) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(LearningDetailPalette.stroke, lineWidth: 0.8)
                        }
                } else if phase.error != nil {
                    ContentUnavailableView("图片暂不可用", systemImage: "photo")
                        .frame(height: 160)
                } else {
                    ProgressView().frame(maxWidth: .infinity).frame(height: 160)
                }
            }
            .padding(.vertical, 10)

        default:
            EmptyView()
        }
    }
}
