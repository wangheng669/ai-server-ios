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
            Divider().opacity(0.5)
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
            } else {
                LearningDetailPlaceholder(topic: topic)
            }
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task { await repository.load(id: topic.id) }
    }

    private var detailBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            Spacer()
            Text(topic.category).font(.system(size: 17, weight: .semibold))
            Spacer()
            Button { openURL(topic.url) } label: {
                Image(systemName: "safari")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("查看内容来源")
        }
        .padding(.horizontal, 6)
        .frame(height: 50)
    }
}

private struct LearningDetailPlaceholder: View {
    let topic: LearningTopic

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                Text(topic.title)
                    .font(.system(size: 34, weight: .bold))
                    .tracking(-0.5)
                    .padding(.bottom, 10)
                if !topic.summary.isEmpty {
                    Text(topic.summary)
                        .font(.system(size: 17))
                        .foregroundStyle(.secondary)
                        .lineSpacing(6)
                        .padding(.bottom, 24)
                }
                ProgressView()
                    .controlSize(.small)
                    .padding(.bottom, 24)
                ForEach(0..<4, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.secondary.opacity(0.12))
                        .frame(height: index == 0 ? 28 : 18)
                        .frame(maxWidth: index.isMultiple(of: 2) ? .infinity : 260)
                        .padding(.bottom, 16)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
        }
        .scrollIndicators(.hidden)
        .accessibilityLabel("正在读取课程内容")
    }
}

private struct LearningArticleView: View {
    let topic: LearningTopic
    let detail: LearningDetail
    @State private var player: AVPlayer?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                Text(detail.title)
                    .font(.system(size: 34, weight: .bold))
                    .tracking(-0.5)
                    .padding(.bottom, 10)

                HStack(spacing: 7) {
                    if !detail.viewsText.isEmpty { Text("\(detail.viewsText)人学过") }
                    if !displayDate.isEmpty {
                        Text("·")
                        Text(displayDate)
                    }
                }
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .padding(.bottom, 24)

                if let videoURL = topic.mediaURL(detail.videoURLValue) {
                    video(url: videoURL)
                        .padding(.bottom, 28)
                }

                ForEach(detail.blocks) { block in
                    LearningBlockView(topic: topic, block: block)
                }

                Text("内容来源：富途学习中心")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 26)
                    .padding(.bottom, 40)
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

    private var displayDate: String {
        if let seconds = TimeInterval(detail.updatedAt), seconds > 1_000_000_000 {
            return Date(timeIntervalSince1970: seconds)
                .formatted(.dateTime.year().month().day())
        }
        return detail.updatedAt
    }

    @ViewBuilder
    private func video(url: URL) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black)
            if let player {
                VideoPlayer(player: player)
            } else {
                AsyncImage(url: topic.mediaURL(detail.videoPosterURLValue)) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit()
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
                        .font(.system(size: 28))
                        .foregroundStyle(.white)
                        .frame(width: 68, height: 68)
                        .background(.black.opacity(0.55), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("播放课程视频")
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct LearningBlockView: View {
    let topic: LearningTopic
    let block: LearningBlock

    var body: some View {
        switch block.type {
        case "heading":
            Text(block.text ?? "")
                .font(.system(size: block.level == 1 ? 25 : 23, weight: .bold))
                .padding(.leading, 14)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(HoldingsPalette.purple)
                        .frame(width: 4)
                }
                .padding(.top, 18)
                .padding(.bottom, 14)
        case "paragraph":
            Text(block.text ?? "")
                .font(.system(size: 17))
                .lineSpacing(8)
                .foregroundStyle(Color(uiColor: .label))
                .padding(.bottom, 18)
        case "list":
            VStack(alignment: .leading, spacing: 10) {
                ForEach(block.items ?? [], id: \.self) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(HoldingsPalette.purple)
                            .frame(width: 5, height: 5)
                            .padding(.top, 9)
                        Text(item).font(.system(size: 17)).lineSpacing(6)
                    }
                }
            }
            .padding(.bottom, 18)
        case "image":
            AsyncImage(url: topic.mediaURL(block.imageURLValue)) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
