import SwiftUI
import UIKit

struct PersonDetailSheet: View {
    @Binding var selectedPerson: SpecialPerson?
    let people: [SpecialPerson]
    let onClose: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var incomingEdge: Edge = .trailing

    init(
        selectedPerson: Binding<SpecialPerson?>,
        people: [SpecialPerson],
        onClose: @escaping () -> Void
    ) {
        _selectedPerson = selectedPerson
        self.people = people
        self.onClose = onClose
    }

    var body: some View {
        NavigationStack {
            if let person = selectedPerson {
                ZStack(alignment: .bottomTrailing) {
                    KnowledgePagePalette.canvas.ignoresSafeArea()

                    PersonDetailPage(person: person, movePerson: movePerson)
                        .id(person.id)
                        .transition(reduceMotion ? .opacity : personTransition)

                    HStack(spacing: 5) {
                        if people.count > 1 {
                            personPageButton("上一个人物", symbol: "chevron.left", offset: -1)
                            personPageButton("下一个人物", symbol: "chevron.right", offset: 1)
                            Divider().frame(height: 20)
                        }
                        DetailSheetCloseButton(action: onClose, accessibilityLabel: "关闭人物详情")
                    }
                    .padding(4)
                    .background(.regularMaterial, in: Capsule())
                    .padding(14)
                }
                .clipped()

            }
        }
        .task(id: selectedPerson?.id) {
            guard let selectedPerson else { return }
            await PeopleImagePreheater.preheatDetail(
                for: selectedPerson,
                baseURL: ServerConfiguration.currentURL
            )
            await preheatAdjacentPeople(around: selectedPerson)
        }
    }

    private var personTransition: AnyTransition {
        let outgoingEdge: Edge = incomingEdge == .trailing ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: incomingEdge).combined(with: .opacity),
            removal: .move(edge: outgoingEdge).combined(with: .opacity)
        )
    }

    private func personPageButton(_ label: String, symbol: String, offset: Int) -> some View {
        Button {
            movePerson(offset)
        } label: {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func movePerson(_ offset: Int) {
        let orderedPeople = orderedPeople
        guard orderedPeople.count > 1, let currentPerson = selectedPerson,
              let currentIndex = orderedPeople.firstIndex(where: { $0.id == currentPerson.id }) else { return }
        let nextIndex = (currentIndex + offset + orderedPeople.count) % orderedPeople.count
        incomingEdge = offset > 0 ? .trailing : .leading
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) {
            selectedPerson = orderedPeople[nextIndex]
        }
    }

    private var orderedPeople: [SpecialPerson] {
        people.sorted(by: SpecialPerson.activityOrder)
    }

    private func preheatAdjacentPeople(around person: SpecialPerson) async {
        let orderedPeople = orderedPeople
        guard orderedPeople.count > 1,
              let currentIndex = orderedPeople.firstIndex(where: { $0.id == person.id }) else {
            return
        }
        let previousIndex = (currentIndex - 1 + orderedPeople.count) % orderedPeople.count
        let nextIndex = (currentIndex + 1) % orderedPeople.count
        await withTaskGroup(of: Void.self) { group in
            for index in Set([previousIndex, nextIndex]) {
                let adjacentPerson = orderedPeople[index]
                group.addTask {
                    await PeopleImagePreheater.preheatDetail(
                        for: adjacentPerson,
                        baseURL: ServerConfiguration.currentURL,
                        includesPhotos: false
                    )
                }
            }
        }
    }
}

enum PeopleImagePreheater {
    @MainActor
    static func preheatDetail(for person: SpecialPerson, baseURL: URL, includesPhotos: Bool = true) async {
        let avatarURL = person.avatarAssetName == nil ? person.avatarURL(baseURL: baseURL) : nil
        if let request = ImageLoader.avatarRequest(avatarURL, size: 82) {
            _ = await ImageLoader.shared.image(for: request)
        }

        guard includesPhotos, !Task.isCancelled else { return }
        let thumbnailSize = CGSize(width: 154, height: 96)
        let photoURLs = person.photos.prefix(3).compactMap { $0.imageURL(baseURL: baseURL) }
        await withTaskGroup(of: Void.self) { group in
            for url in photoURLs {
                group.addTask {
                    _ = await ImageLoader.load(url, targetSize: thumbnailSize)
                }
            }
        }
    }
}

