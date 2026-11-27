import SwiftUI
import UIKit

enum KnowledgeConceptImageLoading {
    static let targetSize = CGSize(width: 430, height: 250)

    static func prefetch(_ concepts: [KnowledgeConceptCard]) async {
        let urls = Set(concepts.compactMap(\.coverURL))
        await withTaskGroup(of: Void.self) { group in
            for url in urls {
                group.addTask {
                    _ = await ImageLoader.load(url, targetSize: targetSize)
                }
            }
        }
    }
}

private struct KnowledgeConceptCachedImage<Success: View, Placeholder: View>: View {
    let url: URL?
    let success: (Image) -> Success
    let placeholder: (Bool) -> Placeholder

    @State private var image: UIImage?
    @State private var isLoading = true

    init(
        url: URL?,
        @ViewBuilder success: @escaping (Image) -> Success,
        @ViewBuilder placeholder: @escaping (Bool) -> Placeholder
    ) {
        self.url = url
        self.success = success
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let image {
                success(Image(uiImage: image))
            } else {
                placeholder(isLoading)
            }
        }
        .task(id: url) {
            image = nil
            guard let url else {
                isLoading = false
                return
            }

            isLoading = true
            let loadedImage = await ImageLoader.load(
                url,
                targetSize: KnowledgeConceptImageLoading.targetSize
            )
            guard !Task.isCancelled else { return }
            image = loadedImage
            isLoading = false
        }
    }
}

struct KnowledgeConceptDeck: View {
    let concepts: [KnowledgeConceptCard]
    @Binding var selectedID: String?
    let open: (KnowledgeConceptCard) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let accent = KnowledgePagePalette.archive

