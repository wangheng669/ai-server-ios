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
    @State private var store = LearningStore()
    @State private var repository = LearningContentRepository()
    @State private var path: [LearningRoute] = []
    @State private var selectedCategory = "股票"
    @State private var selectedSection: KnowledgeSection = {
        #if DEBUG
        (ProcessInfo.processInfo.arguments.contains("--learning-books-preview") ||
            ProcessInfo.processInfo.arguments.contains("--learning-book-preview")) ? .books : .investment
        #else
        .investment
        #endif
    }()
    @State private var query = ""
    @State private var showsSearch = false

    init(showsDetail: Binding<Bool> = .constant(false)) {
        _showsDetail = showsDetail
    }

    var body: some View {
        NavigationStack(path: $path) {
            knowledgeHome
            .background(Color(uiColor: .systemBackground).ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: LearningRoute.self) { route in
                switch route {
                case let .topic(topic):
                    LearningDetailView(topic: topic, repository: repository)
                }
            }
        }
        .task {
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
                path = [.topic(topic)]
            }
            #endif
        }
        .onChange(of: path.isEmpty, initial: true) { _, isEmpty in
            showsDetail = !isEmpty
        }
        .task(id: prefetchKey) {
            guard selectedSection == .investment,
                  let catalog = store.catalog,
                  let section = catalog.sections.first(where: { $0.name == selectedCategory }) else {
                return
            }
            await repository.prefetch(section.topics.prefix(10))
        }
        .onDisappear { showsDetail = false }
    }

    private var prefetchKey: String {
        "\(store.catalog?.fetchedAt.timeIntervalSince1970 ?? 0)-\(selectedSection)-\(selectedCategory)"
    }

    private var knowledgeHome: some View {
        ZStack {
            KnowledgePagePalette.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                sectionPicker
                if showsSearch {
                    searchField
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        switch selectedSection {
                        case .investment:
                            investmentContent
                        case .books:
                            booksContent
                        }
                    }
                    .padding(.top, 22)
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
        .animation(.snappy(duration: 0.24), value: showsSearch)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("知识")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text(selectedSection.subtitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
            }
            Spacer()
            Button {
                showsSearch.toggle()
                if !showsSearch { query = "" }
            } label: {
                Image(systemName: showsSearch ? "xmark" : "magnifyingglass")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 42, height: 42)
                    .background(KnowledgePagePalette.surface, in: Circle())
                    .overlay {
                        Circle()
                            .stroke(KnowledgePagePalette.stroke, lineWidth: 0.7)
                    }
                    .shadow(color: .black.opacity(0.045), radius: 8, y: 3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                showsSearch ? "关闭搜索" : "搜索\(selectedSection.title)内容"
            )
        }
        .padding(.horizontal, 20)
        .padding(.top, 13)
        .padding(.bottom, 18)
    }

    private var sectionPicker: some View {
        HStack(spacing: 5) {
            sectionButton(.investment)
            sectionButton(.books)
        }
        .padding(5)
        .frame(height: 52)
        .background(KnowledgePagePalette.segmentBackground)
        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .padding(.horizontal, 20)
        .padding(.bottom, showsSearch ? 14 : 0)
    }

    private func sectionButton(_ section: KnowledgeSection) -> some View {
        Button {
            guard selectedSection != section else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                selectedSection = section
                query = ""
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: section.icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(section.title)
                    .font(.system(size: 16, weight: .semibold))
            }
                .foregroundStyle(selectedSection == section ? Color.white : Color.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    if selectedSection == section {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(KnowledgePagePalette.accent)
                            .shadow(color: KnowledgePagePalette.accent.opacity(0.22), radius: 7, y: 3)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectedSection == section ? .isSelected : [])
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(selectedSection.searchPlaceholder, text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(KnowledgePagePalette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(KnowledgePagePalette.stroke, lineWidth: 0.7)
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var investmentContent: some View {
        if let catalog = store.catalog {
            if query.isEmpty {
                featuredTopic(in: catalog)
                categoryPicker(catalog.sections)
                topicList(catalog)
            } else {
                investmentSearchResults(catalog)
            }
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
    private func featuredTopic(in catalog: LearningCatalog) -> some View {
        if let topic = catalog.sections
            .flatMap(\.topics)
            .first(where: { $0.title.contains("市盈率") }) ?? catalog.sections.first?.topics.first {
            Button {
                path.append(.topic(topic))
            } label: {
                ZStack(alignment: .leading) {
                    LearningHeroArtwork()
                    VStack(alignment: .leading, spacing: 0) {
                        Text("今日精选")
                            .font(.system(size: 12, weight: .bold))
                            .tracking(1.5)
                            .foregroundStyle(.white.opacity(0.7))
                        Text("从零开始\n读懂股票")
                            .font(.system(size: 27, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineSpacing(2)
                            .padding(.top, 10)
                        Spacer()
                        HStack(spacing: 8) {
                            Text("12 个基础概念")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.74))
                            Circle()
                                .fill(.white.opacity(0.36))
                                .frame(width: 3, height: 3)
                            Text("开始学习")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(22)
                }
                .frame(height: 190)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 0.7)
                }
                .shadow(color: KnowledgePagePalette.accent.opacity(0.16), radius: 18, y: 9)
                .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            }
            .buttonStyle(LearningPressStyle())
            .padding(.horizontal, 20)
        }
    }

    private func categoryPicker(_ sections: [LearningSection]) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 9) {
                ForEach(sections) { section in
                    Button {
                        withAnimation(.easeOut(duration: 0.16)) {
                            selectedCategory = section.name
                        }
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: categoryIcon(section.name))
                                .font(.system(size: 13, weight: .semibold))
                            Text(section.name)
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(
                            selectedCategory == section.name ? Color.white : Color.secondary
                        )
                        .padding(.horizontal, 15)
                        .frame(height: 40)
                        .background(
                            selectedCategory == section.name
                                ? KnowledgePagePalette.accent
                                : KnowledgePagePalette.surface,
                            in: Capsule()
                        )
                        .overlay {
                            if selectedCategory != section.name {
                                Capsule()
                                    .stroke(KnowledgePagePalette.stroke, lineWidth: 0.7)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedCategory == section.name ? .isSelected : [])
                }
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .padding(.top, 22)
    }

    @ViewBuilder
    private func topicList(_ catalog: LearningCatalog) -> some View {
        let topics = filteredTopics(catalog)
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(selectedCategory)知识")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("循序渐进，建立自己的投资框架")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(topics.count) 篇")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(KnowledgePagePalette.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(KnowledgePagePalette.accent.opacity(0.09), in: Capsule())
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .padding(.bottom, 13)

        if topics.isEmpty {
            ContentUnavailableView(
                "没有找到相关内容",
                systemImage: "magnifyingglass",
                description: Text("试试其他关键词")
            )
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        } else {
            VStack(spacing: 0) {
                ForEach(topics) { topic in
                    Button {
                        path.append(.topic(topic))
                    } label: {
                        LearningTopicRow(topic: topic)
                    }
                    .buttonStyle(LearningPressStyle())
                    if topic.id != topics.last?.id {
                        Divider().padding(.leading, 112)
                    }
                }
            }
            .background(KnowledgePagePalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(KnowledgePagePalette.stroke, lineWidth: 0.7)
            }
            .padding(.horizontal, 20)
        }
    }

    @ViewBuilder
    private func investmentSearchResults(_ catalog: LearningCatalog) -> some View {
        let topics = filteredTopics(catalog)

        HStack(alignment: .firstTextBaseline) {
            Text("搜索结果")
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Spacer()
            Text("\(topics.count) 篇")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)

        if topics.isEmpty {
            ContentUnavailableView(
                "没有找到相关内容",
                systemImage: "magnifyingglass",
                description: Text("试试其他关键词")
            )
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        } else {
            VStack(spacing: 0) {
                ForEach(topics) { topic in
                    Button {
                        path.append(.topic(topic))
                    } label: {
                        LearningTopicRow(topic: topic)
                    }
                    .buttonStyle(LearningPressStyle())
                    if topic.id != topics.last?.id {
                        Divider().padding(.leading, 112)
                    }
                }
            }
            .background(KnowledgePagePalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(KnowledgePagePalette.stroke, lineWidth: 0.7)
            }
            .padding(.horizontal, 20)
        }
    }

    @ViewBuilder
    private var booksContent: some View {
        let books = filteredBooks()
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 5) {
                Text(query.isEmpty ? "精选书架" : "搜索结果")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                if query.isEmpty {
                    Text("值得反复阅读的思想与人物")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("\(books.count) 本")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(KnowledgePagePalette.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(KnowledgePagePalette.accent.opacity(0.09), in: Capsule())
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)

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
                query.isEmpty ? "暂无可展示书籍" : "没有找到相关书籍",
                systemImage: "books.vertical",
                description: Text("试试书名、作者或投资主题")
            )
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        } else {
            VStack(spacing: 14) {
                ForEach(Array(books.enumerated()), id: \.element.id) { index, book in
                    Button {
                        if let url = book.openURL {
                            openURL(url)
                        }
                    } label: {
                        KnowledgeFeaturedBookCard(
                            book: book,
                            source: store.bookshelf?.source ?? "微信读书",
                            paletteIndex: index
                        )
                    }
                    .buttonStyle(LearningPressStyle())
                }
            }
            .padding(.horizontal, 20)

            if query.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(KnowledgePagePalette.accent)
                    Text("书架会持续加入精选好书")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 18)
            }
        }
    }

    private func filteredTopics(_ catalog: LearningCatalog) -> [LearningTopic] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return catalog.sections
                .flatMap(\.topics)
                .filter {
                    $0.title.localizedCaseInsensitiveContains(trimmed) ||
                        $0.summary.localizedCaseInsensitiveContains(trimmed)
                }
        }
        return catalog.sections.first(where: { $0.name == selectedCategory })?.topics ?? []
    }

    private func filteredBooks() -> [KnowledgeBook] {
        let books = store.bookshelf?.books ?? []
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return books }
        return books.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed) ||
                $0.author.localizedCaseInsensitiveContains(trimmed) ||
                ($0.category?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }

    private func categoryIcon(_ category: String) -> String {
        switch category {
        case "股票": "chart.line.uptrend.xyaxis"
        case "基金": "chart.pie"
        case "期货": "chart.bar.xaxis"
        case "期权": "point.3.connected.trianglepath.dotted"
        default: "globe.asia.australia"
        }
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

    var searchPlaceholder: String {
        switch self {
        case .investment: "搜索投资知识"
        case .books: "搜索书名、作者或主题"
        }
    }

    var subtitle: String {
        switch self {
        case .investment: "建立清晰、可复用的认知框架"
        case .books: "从好书中认识思想与世界"
        }
    }

    var icon: String {
        switch self {
        case .investment: "chart.line.uptrend.xyaxis"
        case .books: "books.vertical.fill"
        }
    }
}

