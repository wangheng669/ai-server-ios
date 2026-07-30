import SwiftUI

private enum KnowledgeConceptPalette {
    static let accent = Color(red: 0.76, green: 0.29, blue: 0.12)
    static let paper = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.secondarySystemBackground
                : UIColor(red: 0.995, green: 0.982, blue: 0.95, alpha: 1)
        }
    )
    static let line = Color.primary.opacity(0.10)
}

struct KnowledgeConceptCarouselCard: View {
    let concept: KnowledgeConceptCard
    let index: Int
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(concept.subtitle.isEmpty ? concept.kind.title : concept.subtitle)
                    .font(.system(size: 13, weight: .semibold, design: .serif))
                    .foregroundStyle(KnowledgeConceptPalette.accent)
                    .padding(.horizontal, 11)
                    .frame(height: 31)
                    .background(KnowledgeConceptPalette.accent.opacity(0.08), in: Capsule())
                Spacer()
                Text(String(format: "%02d / %02d", index + 1, count))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Text(concept.title)
                .font(.system(size: 35, weight: .bold, design: .serif))
                .foregroundStyle(.primary)
                .padding(.top, 17)

            conceptImage
                .frame(height: 225)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.top, 16)

            Text(concept.summary)
                .font(.system(size: 15, weight: .medium, design: .serif))
                .foregroundStyle(.primary.opacity(0.84))
                .lineSpacing(4)
                .lineLimit(3)
                .padding(.top, 15)

            Divider()
                .padding(.vertical, 14)

            Text("为什么重要")
                .font(.system(size: 17, weight: .bold, design: .serif))
                .foregroundStyle(KnowledgeConceptPalette.accent)
            Text(concept.importance)
                .font(.system(size: 14, design: .serif))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .lineLimit(3)
                .padding(.top, 6)

            if !concept.keyPeople.isEmpty {
                Text("关键人物")
                    .font(.system(size: 15, weight: .bold, design: .serif))
                    .foregroundStyle(KnowledgeConceptPalette.accent)
                    .padding(.top, 13)
                ScrollView(.horizontal) {
                    HStack(spacing: 7) {
                        ForEach(concept.keyPeople.prefix(4), id: \.self) { person in
                            Text(person)
                                .font(.system(size: 12.5, weight: .medium))
                                .padding(.horizontal, 10)
                                .frame(height: 29)
                                .background(Color.primary.opacity(0.055), in: Capsule())
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .padding(.top, 7)
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                Text("W")
                    .font(.system(size: 15, weight: .bold, design: .serif))
                    .frame(width: 29, height: 29)
                    .background(Color.primary.opacity(0.045), in: Circle())
                Text("资料来源：维基百科")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(KnowledgeConceptPalette.paper)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(KnowledgeConceptPalette.line, lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.07), radius: 16, y: 8)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(concept.title)，\(concept.summary)")
        .accessibilityHint("打开详细内容")
    }

    @ViewBuilder
    private var conceptImage: some View {
        AsyncImage(url: concept.coverURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
                    .saturation(0.42)
                    .contrast(0.93)
                    .overlay(Color(red: 0.55, green: 0.34, blue: 0.14).opacity(0.08))
            case .failure:
                imageFallback
            case .empty:
                imageFallback
                    .overlay { ProgressView().controlSize(.small) }
            @unknown default:
                imageFallback
            }
        }
    }

    private var imageFallback: some View {
        ZStack {
            Color.primary.opacity(0.045)
            Image(systemName: concept.kind == .person ? "person.crop.rectangle" : "building.columns")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(KnowledgeConceptPalette.accent.opacity(0.55))
        }
    }
}

struct KnowledgeConceptDetailSheet: View {
    let cards: [KnowledgeConceptCard]
    let initialID: String

    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: String
    @State private var wikipediaEntity: WikipediaEntity?

