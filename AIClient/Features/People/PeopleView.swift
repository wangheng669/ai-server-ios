import SwiftUI
import UIKit

struct PeopleView: View {
    @Binding private var showsDetail: Bool
    private let store: PeopleStore
    @State private var selectedPerson: SpecialPerson?
    @State private var selectedTopic = PeopleTopic.technology
    @State private var listScrollPersonID: SpecialPerson.ID?

    init(store: PeopleStore, showsDetail: Binding<Bool> = .constant(false)) {
        self.store = store
        _showsDetail = showsDetail
    }

    private var filteredPeople: [SpecialPerson] {
        store.people.filter { $0.topic == selectedTopic }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                topicPicker
                peopleList
            }
            .background(Color(uiColor: .systemBackground).ignoresSafeArea())
            .navigationBarHidden(true)
            .navigationDestination(item: $selectedPerson) { person in
                PersonDetailPage(person: person)
            }
        }
        .task {
            await store.load()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--person-detail-preview") ||
                ProcessInfo.processInfo.arguments.contains("--video-detail-preview") {
                selectedPerson = store.people.first { $0.name == "Sam Altman" }
            }
            #endif
        }
        .onAppear { showsDetail = selectedPerson != nil }
        .onChange(of: selectedPerson) { _, person in
            showsDetail = person != nil
        }
        .onDisappear { showsDetail = false }
    }

    private var topicPicker: some View {
        HStack(spacing: 0) {
            ForEach(store.topics) { topic in
                Button {
                    withAnimation(.snappy(duration: 0.2)) { selectedTopic = topic }
                } label: {
                    VStack(spacing: 12) {
                        Text(topic.rawValue)
                            .font(.system(size: 15, weight: selectedTopic == topic ? .semibold : .regular))
                            .foregroundStyle(selectedTopic == topic ? Color.accentColor : Color.secondary)
                        Capsule()
                            .fill(selectedTopic == topic ? Color.accentColor : Color.clear)
                            .frame(width: 24, height: 3)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedTopic == topic ? .isSelected : [])
            }
        }
        .padding(.top, 13)
        .overlay(alignment: .bottom) { Divider() }
    }

    @ViewBuilder
    private var peopleList: some View {
        if store.isLoading && filteredPeople.isEmpty {
            PeopleLoadingTimeline()
        } else if let error = store.errorMessage, filteredPeople.isEmpty {
            ContentUnavailableView {
                Label("载入失败", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error)
            } actions: {
                Button("重试") { Task { await store.load(force: true) } }
            }
        } else if filteredPeople.isEmpty {
            ContentUnavailableView(
                "暂无\(selectedTopic.rawValue)人物",
                systemImage: "person.2",
                description: Text("这一分类暂时还没有收录人物")
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    featuredPeople
                    Text("最新动态")
                        .font(.system(size: 22, weight: .bold))
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 8)
                    ForEach(filteredPeople) { person in
                        Button { selectedPerson = person } label: {
                            PersonActivityRow(person: person, latestPost: store.latestPost(for: person))
                        }
                        .buttonStyle(PeoplePressStyle())
                        if person.id != filteredPeople.last?.id {
                            Divider().padding(.leading, 84)
                        }
                    }
                }
                .scrollTargetLayout()
                .padding(.bottom, 20)
            }
            .scrollPosition(id: $listScrollPersonID, anchor: .top)
            .scrollIndicators(.hidden)
            .refreshable { await store.load(force: true) }
            .onChange(of: selectedTopic) { _, _ in listScrollPersonID = nil }
        }
    }

    private var featuredPeople: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(filteredPeople.prefix(4)) { person in
                Button { selectedPerson = person } label: {
                    VStack(spacing: 10) {
                        AvatarView(
                            url: person.avatarURL(baseURL: ServerConfiguration.currentURL),
                            name: person.name,
                            size: 68,
                            assetName: person.avatarAssetName
                        )
                        Text(person.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PeoplePressStyle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 20)
    }
}

private struct PersonActivityRow: View {
    let person: SpecialPerson
    let latestPost: Post?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            AvatarView(
                url: person.avatarURL(baseURL: ServerConfiguration.currentURL),
                name: person.name,
                size: 50,
                assetName: person.avatarAssetName
            )
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(person.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(latestPost?.formattedTime ?? person.relativeTime)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(person.organizationName ?? person.secondaryLabel ?? person.topic.rawValue)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(latestPost?.displayContent ?? person.summary)
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)
                    .lineSpacing(3)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

private struct PeopleLoadingTimeline: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 22) {
                    ForEach(0..<4, id: \.self) { _ in
                        VStack(spacing: 10) {
                            Circle().frame(width: 82, height: 82)
                            Text("人物姓名").font(.caption)
                        }
                        .frame(width: 88)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 22)
                Text("最新动态")
                    .font(.title2.bold())
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                ForEach(0..<4, id: \.self) { _ in
                    HStack(alignment: .top, spacing: 14) {
                        Circle().frame(width: 50, height: 50)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("人物姓名").font(.headline)
                            Text("人物的最新动态内容将在这里显示")
                            Text("更多动态摘要内容")
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                }
            }
            .foregroundStyle(Color.secondary.opacity(0.28))
            .redacted(reason: .placeholder)
        }
    }
}

