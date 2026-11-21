import SwiftUI
import UIKit

private enum KnowledgeConceptPalette {
    static let accent = Color(red: 0.76, green: 0.29, blue: 0.12)
}

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

struct KnowledgeConceptCarouselCard: View {
    let concept: KnowledgeConceptCard
    let index: Int
    let count: Int
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            hero

            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    Text("W")
                        .font(.system(size: 25, weight: .medium, design: .serif))
                        .frame(width: 44, height: 44)
                        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("维基百科")
                            .font(.system(size: 16, weight: .semibold))
                        Text(concept.wikipediaTitle)
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                    }
                }

                Text(concept.summary)
                    .font(.system(size: 18, weight: .medium, design: .serif))
                    .foregroundStyle(.primary.opacity(0.88))
                    .lineSpacing(7)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                HStack(alignment: .bottom, spacing: 12) {
                    Text(concept.imageAttribution)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)

                    HStack(spacing: 5) {
                        Text("打开维基百科")
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(KnowledgeConceptPalette.accent)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 108)
        }
        .frame(width: width, height: height, alignment: .top)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(concept.title)，\(concept.summary)")
        .accessibilityHint("打开维基百科词条")
    }

    private var hero: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                conceptImage
                    .frame(width: proxy.size.width, height: heroHeight)
                    .clipped()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.72)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Spacer()

                        Text("\(index + 1) / \(count)")
                            .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(.ultraThinMaterial, in: Capsule())
                    }

                    Spacer(minLength: 0)

                    Text(concept.title)
                        .font(.system(size: 31, weight: .bold, design: .serif))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                .padding(17)
            }
            .frame(width: proxy.size.width, height: heroHeight)
            .clipped()
        }
        .frame(height: heroHeight)
        .clipped()
    }

    private var heroHeight: CGFloat {
        min(232, max(190, height * 0.34))
    }

    @ViewBuilder
    private var conceptImage: some View {
        KnowledgeConceptCachedImage(url: concept.coverURL) { image in
            GeometryReader { proxy in
                ZStack {
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .blur(radius: 18)
                        .scaleEffect(1.08)
                        .overlay(Color.black.opacity(0.16))

                    image
                        .resizable()
                        .scaledToFit()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
            }
            .saturation(0.72)
            .contrast(0.96)
            .overlay(Color(red: 0.55, green: 0.34, blue: 0.14).opacity(0.05))
        } placeholder: { isLoading in
            imageFallback
                .overlay {
                    if isLoading {
                        ProgressView().controlSize(.small)
                    }
                }
        }
    }

    private var imageFallback: some View {
        ZStack {
            LinearGradient(
                colors: [
                    KnowledgeConceptPalette.accent.opacity(0.24),
                    Color.primary.opacity(0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: concept.kind == .person ? "person.crop.rectangle" : "building.columns")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.white.opacity(0.8))
        }
    }
}
