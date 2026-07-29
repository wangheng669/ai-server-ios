import AVKit
import Observation
import SwiftUI

struct LearningDetailView: View {
    let topic: LearningTopic
    let repository: LearningContentRepository
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            detailBar
            progressRule

            if let loaded = repository.topic(id: topic.id), let detail = loaded.detail {
                LearningArticleView(topic: loaded, detail: detail)
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
                Text("第 1 节 · 基础概念")
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
                    .frame(width: geometry.size.width / 6)
            }
        }
        .frame(height: 2)
        .accessibilityHidden(true)
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
            Text("12 分钟")
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(LearningDetailPalette.accent)
    }
}

private struct LearningArticleView: View {
    let topic: LearningTopic
    let detail: LearningDetail
    @Environment(\.dismiss) private var dismiss
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
                    Text("本节阅读完成")
                        .font(.system(size: 16, weight: .semibold))
                    Text("返回路径，继续建立投资框架")
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
                dismiss()
            } label: {
                HStack {
                    Text("返回学习路径")
                    Spacer()
                    Image(systemName: "arrow.right")
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
        guard let seconds = detail.videoDuration, seconds > 0 else { return "12 分钟" }
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
