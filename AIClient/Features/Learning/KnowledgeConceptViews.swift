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
                        .fixedSize(horizontal: false, vertical: true)

                    if concept.wikipediaURL != nil {
                        Button {
                            open(concept)
                        } label: {
                            HStack {
                                Label("阅读维基百科", systemImage: "book.pages")
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .accessibilityHidden(true)
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(accent)
                            .padding(12)
                            .frame(minHeight: 44)
                            .background(accent.opacity(0.10), in: .rect(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }

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