    var body: some View {
        if let first = concepts.first {
            let index = concepts.firstIndex { $0.id == selectedID } ?? 0
            let concept = concepts[index]
            VStack(alignment: .leading, spacing: 12) {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        ForEach(concepts) { item in
                            artwork(for: item)
                                .containerRelativeFrame(.horizontal)
                                .id(item.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, 20, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
                .scrollPosition(id: $selectedID)
                .scrollIndicators(.hidden)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 6) {
                        Text(concept.kind.title)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(accent)
                        Spacer()
                        pageButton("chevron.left", title: "上一张", index: index - 1)
                        Text("\(index + 1) / \(concepts.count)")
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("第\(index + 1)张，共\(concepts.count)张")
                        pageButton("chevron.right", title: "下一张", index: index + 1)
                    }

                    Text(concept.title)
                        .font(.largeTitle.weight(.bold))
                        .accessibilityAddTraits(.isHeader)

                    Text(concept.summary)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineSpacing(5)
                        .lineLimit(4)

                    Button {
                        open(concept)
                    } label: {
                        HStack {
                            Label("阅读概念详情", systemImage: "book.pages")
                            Spacer()
                            Image(systemName: "arrow.right").accessibilityHidden(true)
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(accent)
                        .padding(12)
                        .frame(minHeight: 44)
                        .background(accent.opacity(0.10), in: .rect(cornerRadius: 11))
                    }
                    .buttonStyle(.plain)

                    if !concept.imageAttribution.isEmpty {
                        Text(concept.imageAttribution)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(15)
                .knowledgeCard()
                .padding(.horizontal, 20)
            }
            .onAppear {
                if selectedID == nil { selectedID = first.id }
            }
        }
    }

    private func pageButton(_ symbol: String, title: String, index: Int) -> some View {
        let isAvailable = concepts.indices.contains(index)
        return Button {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
                selectedID = concepts[index].id
            }
        } label: {
            Image(systemName: symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(isAvailable ? accent : .secondary)
                .frame(width: 44, height: 44)
                .background(accent.opacity(isAvailable ? 0.10 : 0.035), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .disabled(!isAvailable)
    }

    private func artwork(for concept: KnowledgeConceptCard) -> some View {
        GeometryReader { geometry in
            KnowledgeConceptCachedImage(url: concept.coverURL) { image in
                image.resizable().scaledToFill()
            } placeholder: { loading in
                ZStack {
                    accent.opacity(0.13)
                    if loading {
                        ProgressView().tint(accent)
                    } else {
                        Image(systemName: concept.kind == .person ? "person.crop.rectangle" : "books.vertical")
                            .font(.largeTitle.weight(.light))
                            .foregroundStyle(accent)
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .frame(height: 204)
        .clipShape(.rect(cornerRadius: 17))
    }
}

struct KnowledgeConceptDetailView: View {
    let concept: KnowledgeConceptCard
    @Environment(\.dismiss) private var dismiss
    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            KnowledgeConceptDetailPage(id: concept.id, initialCard: concept)
                .navigationTitle("概念卡片")
                .navigationDestination(for: String.self) { id in
                    KnowledgeConceptDetailPage(id: id)
                        .navigationTitle("概念卡片")
                }
        }
        .floatingSheetClose("关闭概念详情", action: dismiss.callAsFunction)
    }
}

private struct KnowledgeConceptDetailPage: View {
    let id: String
    var initialCard: KnowledgeConceptCard?
    @State private var detail: KnowledgeConceptDetail?
    @State private var failed = false
    @State private var retry = 0
    @State private var reference: WikipediaEntity?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let card = detail?.card ?? initialCard {
                    header(card)
                }
                if let detail {
                    section("背景", lines: [detail.content.background])
                    timeline(detail.content.timeline)
                    section("要点", lines: detail.content.keyPoints)
                    section("相关人物", lines: detail.content.keyPeople)
                    if !detail.related.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            heading("相关概念")
                            ForEach(detail.related) { related in
                                NavigationLink(value: related.id) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(related.title).font(.headline)
                                            if !related.subtitle.isEmpty {
                                                Text(related.subtitle).font(.footnote).foregroundStyle(.secondary)
                                            }
                                        }
                                        .foregroundStyle(.primary)
                                        Spacer(minLength: 6)
                                        Image(systemName: "chevron.right")
                                            .font(.footnote.weight(.semibold))
                                            .foregroundStyle(KnowledgePagePalette.archive)
                                            .accessibilityHidden(true)
                                    }
                                    .padding(11)
                                    .frame(minHeight: 44)
                                    .knowledgeCard(cornerRadius: 11)
                                }
                            }
                        }
                    }
                } else if failed {
                    ContentUnavailableView {
                        Label("概念详情载入失败", systemImage: "wifi.exclamationmark")
                    } actions: {
                        Button("重试") { retry += 1 }
                    }
                } else {
                    ProgressView("正在载入概念详情")
                }
                if let card = detail?.card ?? initialCard, let url = card.wikipediaURL {
                    Button {
                        reference = WikipediaEntity(
                            id: card.id, term: card.wikipediaTitle, title: card.wikipediaTitle,
                            summary: card.summary, url: url
                        )
                    } label: {
                            Label("阅读维基百科", systemImage: "book.pages")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(KnowledgePagePalette.archive)
                            .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
                            .padding(.horizontal, 12)
                            .knowledgeCard(cornerRadius: 12)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 84)
            .frame(maxWidth: .infinity)
        }
        .background(KnowledgePagePalette.canvas.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task(id: retry) {
            guard detail == nil else { return }
            failed = false
            do {
                let loaded = try await LearningService().fetchConcept(id: id)
                try Task.checkCancellation()
                detail = loaded
            } catch {
                if !Task.isCancelled { failed = true }
            }
        }
        .appSheet(item: $reference) { entity in
            WikipediaReaderView(entity: entity)
                .wikipediaReaderPresentation()
        }
    }

    private func header(_ card: KnowledgeConceptCard) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let url = card.coverURL {
                KnowledgeConceptCachedImage(url: url) { image in
                    image.resizable().scaledToFit()
                } placeholder: { loading in
                    if loading { ProgressView().frame(maxWidth: .infinity, minHeight: 70) }
                }
                .frame(maxWidth: .infinity, maxHeight: 265)
                .clipShape(.rect(cornerRadius: 12))
                if !card.imageAttribution.isEmpty {
                    Text(card.imageAttribution).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Text(card.kind.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(KnowledgePagePalette.archive)
            Text(card.title)
                .font(.largeTitle.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            if !card.subtitle.isEmpty {
                Text(card.subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Text(card.summary).font(.body).lineSpacing(5)
            if !card.importance.isEmpty {
                Label(card.importance, systemImage: "lightbulb")
                    .font(.subheadline)
                    .foregroundStyle(KnowledgePagePalette.archive)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(KnowledgePagePalette.archive.opacity(0.07), in: .rect(cornerRadius: 16))
    }

    @ViewBuilder
    private func section(_ title: String, lines: [String]) -> some View {
        let content = lines.filter { !$0.isEmpty }
        if !content.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                heading(title)
                ForEach(Array(content.enumerated()), id: \.offset) { _, line in
                    Text(line).font(.body).lineSpacing(4).textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .knowledgeCard(cornerRadius: 13)
        }
    }

    @ViewBuilder
    private func timeline(_ points: [KnowledgeConceptDetail.TimelinePoint]) -> some View {
        if !points.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                heading("时间线")
                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(point.date)
                            .font(.footnote.monospacedDigit().weight(.semibold))
                            .foregroundStyle(KnowledgePagePalette.archive)
                        Text(point.title).font(.headline)
                        Text(point.description).font(.subheadline).lineSpacing(4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 10)
                    .overlay(alignment: .leading) {
                        Capsule().fill(KnowledgePagePalette.archive.opacity(0.4)).frame(width: 2)
                    }
                }
            }
        }
    }

    private func heading(_ text: String) -> some View {
        Text(text).font(.headline).accessibilityAddTraits(.isHeader)
    }
}
