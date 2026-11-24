import SwiftUI
import UIKit
import OSLog
import AVFoundation
import UserNotifications

private let learningImageLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "AIServerClient",
    category: "LearningImages"
)

struct LearningView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.rootTabIsActive) private var rootTabIsActive
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let peopleStore: PeopleStore
    @State private var store: LearningStore
    @State private var repository = LearningContentRepository()
    @State private var progressStore = LearningProgressStore()
    @State private var selectedRoute: LearningRoute?
    @State private var resumedLesson: LearningRoute?
    @State private var selectedIdeologyPerson: SpecialPerson?
    @State private var ideologyCampFilter: IdeologyCampFilter = .all
    @State private var selectedConcept: KnowledgeConceptCard?
    @State private var selectedConceptID: String?
    @State private var shuffledConcepts: [KnowledgeConceptCard] = []
    @State private var presentedSection: KnowledgeSection? = {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--city-preview") || arguments.contains("--city-province-preview") ||
            arguments.contains("--city-city-preview") || arguments.contains("--city-district-preview") {
            return .city
        }
        if arguments.contains("--people-preview") || arguments.contains("--person-detail-preview") ||
            arguments.contains("--article-detail-preview") {
            return .people
        }
        if ProcessInfo.processInfo.arguments.contains("--learning-books-preview") ||
            ProcessInfo.processInfo.arguments.contains("--learning-book-preview") {
            return .books
        }
        if ProcessInfo.processInfo.arguments.contains("--learning-concepts-preview") ||
            ProcessInfo.processInfo.arguments.contains("--learning-concept-detail-preview") {
            return .concepts
        }
        if ProcessInfo.processInfo.arguments.contains("--learning-ideology-preview") {
            return .ideology
        }
        if ProcessInfo.processInfo.arguments.contains("--learning-detail-preview") ||
            ProcessInfo.processInfo.arguments.contains("--learning-video-preview") {
            return .investment
        }
        #endif
        return nil
    }()
    @State private var readingReminder = ReadingReminderManager()

    @MainActor
    init(
        peopleStore: PeopleStore,
        store: LearningStore
    ) {
        self.peopleStore = peopleStore
        _store = State(initialValue: store)
    }

    var body: some View {
        ScrollView {
            knowledgeHome
        }
        .refreshable {
            async let overview: Void = store.loadOverview(force: true)
            await peopleStore.load(force: true)
            await overview
        }
        .scrollIndicators(.hidden)
        .background(KnowledgePagePalette.surface.ignoresSafeArea())
        .accessibilityIdentifier("knowledge-home")
        .appSheet(item: $presentedSection, onDismiss: resetSectionSelection) { section in
            knowledgeSection(section)
        }
        .appSheet(item: $resumedLesson) { route in
            lessonDetail(route)
        }
        .task(id: rootTabIsActive) {
            guard rootTabIsActive else { return }
            await store.loadOverview()
            #if DEBUG
            if (ProcessInfo.processInfo.arguments.contains("--learning-detail-preview") ||
                ProcessInfo.processInfo.arguments.contains("--learning-video-preview")),
               selectedRoute == nil,
               let topic = store.catalog?.sections
                .flatMap(\.topics)
                .first(where: { $0.title.contains("市盈率") }) {
                let milestones = LearningMilestone.plan(from: store.catalog?.stockTopics ?? [])
                if let index = milestones.firstIndex(where: { $0.topic.id == topic.id }) {
                    selectedRoute = route(for: milestones[index], at: index, total: milestones.count)
                } else {
                    selectedRoute = .topic(topic)
                }
            }
            #endif
        }
        .task(id: rootTabIsActive, priority: .utility) {
            guard rootTabIsActive else { return }
            await peopleStore.load()
        }
        .task(id: "books-\(rootTabIsActive)") {
            guard rootTabIsActive else { return }
            await readingReminder.restore()
        }
        .task(id: conceptImagePrefetchKey) {
            guard rootTabIsActive,
                  let concepts = store.conceptLibrary?.concepts else {
                return
            }
            await KnowledgeConceptImageLoading.prefetch(Array(concepts.prefix(3)))
        }
    }

    private var conceptImagePrefetchKey: String {
        let imageURLs = store.conceptLibrary?.concepts.prefix(3).compactMap {
            $0.coverURL?.absoluteString
        } ?? []
        return "\(rootTabIsActive)-\(imageURLs.joined(separator: "|"))"
    }

    private var knowledgeHome: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("知识")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            if let notice = store.savedContentNotice {
                Label(notice, systemImage: "clock.arrow.circlepath")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("knowledge-saved-content")
            }
            investmentOverview
            VStack(alignment: .leading, spacing: 10) {
                knowledgeHeading("阅读")
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(spacing: 10))
                    : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
                layout {
                    bookCollection
                    conceptCollection
                }
            }
            VStack(alignment: .leading, spacing: 7) {
                knowledgeHeading("探索")
                explorationDirectory
            }
        }
        .frame(maxWidth: 600)
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity)
    }

    private var investmentOverview: some View {
        let milestones = LearningMilestone.plan(from: store.catalog?.stockTopics ?? [])
        let completed = progressStore.completedCount(in: milestones.map(\.topic))
        let currentIndex = milestones.firstIndex { !progressStore.isCompleted($0.topic.id) }

        return VStack(spacing: 0) {
            if let index = currentIndex ?? milestones.indices.last {
                let milestone = milestones[index]
                let actionTitle = completed == milestones.count ? "复习课程" : "继续学习"
                Button {
                    resumedLesson = route(for: milestone, at: index, total: milestones.count)
                } label: {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("股票入门")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(KnowledgePagePalette.accent)
                            Spacer(minLength: 8)
                            HStack(spacing: 5) {
                                Text(actionTitle)
                                Image(systemName: "arrow.right")
                                    .accessibilityHidden(true)
                            }
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(KnowledgePagePalette.accent)
                        }

                        Text(milestone.title)
                            .font(.title3.bold())
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)

                        ProgressView(value: Double(completed), total: Double(milestones.count))
                            .tint(KnowledgePagePalette.accent)
                            .accessibilityHidden(true)

                        Text("已完成 \(completed) / \(milestones.count) 节")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(15)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(KnowledgePagePalette.accent.opacity(0.065))
                }
                .buttonStyle(LearningPressStyle())
                .accessibilityIdentifier("knowledge-investment-resume")
            }

            investmentEntry(hasPath: !milestones.isEmpty)
        }
        .knowledgeCard(cornerRadius: 18)
    }

    private func investmentEntry(hasPath: Bool) -> some View {
        let lesson = store.videoLibrary?.lessons.first
        let courseStatus: String
        if !hasPath, store.errorMessage != nil {
            courseStatus = "学习路径载入失败"
        } else {
            courseStatus = knowledgeStatus(
                count: store.videoLibrary?.lessons.count,
                unit: "节视频课",
                error: store.videoLibraryErrorMessage
            )
        }

        return Button {
            presentedSection = .investment
        } label: {
            KnowledgeDirectoryRow(title: "投资学习", subtitle: courseStatus) {
                KnowledgeHomeImage(url: lesson?.coverURL, size: CGSize(width: 112, height: 74)) { image in
                    if let image {
                        image.resizable().scaledToFill()
                    } else {
                        knowledgeSymbol(.investment)
                    }
                }
                .frame(width: 62, height: 42)
                .clipShape(.rect(cornerRadius: 8))
            }
            .padding(.horizontal, 12)
        }
        .buttonStyle(LearningPressStyle())
        .accessibilityIdentifier("knowledge-investment-entry")
    }

    private var bookCollection: some View {
        let book = store.bookshelf?.books.first
        return KnowledgeCollectionTile(
            section: .books,
            status: knowledgeStatus(
                count: store.bookshelf?.books.count,
                unit: "本",
                error: store.bookshelfErrorMessage
            ),
            itemTitle: book?.title,
            open: { presentedSection = .books }
        ) {
            KnowledgeHomeImage(url: book?.coverURL, size: CGSize(width: 120, height: 128)) { image in
                if let image {
                    image.resizable().scaledToFit()
                } else {
                    knowledgeSymbol(.books)
                }
            }
            .frame(width: 48, height: 56)
            .clipShape(.rect(cornerRadius: 5))
        }
    }

    private var conceptCollection: some View {
        let concept = store.conceptLibrary?.concepts.first
        return KnowledgeCollectionTile(
            section: .concepts,
            status: knowledgeStatus(
                count: store.conceptLibrary?.concepts.count,
                unit: "张",
                error: store.conceptLibraryErrorMessage
            ),
            itemTitle: concept?.title,
            open: { presentedSection = .concepts }
        ) {
            KnowledgeHomeImage(url: concept?.coverURL, size: CGSize(width: 68, height: 68)) { image in
                if let image {
                    image.resizable().scaledToFill()
                } else {
                    knowledgeSymbol(.concepts)
                }
            }
            .frame(width: 62, height: 56)
            .clipShape(.rect(cornerRadius: 8))
        }
    }

    private var explorationDirectory: some View {
        VStack(spacing: 0) {
            directoryEntry(.people, subtitle: directoryStatus(for: peopleStore.people.count)) {
                if let person = peopleStore.people.first {
                    AvatarView(
                        url: person.avatarURL(baseURL: peopleStore.baseURL),
                        name: person.name,
                        size: 38,
                        assetName: person.avatarAssetName
                    )
                } else {
                    knowledgeSymbol(.people)
                }
            }

            Divider().padding(.leading, 66)

            directoryEntry(.ideology, subtitle: directoryStatus(for: ideologyPeople.count)) {
                knowledgeSymbol(.ideology)
            }

            Divider().padding(.leading, 66)

            directoryEntry(.city, subtitle: "广东 · 21 个城市") {
                Image("ShenzhenSkyline")
                    .resizable()
                    .scaledToFill()
            }
        }
    }

    private func directoryEntry<Artwork: View>(
        _ section: KnowledgeSection,
        subtitle: String,
        @ViewBuilder artwork: @escaping () -> Artwork
    ) -> some View {
        Button {
            presentedSection = section
        } label: {
            KnowledgeDirectoryRow(title: section.title, subtitle: subtitle) {
                artwork()
                    .frame(width: 46, height: 42)
                    .clipShape(.rect(cornerRadius: 8))
            }
            .padding(.horizontal, 8)
        }
        .buttonStyle(LearningPressStyle())
        .accessibilityIdentifier(section.entryIdentifier)
    }

    private func knowledgeHeading(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .accessibilityAddTraits(.isHeader)
    }

    private func knowledgeSymbol(_ section: KnowledgeSection) -> some View {
        Image(systemName: section.icon)
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(section.tint)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(section.tint.opacity(0.09))
    }

    private func directoryStatus(for count: Int) -> String {
        knowledgeStatus(
            count: peopleStore.hasLoadedDirectory || !peopleStore.people.isEmpty ? count : nil,
            unit: "位",
            error: peopleStore.errorMessage
        )
    }

    private func knowledgeStatus(count: Int?, unit: String, error: String?) -> String {
        if let count {
            return error == nil ? "\(count) \(unit)" : "\(count) \(unit) · 更新失败"
        }
        return error == nil ? "载入中" : "载入失败"
    }

    @ViewBuilder
    private func knowledgeSection(_ section: KnowledgeSection) -> some View {
        switch section {
        case .investment:
            KnowledgeSectionPanel(title: section.title) {
                investmentContent
            }
            .appSheet(item: $selectedRoute) { route in
                lessonDetail(route)
            }
        case .books:
            KnowledgeSectionPanel(title: section.title) {
                booksContent
            }
        case .concepts:
            KnowledgeSectionPanel(title: section.title) {
                conceptsContent
            }
            .appSheet(item: $selectedConcept) { concept in
                if let url = concept.wikipediaURL {
                    WikipediaReaderView(
                        entity: WikipediaEntity(
                            id: concept.id,
                            term: concept.wikipediaTitle,
                            title: concept.wikipediaTitle,
                            summary: concept.summary,
                            url: url
                        )
                    )
                    .wikipediaReaderPresentation()
                }
            }
            #if DEBUG
            .onChange(of: store.conceptLibrary?.concepts, initial: true) { _, concepts in
                guard ProcessInfo.processInfo.arguments.contains("--learning-concept-detail-preview"),
                      selectedConcept == nil, let concepts, !concepts.isEmpty else { return }
                let index = conceptCardPreviewIndex ?? 0
                selectedConcept = concepts[concepts.indices.contains(index) ? index : 0]
            }
            #endif
        case .ideology:
            KnowledgeSectionPanel(title: section.title) {
                ideologyCampPicker
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
                ideologyContent
            }
            .appSheet(isPresented: ideologyPersonIsPresented) {
                PersonDetailSheet(
                    selectedPerson: $selectedIdeologyPerson,
                    people: ideologyPeople,
                    onClose: { selectedIdeologyPerson = nil }
                )
                .appPresentationDetents([.large])
                .appPresentationCornerRadius(28)
                .appPresentationScrollsWithoutExpanding()
            }
        case .people:
            PeopleView(store: peopleStore)
                .readingSheetPresentation()
        case .city:
            CityNewsView()
                .readingSheetPresentation()
        }
    }

    private func lessonDetail(_ route: LearningRoute) -> some View {
        NavigationStack {
            switch route {
            case let .topic(topic, position):
                LearningDetailView(
                    topic: topic,
                    repository: repository,
                    progressStore: progressStore,
                    position: position
                )
            case let .videoLesson(lesson):
                LearningVideoLessonDetailView(seed: lesson)
            }
        }
        .appPresentationDetents([.large])
        .appPresentationCornerRadius(28)
        .appPresentationScrollsWithoutExpanding()
    }

    private func resetSectionSelection() {
        selectedRoute = nil
        selectedConcept = nil
        selectedIdeologyPerson = nil
    }

    @ViewBuilder
    private var investmentContent: some View {
        videoLessons
        if let catalog = store.catalog {
            let milestones = LearningMilestone.plan(from: catalog.stockTopics)
            WeeklyStudyCard(studiedDays: progressStore.studyDays())
                .padding(.horizontal, 20)
            learningPath(milestones)
            savedTopics(in: catalog, excluding: Set(milestones.map(\.topic.id)))
        } else if store.isLoading {
            InvestmentContentLoadingView()
        } else {
            ContentUnavailableView {
                Label("投资知识载入失败", systemImage: "wifi.exclamationmark")
            } description: {
                Text(store.errorMessage ?? "请稍后重试")
            } actions: {
                Button("重试") { Task { await store.load(force: true) } }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
        }
    }

    @ViewBuilder
    private var videoLessons: some View {
        if let lessons = store.videoLibrary?.lessons, !lessons.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("小Lin说")
                        .font(.system(size: 20, weight: .bold, design: .serif))
                    Text("投资视频课")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(KnowledgePagePalette.supportingText)
                    Spacer()
                    Label("\(lessons.count) 期", systemImage: "play.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(KnowledgePagePalette.accent)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)

                ScrollView(.horizontal) {
                    LazyHStack(spacing: 13) {
                        ForEach(lessons) { lesson in
                            Button {
                                selectedRoute = .videoLesson(lesson)
                            } label: {
                                LearningVideoLessonCard(lesson: lesson)
                            }
                            .buttonStyle(LearningPressStyle())
                            .accessibilityIdentifier("knowledge-video-\(lesson.id)")
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .scrollIndicators(.hidden)
                .padding(.bottom, 18)
            }
        } else if store.isVideoLibraryLoading {
            ContentLoadingPlaceholder(title: "正在载入课程视频", layout: .cards)
        } else if let error = store.videoLibraryErrorMessage {
            ContentUnavailableView {
                Label("投资视频课载入失败", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error)
            } actions: {
                Button("重试") { Task { await store.loadVideoLibrary(force: true) } }
            }
        }
    }

    @ViewBuilder
    private func learningPath(_ milestones: [LearningMilestone]) -> some View {
        Text("股票入门路径")
            .font(.system(size: 24, weight: .bold, design: .serif))
            .padding(.horizontal, 20)
            .padding(.top, 26)
            .padding(.bottom, 13)

        if milestones.isEmpty {
            ContentUnavailableView(
                "暂无学习内容",
                systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                description: Text("稍后重新进入页面查看")
            )
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
        } else {
            let completedCount = progressStore.completedCount(in: milestones.map(\.topic))
            let currentIndex = milestones.firstIndex {
                !progressStore.isCompleted($0.topic.id)
            }
            VStack(spacing: 0) {
                ForEach(Array(milestones.enumerated()), id: \.element.id) { index, milestone in
                    Button {
                        selectedRoute = route(for: milestone, at: index, total: milestones.count)
                    } label: {
                        LearningMilestoneRow(
                            number: index + 1,
                            title: milestone.title,
                            topic: milestone.topic,
                            isCurrent: index == currentIndex,
                            isCompleted: progressStore.isCompleted(milestone.topic.id),
                            isLast: index == milestones.count - 1,
                            completedCount: completedCount,
                            totalCount: milestones.count
                        )
                    }
                    .buttonStyle(LearningPressStyle())
                    .accessibilityIdentifier("knowledge-lesson-\(milestone.topic.id)")
                }
            }
            .padding(.horizontal, 20)
        }
    }

    @ViewBuilder
    private func savedTopics(in catalog: LearningCatalog, excluding excludedIDs: Set<String>) -> some View {
        let topics = Array(
            catalog.sections
                .flatMap(\.topics)
                .filter { !excludedIDs.contains($0.id) }
                .prefix(2)
        )
        if topics.isEmpty {
            EmptyView()
        } else {
            Divider()
                .padding(.horizontal, 20)
                .padding(.top, 20)

            Text("稍后阅读")
                .font(.system(size: 21, weight: .bold, design: .serif))
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 7)

            VStack(spacing: 0) {
                ForEach(topics) { topic in
                    Button {
                        selectedRoute = .topic(topic)
                    } label: {
                        LearningTopicRow(topic: topic)
                    }
                    .buttonStyle(LearningPressStyle())
                    if topic.id != topics.last?.id {
                        Divider().padding(.leading, 112)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    @ViewBuilder
    private var booksContent: some View {
        let books = store.bookshelf?.books ?? []
        if let bookshelf = store.bookshelf, !books.isEmpty {
            Text("\(books.count) 本 · \(bookshelf.source)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }

        if store.isBookshelfLoading && store.bookshelf == nil {
            ContentLoadingPlaceholder(title: "正在载入书架", layout: .cards)
        } else if store.bookshelfErrorMessage != nil && store.bookshelf == nil {
            ContentUnavailableView {
                Label("书架载入失败", systemImage: "wifi.exclamationmark")
            } description: {
                Text("请稍后重试")
            } actions: {
                Button("重新载入") {
                    Task { await store.loadBookshelf(force: true) }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 36)
        } else if books.isEmpty {
            ContentUnavailableView(
                "暂无可展示书籍",
                systemImage: "books.vertical",
                description: Text("稍后重新进入页面查看")
            )
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        } else {
            BooksReadingSummaryCard(
                bookshelf: store.bookshelf,
                reminder: readingReminder
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            if let book = books.first {
                Button {
                    if let url = book.openURL {
                        openURL(url)
                    }
                } label: {
                    BookReadingDeskCard(
                        book: book,
                        source: store.bookshelf?.source ?? "微信读书"
                    )
                }
                .buttonStyle(LearningPressStyle())
                .padding(.horizontal, 20)

                if books.count > 1 {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("书架")
                            .font(.system(size: 17, weight: .bold, design: .serif))

                        ForEach(Array(books.dropFirst().enumerated()), id: \.element.id) { index, recentBook in
                            Button {
                                if let url = recentBook.openURL {
                                    openURL(url)
                                }
                            } label: {
                                RecentKnowledgeBookRow(
                                    book: recentBook,
                                    paletteIndex: index + 1
                                )
                            }
                            .buttonStyle(LearningPressStyle())

                            if recentBook.id != books.last?.id {
                                Divider()
                                    .padding(.leading, 76)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 22)
                }
            }
        }
    }

    @ViewBuilder
    private var conceptsContent: some View {
        if let library = store.conceptLibrary {
            let concepts = shuffledConcepts.isEmpty ? library.concepts : shuffledConcepts
            VStack(alignment: .leading, spacing: 0) {
                if concepts.isEmpty {
                    ContentUnavailableView(
                        "暂无概念",
                        systemImage: "rectangle.stack",
                        description: Text("稍后重新进入页面查看")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 36)
                } else {
                    GeometryReader { proxy in
                        ScrollView(.horizontal) {
                            LazyHStack(spacing: 12) {
                                ForEach(Array(concepts.enumerated()), id: \.element.id) { index, concept in
                                    KnowledgeConceptCarouselCard(
                                        concept: concept,
                                        index: index,
                                        count: concepts.count,
                                        width: max(280, proxy.size.width - 40),
                                        height: proxy.size.height
                                    )
                                    .frame(width: max(280, proxy.size.width - 40))
                                    .id(concept.id)
                                    .onTapGesture {
                                        selectedConcept = concept
                                    }
                                }
                            }
                            .scrollTargetLayout()
                            .padding(.horizontal, 20)
                        }
                        .scrollIndicators(.hidden)
                        .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
                        .scrollPosition(id: $selectedConceptID)
                    }
                    .frame(height: 540)
                }
            }
            .onChange(of: library.concepts, initial: true) { _, loadedConcepts in
                #if DEBUG
                let isConceptPreview = ProcessInfo.processInfo.arguments.contains(
                    "--learning-concepts-preview"
                ) || ProcessInfo.processInfo.arguments.contains(
                    "--learning-concept-detail-preview"
                )
                let shuffled = isConceptPreview
                    ? loadedConcepts
                    : Array(loadedConcepts.prefix(1)) + loadedConcepts.dropFirst().shuffled()
                #else
                let shuffled = Array(loadedConcepts.prefix(1)) + loadedConcepts.dropFirst().shuffled()
                #endif
                shuffledConcepts = shuffled
                let IDs = shuffled.map(\.id)
                #if DEBUG
                if let previewIndex = conceptCardPreviewIndex,
                   IDs.indices.contains(previewIndex) {
                    self.selectedConceptID = IDs[previewIndex]
                    return
                }
                #endif
                self.selectedConceptID = IDs.first
            }
        } else if store.isConceptLibraryLoading {
            ContentLoadingPlaceholder(title: "正在载入概念卡片", layout: .cards)
        } else if store.conceptLibraryErrorMessage != nil {
            ContentUnavailableView {
                Label("概念载入失败", systemImage: "wifi.exclamationmark")
            } description: {
                Text(store.conceptLibraryErrorMessage ?? "请稍后重试")
            } actions: {
                Button("重新载入") {
                    Task { await store.loadConceptLibrary(force: true) }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 36)
        } else {
            ContentUnavailableView(
                "暂无概念",
                systemImage: "rectangle.stack",
                description: Text("稍后重新进入页面查看")
            )
            .frame(maxWidth: .infinity)
            .padding(.top, 36)
        }
    }

    #if DEBUG
    private var conceptCardPreviewIndex: Int? {
        let prefix = "--learning-concept-card-index="
        guard let argument = ProcessInfo.processInfo.arguments.first(where: {
            $0.hasPrefix(prefix)
        }) else {
            return nil
        }
        return Int(argument.dropFirst(prefix.count))
    }
    #endif

    @ViewBuilder
    private var ideologyContent: some View {
        if peopleStore.isLoading && peopleStore.people.isEmpty {
            IdeologyContentLoadingView()
        } else if let error = peopleStore.errorMessage, peopleStore.people.isEmpty {
            ContentUnavailableView {
                Label("人物载入失败", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error)
            } actions: {
                Button("重新载入") {
                    Task { await peopleStore.load(force: true) }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 36)
        } else if ideologyPeople.isEmpty {
            ContentUnavailableView(
                "暂无人物",
                systemImage: "person.2",
                description: Text("人物资料正在整理中")
            )
            .frame(maxWidth: .infinity)
            .padding(.top, 36)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(visibleIdeologyCamps) { camp in
                    ideologyCampSection(
                        title: camp.title,
                        color: camp.color,
                        people: ideologyPeople.filter { IdeologyCamp(person: $0) == camp }
                    )
                }

                if ideologyCampFilter == .all, !unassignedIdeologyPeople.isEmpty {
                    ideologyCampSection(
                        title: "未分组",
                        color: .secondary,
                        people: unassignedIdeologyPeople
                    )
                }

                Text("阵营仅为内容整理标签")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
    }

    private var ideologyCampPicker: some View {
        HStack(spacing: 0) {
            ForEach(IdeologyCampFilter.allCases) { filter in
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        ideologyCampFilter = filter
                    }
                } label: {
                    Text(filter.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ideologyCampFilter == filter ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .background {
                            if ideologyCampFilter == filter {
                                Capsule()
                                    .fill(KnowledgePagePalette.surface)
                                    .overlay {
                                        Capsule()
                                            .stroke(KnowledgePagePalette.stroke, lineWidth: 0.8)
                                    }
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.035), in: Capsule())
        .overlay {
            Capsule()
                .stroke(KnowledgePagePalette.stroke, lineWidth: 0.7)
        }
        .sensoryFeedback(.selection, trigger: ideologyCampFilter)
    }

    private func ideologyCampSection(
        title: String,
        color: Color,
        people: [SpecialPerson]
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                Text("\(people.count)")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 8, alignment: .top),
                    count: 5
                ),
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(people) { person in
                    Button {
                        selectedIdeologyPerson = person
                    } label: {
                        IdeologyPersonGridCell(
                            person: person,
                            baseURL: peopleStore.baseURL
                        )
                    }
                    .buttonStyle(LearningPressStyle())
                    .accessibilityIdentifier("ideology-person-\(person.id)")
                }
            }
        }
    }

    private var visibleIdeologyCamps: [IdeologyCamp] {
        switch ideologyCampFilter {
        case .all:
            IdeologyCamp.allCases
        case .loyalist:
            [.loyalist]
        case .rebel:
            [.rebel]
        }
    }

    private var ideologyPeople: [SpecialPerson] {
        peopleStore.people.filter { $0.topic == .ideology }
    }

    private var unassignedIdeologyPeople: [SpecialPerson] {
        ideologyPeople.filter { IdeologyCamp(person: $0) == nil }
    }

    private var ideologyPersonIsPresented: Binding<Bool> {
        Binding(
            get: { selectedIdeologyPerson != nil },
            set: { isPresented in
                if !isPresented {
                    selectedIdeologyPerson = nil
                }
            }
        )
    }

    private func route(
        for milestone: LearningMilestone,
        at index: Int,
        total: Int
    ) -> LearningRoute {
        .topic(milestone.topic, position: LearningLessonPosition(title: milestone.title, number: index + 1, count: total))
    }
}

private enum KnowledgeSection: String, Identifiable {
    case investment
    case books
    case concepts
    case people
    case ideology
    case city

    var id: Self { self }
    var entryIdentifier: String { "knowledge-\(rawValue)-entry" }

    var title: String {
        switch self {
        case .investment: "投资学习"
        case .books: "书籍"
        case .concepts: "概念卡片"
        case .people: "人物"
        case .ideology: "思想图谱"
        case .city: "城市观察"
        }
    }

    var icon: String {
        switch self {
        case .investment: "chart.line.uptrend.xyaxis"
        case .books: "books.vertical"
        case .concepts: "rectangle.on.rectangle"
        case .people: "person.2"
        case .ideology: "point.3.connected.trianglepath.dotted"
        case .city: "building.2"
        }
    }

    var tint: Color {
        switch self {
        case .investment: KnowledgePagePalette.accent
        case .books, .people: Color(red: 0.23, green: 0.40, blue: 0.32)
        case .concepts: Color(red: 0.59, green: 0.33, blue: 0.16)
        case .ideology, .city: Color(red: 0.30, green: 0.33, blue: 0.54)
        }
    }
}

private struct KnowledgeCollectionTile<Artwork: View>: View {
    let section: KnowledgeSection
    let status: String
    let itemTitle: String?
    let open: () -> Void
    @ViewBuilder let artwork: () -> Artwork
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 4) {
                    Text(section.title)
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 3)
                        .accessibilityHidden(true)
                }

                HStack(alignment: .center, spacing: 7) {
                    artwork()
                        .accessibilityHidden(true)
                    if let itemTitle {
                        Text(itemTitle)
                            .font(.footnote.weight(.medium))
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                    }
                }

                Text(status)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.leading)
            .padding(11)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .knowledgeCard(cornerRadius: 14)
        }
        .buttonStyle(LearningPressStyle())
        .accessibilityIdentifier(section.entryIdentifier)
    }
}

private struct KnowledgeDirectoryRow<Artwork: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let artwork: () -> Artwork

    var body: some View {
        HStack(spacing: 12) {
            artwork()
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.leading)

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 8)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }
}

private struct KnowledgeSectionPanel<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                DetailSheetCloseButton(action: dismiss.callAsFunction, accessibilityLabel: "关闭\(title)")
                    .accessibilityIdentifier("detail-sheet-close")
            }
            .padding(.leading, 20)
            .padding(.trailing, 12)
            .padding(.vertical, 8)
            .background(KnowledgePagePalette.surface)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, content: content)
                    .padding(.top, 14)
                    .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
        }
        .background(KnowledgePagePalette.surface.ignoresSafeArea())
        .readingSheetPresentation()
    }
}

