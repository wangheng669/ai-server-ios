import SwiftUI
import UIKit

struct LearningView: View {
    @Binding private var showsDetail: Bool
    @State private var store = LearningStore()
    @State private var repository = LearningContentRepository()
    @State private var path: [LearningTopic] = []
    @State private var selectedCategory = "股票"
    @State private var query = ""
    @State private var showsSearch = false

    init(showsDetail: Binding<Bool> = .constant(false)) {
        _showsDetail = showsDetail
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let catalog = store.catalog {
                    learningHome(catalog)
                } else if store.isLoading {
                    LearningLoadingView()
                } else {
                    ContentUnavailableView {
                        Label("学习内容载入失败", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(store.errorMessage ?? "请稍后重试")
                    } actions: {
                        Button("重试") { Task { await store.load(force: true) } }
                    }
                }
            }
            .background(Color(uiColor: .systemBackground).ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: LearningTopic.self) { topic in
                LearningDetailView(topic: topic, repository: repository)
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
                path = [topic]
            }
            #endif
        }
        .onChange(of: path.isEmpty, initial: true) { _, isEmpty in
            showsDetail = !isEmpty
        }
        .task(id: prefetchKey) {
            guard let catalog = store.catalog,
                  let section = catalog.sections.first(where: { $0.name == selectedCategory }) else {
                return
            }
            await repository.prefetch(section.topics.prefix(10))
        }
        .onDisappear { showsDetail = false }
    }

    private var prefetchKey: String {
        "\(store.catalog?.fetchedAt.timeIntervalSince1970 ?? 0)-\(selectedCategory)"
    }

    private func learningHome(_ catalog: LearningCatalog) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                header
                if showsSearch {
                    searchField
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if query.isEmpty {
                    featuredTopic(in: catalog)
                    categoryPicker(catalog.sections)
                }
                topicList(catalog)
            }
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .safeAreaPadding(.bottom, 90)
        .refreshable { await store.load(force: true) }
        .animation(.easeOut(duration: 0.18), value: showsSearch)
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("学习")
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
            .accessibilityLabel(showsSearch ? "关闭搜索" : "搜索投资知识")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 18)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("搜索投资知识", text: $query)
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
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private func featuredTopic(in catalog: LearningCatalog) -> some View {
        if let topic = catalog.sections
            .flatMap(\.topics)
            .first(where: { $0.title.contains("市盈率") }) ?? catalog.sections.first?.topics.first {
            Button {
                path.append(topic)
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
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(query.isEmpty ? "\(selectedCategory)知识" : "搜索结果")
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
                        path.append(topic)
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
            finishedLoading = false
            let url = topic.mediaURL(topic.thumbnailURLValue)
            image = await ImageLoader.load(
                url,
                targetSize: CGSize(width: 84, height: 58)
            )
            finishedLoading = true
        }
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

private struct LearningLoadingView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("学习").font(.system(size: 38, weight: .bold))
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
            .padding(20)
            .foregroundStyle(Color.secondary.opacity(0.16))
            .redacted(reason: .placeholder)
        }
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
