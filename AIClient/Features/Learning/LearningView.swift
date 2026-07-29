import SwiftUI
import UIKit
import OSLog

private let learningImageLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "AIServerClient",
    category: "LearningImages"
)

struct LearningView: View {
    @Binding private var showsDetail: Bool
    @State private var store = LearningStore()
    @State private var repository = LearningContentRepository()
    @State private var path: [LearningRoute] = []
    @State private var selectedCategory = "股票"
    @State private var selectedSection: KnowledgeSection = {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--learning-books-preview") ? .books : .investment
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
                case let .book(book):
                    KnowledgeBookDetailView(book: book)
                }
            }
        }
        .task {
            await store.load()
            #if DEBUG
            if (ProcessInfo.processInfo.arguments.contains("--learning-detail-preview") ||
                ProcessInfo.processInfo.arguments.contains("--learning-video-preview")),
               path.isEmpty,
               let topic = store.catalog?.sections
                .flatMap(\.topics)
                .first(where: { $0.title.contains("市盈率") }) {
                path = [.topic(topic)]
            } else if ProcessInfo.processInfo.arguments.contains("--learning-book-preview"),
                      path.isEmpty,
                      let book = KnowledgeBook.featured.first {
                path = [.book(book)]
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
                    break
                }
            }
        }
        .animation(.easeOut(duration: 0.18), value: showsSearch)
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("知识")
                .font(.system(size: 38, weight: .bold))
            Spacer()
            Button {
                showsSearch.toggle()
                if !showsSearch { query = "" }
            } label: {
                Image(systemName: showsSearch ? "xmark" : "magnifyingglass")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(Color(uiColor: .secondarySystemBackground), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                showsSearch ? "关闭搜索" : "搜索\(selectedSection.title)内容"
            )
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var sectionPicker: some View {
        HStack(spacing: 0) {
            sectionButton(.investment)
            sectionButton(.books)
        }
        .frame(height: 48)
        .padding(.horizontal, 20)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.secondary.opacity(0.16))
                .frame(height: 0.5)
                .padding(.horizontal, 20)
        }
        .padding(.bottom, showsSearch ? 14 : 20)
    }

    private func sectionButton(_ section: KnowledgeSection) -> some View {
        Button {
            guard selectedSection != section else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                selectedSection = section
                query = ""
            }
        } label: {
            Text(section.title)
                .font(.system(size: 17, weight: selectedSection == section ? .semibold : .medium))
                .foregroundStyle(selectedSection == section ? Color.primary : Color.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottom) {
                    if selectedSection == section {
                        Capsule()
                            .fill(HoldingsPalette.purple)
                            .frame(width: 38, height: 3)
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
        .frame(height: 46)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
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
                ZStack(alignment: .bottomLeading) {
                    LearningHeroArtwork()
                    VStack(alignment: .leading, spacing: 14) {
                        Text("从零开始读懂股票")
                            .font(.system(size: 25, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("精选 12 个基础概念")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 7) {
                            Text("开始学习")
                                .font(.system(size: 16, weight: .semibold))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(HoldingsPalette.purple)
                        .padding(.top, 30)
                    }
                    .padding(24)
                }
                .frame(height: 228)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .buttonStyle(LearningPressStyle())
            .padding(.horizontal, 20)
        }
    }

    private func categoryPicker(_ sections: [LearningSection]) -> some View {
        HStack(spacing: 8) {
            ForEach(sections) { section in
                Button {
                    withAnimation(.easeOut(duration: 0.16)) {
                        selectedCategory = section.name
                    }
                } label: {
                    VStack(spacing: 10) {
                        Image(systemName: categoryIcon(section.name))
                            .font(.system(size: 22, weight: .medium))
                        Text(section.name)
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundStyle(
                        selectedCategory == section.name ? HoldingsPalette.purple : Color.secondary
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 78)
                    .background(
                        selectedCategory == section.name
                            ? HoldingsPalette.purple.opacity(0.09)
                            : Color(uiColor: .secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedCategory == section.name ? .isSelected : [])
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    @ViewBuilder
    private func topicList(_ catalog: LearningCatalog) -> some View {
        let topics = filteredTopics(catalog)
        HStack(alignment: .firstTextBaseline) {
            Text("\(selectedCategory)知识")
                .font(.system(size: 23, weight: .bold))
            Spacer()
            Text("\(topics.count) 篇")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
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
            ForEach(topics) { topic in
                Button {
                    path.append(.topic(topic))
                } label: {
                    LearningTopicRow(topic: topic)
                }
                .buttonStyle(LearningPressStyle())
                if topic.id != topics.last?.id {
                    Divider().padding(.leading, 118)
                }
            }
        }
    }

    @ViewBuilder
    private func investmentSearchResults(_ catalog: LearningCatalog) -> some View {
        let topics = filteredTopics(catalog)

        HStack(alignment: .firstTextBaseline) {
            Text("搜索结果")
                .font(.system(size: 23, weight: .bold))
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
            ForEach(topics) { topic in
                Button {
                    path.append(.topic(topic))
                } label: {
                    LearningTopicRow(topic: topic)
                }
                .buttonStyle(LearningPressStyle())
                if topic.id != topics.last?.id {
                    Divider().padding(.leading, 118)
                }
            }
        }
    }

    @ViewBuilder
    private var booksContent: some View {
        let books = filteredBooks()
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 5) {
                Text(query.isEmpty ? "投资经典" : "搜索结果")
                    .font(.system(size: 25, weight: .bold))
                if query.isEmpty {
                    Text("建立体系，训练判断")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("\(books.count) 本")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)

        if books.isEmpty {
            ContentUnavailableView(
                "没有找到相关书籍",
                systemImage: "books.vertical",
                description: Text("试试书名、作者或投资主题")
            )
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        } else {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 20),
                    GridItem(.flexible(), spacing: 20)
                ],
                alignment: .center,
                spacing: 28
            ) {
                ForEach(books) { book in
                    let paletteIndex = KnowledgeBook.featured.firstIndex(where: { $0.id == book.id }) ?? 0
                    Button {
                        path.append(.book(book))
                    } label: {
                        KnowledgeBookCard(book: book, paletteIndex: paletteIndex)
                    }
                    .buttonStyle(LearningPressStyle())
                }
            }
            .padding(.horizontal, 20)
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
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return KnowledgeBook.featured }
        return KnowledgeBook.featured.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed) ||
                ($0.originalTitle?.localizedCaseInsensitiveContains(trimmed) ?? false) ||
                $0.author.localizedCaseInsensitiveContains(trimmed) ||
                $0.summary.localizedCaseInsensitiveContains(trimmed) ||
                $0.keyIdeas.contains { $0.localizedCaseInsensitiveContains(trimmed) }
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
}

private enum LearningRoute: Hashable {
    case topic(LearningTopic)
    case book(KnowledgeBook)
}

private struct KnowledgeBookCard: View {
    let book: KnowledgeBook
    let paletteIndex: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            KnowledgeBookCover(book: book, paletteIndex: paletteIndex)
                .frame(width: 132, height: 184)
                .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 5)
            Text(book.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(book.author)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 132, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(book.title)，作者\(book.author)")
        .accessibilityHint("查看书籍介绍")
    }
}

private struct KnowledgeBookCover: View {
    let book: KnowledgeBook
    let paletteIndex: Int
    var compact = false

    var body: some View {
        ZStack(alignment: .leading) {
            LinearGradient(
                colors: palette,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Rectangle()
                .fill(.black.opacity(0.13))
                .frame(width: compact ? 4 : 7)
            Rectangle()
                .fill(.white.opacity(0.18))
                .frame(width: 1)
                .padding(.leading, compact ? 5 : 9)

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
        .clipShape(RoundedRectangle(cornerRadius: compact ? 5 : 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: compact ? 5 : 9, style: .continuous)
                .stroke(.white.opacity(0.2), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
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

private struct KnowledgeBookDetailView: View {
    let book: KnowledgeBook
    @Environment(\.dismiss) private var dismiss

    private var paletteIndex: Int {
        KnowledgeBook.featured.firstIndex(where: { $0.id == book.id }) ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            detailBar
            Divider().opacity(0.5)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(spacing: 18) {
                        KnowledgeBookCover(book: book, paletteIndex: paletteIndex)
                            .frame(width: 154, height: 216)
                            .shadow(color: .black.opacity(0.16), radius: 14, x: 0, y: 8)
                        VStack(spacing: 7) {
                            Text(book.title)
                                .font(.system(size: 30, weight: .bold))
                                .multilineTextAlignment(.center)
                            if let originalTitle = book.originalTitle {
                                Text(originalTitle)
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            Text(book.author)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 28)
                    .padding(.bottom, 32)

                    detailSection(title: "内容简介", text: book.summary)
                    detailSection(title: "为什么值得读", text: book.recommendation)

                    Text("你会学到")
                        .font(.system(size: 22, weight: .bold))
                        .padding(.bottom, 14)
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(book.keyIdeas.enumerated()), id: \.offset) { index, idea in
                            HStack(alignment: .top, spacing: 12) {
                                Text("\(index + 1)")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(HoldingsPalette.purple)
                                    .frame(width: 26, height: 26)
                                    .background(HoldingsPalette.purple.opacity(0.1), in: Circle())
                                Text(idea)
                                    .font(.system(size: 17))
                                    .lineSpacing(5)
                                    .padding(.top, 2)
                            }
                        }
                    }
                    .padding(.bottom, 30)

                    detailSection(title: "适合谁", text: book.suitableFor)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 50)
            }
            .scrollIndicators(.hidden)
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
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
            Text("书籍")
                .font(.system(size: 17, weight: .semibold))
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 6)
        .frame(height: 50)
    }

    private func detailSection(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 22, weight: .bold))
            Text(text)
                .font(.system(size: 17))
                .foregroundStyle(Color(uiColor: .label))
                .lineSpacing(7)
        }
        .padding(.bottom, 30)
    }
}

private struct LearningHeroArtwork: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    HoldingsPalette.purple.opacity(0.12),
                    Color(red: 0.96, green: 0.95, blue: 1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Canvas { context, size in
                var bars = Path()
                let values: [CGFloat] = [0.24, 0.42, 0.34, 0.58, 0.5, 0.75, 0.68, 0.88]
                let spacing = size.width * 0.055
                let startX = size.width * 0.53
                for (index, value) in values.enumerated() {
                    let x = startX + CGFloat(index) * spacing
                    let centerY = size.height * (0.74 - value * 0.44)
                    bars.move(to: CGPoint(x: x, y: centerY - 14))
                    bars.addLine(to: CGPoint(x: x, y: centerY + 14))
                    bars.addRect(CGRect(x: x - 6, y: centerY - 8, width: 12, height: 16))
                }
                context.stroke(
                    bars,
                    with: .color(HoldingsPalette.purple.opacity(0.34)),
                    lineWidth: 1.5
                )

                var line = Path()
                let points = values.enumerated().map { index, value in
                    CGPoint(
                        x: startX + CGFloat(index) * spacing,
                        y: size.height * (0.77 - value * 0.48)
                    )
                }
                if let first = points.first {
                    line.move(to: first)
                    for point in points.dropFirst() { line.addLine(to: point) }
                }
                context.stroke(
                    line,
                    with: .color(HoldingsPalette.purple.opacity(0.52)),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                )
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
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
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
            RoundedRectangle(cornerRadius: 24).frame(height: 228)
            HStack(spacing: 10) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 18).frame(height: 78)
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
