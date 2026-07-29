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

    private func filteredPeople(for topic: PeopleTopic) -> [SpecialPerson] {
        store.people.filter { $0.topic == topic }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                topicPicker
                TabView(selection: $selectedTopic) {
                    ForEach(store.topics) { topic in
                        peopleList(for: topic)
                            .tag(topic)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
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
                ProcessInfo.processInfo.arguments.contains("--article-detail-preview") ||
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
    private func peopleList(for topic: PeopleTopic) -> some View {
        let people = filteredPeople(for: topic)
        if store.isLoading && people.isEmpty {
            PeopleLoadingTimeline()
        } else if let error = store.errorMessage, people.isEmpty {
            ContentUnavailableView {
                Label("载入失败", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error)
            } actions: {
                Button("重试") { Task { await store.load(force: true) } }
            }
        } else if people.isEmpty {
            ContentUnavailableView(
                "暂无\(topic.rawValue)人物",
                systemImage: "person.2",
                description: Text("这一分类暂时还没有收录人物")
            )
        } else if topic == .history {
            HistoricalPeopleGallery(people: people) { selectedPerson = $0 }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    featuredPeople(people)
                    Text("最新动态")
                        .font(.system(size: 22, weight: .bold))
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 8)
                    ForEach(people) { person in
                        Button { selectedPerson = person } label: {
                            PersonActivityRow(person: person, latestPost: store.latestPost(for: person))
                        }
                        .buttonStyle(PeoplePressStyle())
                        if person.id != people.last?.id {
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

    private func featuredPeople(_ people: [SpecialPerson]) -> some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(people.prefix(4)) { person in
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

    private var activityText: String {
        guard let latestPost, !latestPost.needsXTranslation else { return person.summary }
        return latestPost.displayContent
    }

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
                Text(activityText)
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

private struct HistoricalPeopleGallery: View {
    let people: [SpecialPerson]
    let onSelect: (SpecialPerson) -> Void

    private var featuredPerson: SpecialPerson { people[0] }

    private var keyMilestones: [(person: SpecialPerson, milestone: PersonMilestone)] {
        people.prefix(2).compactMap { person in
            let preferredYear: String? = switch person.userID {
            case "curated:mao-zedong": "1949"
            case "curated:deng-xiaoping": "1978"
            default: nil
            }
            let milestone = preferredYear.flatMap { year in
                person.milestones.first { $0.year == year }
            } ?? person.milestones.first
            return milestone.map { (person, $0) }
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("历史人物")
                        .font(.system(size: 28, weight: .bold))
                    Text("影像、事件与时代")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 14)

                historicalHero(featuredPerson)

                sectionHeader("人物档案")
                    .padding(.top, 22)

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ],
                    spacing: 12
                ) {
                    ForEach(people) { person in
                        Button { onSelect(person) } label: {
                            HistoricalPersonCard(person: person)
                        }
                        .buttonStyle(PeoplePressStyle())
                    }
                }
                .padding(.horizontal, 20)

                if !keyMilestones.isEmpty {
                    sectionHeader("关键节点")
                        .padding(.top, 22)
                    HistoricalMilestoneStrip(items: keyMilestones)
                        .padding(.horizontal, 20)
                }
            }
            .padding(.bottom, 104)
        }
        .scrollIndicators(.hidden)
    }

    private func historicalHero(_ person: SpecialPerson) -> some View {
        Button { onSelect(person) } label: {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let photo = person.photos.first,
                       let url = photo.imageURL(baseURL: ServerConfiguration.currentURL) {
                        RemoteImage(url: url, height: 226, cornerRadius: 18, contentMode: .fill)
                    } else {
                        AvatarView(
                            url: person.avatarURL(baseURL: ServerConfiguration.currentURL),
                            name: person.name,
                            size: 350,
                            assetName: person.avatarAssetName,
                            cornerRadius: 18
                        )
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 226)
                .background(Color(uiColor: .secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                LinearGradient(
                    colors: [.clear, .black.opacity(0.78)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    if let photo = person.photos.first {
                        Text([photo.date, photo.title].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                    }
                    Text(person.name)
                        .font(.system(size: 27, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(18)
            }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PeoplePressStyle())
        .padding(.horizontal, 20)
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 20, weight: .bold))
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 11)
    }
}

private struct HistoricalPersonCard: View {
    let person: SpecialPerson

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            AvatarView(
                url: person.avatarURL(baseURL: ServerConfiguration.currentURL),
                name: person.name,
                size: 180,
                assetName: person.avatarAssetName,
                cornerRadius: 18
            )
            .frame(maxWidth: .infinity)
            .frame(height: 224)
            .scaleEffect(1.04)

            LinearGradient(
                colors: [.clear, .black.opacity(0.86)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(person.name)
                    .font(.system(size: 20, weight: .bold))
                if let lifeYears = person.lifeYears {
                    Text(lifeYears)
                        .font(.system(size: 13, weight: .medium))
                }
                Text(person.roles.first?.title ?? person.summary)
                    .font(.system(size: 12))
                    .lineLimit(2)
                    .lineSpacing(2)
            }
            .foregroundStyle(.white)
            .padding(14)
        }
        .frame(height: 224)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct HistoricalMilestoneStrip: View {
    let items: [(person: SpecialPerson, milestone: PersonMilestone)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.milestone.year)
                        .font(.system(size: 25, weight: .bold, design: .serif))
                    Text(shortTitle(item.milestone.title))
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(item.person.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)

                if index < items.count - 1 {
                    Divider()
                        .frame(height: 62)
                }
            }
        }
        .padding(.vertical, 14)
        .background(
            Color(uiColor: .secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }

    private func shortTitle(_ title: String) -> String {
        title
            .replacingOccurrences(of: "中华人民共和国成立", with: "新中国成立")
            .replacingOccurrences(of: "推动改革开放历史进程", with: "改革开放")
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
    @State private var section: PersonDetailSection
    @State private var ownContentSection = PersonOwnContentSection.posts
    @State private var relatedSection = PersonRelatedSection.videos
    @State private var selectedPost: Post?
    @State private var selectedVideo: PersonVideo?
    @State private var selectedArticle: PersonArticle?
    @State private var selectedPhoto: PersonPhoto?

    init(person: SpecialPerson) {
        self.person = person
        _section = State(initialValue: person.topic == .history ? .profile : .posts)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                personHeader
                if !person.photos.isEmpty {
                    PersonPhotoGallery(photos: person.photos) { selectedPhoto = $0 }
                }
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
                    if let url = person.xProfileURL {
                        Link(destination: url) {
                            Label("在 X 中打开", systemImage: "arrow.up.right.square")
                        }
                    }
                    if let handle = person.xHandle ?? person.handle {
                        Button {
                            UIPasteboard.general.string = handle
                        } label: {
                            Label(person.xHandle == nil ? "复制账号" : "复制 X 账号", systemImage: "doc.on.doc")
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
        .navigationDestination(item: $selectedArticle) { article in
            PersonArticleDetailView(
                articles: store.articles,
                initialArticleID: article.id
            )
        }
        .sheet(item: $selectedPhoto) { photo in
            PersonPhotoViewer(photos: person.photos, initialPhotoID: photo.id)
        }
        .task(id: person.id) {
            await store.load(person: person)
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--article-detail-preview"),
               let article = store.articles.dropFirst().first ?? store.articles.first {
                ownContentSection = .articles
                selectedArticle = article
            }
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
                    if let handle = person.xHandle, let url = person.xProfileURL {
                        Link(destination: url) {
                            HStack(spacing: 4) {
                                Text("X · \(handle)")
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("在 X 中打开 \(handle)")
                    }
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
            ForEach(detailSections) { item in
                Button {
                    withAnimation(.snappy(duration: 0.2)) { section = item }
                } label: {
                    VStack(spacing: 11) {
                        Text(sectionTitle(item))
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

    private var detailSections: [PersonDetailSection] {
        person.topic == .history ? [.profile, .discussions] : PersonDetailSection.allCases
    }

    private func sectionTitle(_ item: PersonDetailSection) -> String {
        if person.topic == .history, item == .profile { return "生平" }
        return item.title
    }

    @ViewBuilder
    private var sectionContent: some View {
        if section == .profile {
            PersonProfileView(person: person)
        } else if section == .discussions {
            relatedContent
        } else if hasArticleSection {
            ownContent
        } else {
            ownPostsContent
        }
    }

    private var hasArticleSection: Bool {
        !store.articles.isEmpty
    }

    private var ownContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("本人内容", selection: $ownContentSection) {
                ForEach(PersonOwnContentSection.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            if ownContentSection == .articles {
                articlesContent
            } else {
                ownPostsContent
            }
        }
    }

    @ViewBuilder
    private var ownPostsContent: some View {
        if store.isLoadingOwnPosts {
            ProgressView("正在载入他的动态…")
                .frame(maxWidth: .infinity).padding(.top, 70)
        } else if let error = store.ownPostsError {
            ContentUnavailableView("载入失败", systemImage: "wifi.exclamationmark", description: Text(error))
                .padding(.top, 36)
        } else if store.ownPosts.isEmpty {
            ContentUnavailableView(
                "暂无本人动态",
                systemImage: "bubble.left",
                description: Text("内容库里还没有收录他本人发布的帖子")
            )
            .padding(.top, 36)
        } else {
            ForEach(store.ownPosts) { post in
                let displayPost = store.postForDisplay(post)
                PersonPostTimelineRow(post: displayPost, compact: false) { selectedPost = displayPost }
                    .task { await store.translateXPostIfNeeded(post) }
                    .task { await store.loadMoreOwnPostsIfNeeded(current: post, person: person) }
            }
            ownPostsPaginationStatus
        }
    }

    @ViewBuilder
    private var articlesContent: some View {
        if store.isLoadingArticles {
            ProgressView("正在载入文章…")
                .frame(maxWidth: .infinity)
                .padding(.top, 54)
        } else if let error = store.articlesError, store.articles.isEmpty {
            ContentUnavailableView("载入失败", systemImage: "wifi.exclamationmark", description: Text(error))
                .padding(.top, 30)
        } else if store.articles.isEmpty {
            ContentUnavailableView(
                "暂无文章",
                systemImage: "doc.text",
                description: Text("内容库里暂时没有收录这位人物的文章")
            )
            .padding(.top, 30)
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("文章 \(store.articles.count)")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Label("最新", systemImage: "chevron.down")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 14)

                ForEach(Array(store.articles.enumerated()), id: \.element.id) { index, article in
                    PersonArticleRow(
                        article: article,
                        featured: index == 0,
                        portraitURL: person.avatarURL(baseURL: ServerConfiguration.currentURL),
                        portraitAssetName: person.avatarAssetName,
                        personName: person.name
                    ) {
                        selectedArticle = article
                    }

                    if index < store.articles.count - 1 {
                        Divider()
                            .padding(.leading, 20)
                    }
                }
            }
            .padding(.bottom, 28)
        }
    }

    private var relatedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            relatedSectionPicker
                .zIndex(1)

            Group {
                switch relatedSection {
                case .videos:
                    if store.isLoadingRelatedVideos {
                        ProgressView("正在载入相关视频…")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 54)
                    } else if let error = store.relatedVideosError, store.relatedVideos.isEmpty {
                        ContentUnavailableView(
                            "载入失败",
                            systemImage: "wifi.exclamationmark",
                            description: Text(error)
                        )
                        .padding(.top, 30)
                    } else if store.relatedVideos.isEmpty {
                        ContentUnavailableView(
                            "暂无相关视频",
                            systemImage: "video",
                            description: Text("内容库里暂时没有收录这位人物的相关视频")
                        )
                        .padding(.top, 30)
                    } else {
                        ForEach(store.relatedVideos) { video in
                            PersonVideoCard(video: video) { selectedVideo = video }
                            Divider().padding(.leading, 20)
                        }
                    }
                case .posts:
                    if store.isLoadingDiscussions {
                        ProgressView("正在查找相关动态…")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 54)
                    } else if let error = store.discussionsError, store.discussions.isEmpty {
                        ContentUnavailableView(
                            "载入失败",
                            systemImage: "wifi.exclamationmark",
                            description: Text(error)
                        )
                        .padding(.top, 30)
                    } else if store.discussions.isEmpty {
                        ContentUnavailableView(
                            "暂无相关动态",
                            systemImage: "bubble.left.and.bubble.right",
                            description: Text("内容库里暂时没有提到这位人物的动态")
                        )
                        .padding(.top, 30)
                    } else {
                        discussionContent(store.discussions)
                    }
                }
            }
            .padding(.top, 24)
            .zIndex(0)
        }
    }

    private var relatedSectionPicker: some View {
        Picker("相关内容", selection: $relatedSection) {
            ForEach(PersonRelatedSection.allCases) { item in
                Text(item.title).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: relatedSection) { _, newValue in
            if newValue == .posts {
                selectedVideo = nil
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(uiColor: .systemBackground))
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
                PersonRelatedPostRow(post: displayPost) { selectedPost = displayPost }
                    .task { await store.translateXPostIfNeeded(post) }
            }
        }
    }
}

private struct PersonPhotoGallery: View {
    let photos: [PersonPhoto]
    let onSelect: (PersonPhoto) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("人物影像")
                    .font(.system(size: 20, weight: .bold))
                Spacer()
                Text("\(photos.count) 张")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal) {
                LazyHStack(spacing: 12) {
                    ForEach(photos) { photo in
                        Button { onSelect(photo) } label: {
                            PersonPhotoCard(photo: photo)
                        }
                        .buttonStyle(PeoplePressStyle())
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.top, 2)
        .padding(.bottom, 20)
    }
}

private struct PersonPhotoCard: View {
    let photo: PersonPhoto

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Group {
                if let url = photo.imageURL(baseURL: ServerConfiguration.currentURL) {
                    RemoteImage(
                        url: url,
                        height: 132,
                        cornerRadius: 14,
                        contentMode: .fit
                    )
                    .background(
                        Color(uiColor: .secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                } else {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.secondary.opacity(0.1))
                        .overlay { Image(systemName: "photo").foregroundStyle(.secondary) }
                }
            }
            .frame(width: 210, height: 132)
            .clipped()

            Text(photo.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text([photo.date, photo.source].compactMap { $0 }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 210, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct PersonPhotoViewer: View {
    let photos: [PersonPhoto]
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPhotoID: PersonPhoto.ID

    init(photos: [PersonPhoto], initialPhotoID: PersonPhoto.ID) {
        self.photos = photos
        _selectedPhotoID = State(initialValue: initialPhotoID)
    }

    private var selectedIndex: Int {
        photos.firstIndex { $0.id == selectedPhotoID } ?? 0
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TabView(selection: $selectedPhotoID) {
                    ForEach(photos) { photo in
                        PersonPhotoPage(photo: photo)
                            .tag(photo.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                if photos.count > 1 {
                    HStack(spacing: 7) {
                        ForEach(photos) { photo in
                            Capsule()
                                .fill(photo.id == selectedPhotoID ? Color.accentColor : Color.secondary.opacity(0.25))
                                .frame(width: photo.id == selectedPhotoID ? 18 : 7, height: 7)
                                .animation(.snappy(duration: 0.2), value: selectedPhotoID)
                        }
                    }
                    .padding(.vertical, 12)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("第 \(selectedIndex + 1) 张，共 \(photos.count) 张")
                }
            }
            .navigationTitle(photos.count > 1 ? "人物影像 \(selectedIndex + 1)/\(photos.count)" : "人物影像")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

private struct PersonPhotoPage: View {
    let photo: PersonPhoto

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let url = photo.imageURL(baseURL: ServerConfiguration.currentURL) {
                    RemoteImage(url: url, height: 430, cornerRadius: 0, contentMode: .fit)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(photo.title)
                        .font(.title2.bold())
                    if let caption = photo.caption {
                        Text(caption)
                            .font(.body)
                            .lineSpacing(4)
                    }
                    Text([photo.date, photo.author, photo.license].compactMap { $0 }.joined(separator: " · "))
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if let sourceURL = photo.sourceURL {
                        Link(destination: sourceURL) {
                            Label("查看来源：\(photo.source)", systemImage: "arrow.up.right.square")
                                .font(.subheadline.weight(.medium))
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
        }
    }
}

private struct PersonRelatedPostRow: View {
    let post: Post
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 12) {
                AvatarView(
                    url: post.avatarURL,
                    name: post.authorName,
                    size: 42
                )

                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(post.authorName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if let handle = post.authorHandle {
                            Text(handle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 6)
                        Text(post.formattedTime ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if post.needsXTranslation {
                        HStack(spacing: 7) {
                            ProgressView()
                                .controlSize(.small)
                            Text("正在翻译为中文…")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }
                        .frame(minHeight: 42, alignment: .leading)
                    } else {
                        Text(post.displayContent)
                            .font(.system(size: 15))
                            .foregroundStyle(.primary)
                            .lineSpacing(3)
                            .lineLimit(6)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(post.needsXTranslation)
        .accessibilityLabel("\(post.authorName)，\(post.needsXTranslation ? "正在翻译为中文" : post.displayContent)")

        Divider()
            .padding(.leading, 74)
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

private enum PersonOwnContentSection: String, CaseIterable, Identifiable {
    case posts
    case articles

    var id: Self { self }
    var title: String {
        switch self {
        case .posts: "动态"
        case .articles: "文章"
        }
    }
}

private enum PersonRelatedSection: String, CaseIterable, Identifiable {
    case videos
    case posts

    var id: Self { self }
    var title: String {
        switch self {
        case .videos: "视频"
        case .posts: "动态"
        }
    }
}

private struct PersonArticleRow: View {
    let article: PersonArticle
    let featured: Bool
    let portraitURL: URL?
    let portraitAssetName: String?
    let personName: String
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(listTitle)
                        .font(.system(size: featured ? 20 : 18, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineSpacing(2)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if !article.displaySummary.isEmpty {
                        Text(article.displaySummary)
                            .font(.system(size: 15))
                            .foregroundStyle(Color.primary.opacity(0.72))
                            .lineSpacing(3)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }

                    Text(metadataLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                if featured {
                    AvatarView(
                        url: portraitURL,
                        name: personName,
                        size: 84,
                        assetName: portraitAssetName
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, featured ? 18 : 15)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("在应用内打开中文文章")
    }

    private var metadataLabel: String {
        [
            article.sourceName,
            article.publishedDateLabel,
            article.readingMinutes > 0 ? "\(article.readingMinutes) 分钟" : nil
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    private var listTitle: String {
        let title = article.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return title == "-" || title.isEmpty ? "\(personName) 最新文章" : title
    }
}

private struct PersonArticleDetailView: View {
    let articles: [PersonArticle]
    let initialArticleID: PersonArticle.ID
    @Environment(\.openURL) private var openURL
    @State private var currentIndex: Int
    @State private var loadedArticle: PersonArticle?
    @State private var errorMessage: String?
    @State private var horizontalOffset: CGFloat = 0

    init(articles: [PersonArticle], initialArticleID: PersonArticle.ID) {
        self.articles = articles
        self.initialArticleID = initialArticleID
        _currentIndex = State(
            initialValue: articles.firstIndex { $0.id == initialArticleID } ?? 0
        )
    }

    private var article: PersonArticle {
        guard articles.indices.contains(currentIndex) else {
            return articles.first!
        }
        return articles[currentIndex]
    }

    var body: some View {
        ZStack(alignment: .leading) {
            if canAdvance {
                Color.accentColor
                    .opacity(0.72)
                    .frame(width: 5)
                    .accessibilityHidden(true)
            }

            Group {
                if let loadedArticle {
                    articleBody(loadedArticle)
                } else if let errorMessage {
                    failureView(errorMessage)
                } else {
                    loadingView
                }
            }
            .offset(x: horizontalOffset)
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let url = article.canonicalURL {
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    Button { openURL(url) } label: {
                        Image(systemName: "safari")
                    }
                }
            }
        }
        .simultaneousGesture(pageGesture)
        .task(id: article.id) {
            loadedArticle = nil
            errorMessage = nil
            await load()
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("正在载入中文正文")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failureView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Color.accentColor)
            Text("中文正文暂时无法载入")
                .font(.system(size: 20, weight: .bold))
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("重新加载") {
                Task { await load() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func articleBody(_ article: PersonArticle) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(article.sourceName.uppercased())
                        .font(.system(size: 12, weight: .bold))
                        .tracking(1.1)
                        .foregroundStyle(Color.accentColor)

                    Text(displayTitle(for: article))
                        .font(.system(size: 32, weight: .bold, design: .serif))
                        .lineSpacing(5)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 8) {
                        if let date = article.publishedDateLabel { Text(date) }
                        if article.readingMinutes > 0 {
                            Circle().fill(Color.secondary.opacity(0.4)).frame(width: 3, height: 3)
                            Text("\(article.readingMinutes) 分钟阅读")
                        }
                        Circle().fill(Color.secondary.opacity(0.4)).frame(width: 3, height: 3)
                        Text("\(currentIndex + 1) / \(articles.count)")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                }
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 26)

                VStack(alignment: .leading, spacing: 24) {
                    ForEach(Array(Self.paragraphs(from: article.displayContent).enumerated()), id: \.offset) { index, paragraph in
                        Text(paragraph)
                            .font(.system(size: index == 0 ? 19 : 18, weight: index == 0 ? .medium : .regular, design: .serif))
                            .foregroundStyle(Color.primary.opacity(0.9))
                            .lineSpacing(8)
                            .textSelection(.enabled)
                    }

                    if let url = article.canonicalURL {
                        Divider().padding(.top, 8)
                        Button { openURL(url) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("英文原文")
                                        .font(.system(size: 15, weight: .semibold))
                                    Text(article.sourceName)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right")
                            }
                            .foregroundStyle(.primary)
                            .padding(16)
                            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 26)
                .background(Color(uiColor: .systemBackground))
            }
            }

            articlePager
        }
    }

    private var articlePager: some View {
        HStack(spacing: 12) {
            if canGoBack {
                Text("向左滑 · 上一篇")
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer(minLength: 0)
                    .frame(maxWidth: .infinity)
            }

            if canAdvance {
                HStack(spacing: 5) {
                    Text("向右滑 · 下一篇")
                    Image(systemName: "arrow.right")
                }
                .foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20)
        .frame(minHeight: 48)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .combine)
    }

    private var pageGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) * 1.35 else {
                    return
                }
                let translation = value.translation.width
                if (translation > 0 && canAdvance) || (translation < 0 && canGoBack) {
                    horizontalOffset = translation * 0.22
                }
            }
            .onEnded { value in
                let horizontal = value.translation.width
                let isHorizontal = abs(horizontal) > abs(value.translation.height) * 1.35
                let targetIndex: Int?
                if isHorizontal, horizontal > 72, canAdvance {
                    targetIndex = currentIndex + 1
                } else if isHorizontal, horizontal < -72, canGoBack {
                    targetIndex = currentIndex - 1
                } else {
                    targetIndex = nil
                }

                withAnimation(.snappy(duration: 0.28)) {
                    horizontalOffset = 0
                    if let targetIndex {
                        currentIndex = targetIndex
                    }
                }
            }
    }

    private var canAdvance: Bool { currentIndex < articles.count - 1 }
    private var canGoBack: Bool { currentIndex > 0 }

    private func load() async {
        errorMessage = nil
        do {
            let value = try await PeopleService().article(id: article.id)
            guard !Task.isCancelled else { return }
            loadedArticle = value
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func paragraphs(from text: String) -> [String] {
        text
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func displayTitle(for article: PersonArticle) -> String {
        let title = article.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard title == "-" || title.isEmpty else { return title }
        guard let firstParagraph = Self.paragraphs(from: article.displayContent).first else {
            return "未命名文章"
        }
        let sentence = firstParagraph
            .components(separatedBy: CharacterSet(charactersIn: "。！？"))
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let sentence, !sentence.isEmpty {
            return sentence
        }
        return "未命名文章"
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

            profileSection(person.topic == .history ? "主要职务" : "当前身份") {
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

            profileSection(person.topic == .history ? "历史主题" : "关注领域") {
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
                profileSection(person.topic == .history ? "生平时间线" : "重要经历") {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(presentedMilestones.enumerated()), id: \.offset) { _, milestone in
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

    private var presentedMilestones: [PersonMilestone] {
        guard person.topic == .history else { return person.milestones }
        return person.milestones.sorted {
            (Int($0.year) ?? .max) < (Int($1.year) ?? .max)
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