private extension View {
    func knowledgeCard(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        return background(KnowledgePagePalette.surface, in: shape)
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(KnowledgePagePalette.stroke, lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

private enum LearningRoute: Hashable, Identifiable {
    case topic(LearningTopic, position: LearningLessonPosition? = nil)
    case videoLesson(LearningVideoLesson)

    var id: String {
        switch self {
        case let .topic(topic, _): "topic-\(topic.id)"
        case let .videoLesson(lesson): "video-\(lesson.id)"
        }
    }
}

private enum KnowledgePagePalette {
    static let accent = InvestmentDesign.accent
    static let sage = Color(red: 0.40, green: 0.48, blue: 0.39)
    static let canvas = InvestmentDesign.canvas
    static let surface = InvestmentDesign.surface
    static let stroke = InvestmentDesign.divider
    static let supportingText = Color.secondary
}

enum IdeologyCamp: String, CaseIterable, Identifiable {
    case loyalist = "忠臣"
    case rebel = "反贼"

    var id: Self { self }
    var title: String {
        switch self {
        case .loyalist: "正方"
        case .rebel: "反方"
        }
    }

    var color: Color {
        switch self {
        case .loyalist:
            KnowledgePagePalette.accent
        case .rebel:
            Color(red: 0.20, green: 0.38, blue: 0.58)
        }
    }

    init?(person: SpecialPerson) {
        guard let camp = Self.allCases.first(where: { person.focusTags.contains($0.rawValue) }) else {
            return nil
        }
        self = camp
    }
}

private enum IdeologyCampFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case loyalist = "忠臣"
    case rebel = "反贼"

    var id: Self { self }
    var title: String {
        switch self {
        case .all: "全部"
        case .loyalist: "正方"
        case .rebel: "反方"
        }
    }
}

private struct IdeologyPersonGridCell: View {
    let person: SpecialPerson
    let baseURL: URL

    var body: some View {
        VStack(spacing: 5) {
            AvatarView(
                url: person.avatarURL(baseURL: baseURL),
                name: person.name,
                size: 50,
                assetName: person.avatarAssetName
            )

            Text(person.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct WeeklyStudyCard: View {
    private let days = ["一", "二", "三", "四", "五", "六", "日"]
    let studiedDays: Set<Int>

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("本周学习")
                    .font(.system(size: 16, weight: .semibold))
                Text("\(studiedDays.count)")
                    .font(.system(size: 25, weight: .bold, design: .serif))
                    .foregroundStyle(KnowledgePagePalette.accent)
                Text("天")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(KnowledgePagePalette.supportingText)
                Spacer()
                Text(studiedDays.isEmpty ? "完成课程后记录" : "保持节奏")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(KnowledgePagePalette.supportingText)
            }

            HStack {
                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                    VStack(spacing: 9) {
                        Text(day)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(KnowledgePagePalette.supportingText)
                        Circle()
                            .fill(
                                studiedDays.contains(index)
                                    ? KnowledgePagePalette.accent
                                    : KnowledgePagePalette.stroke
                            )
                            .frame(width: 8, height: 8)
                    }
                    if index != days.indices.last {
                        Spacer()
                    }
                }
            }
        }
        .padding(17)
        .background(KnowledgePagePalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(KnowledgePagePalette.stroke, lineWidth: 0.8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("本周学习\(studiedDays.count)天")
    }
}

private struct LearningVideoLessonCard: View {
    let lesson: LearningVideoLesson

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: lesson.coverURL) { phase in
                    if case let .success(image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        LinearGradient(
                            colors: [
                                Color(red: 0.22, green: 0.16, blue: 0.13),
                                KnowledgePagePalette.accent.opacity(0.78)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                }
                .frame(width: 210, height: 112)
                .clipped()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.64)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                HStack(spacing: 7) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text(lesson.durationText)
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(height: 27)
                .background(.black.opacity(0.55), in: Capsule())
                .padding(9)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(lesson.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(lesson.creator)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(KnowledgePagePalette.supportingText)
            }
            .padding(11)
        }
        .frame(width: 210)
        .background(KnowledgePagePalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(KnowledgePagePalette.stroke, lineWidth: 0.8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("打开视频课")
    }
}

private struct LearningVideoLessonDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var lesson: LearningVideoLesson
    @State private var isLoadingDetail = false
    @State private var player: AVPlayer?
    @State private var playbackState: LearningVideoPlaybackState = .idle
    @State private var playbackTask: Task<Void, Never>?
    @State private var pendingStartSeconds = 0
    @State private var isPlaying = false
    @State private var currentPlaybackTime = 0.0
    @State private var playbackDuration = 0.0
    @State private var timeObserver: Any?
    @State private var showsFullscreenPlayer = false
    @State private var posterImage: UIImage?

    init(seed: LearningVideoLesson) {
        _lesson = State(initialValue: seed)
    }

    var body: some View {
        ZStack {
            KnowledgePagePalette.canvas.ignoresSafeArea()
            VStack(spacing: 0) {
                videoSurface

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        heroMetadata
                        introduction
                        watchPoints
                        chapters
                        relatedTopics
                        sourceNote
                    }
                    .padding(.bottom, 44)
                }
                .scrollIndicators(.hidden)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            DetailSheetCloseButton(action: dismiss.callAsFunction, accessibilityLabel: "关闭视频详情")
                .padding(16)
        }
        .background(InteractivePopGestureEnabler())
        .toolbar(.hidden, for: .navigationBar)
        .appFullScreenCover(isPresented: $showsFullscreenPlayer) {
            GeometryReader { geometry in
                ZStack {
                    Color.black.ignoresSafeArea()
                    if let player {
                        LearningInlineVideoPlayer(
                            player: player,
                            posterURL: lesson.coverURL,
                            posterImage: posterImage,
                            isPlaying: $isPlaying,
                            currentTime: $currentPlaybackTime,
                            duration: $playbackDuration,
                            isFullscreen: true
                        ) {
                            dismissFullscreenPlayer()
                        }
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .persistentSystemOverlays(.hidden)
            .onDisappear {
                AppOrientationController.shared.setVideoFullscreen(false)
            }
        }
        .task(id: lesson.id) {
            guard lesson.chapters.isEmpty else { return }
            isLoadingDetail = true
            defer { isLoadingDetail = false }
            if let detail = try? await LearningService().fetchVideoLesson(id: lesson.id) {
                lesson = detail
            }
        }
        .task(id: lesson.coverURL) {
            guard let url = lesson.coverURL else { return }
            posterImage = await ImageLoader.load(
                url,
                targetSize: CGSize(width: 1_200, height: 675)
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemFailedToPlayToEndTime)) { notification in
            guard let failedItem = notification.object as? AVPlayerItem,
                  failedItem === player?.currentItem else { return }
            player?.pause()
            player = nil
            playbackState = .failed
        }
        .onDisappear {
            playbackTask?.cancel()
            stopObservingPlayback()
            player?.pause()
            player = nil
        }
    }

    private var videoSurface: some View {
        ZStack {
            Color.black

            if let player {
                LearningInlineVideoPlayer(
                    player: player,
                    posterURL: lesson.coverURL,
                    posterImage: posterImage,
                    isPlaying: $isPlaying,
                    currentTime: $currentPlaybackTime,
                    duration: $playbackDuration
                ) {
                    presentFullscreenPlayer()
                }
            } else {
                AsyncImage(url: lesson.coverURL) { phase in
                    if case let .success(image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        LinearGradient(
                            colors: [.black, KnowledgePagePalette.accent.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                }
                .clipped()

                if playbackState != .loading {
                    LinearGradient(
                        colors: [.black.opacity(0.20), .clear, .black.opacity(0.48)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }

            switch playbackState {
            case .idle:
                playButton(symbol: "play.fill", accessibilityLabel: "播放视频")
            case .loading:
                LearningVideoLoadingIndicator()
            case .playing:
                EmptyView()
            case .failed:
                Button {
                    startPlayback()
                } label: {
                    Label("重新加载", systemImage: "arrow.clockwise")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 40)
                        .background(.black.opacity(0.68), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipped()
        .shadow(color: .black.opacity(0.12), radius: 10, y: 5)
        .zIndex(2)
    }

    private var heroMetadata: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Text(lesson.creator)
                    .foregroundStyle(KnowledgePagePalette.accent)
                Text("·")
                Text(lesson.durationText)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)

            Text(lesson.title)
                .font(.system(size: 29, weight: .bold, design: .serif))
                .foregroundStyle(.primary)
                .tracking(-0.3)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    private func playButton(symbol: String, accessibilityLabel: String) -> some View {
        Button {
            startPlayback()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 25, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 62, height: 62)
                .background(KnowledgePagePalette.accent.opacity(0.94), in: Circle())
                .shadow(color: .black.opacity(0.28), radius: 9, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func presentFullscreenPlayer() {
        AppOrientationController.shared.setVideoFullscreen(true)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            showsFullscreenPlayer = true
        }
    }

    private func dismissFullscreenPlayer() {
        AppOrientationController.shared.setVideoFullscreen(false)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            showsFullscreenPlayer = false
        }
    }

    private func startPlayback(at seconds: Int = 0) {
        if let player {
            seek(player, to: seconds)
            playbackState = .playing
            player.play()
            isPlaying = true
            return
        }
        pendingStartSeconds = seconds
        if playbackTask != nil { return }
        guard let pageURL = lesson.watchURL() else {
            playbackState = .failed
            return
        }

        playbackState = .loading
        playbackTask = Task { @MainActor in
            defer { playbackTask = nil }
            do {
                let source = try await APIClient(
                    baseURL: ServerConfiguration.currentURL
                ).resolveBilibiliPlayback(url: pageURL, title: lesson.title)
                try Task.checkCancellation()

                let asset = AVURLAsset(
                    url: source.url,
                    options: ["AVURLAssetHTTPHeaderFieldsKey": source.httpHeaders]
                )
                guard try await asset.load(.isPlayable) else {
                    throw LearningError.invalidResponse
                }
                try Task.checkCancellation()

                #if !targetEnvironment(simulator)
                let audioSession = AVAudioSession.sharedInstance()
                try? audioSession.setCategory(.playback, mode: .moviePlayback)
                try? audioSession.setActive(true)
                #endif

                let item = AVPlayerItem(asset: asset)
                item.preferredForwardBufferDuration = 2
                let newPlayer = AVPlayer(playerItem: item)
                newPlayer.automaticallyWaitsToMinimizeStalling = true
                #if targetEnvironment(simulator)
                newPlayer.isMuted = true
                #endif
                player = newPlayer
                playbackState = .playing
                observePlayback(newPlayer)
                seek(newPlayer, to: pendingStartSeconds)
                newPlayer.play()
                isPlaying = true
            } catch is CancellationError {
                return
            } catch {
                player = nil
                playbackState = .failed
            }
        }
    }

    private func seek(_ player: AVPlayer, to seconds: Int) {
        guard seconds > 0 else { return }
        player.seek(
            to: CMTime(seconds: Double(seconds), preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    private func observePlayback(_ player: AVPlayer) {
        stopObservingPlayback()
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { time in
            currentPlaybackTime = max(0, time.seconds.isFinite ? time.seconds : 0)
            let seconds = player.currentItem?.duration.seconds ?? 0
            if seconds.isFinite, seconds > 0 {
                playbackDuration = seconds
            }
        }
    }

    private func stopObservingPlayback() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("这堂课讲什么")
            Text(lesson.description.isEmpty ? lesson.summary : lesson.description)
                .font(.system(size: 15.5))
                .foregroundStyle(.primary.opacity(0.86))
                .lineSpacing(6)
        }
        .padding(.horizontal, 20)
        .padding(.top, 26)
    }

    @ViewBuilder
    private var watchPoints: some View {
        if !lesson.watchPoints.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("带着问题看")
                VStack(alignment: .leading, spacing: 13) {
                    ForEach(Array(lesson.watchPoints.enumerated()), id: \.offset) { index, point in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .frame(width: 23, height: 23)
                                .background(KnowledgePagePalette.accent, in: Circle())
                            Text(point)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.primary.opacity(0.88))
                                .padding(.top, 2)
                        }
                    }
                }
                .padding(16)
                .background(KnowledgePagePalette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(KnowledgePagePalette.stroke, lineWidth: 0.8)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
        }
    }

    @ViewBuilder
    private var chapters: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                sectionTitle("章节")
                Spacer()
                if isLoadingDetail { ProgressView().controlSize(.small) }
            }

            if !lesson.chapters.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(lesson.chapters.enumerated()), id: \.element.id) { index, chapter in
                        Button {
                            startPlayback(at: chapter.startSeconds)
                        } label: {
                            HStack(spacing: 13) {
                                Text(chapter.timestampText)
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(KnowledgePagePalette.accent)
                                    .frame(width: 42, alignment: .leading)
                                Text(chapter.title)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                Image(systemName: "play.circle")
                                    .font(.system(size: 18))
                                    .foregroundStyle(KnowledgePagePalette.accent)
                            }
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if index != lesson.chapters.indices.last {
                            Divider().padding(.leading, 55)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
    }

    @ViewBuilder
    private var relatedTopics: some View {
        if !lesson.relatedTopics.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("顺着学")
                Text("这些概念能帮你把视频里的方法落到具体知识上。")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(lesson.relatedTopics) { topic in
                            Text(topic.title)
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(KnowledgePagePalette.accent)
                                .padding(.horizontal, 11)
                                .frame(height: 32)
                                .background(KnowledgePagePalette.accent.opacity(0.09), in: Capsule())
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
        }
    }

    private var sourceNote: some View {
        Text("视频版权归原作者所有，本页使用应用内播放器提供学习导览。")
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 20)
            .padding(.top, 30)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 21, weight: .bold, design: .serif))
    }
}

private struct LearningVideoLoadingIndicator: View {
    @State private var rotates = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.36), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: 0.26)
                .stroke(
                    .white,
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                )
                .rotationEffect(.degrees(rotates ? 360 : 0))
        }
        .frame(width: 32, height: 32)
        .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
        .accessibilityLabel("正在载入视频")
        .onAppear {
            withAnimation(.linear(duration: 0.72).repeatForever(autoreverses: false)) {
                rotates = true
            }
        }
    }
}

private struct LearningInlineVideoPlayer: View {
    let player: AVPlayer
    let posterURL: URL?
    let posterImage: UIImage?
    @Binding var isPlaying: Bool
    @Binding var currentTime: Double
    @Binding var duration: Double
    var isFullscreen = false
    let onFullscreen: () -> Void
    @State private var showsControls = true
    @State private var controlsTask: Task<Void, Never>?
    @State private var isSeeking = false
    @State private var seekPreview = 0.0
    @State private var isVideoReady = false

    var body: some View {
        ZStack {
            LearningPlayerLayer(player: player) {
                guard !isVideoReady else { return }
                withAnimation(.easeOut(duration: 0.16)) {
                    isVideoReady = true
                }
            }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.18)) {
                        showsControls.toggle()
                    }
                    if showsControls, isPlaying {
                        scheduleControlsDismissal()
                    } else {
                        controlsTask?.cancel()
                    }
                }

            if !isVideoReady {
                Group {
                    if let posterImage {
                        Image(uiImage: posterImage)
                            .resizable()
                            .scaledToFill()
                    } else {
                        AsyncImage(url: posterURL) { phase in
                            if case let .success(image) = phase {
                                image
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                Color.clear
                            }
                        }
                    }
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }

            if showsControls {
                HStack(spacing: 28) {
                    seekButton(seconds: -15, symbol: "gobackward.15")

                    Button {
                        togglePlayback()
                    } label: {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 23, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 58, height: 58)
                            .background(.white.opacity(0.18), in: Circle())
                            .overlay {
                                Circle().stroke(.white.opacity(0.28), lineWidth: 0.8)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isPlaying ? "暂停" : "播放")

                    seekButton(seconds: 15, symbol: "goforward.15")
                }

                VStack {
                    Spacer()
                    HStack(spacing: 9) {
                        Text(timeText(isSeeking ? seekPreview : currentTime))
                            .frame(width: 38, alignment: .leading)

                        Slider(
                            value: Binding(
                                get: {
                                    min(
                                        max(isSeeking ? seekPreview : currentTime, 0),
                                        max(duration, 1)
                                    )
                                },
                                set: { seekPreview = $0 }
                            ),
                            in: 0...max(duration, 1),
                            onEditingChanged: { editing in
                                isSeeking = editing
                                if editing {
                                    seekPreview = currentTime
                                    controlsTask?.cancel()
                                } else {
                                    seek(to: seekPreview)
                                    if isPlaying { scheduleControlsDismissal() }
                                }
                            }
                        )
                        .tint(KnowledgePagePalette.accent)

                        Text(timeText(duration))
                            .frame(width: 38, alignment: .trailing)
                    }
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.72), radius: 2, y: 1)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                controlsTask?.cancel()
                onFullscreen()
            } label: {
                Image(systemName: isFullscreen ? "xmark" : "arrow.up.left.and.arrow.down.right")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.55), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isFullscreen ? "关闭全屏视频" : "全屏播放")
            .padding(16)
        }
        .onAppear {
            if isPlaying { scheduleControlsDismissal() }
        }
        .onDisappear {
            controlsTask?.cancel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { note in
            guard let item = note.object as? AVPlayerItem,
                  item === player.currentItem else { return }
            isPlaying = false
            showsControls = true
            controlsTask?.cancel()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(isFullscreen ? "learning-fullscreen-player" : "learning-inline-player")
        .accessibilityValue("\(Int(currentTime))")
    }

    private func seekButton(seconds: Double, symbol: String) -> some View {
        Button {
            let target = min(max(currentTime + seconds, 0), max(duration, 0))
            seek(to: target)
            if isPlaying { scheduleControlsDismissal() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(seconds < 0 ? "后退15秒" : "前进15秒")
    }

    private func togglePlayback() {
        if isPlaying {
            player.pause()
            controlsTask?.cancel()
        } else {
            if currentTime >= duration - 0.5, duration > 0 {
                seek(to: 0)
            }
            player.play()
            scheduleControlsDismissal()
        }
        isPlaying.toggle()
    }

    private func seek(to seconds: Double) {
        let target = max(seconds, 0)
        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        currentTime = target
    }

    private func scheduleControlsDismissal() {
        controlsTask?.cancel()
        controlsTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, isPlaying, !isSeeking else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                showsControls = false
            }
        }
    }

    private func timeText(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let value = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

private struct LearningPlayerLayer: UIViewRepresentable {
    let player: AVPlayer
    let onReadyForDisplay: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onReadyForDisplay: onReadyForDisplay)
    }

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.playerLayer.player = player
        context.coordinator.observe(view.playerLayer)
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {
        context.coordinator.onReadyForDisplay = onReadyForDisplay
        view.playerLayer.player = player
        context.coordinator.observe(view.playerLayer)
    }

    static func dismantleUIView(_ view: PlayerView, coordinator: Coordinator) {
        view.playerLayer.player = nil
        coordinator.stopObserving()
    }

    final class PlayerView: UIView {
        override class var layerClass: AnyClass {
            AVPlayerLayer.self
        }

        var playerLayer: AVPlayerLayer {
            layer as! AVPlayerLayer
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .black
            playerLayer.videoGravity = .resizeAspect
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }

    final class Coordinator {
        var onReadyForDisplay: () -> Void
        private weak var observedLayer: AVPlayerLayer?
        private var observation: NSKeyValueObservation?

        init(onReadyForDisplay: @escaping () -> Void) {
            self.onReadyForDisplay = onReadyForDisplay
        }

        func observe(_ layer: AVPlayerLayer) {
            guard observedLayer !== layer else { return }
            stopObserving()
            observedLayer = layer
            observation = layer.observe(
                \.isReadyForDisplay,
                options: [.initial, .new]
            ) { [weak self] layer, _ in
                guard layer.isReadyForDisplay else { return }
                DispatchQueue.main.async {
                    self?.onReadyForDisplay()
                }
            }
        }

        func stopObserving() {
            observation = nil
            observedLayer = nil
        }
    }
}

private enum LearningVideoPlaybackState: Equatable {
    case idle
    case loading
    case playing
    case failed
}

private struct LearningMilestoneRow: View {
    let number: Int
    let title: String
    let topic: LearningTopic
    let isCurrent: Bool
    let isCompleted: Bool
    let isLast: Bool
    let completedCount: Int
    let totalCount: Int

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Circle()
                    .fill(
                        isCompleted
                            ? KnowledgePagePalette.sage
                            : (isCurrent ? KnowledgePagePalette.accent : KnowledgePagePalette.canvas)
                    )
                    .frame(width: 27, height: 27)
                    .overlay {
                        Circle().stroke(
                            (isCurrent || isCompleted)
                                ? .clear
                                : Color.secondary.opacity(0.35),
                            lineWidth: 1
                        )
                        if isCompleted {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                        } else {
                            Text("\(number)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(isCurrent ? .white : .secondary)
                        }
                    }
                if !isLast {
                    Rectangle()
                        .fill(KnowledgePagePalette.stroke)
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 28)
            .frame(maxHeight: .infinity, alignment: .top)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                    Spacer()
                    Image(systemName: isCurrent ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                if isCurrent {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(KnowledgePagePalette.accent)
                            .frame(width: 7, height: 7)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(topic.title)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(topic.hasVideo == true ? "含视频" : topic.category)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("继续")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 13)
                            .frame(height: 36)
                            .background(KnowledgePagePalette.accent, in: RoundedRectangle(cornerRadius: 9))
                    }
                    .padding(12)
                    .background(KnowledgePagePalette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(KnowledgePagePalette.stroke, lineWidth: 0.7)
                    }

                    HStack(spacing: 10) {
                        Text("已完成 \(completedCount)/\(totalCount)")
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule().fill(KnowledgePagePalette.stroke)
                                Capsule()
                                    .fill(KnowledgePagePalette.accent)
                                    .frame(
                                        width: totalCount > 0
                                            ? geometry.size.width * CGFloat(completedCount) / CGFloat(totalCount)
                                            : 0
                                    )
                            }
                        }
                        .frame(height: 2)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 12)
                } else {
                    Text(topic.title)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.bottom, 18)
                }
            }
            .padding(.top, 3)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(number)，\(title)，\(topic.title)")
        .accessibilityHint("打开课程")
    }
}