private struct PersonDetailPage: View {
    let person: SpecialPerson
    @State private var store = PersonDetailStore()
    @State private var section = PersonDetailSection.posts
    @State private var selectedPost: Post?
    @State private var selectedVideo: PersonVideo?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                personHeader
                sectionPicker
                sectionContent
            }
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if let handle = person.handle {
                        Button {
                            UIPasteboard.general.string = handle
                        } label: {
                            Label("复制账号", systemImage: "doc.on.doc")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("更多")
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .navigationDestination(item: $selectedPost) { post in PostDetailView(post: post) }
        .navigationDestination(item: $selectedVideo) { video in
            PersonVideoDetailView(video: video)
        }
        .task(id: person.id) {
            await store.load(person: person)
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--video-detail-preview"),
               let video = store.relatedVideos.first {
                section = .discussions
                selectedVideo = video
            }
            #endif
        }
    }

    private var personHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                AvatarView(
                    url: person.avatarURL(baseURL: ServerConfiguration.currentURL),
                    name: person.name,
                    size: 82,
                    assetName: person.avatarAssetName
                )
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(person.name)
                            .font(.system(size: 24, weight: .bold))
                        if person.hasOwnPostSource {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    Text(personOrganizationLine)
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Text("\(person.topic.rawValue) · \(person.focusTags.first ?? "人物")")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                }
            }

            HStack(spacing: 9) {
                ForEach(person.focusTags, id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(Color.secondary.opacity(0.09), in: Capsule())
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 5)
        .padding(.bottom, 18)
    }

    private var personOrganizationLine: String {
        person.organizationName ?? (person.hasXSource ? "X 来源" : "人物资料")
    }

    private var sectionPicker: some View {
        HStack(spacing: 0) {
            ForEach(PersonDetailSection.allCases) { item in
                Button {
                    withAnimation(.snappy(duration: 0.2)) { section = item }
                } label: {
                    VStack(spacing: 11) {
                        Text(item.title)
                            .font(.system(size: 16, weight: section == item ? .semibold : .regular))
                            .foregroundStyle(section == item ? Color.accentColor : Color.secondary)
                        Capsule().fill(section == item ? Color.accentColor : Color.clear).frame(width: 42, height: 3)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .overlay(alignment: .bottom) { Divider() }
    }

    @ViewBuilder
    private var sectionContent: some View {
        if section == .profile {
            PersonProfileView(person: person)
        } else if sectionIsLoading {
            ProgressView(section == .posts ? "正在载入他的动态…" : "正在查找相关讨论…")
                .frame(maxWidth: .infinity).padding(.top, 70)
        } else if let error = sectionError {
            ContentUnavailableView("载入失败", systemImage: "wifi.exclamationmark", description: Text(error))
                .padding(.top, 36)
        } else {
            let posts = section == .posts ? store.ownPosts : store.discussions
            if section == .discussions, !store.relatedVideos.isEmpty || !posts.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    if !store.relatedVideos.isEmpty {
                        Text("相关视频")
                            .font(.system(size: 20, weight: .bold))
                            .padding(.horizontal, 20)
                            .padding(.top, 17)
                            .padding(.bottom, 10)
                        ForEach(store.relatedVideos) { video in
                            PersonVideoCard(video: video) {
                                selectedVideo = video
                            }
                            Divider().padding(.leading, 20)
                        }
                    }
                    if !posts.isEmpty {
                        discussionContent(posts)
                    }
                }
            } else if posts.isEmpty {
                ContentUnavailableView(
                    section == .posts ? "暂无本人动态" : "暂无相关讨论",
                    systemImage: section == .posts ? "bubble.left" : "bubble.left.and.bubble.right",
                    description: Text(section == .posts ? "内容库里还没有收录他本人发布的帖子" : "内容库里暂时没有提到这位人物的讨论")
                )
                .padding(.top, 36)
            } else {
                ForEach(posts) { post in
                    let displayPost = store.postForDisplay(post)
                    PersonPostTimelineRow(post: displayPost, compact: false) { selectedPost = displayPost }
                        .task { await store.translateXPostIfNeeded(post) }
                        .task { await store.loadMoreOwnPostsIfNeeded(current: post, person: person) }
                }
                ownPostsPaginationStatus
            }
        }
    }

    @ViewBuilder
    private var ownPostsPaginationStatus: some View {
        if store.isLoadingMoreOwnPosts {
            ProgressView("正在载入更多动态…")
                .frame(maxWidth: .infinity)
                .padding(20)
        } else if store.ownPostsLoadMoreError != nil, let last = store.ownPosts.last {
            Button("加载失败，点按重试") {
                Task { await store.loadMoreOwnPostsIfNeeded(current: last, person: person) }
            }
            .font(.footnote)
            .frame(maxWidth: .infinity)
            .padding(20)
        } else if !store.canLoadMoreOwnPosts, !store.ownPosts.isEmpty {
            Text("已显示全部动态")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(20)
        }
    }

    private var sectionIsLoading: Bool {
        if section == .profile { return false }
        return section == .posts ? store.isLoadingOwnPosts : store.isLoadingDiscussions
    }

    private var sectionError: String? {
        if section == .profile { return nil }
        if section == .posts { return store.ownPostsError }
        if !store.relatedVideos.isEmpty || !store.discussions.isEmpty { return nil }
        return store.discussionsError ?? store.relatedVideosError
    }

    private func discussionContent(_ posts: [Post]) -> some View {
        let today = posts.filter(\.isRecentDiscussion)
        let earlier = posts.filter { !$0.isRecentDiscussion }
        return VStack(alignment: .leading, spacing: 0) {
            if !today.isEmpty {
                discussionGroup(title: "今天", countLabel: "\(posts.count) 条相关讨论", posts: today)
            }
            if !earlier.isEmpty {
                discussionGroup(title: "本周", posts: earlier)
            }
        }
    }

    private func discussionGroup(title: String, countLabel: String? = nil, posts: [Post]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(title).font(.system(size: 20, weight: .bold))
                if let countLabel {
                    Text(countLabel).font(.system(size: 14)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20).padding(.top, 15).padding(.bottom, 7)
            ForEach(posts) { post in
                let displayPost = store.postForDisplay(post)
                PersonPostTimelineRow(post: displayPost, compact: true) { selectedPost = displayPost }
                    .task { await store.translateXPostIfNeeded(post) }
            }
        }
    }
}

private struct PersonVideoCard: View {
    let video: PersonVideo
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 9) {
            ZStack {
                if let coverURL = video.coverURL {
                    RemoteImage(url: coverURL, height: 190, cornerRadius: 12)
                }
                Image(systemName: "play.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(.black.opacity(0.68), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 2))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 190)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                if !video.durationLabel.isEmpty {
                    Text(video.durationLabel)
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 5))
                        .padding(8)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Text(video.channelName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 5))
                    .padding(8)
            }

            Text(video.displayTitle)
                .font(.system(size: 16, weight: .semibold))
                .lineLimit(2)
                .lineSpacing(2)

            HStack(spacing: 8) {
                Text(video.videoType == "speech" ? "演讲" : video.videoType == "podcast" ? "播客" : "访谈")
                Text("·")
                Text(video.channelName)
                if let date = video.publishedDateLabel {
                    Text("·")
                    Text(date)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }
}