enum PersonWikipediaPresentation {
    static func entity(
        for person: SpecialPerson,
        account: PersonSocialAccount
    ) -> WikipediaEntity? {
        guard let url = account.profileURL,
              let host = url.host?.lowercased(),
              host == "wikipedia.org" || host.hasSuffix(".wikipedia.org") else {
            return nil
        }
        return WikipediaEntity(
            id: account.id,
            term: person.name,
            title: account.displayHandle,
            summary: person.summary,
            url: url
        )
    }
}

private struct PersonDetailPage: View {
    private struct ArticleSelection: Identifiable {
        let id: Int64
        let articles: [PersonArticle]
    }

    private static let articleSearchAnchor = "person-article-search"

    let person: SpecialPerson
    let movePerson: (Int) -> Void
    @ObservedObject private var pushNotifications = PersonPushNotificationManager.shared
    @State private var store = PersonDetailStore()
    @State private var section: PersonDetailSection
    @State private var selectedPost: Post?
    @State private var selectedArticle: ArticleSelection?
    @State private var articleSearchText = ""
    @FocusState private var articleSearchIsFocused: Bool
    @State private var selectedPhoto: PersonPhoto?
    @State private var presentedWikipediaEntity: WikipediaEntity?

    init(person: SpecialPerson, movePerson: @escaping (Int) -> Void) {
        self.person = person
        self.movePerson = movePerson
        _section = State(initialValue: person.topic == .history ? .profile : .posts)
    }

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    personHeader.simultaneousGesture(
                        DragGesture(minimumDistance: 32).onEnded { value in
                            let distance = value.translation.width
                            guard abs(distance) >= 64, abs(distance) > abs(value.translation.height) * 1.25 else { return }
                            movePerson(distance < 0 ? 1 : -1)
                        }
                    )
                    if !person.photos.isEmpty {
                        CompactPersonPhotoGallery(photos: person.photos) { selectedPhoto = $0 }
                    }
                    Section {
                        sectionContent
                    } header: {
                        sectionPicker
                    }
                }
                .frame(maxWidth: 650)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 80)
            }
            .onChange(of: articleSearchIsFocused) { _, isFocused in
                guard isFocused else { return }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(180))
                    withAnimation(.snappy(duration: 0.28)) {
                        reader.scrollTo(Self.articleSearchAnchor, anchor: .center)
                    }
                }
            }
        }
        .background(KnowledgePagePalette.canvas)
        .knowledgeWebLinks()
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .appSheet(item: $selectedArticle) { selection in
            NavigationStack {
                PersonArticleDetailView(
                    articles: selection.articles,
                    initialArticleID: selection.id
                )
            }
            .knowledgeWebLinks()
            .readingSheetPresentation()
        }
        .appSheet(item: $selectedPost) { post in
            NavigationStack {
                PostDetailView(post: post)
            }
            .knowledgeWebLinks()
            .readingSheetPresentation()
        }
        .appSheet(item: $selectedPhoto) { photo in
            PersonPhotoViewer(photos: person.photos, initialPhotoID: photo.id)
                .knowledgeWebLinks()
                .readingSheetPresentation()
        }
        .appSheet(item: $presentedWikipediaEntity) { entity in
            WikipediaReaderView(entity: entity)
                .wikipediaReaderPresentation()
        }
        .task(id: person.id) {
            await store.load(person: person)
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--article-detail-preview"),
               let article = store.articles.dropFirst().first ?? store.articles.first {
                section = .articles
                selectedArticle = ArticleSelection(id: article.id, articles: store.articles)
            }

            #endif
        }

        .task(id: normalizedArticleQuery) {
            await store.searchArticles(personID: person.id, query: normalizedArticleQuery)
        }
    }



    private var personHeader: some View {
        let accent = person.topic == .ideology ? KnowledgePagePalette.graph : KnowledgePagePalette.accent
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 13) {
                AvatarView(
                    url: person.avatarURL(baseURL: ServerConfiguration.currentURL),
                    name: person.name,
                    size: 64,
                    assetName: person.avatarAssetName
                )
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text(person.topic.rawValue)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accent)

                    HStack(spacing: 6) {
                        Text(person.name)
                            .font(.title.weight(.bold))
                            .accessibilityAddTraits(.isHeader)
                        if person.hasOwnPostSource {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.footnote)
                                .foregroundStyle(accent)
                                .accessibilityLabel("收录本人动态")
                        }
                    }

                    Text(personOrganizationLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let account = person.socialAccounts.first {
                        socialAccountDestination(account) {
                            Label(account.displayHandle, systemImage: "arrow.up.right")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(accent)
                        }
                        .accessibilityLabel("在\(account.platform)中打开\(account.displayHandle)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                compactNotificationControl
            }

            if !person.displayFocusTags.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(person.displayFocusTags, id: \.self) { tag in
                            Text(tag)
                                .font(.footnote)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(accent.opacity(0.09), in: Capsule())
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(14)
        .knowledgeCard()
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 10)
    }

    private var personOrganizationLine: String {
        person.organizationName ?? (person.hasXSource ? "X 来源" : "人物资料")
    }

    @ViewBuilder
    private func socialAccountDestination<Label: View>(
        _ account: PersonSocialAccount,
        @ViewBuilder label: () -> Label
    ) -> some View {
        if let entity = PersonWikipediaPresentation.entity(for: person, account: account) {
            Button {
                presentedWikipediaEntity = entity
            } label: {
                label()
            }
        } else if let url = account.profileURL {
            Link(destination: url) {
                label()
            }
        }
    }

    private var compactNotificationControl: some View {
        let isEnabled = pushNotifications.isEnabled(for: person.id)
        return Button {
            Task {
                await pushNotifications.setEnabled(!isEnabled, for: person.id)
            }
        } label: {
            Group {
                if pushNotifications.isUpdating {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: isEnabled ? "bell.fill" : "bell")
                        .font(.system(size: 15, weight: .semibold))
                }
            }
            .foregroundStyle(
                pushNotifications.errorMessage == nil
                    ? (isEnabled ? Color.accentColor : Color.secondary)
                    : Color.red
            )
            .frame(width: 44, height: 44)
            .background(
                (isEnabled ? Color.accentColor : Color.secondary).opacity(0.1),
                in: Circle()
            )
            .overlay {
                Circle()
                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
            }
        }
        .buttonStyle(PeoplePressStyle())
        .disabled(pushNotifications.isUpdating)
        .accessibilityLabel(
            isEnabled ? "关闭\(person.name)本机提醒" : "开启\(person.name)本机提醒"
        )
        .accessibilityHint("本人动态或新访谈、圆桌、播客发布时通知")
    }

    private var sectionPicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 5) {
                ForEach(detailSections) { item in
                    Button {
                        section = item
                        articleSearchIsFocused = false
                    } label: {
                        Label(item == .profile && person.topic == .history ? "生平" : item.title, systemImage: item.symbol)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 11)
                            .frame(minHeight: 44)
                            .foregroundStyle(section == item ? .white : KnowledgePagePalette.accent)
                            .background(section == item ? KnowledgePagePalette.hero : .clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(section == item ? .isSelected : [])
                }
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .padding(.vertical, 8)
        .background(KnowledgePagePalette.canvas)
        .overlay(alignment: .bottom) {
            Rectangle().fill(KnowledgePagePalette.stroke).frame(height: 1)
        }
    }

    private var detailSections: [PersonDetailSection] {
        if person.topic == .history {
            return store.articles.isEmpty && store.articlesError == nil
                ? [.profile, .discussions] : [.profile, .articles, .discussions]
        }
        return PersonDetailSection.allCases
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch section {
        case .posts: ownPostsContent
        case .articles: articlesContent
        case .discussions: relatedContent
        case .profile:
            PersonProfileView(person: person) { presentedWikipediaEntity = $0 }
        }
    }

    @ViewBuilder
    private var ownPostsContent: some View {
        if store.isLoadingOwnPosts && store.ownPosts.isEmpty {
            ContentLoadingPlaceholder(title: "正在载入动态")
        } else if let error = store.ownPostsError, store.ownPosts.isEmpty {
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
            LazyVStack(alignment: .leading, spacing: 10) {
                KnowledgeSectionHeading("本人动态", detail: "\(store.ownPosts.count) 条已载入")
                ForEach(store.ownPosts) { post in
                    let displayPost = store.postForDisplay(post)
                    PersonPostTimelineRow(post: displayPost) { selectedPost = displayPost }
                        .task { await store.loadMoreOwnPostsIfNeeded(current: post, person: person) }
                }
                ownPostsPaginationStatus
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
        }
    }

    @ViewBuilder
    private var articlesContent: some View {
        if store.isLoadingArticles && store.articles.isEmpty {
            ContentLoadingPlaceholder(title: "正在载入文章")
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
            LazyVStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(KnowledgePagePalette.accent)
                        .accessibilityHidden(true)
                    TextField("搜索标题、摘要和正文", text: $articleSearchText)
                        .focused($articleSearchIsFocused)
                        .submitLabel(.search)
                        .onSubmit { articleSearchIsFocused = false }
                    if !articleSearchText.isEmpty {
                        Button("清除文章搜索", systemImage: "xmark.circle.fill") { articleSearchText = "" }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 46)
                .knowledgeCard(cornerRadius: 12)
                .id(Self.articleSearchAnchor)

                KnowledgeSectionHeading("文章", detail: articleSearchStatus)

                if isArticleSearchPending {
                    ProgressView("正在搜索正文")
                        .frame(maxWidth: .infinity)
                        .padding(20)
                } else if !normalizedArticleQuery.isEmpty, let error = store.articleSearchError {
                    ContentUnavailableView("搜索失败", systemImage: "wifi.exclamationmark", description: Text(error))
                } else if filteredArticles.isEmpty {
                    ContentUnavailableView("没有找到相关文章", systemImage: "doc.text.magnifyingglass")
                } else {
                    ForEach(filteredArticles) { article in
                        PersonArticleRow(
                            article: article,
                            featured: normalizedArticleQuery.isEmpty && article.id == filteredArticles.first?.id,
                            personName: person.name
                        ) {
                            selectedArticle = ArticleSelection(id: article.id, articles: filteredArticles)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
        }
    }

    private var normalizedArticleQuery: String {
        articleSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isArticleSearchPending: Bool {
        !normalizedArticleQuery.isEmpty &&
            (store.articleSearchQuery != normalizedArticleQuery || store.isSearchingArticles)
    }

    private var filteredArticles: [PersonArticle] {
        guard !normalizedArticleQuery.isEmpty else { return store.articles }
        guard store.articleSearchQuery == normalizedArticleQuery else { return [] }
        return store.articleSearchResults ?? []
    }

    private var articleSearchStatus: String {
        guard !normalizedArticleQuery.isEmpty else {
            return "\(store.articles.count) 篇"
        }
        if isArticleSearchPending {
            return "搜索中"
        }
        return "找到 \(filteredArticles.count) 篇"
    }

    @ViewBuilder
    private var relatedContent: some View {
        if store.isLoadingDiscussions && store.discussions.isEmpty {
            ContentLoadingPlaceholder(title: "正在查找相关动态")
        } else if let error = store.discussionsError, store.discussions.isEmpty {
            ContentUnavailableView("相关动态载入失败", systemImage: "wifi.exclamationmark", description: Text(error))
        } else if store.discussions.isEmpty {
            ContentUnavailableView("暂无相关动态", systemImage: "bubble.left.and.bubble.right")
        } else {
            discussionContent(store.discussions)
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

    private func discussionContent(_ posts: [Post]) -> some View {
        let today = posts.filter(\.isRecentDiscussion)
        let earlier = posts.filter { !$0.isRecentDiscussion }
        return LazyVStack(alignment: .leading, spacing: 13) {
            if !today.isEmpty { discussionGroup(title: "今天", posts: today) }
            if !earlier.isEmpty { discussionGroup(title: "本周稍早", posts: earlier) }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }

    private func discussionGroup(title: String, posts: [Post]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            KnowledgeSectionHeading(title, detail: "\(posts.count) 条")
            ForEach(posts) { post in
                let displayPost = store.postForDisplay(post)
                PersonRelatedPostRow(post: displayPost) { selectedPost = displayPost }
            }
        }
    }
}

private struct CompactPersonPhotoGallery: View {
    let photos: [PersonPhoto]
    let onSelect: (PersonPhoto) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            KnowledgeSectionHeading("人物影像", detail: "\(photos.count) 张")
                .padding(.horizontal, 20)

            ScrollView(.horizontal) {
                LazyHStack(spacing: 10) {
                    ForEach(photos) { photo in
                        Button {
                            onSelect(photo)
                        } label: {
                            Group {
                                if let url = photo.imageURL(baseURL: ServerConfiguration.currentURL) {
                                    RemoteImage(
                                        url: url,
                                        targetWidth: 154,
                                        height: 96,
                                        cornerRadius: 13,
                                        contentMode: .fill
                                    )
                                } else {
                                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                                        .fill(Color.secondary.opacity(0.1))
                                        .overlay {
                                            Image(systemName: "photo")
                                                .foregroundStyle(.secondary)
                                        }
                                }
                            }
                            .frame(width: 154, height: 96)
                            .background(
                                Color(uiColor: .secondarySystemBackground),
                                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                        }
                        .buttonStyle(PeoplePressStyle())
                        .accessibilityLabel(photo.title)
                        .accessibilityIdentifier("person-photo-\(photo.id)")
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.top, 6)
        .padding(.bottom, 12)
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
        VStack(spacing: 0) {
            TabView(selection: $selectedPhotoID) {
                ForEach(photos) { photo in
                    PersonPhotoPage(photo: photo).tag(photo.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack(spacing: 5) {
                photoArrow("上一张", symbol: "chevron.left", offset: -1)
                Text("\(selectedIndex + 1) / \(photos.count)")
                    .font(.footnote.monospacedDigit())
                    .accessibilityLabel("第 \(selectedIndex + 1) 张，共 \(photos.count) 张")
                photoArrow("下一张", symbol: "chevron.right", offset: 1)
                Spacer(minLength: 0)
                DetailSheetCloseButton(action: dismiss.callAsFunction, accessibilityLabel: "关闭人物影像")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(KnowledgePagePalette.surface)
            .overlay(alignment: .top) { Divider() }
        }
        .background(KnowledgePagePalette.canvas.ignoresSafeArea())
    }

    private func photoArrow(_ title: String, symbol: String, offset: Int) -> some View {
        let index = selectedIndex + offset
        return Button {
            guard photos.indices.contains(index) else { return }
            selectedPhotoID = photos[index].id
        } label: {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .disabled(!photos.indices.contains(index))
    }
}

private struct PersonPhotoPage: View {
    let photo: PersonPhoto

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let url = photo.imageURL(baseURL: ServerConfiguration.currentURL) {
                    RemoteImage(url: url, height: 340, cornerRadius: 15, contentMode: .fit)
                        .padding(7)
                        .background(KnowledgePagePalette.hero, in: .rect(cornerRadius: 16))
                } else {
                    ContentUnavailableView("暂无影像", systemImage: "photo")
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(photo.title)
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .knowledgeCard()
            }
            .frame(maxWidth: 650)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct PersonRelatedPostRow: View {
    let post: Post
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 6) {
                if let attribution = post.xRepostAttributionText {
                    Label(attribution, systemImage: "arrow.2.squarepath")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 3)
                }

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
            }
            .padding(13)
            .knowledgeCard(cornerRadius: 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(post.needsXTranslation)
        .accessibilityLabel("\(post.authorName)，\(post.needsXTranslation ? "正在翻译为中文" : post.displayContent)")
    }
}


private enum PersonDetailSection: String, CaseIterable, Identifiable {
    case posts, articles, discussions, profile
    var id: Self { self }

    var title: String {
        switch self {
        case .posts: "动态"
        case .articles: "文章"
        case .discussions: "相关"
        case .profile: "简介"
        }
    }

    var symbol: String {
        switch self {
        case .posts: "text.bubble"
        case .articles: "doc.text"
        case .discussions: "bubble.left.and.bubble.right"
        case .profile: "person.text.rectangle"
        }
    }
}

private struct PersonArticleRow: View {
    let article: PersonArticle
    let featured: Bool
    let personName: String
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(metadataLabel)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(featured ? KnowledgePagePalette.heroTint : .secondary)
                    Spacer(minLength: 6)
                    Image(systemName: "arrow.up.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(featured ? .white : KnowledgePagePalette.accent)
                        .accessibilityHidden(true)
                }
                Text(listTitle)
                    .font(featured ? .title3.weight(.bold) : .headline)
                    .foregroundStyle(featured ? .white : .primary)
                    .lineLimit(3)
                if !article.displaySummary.isEmpty {
                    Text(article.displaySummary)
                        .font(.subheadline)
                        .foregroundStyle(featured ? .white.opacity(0.85) : .secondary)
                        .lineLimit(3)
                }
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(featured ? KnowledgePagePalette.hero : KnowledgePagePalette.surface, in: .rect(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(KnowledgePagePalette.stroke, lineWidth: 1).allowsHitTesting(false) }
        }
        .buttonStyle(.plain)
        .accessibilityHint("打开中文文章")
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
    @Environment(\.dismiss) private var dismiss
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
        VStack(spacing: 0) {
            Group {
                if let loadedArticle { articleBody(loadedArticle) }
                else {
                    VStack(spacing: 0) {
                        if let errorMessage { failureView(errorMessage) }
                        else { loadingView }
                        articlePager
                    }
                }
            }
            .offset(x: horizontalOffset)
        }
        .background(KnowledgePagePalette.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .simultaneousGesture(pageGesture)
        .task(id: article.id) {
            loadedArticle = nil
            errorMessage = nil
            await load()
        }
    }

    private var loadingView: some View {
        ContentLoadingPlaceholder(title: "正在载入正文", layout: .article, rowCount: 4)
            .frame(maxHeight: .infinity, alignment: .top)
    }

    private func failureView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(KnowledgePagePalette.accent)
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
                LazyVStack(alignment: .leading, spacing: 17) {
                    VStack(alignment: .leading, spacing: 9) {
                        Label(article.sourceName, systemImage: "doc.text")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(KnowledgePagePalette.accent)
                        Text(displayTitle(for: article))
                            .font(.largeTitle.weight(.bold))
                            .lineSpacing(3)
                            .accessibilityAddTraits(.isHeader)
                        Text([
                            article.publishedDateLabel,
                            article.readingMinutes > 0 ? "\(article.readingMinutes) 分钟阅读" : nil
                        ].compactMap { $0 }.joined(separator: " · "))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(KnowledgePagePalette.accent.opacity(0.08), in: .rect(cornerRadius: 14))

                    ForEach(Array(Self.paragraphs(from: article.displayContent).enumerated()), id: \.offset) { _, paragraph in
                        Text(paragraph)
                            .font(.body)
                            .lineSpacing(8)
                            .textSelection(.enabled)
                    }

                    if let url = article.canonicalURL {
                        Button { openURL(url) } label: {
                            HStack {
                                Label("英文原文", systemImage: "safari")
                                Spacer()
                                Image(systemName: "arrow.up.right").accessibilityHidden(true)
                            }
                            .font(.subheadline.weight(.semibold))
                            .padding(12)
                            .foregroundStyle(KnowledgePagePalette.accent)
                            .knowledgeCard(cornerRadius: 12)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: 650, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 17)
                .frame(maxWidth: .infinity)
                .measureReadingSheetContent(when: article.id == self.article.id, additionalHeight: 55)
            }
            .accessibilityIdentifier("person-article-scroll")

            articlePager
        }
    }

    private var articlePager: some View {
        HStack(spacing: 5) {
            Button { changeArticle(by: -1) } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 44)
            }
            .accessibilityLabel("上一篇")
            .disabled(!canGoBack)
            .accessibilityIdentifier("person-article-previous")
            Text("\(currentIndex + 1) / \(articles.count)")
                .font(.footnote.monospacedDigit())
                .accessibilityLabel("第 \(currentIndex + 1) 篇，共 \(articles.count) 篇")
            Button { changeArticle(by: 1) } label: {
                Image(systemName: "chevron.right").frame(width: 44, height: 44)
            }
            .accessibilityLabel("下一篇")
            .disabled(!canAdvance)
            .accessibilityIdentifier("person-article-next")
            Spacer(minLength: 0)
            if let url = article.canonicalURL {
                Menu {
                    ShareLink(item: url) { Label("分享文章", systemImage: "square.and.arrow.up") }
                    Button("查看文章原文", systemImage: "safari") { openURL(url) }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("文章操作")
            }
            DetailSheetCloseButton(action: dismiss.callAsFunction, accessibilityLabel: "关闭文章详情")
        }
        .font(.subheadline.weight(.medium))
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background(KnowledgePagePalette.surface)
        .overlay(alignment: .top) { Divider() }
    }

    private func changeArticle(by offset: Int) {
        let target = currentIndex + offset
        guard articles.indices.contains(target) else { return }
        currentIndex = target
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
    let onOpen: () -> Void
    @State private var isExpanded = false

    private var displayContent: String {
        post.isBilibili ? post.bilibiliListContent : post.displayContent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text([post.formattedTime, post.sourceName].compactMap { $0 }.joined(separator: " · "))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(KnowledgePagePalette.accent)
            if let attribution = post.xRepostAttributionText {
                Label(attribution, systemImage: "arrow.2.squarepath")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Button(action: onOpen) {
                Text(displayContent)
                    .font(.body)
                    .lineSpacing(4)
                    .lineLimit(isExpanded ? nil : 7)
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

            if let reply = post.meta?.replyContext,
               let replyText = reply.displayText {
                XReplyContextCard(reply: reply, text: replyText)
            } else if let handle = replyHandle {
                Label("回复 \(handle)", systemImage: "arrowshape.turn.up.left")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
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

        }
        .padding(14)
        .knowledgeCard(cornerRadius: 15)
    }

    private var shouldOfferExpansion: Bool {
        displayContent.count > 280 || displayContent.filter(\.isNewline).count > 4
    }

    private var replyHandle: String? {
        guard let value = post.meta?.inReplyToScreenName?
            .trimmingCharacters(in: CharacterSet(charactersIn: "@")),
              !value.isEmpty else { return nil }
        return "@\(value)"
    }
}

struct XReplyContextCard: View {
    let reply: XReplyContext
    let text: String
    var isDetail = false
    var isTimeline = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("回复 \(reply.handle ?? "这条动态")", systemImage: "arrowshape.turn.up.left")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 9) {
                if let avatar = reply.avatarURL.flatMap(MediaURL.image) {
                    AvatarView(url: avatar, name: reply.authorName ?? reply.handle ?? "回复", size: 28)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        if let name = reply.authorName, !name.isEmpty {
                            Text(name).font(.system(size: isDetail ? 15 : 13, weight: .semibold))
                        }
                        if let handle = reply.handle {
                            Text(handle).font(.system(size: isDetail ? 14 : 12)).foregroundStyle(.secondary)
                        }
                    }
                    if !isDetail && !isTimeline {
                        replyText
                    }
                }
            }
            if isTimeline {
                LocalTranslatedText(original: reply.text ?? text, serverChinese: reply.textZH, field: .reply)
                    .font(.system(size: 15))
                    .lineSpacing(2)
                    .lineLimit(6)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if isDetail {
                XDetailContextText(text: text)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .background((isDetail || isTimeline) ? Color(uiColor: .systemBackground) : Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
        }
    }
    private var replyText: some View {
        Text(text)
            .font(isDetail ? .body : .system(size: 14))
            .lineSpacing(isDetail ? 5 : 3)
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PersonProfileView: View {
    let person: SpecialPerson
    let openWikipedia: (WikipediaEntity) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !person.summary.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Label(person.topic == .history ? "生平概要" : "人物简介", systemImage: "person.text.rectangle")
                        .font(.headline)
                        .foregroundStyle(KnowledgePagePalette.accent)
                    Text(person.summary)
                        .font(.body)
                        .lineSpacing(6)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(KnowledgePagePalette.accent.opacity(0.08), in: .rect(cornerRadius: 15))
                .padding(.horizontal, 20)
                .padding(.top, 14)
            }

            if !person.roles.isEmpty {
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

            }

            if !person.displayFocusTags.isEmpty {
                profileSection(person.topic == .history ? "历史主题" : "关注领域") {
                    ScrollView(.horizontal) {
                        HStack(spacing: 7) {
                            ForEach(person.displayFocusTags, id: \.self) { tag in
                                Text(tag)
                                    .font(.footnote.weight(.medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(KnowledgePagePalette.accent.opacity(0.08), in: Capsule())
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }

            if !person.socialAccounts.isEmpty {
                profileSection("社交媒体") {
                    VStack(spacing: 0) {
                        ForEach(Array(person.socialAccounts.enumerated()), id: \.element.id) { index, account in
                            socialAccountDestination(account)
                            if index < person.socialAccounts.count - 1 { Divider() }
                        }
                    }
                }
            }

            if !person.milestones.isEmpty {
                profileSection(person.topic == .history ? "生平时间线" : "重要经历") {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(presentedMilestones.enumerated()), id: \.offset) { _, milestone in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(milestone.year)
                                    .font(.caption.monospacedDigit().weight(.semibold))
                                    .foregroundStyle(KnowledgePagePalette.accent)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 4)
                                    .background(KnowledgePagePalette.accent.opacity(0.09), in: .rect(cornerRadius: 6))
                                Text(milestone.title)
                                    .font(.subheadline)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }

            if !person.relatedPeople.isEmpty {
                profileSection("相关人物") {
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: 12) {
                            ForEach(person.relatedPeople) { related in
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
                                .frame(width: 88)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
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

    @ViewBuilder
    private func socialAccountDestination(_ account: PersonSocialAccount) -> some View {
        if let entity = PersonWikipediaPresentation.entity(for: person, account: account) {
            Button {
                openWikipedia(entity)
            } label: {
                socialAccountRow(account, opensInApp: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("在应用内查看\(account.displayHandle)的维基百科词条")
        } else if let url = account.profileURL {
            Link(destination: url) {
                socialAccountRow(account, opensInApp: false)
            }
            .accessibilityLabel("在\(account.platform)中打开\(account.displayHandle)")
        }
    }

    private func socialAccountRow(
        _ account: PersonSocialAccount,
        opensInApp: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: socialIcon(for: account.platform))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(account.platform)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                Text(account.displayHandle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: opensInApp ? "chevron.right" : "arrow.up.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    private var presentedMilestones: [PersonMilestone] {
        guard person.topic == .history else { return person.milestones }
        return person.milestones.sorted {
            (Int($0.year) ?? .max) < (Int($1.year) ?? .max)
        }
    }

    private func socialIcon(for platform: String) -> String {
        switch platform.lowercased() {
        case "微博": "message.fill"
        case "哔哩哔哩", "bilibili": "play.rectangle.fill"
        case "x": "at"
        default: "link"
        }
    }

    private func profileSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            KnowledgeSectionHeading(title)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .knowledgeCard()
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }
}

private struct XQuotedPostCard: View {
    let quote: XQuotedPost
    @State private var liveTranslation: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                if let avatar = quote.author?.profileImageURL.flatMap(MediaURL.image) {
                    AvatarView(url: avatar, name: quote.author?.name ?? "引用动态", size: 24)
                }
                Text(quote.author?.name ?? "引用动态").font(.subheadline.weight(.semibold)).lineLimit(1)
                if let handle = quote.author?.handle {
                    Text(handle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            if let text = displayedText {
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

    private var displayedText: String? {
        return nonempty(quote.textZH)
            ?? liveTranslation
            ?? quote.originalText
    }

    private func nonempty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
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
                        targetWidth: itemWidth,
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
