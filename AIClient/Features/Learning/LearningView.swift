import SwiftUI
import UIKit
import OSLog

private let learningImageLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "AIServerClient",
    category: "LearningImages"
)

struct LearningView: View {
    @Binding private var showsDetail: Bool
    @Environment(\.openURL) private var openURL
    @Environment(\.rootTabIsActive) private var rootTabIsActive
    @State private var store = LearningStore()
    @State private var repository = LearningContentRepository()
    @State private var progressStore = LearningProgressStore()
    @State private var path: [LearningRoute] = []
    @State private var selectedSection: KnowledgeSection = {
        #if DEBUG
        (ProcessInfo.processInfo.arguments.contains("--learning-books-preview") ||
            ProcessInfo.processInfo.arguments.contains("--learning-book-preview")) ? .books : .investment
        #else
        .investment
        #endif
    }()

    init(showsDetail: Binding<Bool> = .constant(false)) {
        _showsDetail = showsDetail
    }

    var body: some View {
        NavigationStack(path: $path) {
            knowledgeHome
            .background(Color(uiColor: .systemBackground).ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: LearningRoute.self) { route in
                LearningDetailView(
                    topic: route.topic,
                    repository: repository,
                    progressStore: progressStore,
                    lessonTitle: route.lessonTitle,
                    lessonNumber: route.lessonNumber,
                    lessonCount: route.lessonCount
                )
            }
        }
        .task(id: rootTabIsActive) {
            guard rootTabIsActive else { return }
            async let catalog: Void = store.load()
            async let bookshelf: Void = store.loadBookshelf()
            _ = await (catalog, bookshelf)
            #if DEBUG
            if (ProcessInfo.processInfo.arguments.contains("--learning-detail-preview") ||
                ProcessInfo.processInfo.arguments.contains("--learning-video-preview")),
               path.isEmpty,
               let topic = store.catalog?.sections
                .flatMap(\.topics)
                .first(where: { $0.title.contains("市盈率") }) {
                let topics = store.catalog.map { stockTopics(in: $0) } ?? []
                let milestones = learningMilestones(from: topics)
                if let index = milestones.firstIndex(where: { $0.topic.id == topic.id }) {
                    path = [route(for: milestones[index], at: index, total: milestones.count)]
                } else {
                    path = [LearningRoute(topic: topic)]
                }
            }
            #endif
        }
        .onChange(of: path.isEmpty, initial: true) { _, isEmpty in
            showsDetail = !isEmpty
        }
        .task(id: "\(rootTabIsActive)-\(prefetchKey)") {
            guard rootTabIsActive,
                  selectedSection == .investment,
                  let catalog = store.catalog,
                  let section = catalog.sections.first(where: { $0.name == "股票" }) ??
                    catalog.sections.first else {
                return
            }
            await repository.prefetch(section.topics.prefix(10))
        }
        .onDisappear { showsDetail = false }
    }

    private var prefetchKey: String {
        "\(store.catalog?.fetchedAt.timeIntervalSince1970 ?? 0)-\(selectedSection)"
    }