private struct PersonVideoDetailView: View {
    let video: PersonVideo
    @State private var cues: [PersonVideoSubtitleCue] = []
    @State private var subtitleStatus = "loading"
    @State private var subtitleError: String?
    @State private var currentMS: Int64 = 0
    @State private var isFullscreen = false

    var body: some View {
        VStack(spacing: 0) {
            player(instanceID: "detail-inline")
                .aspectRatio(16 / 9, contentMode: .fit)
                .frame(maxWidth: 320)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .background(Color(uiColor: .systemBackground))

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18, pinnedViews: [.sectionHeaders]) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(video.displayTitle)
                            .font(.system(size: 22, weight: .bold))
                            .lineSpacing(3)
                        Text([video.channelName, video.publishedDateLabel, video.durationLabel]
                            .compactMap { $0 }
                            .filter { !$0.isEmpty }
                            .joined(separator: " · "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let description = video.description, !description.isEmpty {
                            Text(description)
                                .font(.system(size: 15))
                                .lineSpacing(4)
                                .foregroundStyle(.secondary)
                                .lineLimit(5)
                        }
                    }
                    .padding(.horizontal, 18)

                    Text("中文字幕")
                        .font(.system(size: 20, weight: .bold))
                        .padding(.horizontal, 18)

                    if subtitleStatus == "loading" {
                        ProgressView("首次打开正在提取字幕…")
                            .padding(.horizontal, 18)
                    } else if let subtitleError {
                        ContentUnavailableView(
                            "字幕载入失败",
                            systemImage: "captions.bubble",
                            description: Text(subtitleError)
                        )
                        .padding(.horizontal, 18)
                    } else if cues.isEmpty {
                        ContentUnavailableView("暂无可用字幕", systemImage: "captions.bubble")
                            .padding(.horizontal, 18)
                    } else if let activeCue {
                        Section {
                            subtitleRows(excluding: activeCue.id)
                        } header: {
                            currentSubtitleCard(activeCue)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 8)
                                .background(Color(uiColor: .systemBackground))
                        }
                    } else {
                        subtitleRows(excluding: nil)
                    }
                }
                .padding(.top, 16)
                .padding(.bottom, 30)
            }
        }
        .navigationTitle("视频详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task(id: video.id) { await loadSubtitles() }
        .fullScreenCover(isPresented: $isFullscreen) {
            ZStack {
                Color.black.ignoresSafeArea()
                player(instanceID: "detail-full", showsFullscreenButton: false)
                    .ignoresSafeArea()
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
                Button {
                    YouTubeWarmPlayerPool.shared.pause(
                        videoID: video.platformVideoID,
                        instanceID: "detail-full",
                        options: .customSubtitles
                    )
                    AppOrientationController.shared.setVideoFullscreen(false)
                    isFullscreen = false
                } label: {
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
    }

    private func player(instanceID: String, showsFullscreenButton: Bool = true) -> some View {
        ZStack(alignment: .topTrailing) {
            YouTubeEmbeddedPlayer(
                videoID: video.platformVideoID,
                instanceID: instanceID,
                options: .customSubtitles,
                onPlaying: {},
                onFailed: {},
                onTime: { seconds in
                    let isFullPlayer = instanceID == "detail-full"
                    guard isFullPlayer == isFullscreen else { return }
                    updatePlaybackTime(seconds)
                }
            )
            if showsFullscreenButton {
                Button {
                    YouTubeWarmPlayerPool.shared.pause(
                        videoID: video.platformVideoID,
                        instanceID: "detail-inline",
                        options: .customSubtitles
                    )
                    AppOrientationController.shared.setVideoFullscreen(true)
                    isFullscreen = true
                    YouTubeWarmPlayerPool.shared.startPlayback(
                        videoID: video.platformVideoID,
                        instanceID: "detail-full",
                        options: .customSubtitles
                    )
                } label: {
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

    @ViewBuilder
    private func subtitleRows(excluding cueID: PersonVideoSubtitleCue.ID?) -> some View {
        ForEach(cues.filter { $0.id != cueID }) { cue in
            Button {
                seek(to: cue)
            } label: {
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
                .padding(.horizontal, 8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("跳转到 \(timeLabel(for: cue.startMS))，\(cue.text)")
            .padding(.horizontal, 18)
            Divider()
                .padding(.horizontal, 18)
        }
    }

    private func currentSubtitleCard(_ cue: PersonVideoSubtitleCue) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 6, height: 6)
                Text("正在播放 · \(timeLabel(for: cue.startMS))")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }

            Text(cue.text)
                .font(.system(size: 16, weight: .medium))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("正在播放，\(timeLabel(for: cue.startMS))，\(cue.text)")
    }

    private var activeCue: PersonVideoSubtitleCue? {
        cue(at: currentMS)
    }

    private func cue(at timestamp: Int64) -> PersonVideoSubtitleCue? {
        guard !cues.isEmpty else { return nil }
        var lower = 0
        var upper = cues.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if cues[middle].startMS <= timestamp {
                lower = middle + 1
            } else {
                upper = middle
            }
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
        YouTubeWarmPlayerPool.shared.seek(
            videoID: video.platformVideoID,
            instanceID: "detail-inline",
            options: .customSubtitles,
            seconds: Double(cue.startMS) / 1_000
        )
    }

    private func timeLabel(for milliseconds: Int64) -> String {
        let totalSeconds = max(0, milliseconds / 1_000)
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }

    private func loadSubtitles() async {
        subtitleStatus = "loading"
        subtitleError = nil
        do {
            let payload = try await PeopleService().subtitles(videoID: video.id)
            cues = payload.cues
            subtitleStatus = payload.status
        } catch {
            subtitleStatus = "failed"
            subtitleError = error.localizedDescription
        }
    }
}

private enum PersonDetailSection: String, CaseIterable, Identifiable {
    case posts
    case discussions
    case profile
    var id: Self { self }
    var title: String {
        switch self {
        case .posts: "动态"
        case .discussions: "相关"
        case .profile: "简介"
        }
    }
}

private struct PersonPostTimelineRow: View {
    let post: Post
    let compact: Bool
    let onOpen: () -> Void
    @State private var isExpanded = false

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            VStack(spacing: 0) {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 9, height: 9)
                    .padding(.top, 5)
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 1)
            }
            .frame(width: 12)

            VStack(alignment: .leading, spacing: 10) {
                Text([post.formattedTime, post.sourceName].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Button(action: onOpen) {
                    Text(post.displayContent)
                        .font(.system(size: compact ? 15 : 16))
                        .lineSpacing(4)
                        .lineLimit(isExpanded ? nil : (compact ? 4 : 8))
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                if shouldOfferExpansion {
                    Button(isExpanded ? "收起" : "展开全文") { isExpanded.toggle() }
                        .font(.subheadline.weight(.medium))
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                }

                if let quote = post.meta?.quotedTweet {
                    XQuotedPostCard(quote: quote)
                }

                if post.previewURL != nil || !post.videoURLs.isEmpty {
                    XFeedMediaView(post: post)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else if let link = post.externalURL {
                    Link(destination: link) {
                        Label(link.host() ?? "打开链接", systemImage: "link")
                            .font(.subheadline)
                            .foregroundStyle(.blue)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                    }
                }

                Divider().padding(.top, 4)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, compact ? 14 : 18)
        .contentShape(Rectangle())
    }

    private var shouldOfferExpansion: Bool {
        post.displayContent.count > (compact ? 150 : 280) || post.displayContent.filter(\.isNewline).count > 4
    }
}

private struct PersonProfileView: View {
    let person: SpecialPerson

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            profileSection("人物简介") {
                Text(person.summary)
                    .font(.system(size: 15))
                    .lineSpacing(4)
                    .foregroundStyle(.primary)
            }

            profileSection("当前身份") {
                VStack(spacing: 0) {
                    ForEach(Array(person.roles.enumerated()), id: \.offset) { index, role in
                        HStack {
                            Text(role.organization)
                            Spacer()
                            Text(role.title).foregroundStyle(.secondary)
                        }
                        .font(.system(size: 15))
                        .padding(.vertical, 10)
                        if index < person.roles.count - 1 { Divider() }
                    }
                }
            }

            profileSection("关注领域") {
                HStack(spacing: 8) {
                    ForEach(person.focusTags, id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 11)
                            .frame(height: 27)
                            .background(Color.secondary.opacity(0.09), in: Capsule())
                    }
                }
            }

            if !person.milestones.isEmpty {
                profileSection("重要经历") {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(person.milestones.enumerated()), id: \.offset) { _, milestone in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Circle().fill(Color.accentColor).frame(width: 8, height: 8)
                                Text(milestone.year)
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 38, alignment: .leading)
                                Text(milestone.title).font(.system(size: 14))
                            }
                        }
                    }
                }
            }

            if !person.relatedPeople.isEmpty {
                profileSection("相关人物") {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(person.relatedPeople.prefix(3)) { related in
                            VStack(spacing: 6) {
                                AvatarView(
                                    url: related.avatarURL(baseURL: ServerConfiguration.currentURL),
                                    name: related.name,
                                    size: 46,
                                    assetName: related.avatarAssetName
                                )
                                Text(related.name)
                                    .font(.system(size: 12, weight: .semibold))
                                    .lineLimit(1)
                                Text(related.relationship)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }

            if let updatedAt = person.profileUpdatedAt {
                Text("资料更新于 \(updatedAt)")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 28)
            }
        }
    }

    private func profileSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.system(size: 17, weight: .bold))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .overlay(alignment: .bottom) { Divider().padding(.leading, 20) }
    }
}