private struct BookReadingDeskCard: View {
    let book: KnowledgeBook
    let source: String

    var body: some View {
        HStack(spacing: 16) {
            ZStack(alignment: .topLeading) {
                KnowledgeBookCover(book: book, paletteIndex: 0)
                    .frame(width: 92, height: 132)
                    .shadow(color: .black.opacity(0.18), radius: 7, x: 0, y: 5)

                Text("继续读")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(KnowledgePagePalette.accent, in: Capsule())
                    .offset(x: -7, y: 8)
            }

            VStack(alignment: .leading, spacing: 0) {
                Text("最近阅读")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(KnowledgePagePalette.accent)

                Text(book.title)
                    .font(.system(size: 18, weight: .bold, design: .serif))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .padding(.top, 7)

                Text(book.author)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.top, 5)

                BookMetadataLine(book: book)
                    .padding(.top, 6)

                Spacer(minLength: 8)

                BookReadingProgressView(book: book)

                HStack(spacing: 5) {
                    Text(book.isFinished ? "再次阅读" : "继续阅读")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(KnowledgePagePalette.accent)
                .padding(.top, 9)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(book.title)，作者\(book.author)")
        .accessibilityHint("在\(source)继续阅读")
    }
}

private struct KnowledgeBookCover: View {
    let book: KnowledgeBook
    let paletteIndex: Int
    var compact = false

    var body: some View {
        ZStack(alignment: .leading) {
            coverArtwork
            Rectangle()
                .fill(.black.opacity(0.13))
                .frame(width: compact ? 4 : 7)
            Rectangle()
                .fill(.white.opacity(0.18))
                .frame(width: 1)
                .padding(.leading, compact ? 5 : 9)

            if book.coverURL == nil {
                fallbackTitle
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: compact ? 5 : 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: compact ? 5 : 9, style: .continuous)
                .stroke(.white.opacity(0.2), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }

    private var coverArtwork: some View {
        KnowledgeHomeImage(url: book.coverURL, size: CGSize(width: 92, height: 132)) { image in
            if let image {
                image.resizable().scaledToFill()
            } else {
                LinearGradient(colors: palette, startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
    }

    private var fallbackTitle: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 9) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: compact ? 10 : 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.82))
            Text(book.title)
                .font(.system(size: compact ? 9 : 17, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(compact ? 3 : 4)
                .minimumScaleFactor(0.78)
            Spacer(minLength: 2)
            Text(book.author)
                .font(.system(size: compact ? 6.5 : 10.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.leading, compact ? 9 : 17)
        .padding(.trailing, compact ? 5 : 10)
        .padding(.vertical, compact ? 7 : 14)
    }

    private var palette: [Color] {
        switch paletteIndex % 5 {
        case 0:
            [Color(red: 0.18, green: 0.16, blue: 0.42), Color(red: 0.42, green: 0.26, blue: 0.68)]
        case 1:
            [Color(red: 0.12, green: 0.30, blue: 0.27), Color(red: 0.26, green: 0.52, blue: 0.43)]
        case 2:
            [Color(red: 0.37, green: 0.14, blue: 0.15), Color(red: 0.69, green: 0.31, blue: 0.25)]
        case 3:
            [Color(red: 0.13, green: 0.26, blue: 0.43), Color(red: 0.20, green: 0.48, blue: 0.64)]
        default:
            [Color(red: 0.42, green: 0.29, blue: 0.10), Color(red: 0.73, green: 0.53, blue: 0.20)]
        }
    }
}

private struct RecentKnowledgeBookRow: View {
    let book: KnowledgeBook
    let paletteIndex: Int

    var body: some View {
        HStack(spacing: 14) {
            KnowledgeBookCover(book: book, paletteIndex: paletteIndex, compact: true)
                .frame(width: 62, height: 88)
                .shadow(color: .black.opacity(0.12), radius: 5, x: 0, y: 3)

            VStack(alignment: .leading, spacing: 0) {
                Text(book.title)
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(book.author)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.top, 5)

                BookMetadataLine(book: book, compact: true)
                    .padding(.top, 5)

                Spacer(minLength: 7)

                BookReadingProgressView(book: book, compact: true)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(book.title)，作者\(book.author)，\(book.displayReadingProgress.map { "阅读进度\($0)%" } ?? (book.isFinished ? "已读完" : "阅读中"))")
        .accessibilityHint("在微信读书打开")
    }
}

private struct BookMetadataLine: View {
    let book: KnowledgeBook
    var compact = false

    private var items: [String] {
        [book.category?.replacingOccurrences(of: "-", with: " / "), book.lastReadText, book.estimatedRemainingText]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
    }

    var body: some View {
        if !items.isEmpty {
            Text(items.joined(separator: " · "))
                .font(.system(size: compact ? 10 : 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
    }
}

@MainActor
@Observable
private final class ReadingReminderManager {
    private static let notificationID = "learning.daily-reading-reminder"
    private static let enabledKey = "learning.daily-reading-reminder.enabled"

    private(set) var isEnabled = UserDefaults.standard.object(forKey: enabledKey) == nil
        ? true
        : UserDefaults.standard.bool(forKey: enabledKey)
    private(set) var isUpdating = false
    private(set) var errorMessage: String?

    func restore() async {
        guard isEnabled, !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }
        await schedule()
    }

    func setEnabled(_ enabled: Bool) async {
        guard !isUpdating else { return }
        isUpdating = true
        errorMessage = nil
        defer { isUpdating = false }
        if enabled {
            await schedule()
        } else {
            UNUserNotificationCenter.current().removePendingNotificationRequests(
                withIdentifiers: [Self.notificationID]
            )
            isEnabled = false
            UserDefaults.standard.set(false, forKey: Self.enabledKey)
        }
    }

    private func schedule() async {
        let center = UNUserNotificationCenter.current()
        var settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            do {
                _ = try await center.requestAuthorization(options: [.alert, .sound])
                settings = await center.notificationSettings()
            } catch {
                errorMessage = "无法申请通知权限"
                return
            }
        }
        guard settings.authorizationStatus == .authorized ||
                settings.authorizationStatus == .provisional else {
            isEnabled = false
            UserDefaults.standard.set(false, forKey: Self.enabledKey)
            errorMessage = "请先在系统设置中允许通知"
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "该读一会儿书了"
        content.body = "打开书架，继续今天的阅读。"
        content.sound = .default
        var date = DateComponents()
        date.hour = 21
        date.minute = 0
        let request = UNNotificationRequest(
            identifier: Self.notificationID,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
        )
        do {
            try await center.add(request)
            isEnabled = true
            UserDefaults.standard.set(true, forKey: Self.enabledKey)
        } catch {
            errorMessage = "读书提醒设置失败"
        }
    }
}

private struct BooksReadingSummaryCard: View {
    let bookshelf: LearningBookshelf?
    let reminder: ReadingReminderManager

    private var remainingText: String {
        bookshelf?.books.first(where: { !$0.isFinished })?.estimatedRemainingText ?? "暂无估算"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                metric(title: "今日阅读", value: bookshelf?.todayReadingText ?? "暂无数据")
                Divider().frame(height: 34).padding(.horizontal, 10)
                metric(title: "昨日阅读", value: bookshelf?.yesterdayReadingText ?? "暂无数据")
                Divider().frame(height: 34).padding(.horizontal, 10)
                metric(title: "当前书籍", value: remainingText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)

            Divider()

            Button {
                Task { await reminder.setEnabled(!reminder.isEnabled) }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: reminder.isEnabled ? "bell.fill" : "bell")
                        .foregroundStyle(KnowledgePagePalette.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("每天 21:00 读书提醒")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(reminder.errorMessage ?? (reminder.isEnabled ? "已开启" : "点击开启"))
                            .font(.system(size: 11))
                            .foregroundStyle(reminder.errorMessage == nil ? Color.secondary : Color.red)
                    }
                    Spacer()
                    if reminder.isUpdating {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: reminder.isEnabled ? "checkmark.circle.fill" : "chevron.right")
                            .foregroundStyle(
                                reminder.isEnabled
                                    ? KnowledgePagePalette.accent
                                    : Color(uiColor: .tertiaryLabel)
                            )
                    }
                }
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .disabled(reminder.isUpdating)
        }
        .padding(.horizontal, 14)
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { Divider() }
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 14, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BookReadingProgressView: View {
    let book: KnowledgeBook
    var compact = false

    var body: some View {
        if let progress = book.displayReadingProgress {
            VStack(alignment: .leading, spacing: compact ? 4 : 7) {
                HStack(spacing: 4) {
                    Text(book.isFinished ? "已读完" : "阅读进度")
                    Spacer(minLength: 4)
                    Text("\(progress)%")
                }
                .font(.system(size: compact ? 10 : 12, weight: .semibold))
                .foregroundStyle(book.isFinished ? Color.secondary : KnowledgePagePalette.accent)

                ProgressView(value: Double(progress), total: 100)
                    .tint(book.isFinished ? Color.secondary : KnowledgePagePalette.accent)
                    .scaleEffect(x: 1, y: compact ? 0.65 : 0.85, anchor: .center)
                    .accessibilityLabel("阅读进度")
                    .accessibilityValue("\(progress)%")
            }
        } else {
            Text(book.isFinished ? "已读完" : "阅读中")
                .font(.system(size: compact ? 10 : 12, weight: .semibold))
                .foregroundStyle(book.isFinished ? Color.secondary : KnowledgePagePalette.accent)
        }
    }
}

private struct LearningTopicRow: View {
    let topic: LearningTopic

    var body: some View {
        HStack(spacing: 14) {
            LearningTopicThumbnail(topic: topic)
            VStack(alignment: .leading, spacing: 6) {
                Text(topic.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if !topic.summary.isEmpty {
                    Text(topic.summary)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

private struct LearningTopicThumbnail: View {
    let topic: LearningTopic
    @State private var result: (request: ImageLoader.Request, image: UIImage?)?

    var body: some View {
        let size = CGSize(width: 84, height: 58)
        let request = topic.imageURL(topic.thumbnailURLValue).map {
            ImageLoader.request(for: $0, targetSize: size, scale: UIScreen.main.scale)
        }
        let finished = result?.request == request
        let image = (finished ? result?.image : nil)
            ?? request.flatMap { ImageLoader.shared.cachedImage(for: $0) }
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                fallback
                    .overlay {
                        if request != nil, !finished {
                            ProgressView().controlSize(.mini)
                        }
                    }
            }
        }
        .frame(width: 84, height: 58)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityHidden(true)
        .task(id: request) {
            await loadImage(request)
        }
    }

    private func loadImage(_ request: ImageLoader.Request?) async {
        guard let request else {
            learningImageLogger.error("Missing thumbnail URL for topic \(topic.id, privacy: .public)")
            return
        }
        guard result?.request != request || result?.image == nil,
              ImageLoader.shared.cachedImage(for: request) == nil else { return }

        for attempt in 1...3 {
            let loadedImage = await ImageLoader.shared.image(for: request)
            guard !Task.isCancelled else { return }
            if let loadedImage {
                result = (request, loadedImage)
                return
            }

            if attempt < 3 {
                try? await Task.sleep(for: .milliseconds(attempt * 350))
                guard !Task.isCancelled else { return }
            }
        }

        result = (request, nil)
        learningImageLogger.error(
            "Failed to load thumbnail for topic \(topic.id, privacy: .public): \(request.url.absoluteString, privacy: .public)"
        )
    }

    private var fallback: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(HoldingsPalette.purple.opacity(0.08))
            .overlay {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(HoldingsPalette.purple.opacity(0.82))
            }
    }

    private var icon: String {
        if topic.title.contains("市盈") || topic.title.contains("估值") { return "chart.line.uptrend.xyaxis" }
        if topic.title.contains("资产负债") || topic.title.contains("收入") { return "doc.text.magnifyingglass" }
        if topic.title.contains("风险") { return "scale.3d" }
        if topic.title.contains("基金") { return "chart.pie" }
        if topic.title.contains("期权") { return "point.3.connected.trianglepath.dotted" }
        return "book.pages"
    }
}

private struct InvestmentContentLoadingView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            RoundedRectangle(cornerRadius: 14).frame(height: 108)
            Text("股票入门路径").font(.title2.bold())
            ForEach(0..<4, id: \.self) { _ in
                HStack {
                    Circle().frame(width: 27, height: 27)
                    RoundedRectangle(cornerRadius: 8).frame(height: 46)
                }
            }
        }
        .padding(.horizontal, 20)
        .foregroundStyle(Color.secondary.opacity(0.16))
        .redacted(reason: .placeholder)
    }
}

private struct IdeologyContentLoadingView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(0..<2, id: \.self) { _ in
                HStack(spacing: 8) {
                    Circle().frame(width: 8, height: 8)
                    RoundedRectangle(cornerRadius: 5).frame(width: 58, height: 18)
                    RoundedRectangle(cornerRadius: 4).frame(width: 18, height: 14)
                }

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
                    spacing: 14
                ) {
                    ForEach(0..<8, id: \.self) { _ in
                        VStack(spacing: 7) {
                            Circle().frame(width: 62, height: 62)
                            RoundedRectangle(cornerRadius: 4).frame(width: 48, height: 13)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .foregroundStyle(Color.secondary.opacity(0.14))
        .redacted(reason: .placeholder)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在载入人物")
    }
}

private struct LearningPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct KnowledgeHomeImage<Content: View>: View {
    let url: URL?
    let size: CGSize
    @ViewBuilder let content: (Image?) -> Content
    @State private var result: (request: ImageLoader.Request, image: UIImage)?

    var body: some View {
        let request = url.map { ImageLoader.request(for: $0, targetSize: size, scale: UIScreen.main.scale) }
        let image = result?.request == request
            ? result?.image
            : request.flatMap { ImageLoader.shared.cachedImage(for: $0) }
        content(image.map { Image(uiImage: $0) })
            .task(id: request) {
                guard let request, result?.request != request else { return }
                guard let loaded = await ImageLoader.shared.image(for: request),
                      !Task.isCancelled else { return }
                result = (request, loaded)
            }
    }
}