    private var knowledgeHome: some View {
        ZStack {
            KnowledgePagePalette.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                sectionPicker
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        switch selectedSection {
                        case .investment:
                            investmentContent
                        case .books:
                            booksContent
                        }
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                }
                .id(selectedSection)
                .scrollIndicators(.hidden)
                .safeAreaPadding(.bottom, 90)
                .refreshable {
                    switch selectedSection {
                    case .investment:
                        await store.load(force: true)
                    case .books:
                        await store.loadBookshelf(force: true)
                    }
                }
            }
        }
    }

    private var sectionPicker: some View {
        HStack(alignment: .top, spacing: 30) {
            sectionButton(.investment)
            sectionButton(.books)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 5)
    }

    private func sectionButton(_ section: KnowledgeSection) -> some View {
        Button {
            guard selectedSection != section else { return }
            withAnimation(.snappy(duration: 0.22)) {
                selectedSection = section
            }
        } label: {
            VStack(spacing: 7) {
                Text(section.title)
                    .font(.system(size: 26, weight: .semibold, design: .serif))
                    .foregroundStyle(selectedSection == section ? Color.primary : Color.secondary)
                Circle()
                    .fill(selectedSection == section ? KnowledgePagePalette.accent : .clear)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectedSection == section ? .isSelected : [])
    }

    @ViewBuilder
    private var investmentContent: some View {
        if let catalog = store.catalog {
            let topics = stockTopics(in: catalog)
            WeeklyStudyCard(studiedDays: progressStore.studyDays())
                .padding(.horizontal, 20)

            learningPath(topics)
            savedTopics(in: catalog, excluding: Set(topics.prefix(4).map(\.id)))
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
    private func learningPath(_ topics: [LearningTopic]) -> some View {
        Text("股票入门路径")
            .font(.system(size: 24, weight: .bold, design: .serif))
            .padding(.horizontal, 20)
            .padding(.top, 26)
            .padding(.bottom, 13)

        if topics.isEmpty {
            ContentUnavailableView(
                "暂无学习内容",
                systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                description: Text("下拉刷新后重试")
            )
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
        } else {
            let milestones = learningMilestones(from: topics)
            let completedCount = progressStore.completedCount(in: milestones.map(\.topic))
            let currentIndex = milestones.firstIndex {
                !progressStore.isCompleted($0.topic.id)
            }
            VStack(spacing: 0) {
                ForEach(Array(milestones.enumerated()), id: \.element.id) { index, milestone in
                    Button {
                        path.append(route(for: milestone, at: index, total: milestones.count))
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
                        path.append(LearningRoute(topic: topic))
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
        Text("正在读")
            .font(.system(size: 24, weight: .bold, design: .serif))
        .padding(.horizontal, 20)
        .padding(.bottom, 12)

        if store.isBookshelfLoading && store.bookshelf == nil {
            ProgressView("正在载入书架")
                .frame(maxWidth: .infinity)
                .padding(.top, 44)
        } else if store.bookshelfErrorMessage != nil && store.bookshelf == nil {
            ContentUnavailableView {
                Label("书架载入失败", systemImage: "wifi.exclamationmark")
            } description: {
                Text("稍后再试，或下拉刷新")
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
                description: Text("下拉刷新后重试")
            )
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        } else {
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

            }
        }
    }

    private func stockTopics(in catalog: LearningCatalog) -> [LearningTopic] {
        catalog.sections.first(where: { $0.name == "股票" })?.topics ??
            catalog.sections.first?.topics ??
            []
    }

    private func learningMilestones(from topics: [LearningTopic]) -> [LearningMilestone] {
        let definitions: [(String, [String])] = [
            ("基础概念", ["净收入", "净资产"]),
            ("读懂财报", ["资产负债", "现金流", "财报"]),
            ("估值方法", ["市盈率", "估值"]),
            ("风险管理", ["风险", "安全边际"])
        ]

        var usedIDs = Set<String>()
        return definitions.enumerated().compactMap { index, definition in
            let matched = topics.first { topic in
                !usedIDs.contains(topic.id) &&
                    definition.1.contains(where: { keyword in topic.title.contains(keyword) })
            }
            let fallback = topics.first { !usedIDs.contains($0.id) } ??
                (topics.indices.contains(index) ? topics[index] : nil)
            guard let topic = matched ?? fallback else { return nil }
            usedIDs.insert(topic.id)
            return LearningMilestone(title: definition.0, topic: topic)
        }
    }

    private func route(
        for milestone: LearningMilestone,
        at index: Int,
        total: Int
    ) -> LearningRoute {
        LearningRoute(
            topic: milestone.topic,
            lessonTitle: milestone.title,
            lessonNumber: index + 1,
            lessonCount: total
        )
    }
}

private enum KnowledgeSection: String {
    case investment
    case books

    var title: String {
        switch self {
        case .investment: "投资"
        case .books: "书籍"
        }
    }
}

private struct LearningRoute: Hashable {
    let topic: LearningTopic
    var lessonTitle: String?
    var lessonNumber: Int?
    var lessonCount: Int?
}

private enum KnowledgePagePalette {
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

private struct LearningMilestone: Identifiable {
    let title: String
    let topic: LearningTopic

    var id: String { "\(title)-\(topic.id)" }
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
                    .foregroundStyle(.secondary)
                Spacer()
                Text(studiedDays.isEmpty ? "完成课程后记录" : "保持节奏")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

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
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(Color(red: 0.81, green: 0.67, blue: 0.48).opacity(0.52))

                Circle()
                    .fill(Color.brown.opacity(0.25))
                    .frame(width: 82, height: 82)
                    .overlay {
                        Circle()
                            .stroke(.white.opacity(0.42), lineWidth: 7)
                            .padding(10)
                    }
                    .offset(x: 142, y: -78)

                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(red: 0.16, green: 0.12, blue: 0.09))
                    .frame(width: 5, height: 112)
                    .rotationEffect(.degrees(18))
                    .offset(x: 143, y: 63)

                KnowledgeBookCover(book: book, paletteIndex: 0)
                    .frame(width: 126, height: 176)
                    .shadow(color: .black.opacity(0.24), radius: 10, x: 0, y: 8)
            }
            .frame(height: 222)

            Text(book.title)
                .font(.system(size: 21, weight: .bold, design: .serif))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .padding(.top, 16)

            Text(book.author)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.top, 5)

            HStack(spacing: 9) {
                Text(book.isFinished ? "已读完" : "阅读中")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(book.isFinished ? "再次阅读" : "继续阅读")
                    .font(.system(size: 13, weight: .semibold))
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(KnowledgePagePalette.accent)
            .padding(.top, 16)

            HStack(spacing: 6) {
                if let category = book.category, !category.isEmpty {
                    Text(category)
                }
                Text("·")
                Text(source)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.top, 12)
        }
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

    @ViewBuilder
    private var coverArtwork: some View {
        if let coverURL = book.coverURL {
            AsyncImage(url: coverURL) { phase in
                switch phase {
                case let .success(image):
                    image.resizable().scaledToFill()
                default:
                    LinearGradient(
                        colors: palette,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
        } else {
            LinearGradient(
                colors: palette,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
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
    @State private var image: UIImage?
    @State private var finishedLoading = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                fallback
                    .overlay {
                        if !finishedLoading {
                            ProgressView().controlSize(.mini)
                        }
                    }
            }
        }
        .frame(width: 84, height: 58)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityHidden(true)
        .task(id: topic.thumbnailURLValue) {
            await loadImage()
        }
    }

    private func loadImage() async {
        image = nil
        finishedLoading = false
        guard let url = topic.mediaURL(topic.thumbnailURLValue) else {
            finishedLoading = true
            learningImageLogger.error("Missing thumbnail URL for topic \(topic.id, privacy: .public)")
            return
        }

        for attempt in 1...3 {
            if let loadedImage = await ImageLoader.load(
                url,
                targetSize: CGSize(width: 84, height: 58)
            ) {
                image = loadedImage
                finishedLoading = true
                return
            }

            guard !Task.isCancelled else { return }
            if attempt < 3 {
                try? await Task.sleep(for: .milliseconds(attempt * 350))
                guard !Task.isCancelled else { return }
            }
        }

        finishedLoading = true
        learningImageLogger.error(
            "Failed to load thumbnail for topic \(topic.id, privacy: .public): \(url.absoluteString, privacy: .public)"
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

private struct LearningPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
