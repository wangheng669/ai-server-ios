import SwiftUI

struct PeopleView: View {
    @Binding private var showsDetail: Bool
    private let store: PeopleStore
    @State private var selectedPerson: SpecialPerson? = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--person-detail-preview") {
            return SpecialPerson.artificialIntelligenceLeaders.first { $0.name == "Mark Zuckerberg" }
        }
        #endif
        return nil
    }()
    @State private var selectedTopic = PeopleTopic.technology
    @State private var query = ""

    init(store: PeopleStore, showsDetail: Binding<Bool> = .constant(false)) {
        self.store = store
        _showsDetail = showsDetail
    }

    private var filteredPeople: [SpecialPerson] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let availablePeople: [SpecialPerson]
        if selectedTopic == .technology {
            let curatedNames = Set(SpecialPerson.artificialIntelligenceLeaders.map(\.name))
            availablePeople = SpecialPerson.artificialIntelligenceLeaders + store.people.filter { !curatedNames.contains($0.name) }
        } else if selectedTopic == .politics {
            let curatedNames = Set(SpecialPerson.politicalFigures.map(\.name))
            availablePeople = SpecialPerson.politicalFigures + store.people.filter { !curatedNames.contains($0.name) }
        } else if selectedTopic == .business {
            let curatedNames = Set(SpecialPerson.chineseEntrepreneurs.map(\.name))
            availablePeople = SpecialPerson.chineseEntrepreneurs + store.people.filter { !curatedNames.contains($0.name) }
        } else if selectedTopic == .history {
            let curatedNames = Set(SpecialPerson.historicalFigures.map(\.name))
            availablePeople = SpecialPerson.historicalFigures + store.people.filter { !curatedNames.contains($0.name) }
        } else {
            availablePeople = store.people
        }
        return availablePeople.filter { person in
            guard !person.isOrganizationAccount else { return false }
            let matchesTopic = person.topic == selectedTopic
            let matchesQuery = keyword.isEmpty
                || person.name.localizedCaseInsensitiveContains(keyword)
                || (person.handle?.localizedCaseInsensitiveContains(keyword) == true)
                || person.summary.localizedCaseInsensitiveContains(keyword)
            return matchesTopic && matchesQuery
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                topicPicker
                Divider()
                peopleList
            }
            .background(Color(uiColor: .systemBackground).ignoresSafeArea())
            .navigationBarHidden(true)
            .navigationDestination(item: $selectedPerson) { person in
                PersonDetailPage(person: person)
            }
        }
        .task { await store.load() }
        .onAppear { showsDetail = selectedPerson != nil }
        .onChange(of: selectedPerson) { _, person in
            showsDetail = person != nil
        }
        .onDisappear { showsDetail = false }
    }

    private var searchField: some View {
        HStack(spacing: 11) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.secondary)
            TextField("搜索人物", text: $query)
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, 15)
        .frame(height: 48)
        .background(Color(uiColor: .systemGray6), in: RoundedRectangle(cornerRadius: 15))
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 16)
    }

    private var topicPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 30) {
                ForEach(PeopleTopic.allCases) { topic in
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { selectedTopic = topic }
                    } label: {
                        VStack(spacing: 9) {
                            Text(topic.rawValue)
                                .font(.system(size: 15, weight: selectedTopic == topic ? .semibold : .regular))
                                .foregroundStyle(selectedTopic == topic ? Color.blue : Color.primary)
                                .fixedSize()
                            Capsule()
                                .fill(selectedTopic == topic ? Color.blue : Color.clear)
                                .frame(width: 22, height: 3)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedTopic == topic ? .isSelected : [])
                }
            }
            .padding(.horizontal, 24)
        }
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var peopleList: some View {
        if store.isLoading && filteredPeople.isEmpty {
            ProgressView("正在载入特别关心…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = store.errorMessage, filteredPeople.isEmpty {
            ContentUnavailableView {
                Label("载入失败", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error)
            } actions: {
                Button("重试") { Task { await store.load(force: true) } }
            }
        } else if filteredPeople.isEmpty {
            ContentUnavailableView.search(text: query)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredPeople) { person in
                        Button { selectedPerson = person } label: {
                            PersonSignalRow(person: person, latestPost: store.latestPost(for: person))
                        }
                        .buttonStyle(PeoplePressStyle())
                        if person.id != filteredPeople.last?.id {
                            Divider().padding(.leading, 92)
                        }
                    }
                }
                .padding(.bottom, 18)
            }
            .scrollIndicators(.hidden)
            .refreshable { await store.load(force: true) }
        }
    }
}

