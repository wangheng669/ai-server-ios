import SwiftUI
import UIKit

struct PersonDetailSheet: View {
    @Binding var selectedPerson: SpecialPerson?
    let people: [SpecialPerson]
    let onClose: () -> Void
    @GestureState private var isHorizontalDragging = false
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
                    Color(uiColor: .systemBackground)
                        .ignoresSafeArea()

                    PersonDetailPage(
                        person: person,
                        showsNavigationChrome: false,
                        usesSheetLayout: true
                    )
                    .id(person.id)
                    .transition(personTransition)
                    .disabled(isHorizontalDragging)

                    closeButton
                        .padding(.bottom, 16)
                        .padding(.trailing, 15)
                }
                .clipped()
                .contentShape(Rectangle())
                .simultaneousGesture(personSwitchGesture)
                .accessibilityHint("左右滑动切换人物，下滑关闭人物详情")
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

    private var personSwitchGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .updating($isHorizontalDragging) { value, isDragging, _ in
                let horizontalDistance = value.translation.width
                let verticalDistance = value.translation.height
                guard abs(horizontalDistance) > abs(verticalDistance) * 1.15 else { return }
                isDragging = true
            }
            .onEnded(switchPerson)
    }

    private var closeButton: some View {
        DetailSheetCloseButton(action: onClose, accessibilityLabel: "关闭人物详情")
    }

    private func switchPerson(_ value: DragGesture.Value) {
        let orderedPeople = orderedPeople
        let horizontalDistance = value.translation.width
        let verticalDistance = value.translation.height
        guard orderedPeople.count > 1,
              abs(horizontalDistance) >= 64,
              abs(horizontalDistance) > abs(verticalDistance) * 1.25,
              let currentPerson = selectedPerson,
              let currentIndex = orderedPeople.firstIndex(where: { $0.id == currentPerson.id }) else {
            return
        }

        let indexOffset = horizontalDistance < 0 ? 1 : -1
        let nextIndex = (currentIndex + indexOffset + orderedPeople.count) % orderedPeople.count
        incomingEdge = horizontalDistance < 0 ? .trailing : .leading
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        withAnimation(.snappy(duration: 0.3)) {
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
        _ = await ImageLoader.load(
            avatarURL,
            targetSize: CGSize(width: 66, height: 66)
        )

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
    let showsNavigationChrome: Bool
    let usesSheetLayout: Bool
    @ObservedObject private var pushNotifications = PersonPushNotificationManager.shared
    @State private var store = PersonDetailStore()
    @State private var section: PersonDetailSection
    @State private var ownContentSection = PersonOwnContentSection.posts
    @State private var selectedPost: Post?
    @State private var selectedArticle: ArticleSelection?
    @State private var articleSearchText = ""
    @FocusState private var articleSearchIsFocused: Bool
    @State private var selectedPhoto: PersonPhoto?
    @State private var presentedWikipediaEntity: WikipediaEntity?

    init(
        person: SpecialPerson,
        showsNavigationChrome: Bool = true,
        usesSheetLayout: Bool = false
    ) {
        self.person = person
        self.showsNavigationChrome = showsNavigationChrome
        self.usesSheetLayout = usesSheetLayout
        _section = State(initialValue: person.topic == .history ? .profile : .posts)
    }

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    personHeader
                    if !person.photos.isEmpty {
                        if usesSheetLayout {
                            CompactPersonPhotoGallery(photos: person.photos) { selectedPhoto = $0 }
                        } else {
                            PersonPhotoGallery(photos: person.photos) { selectedPhoto = $0 }
                        }
                    }
                    Section {
                        sectionContent
                    } header: {
                        sectionPicker
                    }
                }
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
        .background(
            Color(
                uiColor: usesSheetLayout
                    ? .systemGroupedBackground
                    : .systemBackground
            )
        )
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(showsNavigationChrome ? .visible : .hidden, for: .navigationBar)
        .toolbar {
            if showsNavigationChrome {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(person.socialAccounts) { account in
                            if let entity = PersonWikipediaPresentation.entity(
                                for: person,
                                account: account
                            ) {
                                Button {
                                    presentedWikipediaEntity = entity
                                } label: {
                                    Label("在应用内查看维基百科", systemImage: "book.pages")
                                }
                            } else if let url = account.profileURL {
                                Link(destination: url) {
                                    Label("在 \(account.platform) 中打开", systemImage: "arrow.up.right.square")
                                }
                            }
                        }
                        ForEach(person.socialAccounts) { account in
                            Button {
                                UIPasteboard.general.string = account.displayHandle
                            } label: {
                                Label("复制\(account.platform)账号", systemImage: "doc.on.doc")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("更多")
                }
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .appSheet(item: $selectedArticle) { selection in
            NavigationStack {
                PersonArticleDetailView(
                    articles: selection.articles,
                    initialArticleID: selection.id
                )
            }
            .readingSheetPresentation()
        }
        .appSheet(item: $selectedPost) { post in
            NavigationStack {
                PostDetailView(post: post)
            }
            .readingSheetPresentation()
        }
        .appSheet(item: $selectedPhoto) { photo in
            PersonPhotoViewer(photos: person.photos, initialPhotoID: photo.id)
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
                ownContentSection = .articles
                selectedArticle = ArticleSelection(id: article.id, articles: store.articles)
            }

            #endif
        }

        .task(id: normalizedArticleQuery) {
            await store.searchArticles(personID: person.id, query: normalizedArticleQuery)
        }
    }



    @ViewBuilder
    private var personHeader: some View {
        if usesSheetLayout {
            sheetPersonHeader
        } else {
            standardPersonHeader
        }
    }

    private var sheetPersonHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                AvatarView(
                    url: person.avatarURL(baseURL: ServerConfiguration.currentURL),
                    name: person.name,
                    size: 72,
                    assetName: person.avatarAssetName
                )
                .overlay {
                    Circle()
                        .stroke(Color(uiColor: .systemBackground), lineWidth: 3)
                }
                .shadow(color: Color.accentColor.opacity(0.14), radius: 12, y: 5)

                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        Text(person.name)
                            .font(.system(size: 23, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        if person.hasOwnPostSource {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.accentColor)
                        }
                    }

                    Text(personOrganizationLine)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    HStack(spacing: 7) {
                        Text(person.topic.rawValue)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 9)
                            .frame(height: 25)
                            .background(Color.accentColor.opacity(0.11), in: Capsule())

                        if let account = person.socialAccounts.first {
                            socialAccountDestination(account) {
                                HStack(spacing: 3) {
                                    Image(systemName: "at")
                                        .font(.system(size: 10, weight: .semibold))
                                    Text(account.displayHandle.replacingOccurrences(of: "@", with: ""))
                                        .lineLimit(1)
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 8, weight: .bold))
                                }
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                            }
                            .accessibilityLabel("在\(account.platform)中打开\(account.displayHandle)")
                        }
                    }
                }

                Spacer(minLength: 2)

                compactNotificationControl
                    .padding(.trailing, 38)
            }

            if !person.displayFocusTags.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 7) {
                        ForEach(person.displayFocusTags, id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary.opacity(0.78))
                                .padding(.horizontal, 10)
                                .frame(height: 27)
                                .background(.thinMaterial, in: Capsule())
                                .overlay {
                                    Capsule()
                                        .stroke(Color.primary.opacity(0.055), lineWidth: 0.5)
                                }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 30)
        .padding(.bottom, 14)
        .background(alignment: .topLeading) {
            LinearGradient(
                colors: [
                    Color(uiColor: .systemBackground),
                    Color.accentColor.opacity(0.055),
                    Color(uiColor: .systemBackground)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var standardPersonHeader: some View {
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
                    Text("\(person.topic.rawValue) · \(person.displayFocusTags.first ?? "人物")")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                    if let account = person.socialAccounts.first {
                        socialAccountDestination(account) {
                            HStack(spacing: 4) {
                                Text("\(account.platform) · \(account.displayHandle)")
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("在\(account.platform)中打开\(account.displayHandle)")
                    }
                }
            }

            HStack(spacing: 9) {
                ForEach(person.displayFocusTags, id: \.self) { tag in
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

            personNotificationControl
        }
        .padding(.horizontal, 20)
        .padding(.top, 5)
        .padding(.bottom, 18)
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

    private var personNotificationControl: some View {
        let isEnabled = pushNotifications.isEnabled(for: person.id)
        return Button {
            Task {
                await pushNotifications.setEnabled(!isEnabled, for: person.id)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isEnabled ? "bell.fill" : "bell")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(
                        isEnabled ? Color.accentColor : Color.secondary
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(isEnabled ? "已开启本机提醒" : "开启本机提醒")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(pushNotifications.errorMessage ?? "本人动态或新访谈、圆桌、播客发布时通知")
                        .font(.system(size: 11.5))
                        .foregroundStyle(
                            pushNotifications.errorMessage == nil ? Color.secondary : Color.red
                        )
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                if pushNotifications.isUpdating {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(Color.secondary.opacity(0.075), in: RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.plain)
        .disabled(pushNotifications.isUpdating)
        .accessibilityLabel(
            isEnabled ? "关闭\(person.name)本机提醒" : "开启\(person.name)本机提醒"
        )
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
            .frame(width: 36, height: 36)
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
        .padding(.top, usesSheetLayout ? 18 : 0)
        .background(.regularMaterial)
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
            PersonProfileView(person: person, usesCardLayout: usesSheetLayout) {
                presentedWikipediaEntity = $0
            }
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
            ForEach(store.ownPosts) { post in
                let displayPost = store.postForDisplay(post)
                PersonPostTimelineRow(post: displayPost, compact: false) { selectedPost = displayPost }
                    .task { await store.loadMoreOwnPostsIfNeeded(current: post, person: person) }
            }
            ownPostsPaginationStatus
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
            LazyVStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("搜索文章文字", text: $articleSearchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($articleSearchIsFocused)
                        .submitLabel(.search)
                        .onSubmit {
                            articleSearchIsFocused = false
                        }
                    if !articleSearchText.isEmpty {
                        Button {
                            articleSearchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("清除文章搜索")
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 42)
                .background(
                    Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 12)
                )
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .id(Self.articleSearchAnchor)
                .contentShape(Rectangle())
                .onTapGesture {
                    articleSearchIsFocused = true
                }

                HStack(alignment: .firstTextBaseline) {
                    Text(articleSearchStatus)
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

                if isArticleSearchPending {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text("正在搜索文章正文…")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 42)
                } else if !normalizedArticleQuery.isEmpty, let error = store.articleSearchError {
                    ContentUnavailableView(
                        "搜索失败",
                        systemImage: "wifi.exclamationmark",
                        description: Text(error)
                    )
                    .padding(.vertical, 28)
                } else if filteredArticles.isEmpty {
                    ContentUnavailableView(
                        "没有找到相关文章",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("没有包含“\(articleSearchText)”的文章，试试其他关键词")
                    )
                    .padding(.vertical, 32)
                } else {
                    ForEach(Array(filteredArticles.enumerated()), id: \.element.id) { index, article in
                        PersonArticleRow(
                            article: article,
                            featured: articleSearchText.isEmpty && index == 0,
                            portraitURL: person.avatarURL(baseURL: ServerConfiguration.currentURL),
                            portraitAssetName: person.avatarAssetName,
                            personName: person.name
                        ) {
                            selectedArticle = ArticleSelection(id: article.id, articles: filteredArticles)
                        }

                        if index < filteredArticles.count - 1 {
                            Divider()
                                .padding(.leading, 20)
                        }
                    }
                }
            }
            .padding(.bottom, 28)
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
            return "文章 \(store.articles.count)"
        }
        if isArticleSearchPending {
            return "正在搜索标题、摘要和正文…"
        }
        return "找到 \(filteredArticles.count) 篇"
    }

    @ViewBuilder
    private var relatedContent: some View {
                    if store.isLoadingDiscussions && store.discussions.isEmpty {
                        ContentLoadingPlaceholder(title: "正在查找相关动态")
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

private struct CompactPersonPhotoGallery: View {
    let photos: [PersonPhoto]
    let onSelect: (PersonPhoto) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("人物影像")
                    .font(.system(size: 18, weight: .bold))
                Spacer()
                Text("\(photos.count) 张")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
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
        .padding(.bottom, 16)
        .background(Color(uiColor: .systemBackground))
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
                        targetWidth: 210,
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
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .bottomTrailing) {
                DetailSheetCloseButton(action: dismiss.callAsFunction, accessibilityLabel: "关闭人物影像")
                    .padding(16)
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
            VStack(alignment: .leading, spacing: 6) {
                if let attribution = post.xRepostAttributionText {
                    Label(attribution, systemImage: "arrow.2.squarepath")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 54)
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
        .background(Color(uiColor: .systemBackground))
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
            .accessibilityIdentifier("person-article-scroll")

            articlePager
        }
    }

    private var articlePager: some View {
        HStack(spacing: 8) {
            Button { changeArticle(by: -1) } label: {
                Label("上一篇", systemImage: "chevron.left")
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .disabled(!canGoBack)
            .accessibilityIdentifier("person-article-previous")
            Button { changeArticle(by: 1) } label: {
                HStack { Text("下一篇"); Image(systemName: "chevron.right") }
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .disabled(!canAdvance)
            .accessibilityIdentifier("person-article-next")
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
        .padding(.horizontal, 20)
        .background(Color(uiColor: .systemBackground))
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
    let compact: Bool
    let onOpen: () -> Void
    @State private var isExpanded = false

    private var displayContent: String {
        post.isBilibili ? post.bilibiliListContent : post.displayContent
    }

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
                if let attribution = post.xRepostAttributionText {
                    Label(attribution, systemImage: "arrow.2.squarepath")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                Button(action: onOpen) {
                    Text(displayContent)
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

                Divider().padding(.top, 4)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, compact ? 14 : 18)
        .contentShape(Rectangle())
    }

    private var shouldOfferExpansion: Bool {
        displayContent.count > (compact ? 150 : 280) || displayContent.filter(\.isNewline).count > 4
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
                    RemoteImage(url: avatar, targetWidth: 28, height: 28, cornerRadius: 14)
                        .frame(width: 28, height: 28)
                        .clipped()
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
                Text(text)
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
    let usesCardLayout: Bool
    let openWikipedia: (WikipediaEntity) -> Void

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
                    ForEach(person.displayFocusTags, id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 11)
                            .frame(height: 27)
                            .background(Color.secondary.opacity(0.09), in: Capsule())
                    }
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
            Text(title).font(.system(size: usesCardLayout ? 18 : 17, weight: .bold))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, usesCardLayout ? 16 : 20)
        .padding(.vertical, usesCardLayout ? 16 : 0)
        .padding(.top, usesCardLayout ? 0 : 16)
        .padding(.bottom, usesCardLayout ? 0 : 14)
        .background(
            usesCardLayout
                ? Color(uiColor: .secondarySystemGroupedBackground)
                : Color.clear,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .padding(.horizontal, usesCardLayout ? 16 : 0)
        .padding(.top, usesCardLayout ? 10 : 0)
        .overlay(alignment: .bottom) {
            if !usesCardLayout {
                Divider().padding(.leading, 20)
            }
        }
    }
}

private struct XQuotedPostCard: View {
    let quote: XQuotedPost
    @State private var liveTranslation: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                if let avatar = quote.author?.profileImageURL.flatMap(MediaURL.image) {
                    RemoteImage(url: avatar, targetWidth: 24, height: 24, cornerRadius: 12)
                        .frame(width: 24, height: 24).clipped()
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