    init(cards: [KnowledgeConceptCard], initialID: String) {
        self.cards = cards
        self.initialID = initialID
        _selectedID = State(
            initialValue: cards.contains(where: { $0.id == initialID })
                ? initialID
                : cards.first?.id ?? initialID
        )
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedID) {
                ForEach(cards) { card in
                    KnowledgeConceptDetailPage(card: card) { detail in
                        guard let url = detail.wikipediaURL else { return }
                        wikipediaEntity = WikipediaEntity(
                            id: detail.id,
                            term: detail.wikipediaTitle,
                            title: detail.wikipediaTitle,
                            summary: detail.summary,
                            url: url
                        )
                    }
                    .tag(card.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(KnowledgeConceptPalette.paper.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text(currentCard?.kind.title ?? "概念")
                            .font(.headline)
                        if cards.count > 1 {
                            Text("\(currentIndex + 1) / \(cards.count) · 左右滑动")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .animation(.snappy(duration: 0.2), value: selectedID)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .fullScreenCover(item: $wikipediaEntity) { entity in
            WikipediaReaderView(entity: entity, returnTitle: "返回概念详情")
        }
    }

    private var currentIndex: Int {
        cards.firstIndex(where: { $0.id == selectedID }) ?? 0
    }

    private var currentCard: KnowledgeConceptCard? {
        cards.indices.contains(currentIndex) ? cards[currentIndex] : cards.first
    }
}

private struct KnowledgeConceptDetailPage: View {
    let card: KnowledgeConceptCard
    let openWikipedia: (KnowledgeConceptDetail) -> Void

    @State private var detail: KnowledgeConceptDetail?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                hero
                summarySection

                if let detail {
                    detailSections(detail)
                } else if isLoading {
                    ProgressView("正在载入详细内容")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 42)
                } else if let errorMessage {
                    ContentUnavailableView {
                        Label("详细内容载入失败", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("重试") { Task { await load() } }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                }
            }
            .padding(.bottom, 44)
        }
        .background(KnowledgeConceptPalette.paper.ignoresSafeArea())
        .task(id: card.id) { await load() }
    }

    private var hero: some View {
        AsyncImage(url: card.coverURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
                    .saturation(0.45)
                    .contrast(0.94)
            case .failure:
                heroFallback
            case .empty:
                heroFallback.overlay { ProgressView() }
            @unknown default:
                heroFallback
            }
        }
        .frame(height: 250)
        .clipped()
        .overlay(alignment: .bottomLeading) {
            LinearGradient(
                colors: [.clear, .black.opacity(0.56)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 120)
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(card.subtitle.isEmpty ? card.kind.title : card.subtitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.82))
                    Text(card.title)
                        .font(.system(size: 34, weight: .bold, design: .serif))
                        .foregroundStyle(.white)
                }
                .padding(20)
            }
        }
    }

    private var heroFallback: some View {
        ZStack {
            Color.primary.opacity(0.08)
            Image(systemName: card.kind == .person ? "person.crop.rectangle" : "building.columns")
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(KnowledgeConceptPalette.accent.opacity(0.55))
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(card.summary)
                .font(.system(size: 18, weight: .medium, design: .serif))
                .lineSpacing(6)
            sectionCard(title: "为什么重要") {
                Text(card.importance)
                    .font(.system(size: 16, design: .serif))
                    .foregroundStyle(.primary.opacity(0.84))
                    .lineSpacing(5)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
    }

    @ViewBuilder
    private func detailSections(_ detail: KnowledgeConceptDetail) -> some View {
        if !detail.content.background.isEmpty {
            sectionCard(title: "历史背景") {
                Text(detail.content.background)
                    .font(.system(size: 16, design: .serif))
                    .foregroundStyle(.primary.opacity(0.84))
                    .lineSpacing(6)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
        }

        if !detail.content.timeline.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("关键时间线")
                VStack(spacing: 0) {
                    ForEach(Array(detail.content.timeline.enumerated()), id: \.element.id) { index, point in
                        KnowledgeConceptTimelineRow(
                            point: point,
                            isLast: index == detail.content.timeline.indices.last
                        )
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 26)
        }

        if !detail.content.keyPoints.isEmpty {
            sectionCard(title: "理解要点") {
                VStack(alignment: .leading, spacing: 13) {
                    ForEach(Array(detail.content.keyPoints.enumerated()), id: \.offset) { index, point in
                        HStack(alignment: .top, spacing: 11) {
                            Text("\(index + 1)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(KnowledgeConceptPalette.accent, in: Circle())
                            Text(point)
                                .font(.system(size: 15.5, design: .serif))
                                .lineSpacing(4)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
        }

        if !detail.content.keyPeople.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("关键人物")
                FlowLayout(spacing: 8) {
                    ForEach(detail.content.keyPeople, id: \.self) { person in
                        Text(person)
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.horizontal, 13)
                            .frame(height: 36)
                            .background(Color.primary.opacity(0.055), in: Capsule())
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 26)
        }

        sourceSection(detail)
            .padding(.horizontal, 20)
            .padding(.top, 28)
    }

    private func sourceSection(_ detail: KnowledgeConceptDetail) -> some View {
        Button {
            openWikipedia(detail)
        } label: {
            HStack(spacing: 12) {
                Text("W")
                    .font(.system(size: 19, weight: .bold, design: .serif))
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 40)
                    .background(Color.primary.opacity(0.05), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text("维基百科")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("查看「\(detail.wikipediaTitle)」完整词条")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(Color.primary.opacity(0.035))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(detail.wikipediaURL == nil)
        .overlay(alignment: .bottomLeading) {
            if !detail.imageAttribution.isEmpty {
                Text(detail.imageAttribution)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
                    .offset(y: 25)
            }
        }
    }

    private func sectionCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionTitle(title)
            content()
        }
        .padding(17)
        .background(Color.primary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(KnowledgeConceptPalette.line, lineWidth: 0.7)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 20, weight: .bold, design: .serif))
            .foregroundStyle(KnowledgeConceptPalette.accent)
    }

    @MainActor
    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            detail = try await LearningService().fetchConcept(id: card.id)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct KnowledgeConceptTimelineRow: View {
    let point: KnowledgeConceptTimelinePoint
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            VStack(spacing: 0) {
                Circle()
                    .fill(KnowledgeConceptPalette.accent)
                    .frame(width: 10, height: 10)
                if !isLast {
                    Rectangle()
                        .fill(KnowledgeConceptPalette.accent.opacity(0.22))
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 12)

            VStack(alignment: .leading, spacing: 5) {
                Text(point.date)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(KnowledgeConceptPalette.accent)
                Text(point.title)
                    .font(.system(size: 17, weight: .bold, design: .serif))
                Text(point.description)
                    .font(.system(size: 14.5, design: .serif))
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
            }
            .padding(.bottom, isLast ? 0 : 20)
        }
    }
}

private struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let result = layout(subviews: subviews, width: proposal.width ?? .infinity)
        return result.size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let result = layout(subviews: subviews, width: bounds.width)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                proposal: .unspecified
            )
        }
    }

    private func layout(subviews: Subviews, width: CGFloat) -> (size: CGSize, points: [CGPoint]) {
        var points: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: width, height: y + rowHeight), points)
    }
}