private struct PersonSignalRow: View {
    let person: SpecialPerson
    let latestPost: Post?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AvatarView(
                url: person.avatarURL(baseURL: ServerConfiguration.currentURL),
                name: person.name,
                size: 52,
                assetName: person.avatarAssetName
            )
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(person.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(person.secondaryLabel ?? "特别关心")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(latestPost?.displayContent ?? person.summary)
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                    .lineSpacing(2)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(activityLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private var activityLine: String {
        if person.isCurated { return "行业人物" }
        if person.isIndustryPerson { return "X · \(latestPost?.formattedTime ?? "暂无更新")" }
        let count = person.todayCount > 0 ? "今天 \(person.todayCount) 条 · " : ""
        return count + (latestPost?.formattedTime ?? person.relativeTime)
    }
}

private struct PersonDetailPage: View {
    let person: SpecialPerson
    @State private var store = PersonDetailStore()
    @State private var section = PersonDetailSection.posts
    @State private var isBioExpanded = false
    @State private var selectedPost: Post?

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
        .toolbar(.hidden, for: .tabBar)
        .navigationDestination(item: $selectedPost) { post in PostDetailView(post: post) }
        .task(id: person.id) { await store.load(person: person) }
    }

    private var personHeader: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .center, spacing: 16) {
                AvatarView(
                    url: person.avatarURL(baseURL: ServerConfiguration.currentURL),
                    name: person.name,
                    size: 72,
                    assetName: person.avatarAssetName
                )
                VStack(alignment: .leading, spacing: 6) {
                    Text(person.name).font(.system(size: 21, weight: .bold))
                    if let label = person.secondaryLabel {
                        Text(label).font(.system(size: 14)).foregroundStyle(.secondary)
                    }
                    Text(personOrganizationLine)
                        .font(.system(size: 15)).foregroundStyle(.primary)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(person.summary)
                    .font(.system(size: 15)).lineSpacing(3).foregroundStyle(.secondary)
                    .lineLimit(isBioExpanded ? nil : 1)
                if !isBioExpanded {
                    Button("展开") { withAnimation(.easeInOut(duration: 0.18)) { isBioExpanded = true } }
                        .font(.system(size: 15)).buttonStyle(.plain).foregroundStyle(.blue)
                }
            }
        }
        .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 18)
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
                    VStack(spacing: 9) {
                        Text(item.title(count: item == .posts ? store.ownPosts.count : store.discussions.count))
                            .font(.system(size: 16, weight: section == item ? .semibold : .regular))
                            .foregroundStyle(section == item ? Color.primary : Color.secondary)
                        Capsule().fill(section == item ? Color.blue : Color.clear).frame(width: 34, height: 3)
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
        if sectionIsLoading {
            ProgressView(section == .posts ? "正在载入他的动态…" : "正在查找相关讨论…")
                .frame(maxWidth: .infinity).padding(.top, 70)
        } else if let error = sectionError {
            ContentUnavailableView("载入失败", systemImage: "wifi.exclamationmark", description: Text(error))
                .padding(.top, 36)
        } else {
            let posts = section == .posts ? store.ownPosts : store.discussions
            if posts.isEmpty {
                ContentUnavailableView(
                    section == .posts ? "暂无本人动态" : "暂无相关讨论",
                    systemImage: section == .posts ? "bubble.left" : "bubble.left.and.bubble.right",
                    description: Text(section == .posts ? "内容库里还没有收录他本人发布的帖子" : "内容库里暂时没有提到这位人物的讨论")
                )
                .padding(.top, 36)
            } else if section == .discussions {
                discussionContent(posts)
            } else {
                ForEach(posts) { post in
                    let displayPost = store.postForDisplay(post)
                    PersonPostRow(post: displayPost, compact: false) { selectedPost = displayPost }
                        .task { await store.translateXPostIfNeeded(post) }
                        .task { await store.loadMoreOwnPostsIfNeeded(current: post, person: person) }
                    Divider().padding(.leading, 20)
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
        section == .posts ? store.isLoadingOwnPosts : store.isLoadingDiscussions
    }

    private var sectionError: String? {
        section == .posts ? store.ownPostsError : store.discussionsError
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
                PersonPostRow(post: displayPost, compact: true) { selectedPost = displayPost }
                    .task { await store.translateXPostIfNeeded(post) }
                Divider().padding(.leading, 72)
            }
        }
    }
}