private enum LearningRoute: Hashable {
    case topic(LearningTopic)
}

private enum KnowledgePagePalette {
    static let accent = Color(red: 0.35, green: 0.25, blue: 0.73)
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let segmentBackground = Color(uiColor: .tertiarySystemGroupedBackground)
    static let stroke = Color.primary.opacity(0.07)
}

private struct KnowledgeFeaturedBookCard: View {
    let book: KnowledgeBook
    let source: String
    let paletteIndex: Int

    var body: some View {
        HStack(spacing: 18) {
            KnowledgeBookCover(book: book, paletteIndex: paletteIndex)
                .frame(width: 106, height: 148)
                .shadow(color: .black.opacity(0.18), radius: 9, x: 0, y: 6)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "book.closed.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text(source)
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(KnowledgePagePalette.accent)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(KnowledgePagePalette.accent.opacity(0.1), in: Capsule())

                Text(book.title)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .padding(.top, 11)

                Text(book.author)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .padding(.top, 5)

                Spacer(minLength: 12)

                HStack(spacing: 7) {
                    if let category = book.category, !category.isEmpty {
                        Text(category)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    Text("打开阅读")
                        .font(.system(size: 13, weight: .semibold))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(KnowledgePagePalette.accent)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 184, alignment: .leading)
        .background {
            ZStack {
                KnowledgePagePalette.surface
                LinearGradient(
                    colors: [
                        KnowledgePagePalette.accent.opacity(0.09),
                        .clear,
                        Color.blue.opacity(0.035)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(KnowledgePagePalette.stroke, lineWidth: 0.7)
        }
        .shadow(color: .black.opacity(0.045), radius: 14, y: 7)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(book.title)，作者\(book.author)")
        .accessibilityHint("在\(source)打开阅读")
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

private struct LearningHeroArtwork: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.16, green: 0.12, blue: 0.37),
                    KnowledgePagePalette.accent,
                    Color(red: 0.30, green: 0.21, blue: 0.63)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(.white.opacity(0.07))
                .frame(width: 210, height: 210)
                .blur(radius: 2)
                .offset(x: 145, y: -80)
            Canvas { context, size in
                var line = Path()
                let points: [CGPoint] = [
                    CGPoint(x: size.width * 0.51, y: size.height * 0.72),
                    CGPoint(x: size.width * 0.60, y: size.height * 0.59),
                    CGPoint(x: size.width * 0.68, y: size.height * 0.64),
                    CGPoint(x: size.width * 0.76, y: size.height * 0.42),
                    CGPoint(x: size.width * 0.84, y: size.height * 0.49),
                    CGPoint(x: size.width * 0.94, y: size.height * 0.22)
                ]
                if let first = points.first {
                    line.move(to: first)
                    for point in points.dropFirst() {
                        line.addLine(to: point)
                    }
                }
                context.stroke(
                    line,
                    with: .color(.white.opacity(0.72)),
                    style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
                )

                for point in points {
                    context.fill(
                        Path(ellipseIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)),
                        with: .color(.white.opacity(0.92))
                    )
                }
            }
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
        VStack(alignment: .leading, spacing: 20) {
            RoundedRectangle(cornerRadius: 26).frame(height: 190)
            HStack(spacing: 10) {
                ForEach(0..<4, id: \.self) { _ in
                    Capsule().frame(width: 72, height: 40)
                }
            }
            Text("投资知识").font(.title2.bold())
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 14).frame(height: 76)
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
