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
    @State private var readingReminder = ReadingReminderManager.shared

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
        .background(KnowledgePagePalette.canvas.ignoresSafeArea())
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
        VStack(alignment: .leading, spacing: 18) {
            if let notice = store.savedContentNotice {
                Label(notice, systemImage: "clock.arrow.circlepath")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("knowledge-saved-content")
            }

            investmentOverview

            VStack(alignment: .leading, spacing: 9) {
                KnowledgeSectionHeading("阅读")
                VStack(spacing: 0) {
                    bookCollection
                    Divider().padding(.leading, 77)
                    conceptCollection
                }
                .knowledgeCard(cornerRadius: 15)
            }

            VStack(alignment: .leading, spacing: 9) {
                KnowledgeSectionHeading("探索")
                explorationDirectory
            }
        }
        .frame(maxWidth: 650)
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity)
    }

    private var investmentOverview: some View {
        let milestones = LearningMilestone.plan(from: store.catalog?.stockTopics ?? [])
        let completed = progressStore.completedCount(in: milestones.map(\.topic))
        let index = milestones.firstIndex { !progressStore.isCompleted($0.topic.id) }
            ?? milestones.indices.last

        return VStack(alignment: .leading, spacing: 12) {
            Button {
                presentedSection = .investment
            } label: {
                HStack(spacing: 8) {
                    Label("投资学习", systemImage: KnowledgeSection.investment.icon)
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 4)
                    Image(systemName: "arrow.up.right")
                        .font(.footnote.weight(.semibold))
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .foregroundStyle(KnowledgePagePalette.heroTint)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("knowledge-investment-entry")

            if let index {
                let milestone = milestones[index]
                Text(milestone.title)
                    .font(.title.weight(.bold))
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.white)
                ProgressView(value: Double(completed), total: Double(milestones.count))
                    .tint(KnowledgePagePalette.heroTint)
                    .accessibilityLabel("课程进度")
                    .accessibilityValue("已完成 \(completed) 节，共 \(milestones.count) 节")
                ViewThatFits(in: .horizontal) {
                    HStack {
                        progressText(completed, total: milestones.count)
                        Spacer(minLength: 4)
                        resumeButton(milestone, index: index, total: milestones.count, isReview: completed == milestones.count)
                    }
                    VStack(alignment: .leading, spacing: 9) {
                        progressText(completed, total: milestones.count)
                        resumeButton(milestone, index: index, total: milestones.count, isReview: completed == milestones.count)
                    }
                }
            } else {
                Text(store.errorMessage != nil && store.catalog == nil
                     ? "学习路径载入失败"
                     : knowledgeStatus(count: store.videoLibrary?.lessons.count,
                                       unit: "节视频课", error: store.videoLibraryErrorMessage))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.82))
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 18)
                .fill(LinearGradient(
                    colors: [KnowledgePagePalette.hero, Color(red: 0.18, green: 0.28, blue: 0.38)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
        }
    }

    private func progressText(_ completed: Int, total: Int) -> some View {
        Text("股票入门 · \(completed) / \(total) 节")
            .font(.footnote.weight(.medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.80))
    }

    private func resumeButton(_ milestone: LearningMilestone, index: Int, total: Int, isReview: Bool) -> some View {
        Button {
            resumedLesson = route(for: milestone, at: index, total: total)
        } label: {
            Label(isReview ? "复习课程" : "继续学习", systemImage: "arrow.right")
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .foregroundStyle(KnowledgePagePalette.hero)
                .background(KnowledgePagePalette.heroTint, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("knowledge-investment-resume")
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

            Divider().padding(.leading, 64)

            directoryEntry(.ideology, subtitle: directoryStatus(for: ideologyPeople.count)) {
                knowledgeSymbol(.ideology)
            }

            Divider().padding(.leading, 64)

            directoryEntry(.city, subtitle: "广东 · 21 个城市") {
                Image("ShenzhenSkyline")
                    .resizable()
                    .scaledToFill()
            }
        }
        .padding(.horizontal, 5)
        .knowledgeCard(cornerRadius: 17)
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

    private func knowledgeSymbol(_ section: KnowledgeSection) -> some View {
        Image(systemName: section.icon)
            .font(.body.weight(.medium))
            .foregroundStyle(section.tint)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(section.tint.opacity(0.11))
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
            KnowledgeSectionPanel(section: section) {
                investmentContent
            }
            .appSheet(item: $selectedRoute) { route in
                lessonDetail(route)
            }
        case .books:
            KnowledgeSectionPanel(section: section) {
                booksContent
            }
        case .concepts:
            KnowledgeSectionPanel(section: section) {
                conceptsContent
            }
            .appSheet(item: $selectedConcept) { concept in
                KnowledgeConceptDetailView(concept: concept)
                    .readingSheetPresentation()
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
            KnowledgeSectionPanel(section: section) {
                ideologyCampPicker
                    .padding(.horizontal, 20)
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
        .knowledgeWebLinks()
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
        let milestones = LearningMilestone.plan(from: store.catalog?.stockTopics ?? [])
        if store.catalog != nil {
            if store.errorMessage != nil {
                Label("学习路径更新失败", systemImage: "clock.arrow.circlepath")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
            }
            learningPath(milestones)
            WeeklyStudyCard(studiedDays: progressStore.studyDays())
                .padding(.horizontal, 20)
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
            .padding(.vertical, 14)
        }
        videoLessons
        if let catalog = store.catalog {
            learningDirectory(catalog)
        }
    }

    @ViewBuilder
    private var videoLessons: some View {
        if let lessons = store.videoLibrary?.lessons, !lessons.isEmpty {
            VStack(alignment: .leading, spacing: 11) {
                KnowledgeSectionHeading("投资视频课", detail: knowledgeStatus(
                    count: lessons.count,
                    unit: "期",
                    error: store.videoLibraryErrorMessage
                ))
                    .padding(.horizontal, 20)

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
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, 20, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollIndicators(.hidden)
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
        KnowledgeSectionHeading("股票入门路径", detail: milestones.isEmpty ? nil : "\(milestones.count) 节")
            .padding(.horizontal, 20)

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
                            isCompleted: progressStore.isCompleted(milestone.topic.id)
                        )
                    }
                    .buttonStyle(LearningPressStyle())
                    .accessibilityIdentifier("knowledge-lesson-\(milestone.topic.id)")
                    if index != milestones.indices.last {
                        Divider().padding(.leading, 53)
                    }
                }

                ProgressView(value: Double(completedCount), total: Double(milestones.count)) {
                    Text("已完成 \(completedCount) / \(milestones.count) 节")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .tint(KnowledgePagePalette.accent)
                .padding(13)
            }
            .knowledgeCard()
            .padding(.horizontal, 20)
        }
    }

    private func learningDirectory(_ catalog: LearningCatalog) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            KnowledgeSectionHeading("课程与资料", detail: "\(catalog.topicCount) 篇")

            ForEach(catalog.sections) { section in
                DisclosureGroup {
                    LazyVStack(spacing: 0) {
                        ForEach(section.topics) { topic in
                            Button {
                                selectedRoute = .topic(topic)
                            } label: {
                                LearningTopicRow(topic: topic)
                            }
                            .buttonStyle(LearningPressStyle())
                            .accessibilityIdentifier("knowledge-topic-\(topic.id)")

                            if topic.id != section.topics.last?.id {
                                Divider().padding(.leading, 112)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(section.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Spacer(minLength: 4)
                        Text(section.topics.count.formatted())
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .padding(.horizontal, 12)
                .knowledgeCard()
                .accessibilityIdentifier("knowledge-learning-section-\(section.id)")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
    }

    @ViewBuilder
    private var booksContent: some View {
        if let bookshelf = store.bookshelf, let book = bookshelf.books.first {
            VStack(alignment: .leading, spacing: 13) {
                Text(bookshelf.source + " · " + knowledgeStatus(
                    count: bookshelf.books.count,
                    unit: "本",
                    error: store.bookshelfErrorMessage
                ))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(KnowledgePagePalette.reading)
                BooksReadingSummaryCard(bookshelf: bookshelf, reminder: readingReminder)

                KnowledgeSectionHeading("最近打开")
                Button {
                    if let url = book.openURL { openURL(url) }
                } label: {
                    BookReadingDeskCard(book: book, source: bookshelf.source)
                }
                .buttonStyle(LearningPressStyle())
                .disabled(book.openURL == nil)
            }
            .padding(.horizontal, 20)

            if bookshelf.books.count > 1 {
                VStack(alignment: .leading, spacing: 10) {
                    KnowledgeSectionHeading("书架")
                    VStack(spacing: 0) {
                        ForEach(Array(bookshelf.books.dropFirst().enumerated()), id: \.element.id) { index, recentBook in
                            Button {
                                if let url = recentBook.openURL { openURL(url) }
                            } label: {
                                RecentKnowledgeBookRow(book: recentBook, paletteIndex: index + 1)
                                    .padding(.horizontal, 12)
                            }
                            .buttonStyle(LearningPressStyle())
                            .disabled(recentBook.openURL == nil)

                            if recentBook.id != bookshelf.books.last?.id {
                                Divider().padding(.leading, 88)
                            }
                        }
                    }
                    .knowledgeCard()
                }
                .padding(.horizontal, 20)
            }
        } else if store.isBookshelfLoading && store.bookshelf == nil {
            ContentLoadingPlaceholder(title: "正在载入书架", layout: .cards)
        } else if let error = store.bookshelfErrorMessage, store.bookshelf == nil {
            ContentUnavailableView {
                Label("书架载入失败", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error)
            } actions: {
                Button("重新载入") { Task { await store.loadBookshelf(force: true) } }
            }
            .frame(maxWidth: .infinity)
        } else {
            ContentUnavailableView("暂无书籍", systemImage: "books.vertical")
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var conceptsContent: some View {
        if let library = store.conceptLibrary {
            let concepts = shuffledConcepts.isEmpty ? library.concepts : shuffledConcepts
            Group {
                if concepts.isEmpty {
                    ContentUnavailableView("暂无概念", systemImage: "rectangle.stack")
                        .frame(maxWidth: .infinity)
                } else {
                    if store.conceptLibraryErrorMessage != nil {
                        Label("概念更新失败", systemImage: "clock.arrow.circlepath")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                    }
                    KnowledgeConceptDeck(
                        concepts: concepts,
                        selectedID: $selectedConceptID,
                        open: { selectedConcept = $0 }
                    )
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
            VStack(alignment: .leading, spacing: 17) {
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
            .padding(.horizontal, 20)
        }
    }

    private var ideologyCampPicker: some View {
        HStack(spacing: 5) {
            ForEach(IdeologyCampFilter.allCases) { filter in
                Button {
                    ideologyCampFilter = filter
                } label: {
                    Text(filter.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ideologyCampFilter == filter ? KnowledgePagePalette.graph : .secondary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .background(
                            KnowledgePagePalette.graph.opacity(ideologyCampFilter == filter ? 0.12 : 0),
                            in: .rect(cornerRadius: 11)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(ideologyCampFilter == filter ? .isSelected : [])
            }
        }
        .padding(4)
        .knowledgeCard(cornerRadius: 15)
        .sensoryFeedback(.selection, trigger: ideologyCampFilter)
    }

    private func ideologyCampSection(
        title: String,
        color: Color,
        people: [SpecialPerson]
    ) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Capsule()
                    .fill(color)
                    .frame(width: 4, height: 17)
                    .accessibilityHidden(true)
                KnowledgeSectionHeading(title, detail: "\(people.count) 位")
            }

            if people.isEmpty {
                Text("暂无收录")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 245 : 145), spacing: 8)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(people) { person in
                        Button {
                            selectedIdeologyPerson = person
                        } label: {
                            IdeologyPersonGridCell(person: person, baseURL: peopleStore.baseURL)
                                .padding(9)
                                .background(color.opacity(0.08), in: .rect(cornerRadius: 11))
                        }
                        .buttonStyle(LearningPressStyle())
                        .accessibilityIdentifier("ideology-person-\(person.id)")
                    }
                }
            }
        }
        .padding(13)
        .knowledgeCard()
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
        case .books: KnowledgePagePalette.reading
        case .concepts: KnowledgePagePalette.archive
        case .people: KnowledgePagePalette.accent
        case .ideology: KnowledgePagePalette.graph
        case .city: KnowledgePagePalette.atlas
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
            HStack(spacing: 12) {
                artwork()
                    .frame(width: 53)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(section.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if let itemTitle {
                        Text(itemTitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    }
                    Text(status)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(section.tint)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(section.tint)
                    .accessibilityHidden(true)
            }
            .multilineTextAlignment(.leading)
            .padding(12)
            .contentShape(Rectangle())
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
    let section: KnowledgeSection
    @ViewBuilder let content: () -> Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                KnowledgePageHeading(title: section.title, icon: section.icon, tint: section.tint)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 4)
                content()
            }
            .frame(maxWidth: 650)
            .frame(maxWidth: .infinity)
            .padding(.top, 19)
            .padding(.bottom, 80)
        }
        .scrollIndicators(.hidden)
        .background(KnowledgePagePalette.canvas.ignoresSafeArea())
        .floatingSheetClose("关闭\(section.title)", action: dismiss.callAsFunction)
        .knowledgeWebLinks()
        .readingSheetPresentation()
    }
}

struct KnowledgePageHeading: View {
    let title: String
    var icon: String? = nil
    var tint = KnowledgePagePalette.accent

    var body: some View {
        HStack(spacing: 14) {
            if let icon {
                Image(systemName: icon)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(tint)
                    .frame(width: 44, height: 44)
                    .background(tint.opacity(0.11), in: .rect(cornerRadius: 11))
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.largeTitle.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
        }
    }
}

struct KnowledgeSectionHeading: View {
    let title: String
    var detail: String?

    init(_ title: String, detail: String? = nil) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            if let detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    func knowledgeCard(cornerRadius: CGFloat = 17) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        return background(KnowledgePagePalette.surface, in: shape)
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(KnowledgePagePalette.stroke, lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

private struct KnowledgeReadingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var knowledgeReading: Bool {
        get { self[KnowledgeReadingKey.self] }
        set { self[KnowledgeReadingKey.self] = newValue }
    }
}

private struct KnowledgeWebLinks: ViewModifier {
    @State private var link: InAppBrowserDestination?

    func body(content: Content) -> some View {
        content
            .environment(\.openURL, OpenURLAction { url in
                guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
                    return .systemAction
                }
                link = InAppBrowserDestination(url: url)
                return .handled
            })
            .inAppBrowserCover(item: $link)
            .environment(\.knowledgeReading, true)
    }
}

extension View {
    func knowledgeWebLinks() -> some View { modifier(KnowledgeWebLinks()) }
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

enum KnowledgePagePalette {
    static let canvas = adaptive(light: 0xF5F4EF, dark: 0x141A21)
    static let surface = adaptive(light: 0xFFFEFA, dark: 0x202831)
    static let stroke = Color.primary.opacity(0.09)
    static let accent = adaptive(light: 0x275477, dark: 0xA0CEF5)
    static let reading = adaptive(light: 0x42664F, dark: 0xA6CCAC)
    static let archive = adaptive(light: 0x92542F, dark: 0xE8B18C)
    static let graph = adaptive(light: 0x6D527D, dark: 0xD6B7E8)
    static let atlas = adaptive(light: 0x216D69, dark: 0x8BD4CA)
    static let hero = Color(red: 0.10, green: 0.19, blue: 0.28)
    static let heroTint = Color(red: 0.67, green: 0.83, blue: 0.92)

    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 255) / 255,
                green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255,
                alpha: 1
            )
        })
    }
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
            KnowledgePagePalette.graph
        case .rebel:
            KnowledgePagePalette.accent
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
        HStack(spacing: 8) {
            AvatarView(
                url: person.avatarURL(baseURL: baseURL),
                name: person.name,
                size: 34,
                assetName: person.avatarAssetName
            )
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(person.name).font(.subheadline.weight(.semibold))
                if let organization = person.organizationName, !organization.isEmpty {
                    Text(organization).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            .multilineTextAlignment(.leading)
            .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct WeeklyStudyCard: View {
    private let days = ["一", "二", "三", "四", "五", "六", "日"]
    let studiedDays: Set<Int>

    var body: some View {
        VStack(spacing: 16) {
            KnowledgeSectionHeading("本周学习", detail: "\(studiedDays.count) 天")

            HStack {
                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                    VStack(spacing: 9) {
                        Text(day)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
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
        .padding(14)
        .knowledgeCard()
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
                    .foregroundStyle(.secondary)
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

private enum VideoLessonDetailState {
    case loading, loaded, failed
}

private struct LearningVideoLessonDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var lesson: LearningVideoLesson
    @State private var detailState: VideoLessonDetailState = .loading
    @State private var detailRetry = 0
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
                    .clipShape(.rect(cornerRadius: 16))
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        heroMetadata
                        chapters
                        introduction
                        watchPoints
                        relatedTopics
                        if detailState == .failed {
                            Button {
                                detailRetry += 1
                            } label: {
                                Label("重试载入视频资料", systemImage: "arrow.clockwise")
                                    .frame(minHeight: 44)
                            }
                            .padding(.horizontal, 20)
                        }
                        sourceNote
                    }
                    .padding(.bottom, 80)
                }
                .scrollIndicators(.hidden)
            }
            .frame(maxWidth: 650)
        }
        .overlay(alignment: .bottomTrailing) {
            DetailSheetCloseButton(action: dismiss.callAsFunction, accessibilityLabel: "关闭视频详情")
                .padding(16)
        }
        .background(InteractivePopGestureEnabler())
        .toolbar(.hidden, for: .navigationBar)
        .appFullScreenCover(isPresented: $showsFullscreenPlayer) {
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
                        isFullscreen: true,
                        title: lesson.title,
                        chapters: lesson.chapters,
                        onFullscreen: dismissFullscreenPlayer
                    )
                } else {
                    VStack(spacing: 15) {
                        if playbackState == .loading {
                            ProgressView("正在加载视频")
                        } else {
                            Label("视频暂时无法播放", systemImage: "exclamationmark.circle")
                            Button("重新加载", systemImage: "arrow.clockwise") { startPlayback(at: lastPlaybackSecond) }
                                .buttonStyle(.bordered)
                        }
                    }
                    .foregroundStyle(.white)
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .bottomTrailing) {
                        DetailSheetCloseButton(action: dismissFullscreenPlayer, accessibilityLabel: "关闭全屏视频")
                            .padding(16)
                    }
                }
            }
            .preferredColorScheme(.dark)
            .persistentSystemOverlays(.hidden)
            .onDisappear {
                AppOrientationController.shared.setVideoFullscreen(false)
            }
        }
        .task(id: detailRetry) {
            detailState = .loading
            do {
                let detail = try await LearningService().fetchVideoLesson(id: lesson.id)
                try Task.checkCancellation()
                lesson = detail
                detailState = .loaded
            } catch {
                if !Task.isCancelled { detailState = .failed }
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

    private var lastPlaybackSecond: Int {
        currentPlaybackTime.isFinite ? Int(max(0, currentPlaybackTime)) : 0
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
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
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
                .background(KnowledgePagePalette.hero.opacity(0.94), in: Circle())
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
                if detailState == .loading { ProgressView().controlSize(.small) }
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
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if index != lesson.chapters.indices.last {
                            Divider().padding(.leading, 67)
                        }
                    }
                }
                .knowledgeCard()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
    }

    @ViewBuilder
    private var relatedTopics: some View {
        if !lesson.relatedTopics.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("相关知识")
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
        KnowledgeSectionHeading(title)
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
    var title: String? = nil
    var chapters: [LearningVideoChapter] = []
    let onFullscreen: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
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
                LinearGradient(
                    colors: [.black.opacity(0.70), .clear, .clear, .black.opacity(0.83)],
                    startPoint: .top, endPoint: .bottom
                )
                .allowsHitTesting(false)

                VStack(spacing: 0) {
                    if let title {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 12)
                            .padding(.leading, 12)
                            .padding(.trailing, 60)
                            .allowsHitTesting(false)
                    }

                    Spacer(minLength: 0)
                    if isFullscreen {
                        fullscreenControls
                    } else {
                        scrubber
                            .padding(.horizontal, 12)
                            .padding(.bottom, 6)
                    }
                }
                .padding(.horizontal, isFullscreen ? 12 : 0)

                if !isFullscreen {
                    HStack(spacing: 16) {
                        seekButton(seconds: -15, symbol: "gobackward.15")
                        playPauseButton(diameter: 52)
                        seekButton(seconds: 15, symbol: "goforward.15")
                    }
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            fullscreenButton
                .padding(isFullscreen ? 14 : 8)
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

    private var fullscreenButton: some View {
        Button {
            controlsTask?.cancel()
            onFullscreen()
        } label: {
            Image(systemName: isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.72), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isFullscreen ? "退出全屏" : "全屏播放")
    }

    private var fullscreenControls: some View {
        VStack(spacing: 3) {
            scrubber
            ZStack {
                HStack(spacing: 11) {
                    seekButton(seconds: -15, symbol: "gobackward.15")
                    playPauseButton(diameter: 48)
                    seekButton(seconds: 15, symbol: "goforward.15")
                }
                .frame(maxWidth: .infinity)

                if !chapters.isEmpty {
                    HStack {
                        Spacer()
                        Menu {
                            ForEach(chapters) { chapter in
                                Button("\(chapter.timestampText)  \(chapter.title)") {
                                    seek(to: min(Double(chapter.startSeconds), max(duration, 0)))
                                    if isPlaying { scheduleControlsDismissal() }
                                }
                            }
                        } label: {
                            Image(systemName: "list.bullet")
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("视频章节")
                        .simultaneousGesture(TapGesture().onEnded { controlsTask?.cancel() })
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .foregroundStyle(.white)
        .background(Color(red: 0.09, green: 0.12, blue: 0.16).opacity(0.92), in: .rect(cornerRadius: 16))
        .frame(maxWidth: 620)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 9)
    }

    private func playPauseButton(diameter: CGFloat) -> some View {
        Button(action: togglePlayback) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.title3.weight(.bold))
                .foregroundStyle(KnowledgePagePalette.hero)
                .frame(width: diameter, height: diameter)
                .background(KnowledgePagePalette.heroTint, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? "暂停" : "播放")
    }

    private var scrubber: some View {
        HStack(spacing: 9) {
            Text(timeText(isSeeking ? seekPreview : currentTime))
            Slider(
                value: Binding(
                    get: { min(max(isSeeking ? seekPreview : currentTime, 0), max(duration, 1)) },
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
            .tint(KnowledgePagePalette.heroTint)
            .accessibilityLabel("播放进度")
            .accessibilityValue("\(timeText(currentTime))，总时长 \(timeText(duration))")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: seek(to: min(currentTime + 15, max(duration, 0)))
                case .decrement: seek(to: max(0, currentTime - 15))
                @unknown default: break
                }
            }
            Text(timeText(duration))
        }
        .font(.caption2.weight(.semibold).monospacedDigit())
        .foregroundStyle(.white)
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
                .frame(width: 44, height: 44)
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
        guard !voiceOverEnabled else { return }
        controlsTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, isPlaying, !isSeeking else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
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

    var body: some View {
        let tint = isCompleted ? KnowledgePagePalette.reading : KnowledgePagePalette.accent
        HStack(spacing: 11) {
            Group {
                if isCompleted {
                    Image(systemName: "checkmark")
                } else {
                    Text("\(number)")
                        .monospacedDigit()
                }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(tint)
            .frame(width: 30, height: 30)
            .background(tint.opacity(0.12), in: .rect(cornerRadius: 8))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(topic.title)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)

            if isCurrent {
                Text("继续")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(isCurrent ? tint : .secondary)
                .accessibilityHidden(true)
        }
        .padding(12)
        .frame(minHeight: 48)
        .background(isCurrent ? tint.opacity(0.075) : .clear)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(isCompleted ? "已完成，可打开复习" : "打开课程")
    }
}

private struct BookReadingDeskCard: View {
    let book: KnowledgeBook
    let source: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 15))
        layout {
            KnowledgeBookCover(book: book, paletteIndex: 0)
                .frame(width: 86, height: 124)
                .shadow(color: .black.opacity(0.17), radius: 7, x: 0, y: 5)

            VStack(alignment: .leading, spacing: 7) {
                Text(book.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Text(book.author)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                BookMetadataLine(book: book)
                BookReadingProgressView(book: book)
                if book.openURL != nil {
                    Label(book.isFinished ? "再次阅读" : "继续阅读", systemImage: "arrow.up.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(KnowledgePagePalette.reading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(15)
        .background(KnowledgePagePalette.reading.opacity(0.095), in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .combine)
        .accessibilityHint(book.openURL != nil ? "在\(source)打开" : "")
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
        .accessibilityLabel("\(book.title)，作者\(book.author)，\(book.displayReadingProgress.map { "阅读进度\($0)%" } ?? "进度未同步")")
        .accessibilityHint("在微信读书打开")
    }
}

private struct BookMetadataLine: View {
    let book: KnowledgeBook
    var compact = false

    private var items: [String] {
        [book.category?.replacingOccurrences(of: "-", with: " / "), book.lastReadText,
         book.readingDurationText, book.estimatedRemainingText]
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
                .lineLimit(2)
        }
    }
}

@MainActor
@Observable
final class ReadingReminderManager {
    static let shared = ReadingReminderManager()

    private static let notificationID = "learning.daily-reading-reminder"
    private static let enabledKey = "learning.daily-reading-reminder.enabled"

    private(set) var isEnabled = UserDefaults.standard.object(forKey: enabledKey) == nil
        ? true
        : UserDefaults.standard.bool(forKey: enabledKey)
    private(set) var errorMessage: String?
    private var updateTask: Task<Void, Never>?
    var isUpdating: Bool { updateTask != nil }

    func applyNotificationPause(_ paused: Bool) {
        if paused {
            removePendingReminder()
        } else {
            Task {
                await updateTask?.value
                guard UserDefaults.standard.bool(forKey: Self.enabledKey),
                      !PersonPushNotificationManager.shared.notificationsPaused else { return }
                await restore()
            }
        }
    }

    func restore() async {
        guard isEnabled else { return }
        await updateSchedule()
    }

    func setEnabled(_ enabled: Bool) async {
        guard !isUpdating else { return }
        errorMessage = nil
        if enabled {
            await updateSchedule()
        } else {
            removePendingReminder()
            saveEnabled(false)
        }
    }

    private func updateSchedule() async {
        guard updateTask == nil else { return }
        let task = Task {
            defer { updateTask = nil }
            await schedule()
        }
        updateTask = task
        await task.value
    }

    private func schedule() async {
        let center = UNUserNotificationCenter.current()
        var settings = await center.notificationSettings()
        if !PersonPushNotificationManager.shared.notificationsPaused,
           settings.authorizationStatus == .notDetermined {
            do {
                _ = try await center.requestAuthorization(options: [.alert, .sound])
                settings = await center.notificationSettings()
            } catch {
                errorMessage = "无法申请通知权限"
                return
            }
        }
        if PersonPushNotificationManager.shared.notificationsPaused {
            saveEnabled(true)
            return
        }
        guard settings.authorizationStatus == .authorized ||
                settings.authorizationStatus == .provisional else {
            saveEnabled(false)
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
            saveEnabled(true)
            if PersonPushNotificationManager.shared.notificationsPaused {
                removePendingReminder()
            }
        } catch {
            errorMessage = "读书提醒设置失败"
        }
    }

    private func removePendingReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [Self.notificationID]
        )
    }

    private func saveEnabled(_ enabled: Bool) {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
    }
}

private struct BooksReadingSummaryCard: View {
    let bookshelf: LearningBookshelf
    let reminder: ReadingReminderManager

    private var remainingText: String {
        bookshelf.books.first(where: { !$0.isFinished })?.estimatedRemainingText ?? "暂无估算"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                metric(title: "今日阅读", value: bookshelf.todayReadingText)
                Divider().frame(height: 34).padding(.horizontal, 10)
                metric(title: "昨日阅读", value: bookshelf.yesterdayReadingText)
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
        .knowledgeCard()
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
            Text("进度未同步")
                .font(.system(size: compact ? 10 : 12, weight: .semibold))
                .foregroundStyle(.secondary)
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