private enum PersonDetailSection: String, CaseIterable, Identifiable {
    case posts
    case discussions
    var id: Self { self }
    func title(count: Int) -> String {
        let name = self == .posts ? "他的动态" : "相关讨论"
        return count > 0 ? "\(name) \(count)" : name
    }
}

private struct PersonPostRow: View {
    let post: Post
    let compact: Bool
    let onOpen: () -> Void
    @State private var isExpanded = false
    @State private var showsOriginal = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AvatarView(url: post.avatarURL, name: post.authorName, size: compact ? 40 : 48)
            VStack(alignment: .leading, spacing: compact ? 7 : 9) {
                Button(action: onOpen) { authorHeader }
                    .buttonStyle(.plain)

                if isRepost {
                    Label("转发了一条动态", systemImage: "arrow.2.squarepath")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if post.hasTranslation {
                    HStack(spacing: 5) {
                        Image(systemName: "character.bubble")
                        Text(showsOriginal ? "英语原文" : "翻译自英语")
                        Button(showsOriginal ? "显示翻译" : "显示原文") { showsOriginal.toggle() }
                            .foregroundStyle(.blue)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Button(action: onOpen) {
                    Text(visibleContent)
                        .font(.system(size: compact ? 15 : 15.5))
                        .lineSpacing(3)
                        .lineLimit(isExpanded ? nil : (compact ? 4 : 7))
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                if shouldOfferExpansion {
                    Button(isExpanded ? "收起" : "展开全文") { isExpanded.toggle() }
                        .font(.subheadline.weight(.medium))
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                }

                if let quote = post.meta?.quotedTweet {
                    XQuotedPostCard(quote: quote)
                }

                if post.previewURL != nil || !post.videoURLs.isEmpty {
                    XFeedMediaView(post: post)
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

                if !compact {
                    FeedEngagementRow(post: post)
                } else {
                    HStack {
                        FeedEngagementRow(post: post, showsOnlyLikeAndBookmark: true)
                        Spacer(minLength: 0)
                        Button("查看详情", action: onOpen)
                            .font(.caption.weight(.medium))
                            .buttonStyle(.plain)
                            .foregroundStyle(.blue)
                    }
                }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, compact ? 13 : 16)
        .contentShape(Rectangle())
    }

    private var authorHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(post.authorName).font(.system(size: compact ? 16 : 17, weight: .semibold)).lineLimit(1)
                if post.user?.verified == true {
                    Image(systemName: "checkmark.seal.fill").font(.caption).foregroundStyle(.blue)
                }
                Spacer(minLength: 6)
                Text([post.sourceName, post.formattedTime].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            if let handle = post.authorHandle {
                Text(handle).font(.system(size: compact ? 14 : 15)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private var visibleContent: String {
        showsOriginal ? post.originalDisplayContent : post.displayContent
    }

    private var shouldOfferExpansion: Bool {
        visibleContent.count > (compact ? 150 : 260) || visibleContent.filter(\.isNewline).count > 4
    }

    private var isRepost: Bool {
        post.originalDisplayContent.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased().hasPrefix("rt @")
    }
}

private struct XQuotedPostCard: View {
    let quote: XQuotedPost
    @State private var showsOriginal = false

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
            if quote.textZH != nil, quote.originalText != quote.displayText {
                Button(showsOriginal ? "显示翻译" : "显示原文") { showsOriginal.toggle() }
                    .font(.caption).buttonStyle(.plain).foregroundStyle(.blue)
            }
            if let text = showsOriginal ? quote.originalText : quote.displayText {
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
            .background(configuration.isPressed ? Color.primary.opacity(0.045) : Color.clear)
    }
}

#Preview("人物动态") {
    PeopleView(store: PeopleStore())
}