private struct XQuotedPostCard: View {
    let quote: XQuotedPost

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                if let avatar = quote.author?.profileImageURL.flatMap(MediaURL.image) {
                    RemoteImage(url: avatar, height: 24, cornerRadius: 12)
                        .frame(width: 24, height: 24).clipped()
                }
                Text(quote.author?.name ?? "引用动态").font(.subheadline.weight(.semibold)).lineLimit(1)
                if let handle = quote.author?.handle {
                    Text(handle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            if let text = quote.displayText {
                Text(text).font(.subheadline).lineSpacing(2).foregroundStyle(.primary)
            }
            let media = Array((quote.media ?? []).compactMap(\.displayURL).prefix(4))
            if !media.isEmpty {
                XQuotedMediaGrid(urls: media)
            }
        }
        .padding(11)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.18)))
    }
}

private struct XQuotedMediaGrid: View {
    let urls: [URL]

    var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 3
            let columnCount = urls.count == 1 ? 1 : 2
            let itemWidth = max(0, (proxy.size.width - spacing * CGFloat(columnCount - 1)) / CGFloat(columnCount))
            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(itemWidth), spacing: spacing), count: columnCount),
                spacing: spacing
            ) {
                ForEach(urls, id: \.self) { url in
                    RemoteImage(
                        url: url,
                        height: itemHeight,
                        cornerRadius: 6,
                        contentMode: urls.count == 1 ? .fit : .fill
                    )
                    .frame(width: itemWidth, height: itemHeight)
                    .background(Color.secondary.opacity(0.05))
                    .clipped()
                }
            }
            .frame(width: proxy.size.width, alignment: .leading)
            .clipped()
        }
        .frame(height: gridHeight)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private var itemHeight: CGFloat { urls.count == 1 ? 180 : 100 }
    private var gridHeight: CGFloat { urls.count > 2 ? itemHeight * 2 + 3 : itemHeight }
}

private extension Post {
    var isRecentDiscussion: Bool {
        guard let formattedTime else { return false }
        return formattedTime == "刚刚" || formattedTime.contains("分钟前") || formattedTime.contains("小时前")
    }
}

private struct PeoplePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

#Preview("人物动态") {
    PeopleView(store: PeopleStore())
}
