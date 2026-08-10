import SwiftUI

@MainActor
private final class GoogleNoiseStore: ObservableObject {
    @Published private(set) var snapshot: GoogleNoiseSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var translations: [Int64: String] = [:]

    private let client = APIClient(baseURL: ServerConfiguration.currentURL)
    private var loadingTranslationIDs: Set<Int64> = []

    func load(showLoading: Bool = false) async {
        if showLoading { isLoading = true }
        defer { isLoading = false }
        do {
            snapshot = try await client.fetchGoogleNoise(limit: 100)
            errorMessage = nil
        } catch {
            errorMessage = "暂时无法读取 X 信号，请稍后重试"
        }
    }

    func post(for item: GoogleNoiseItem) -> Post? {
        guard let post = item.previewPost,
              let translation = translations[item.id] else { return item.previewPost }
        return post.replacingTranslation(with: translation)
    }

    func translateIfNeeded(_ item: GoogleNoiseItem) async {
        guard item.needsTranslation,
              !item.articleID.isEmpty,
              translations[item.id] == nil,
              !loadingTranslationIDs.contains(item.id) else { return }
        loadingTranslationIDs.insert(item.id)
        defer { loadingTranslationIDs.remove(item.id) }
        do {
            let result = try await client.fetchXTranslation(tweetID: item.articleID)
            guard !Task.isCancelled else { return }
            let value = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, value != item.originalContent else { return }
            translations[item.id] = value
        } catch is CancellationError {
            return
        } catch {
            // Translation is best-effort, matching the X feed behavior.
        }
    }
}

struct GoogleNoiseView: View {
    private enum Sentiment: String, CaseIterable, Identifiable {
        case positive, negative, neutral
        var id: Self { self }
        var title: String {
            switch self {
            case .positive: "正面"
            case .negative: "负面"
            case .neutral: "中性"
            }
        }
    }

    @StateObject private var store = GoogleNoiseStore()
    @State private var sentiment: Sentiment = .positive
    @State private var selectedPost: Post?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemBackground).ignoresSafeArea()
                content
            }
            .navigationTitle("Google 噪音")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await store.load() }
        }
        .sheet(item: $selectedPost) { post in
            NavigationStack {
                PostDetailView(post: post, presentedAsSheet: true)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
            .presentationContentInteraction(.scrolls)
        }
        .task {
            await store.load(showLoading: true)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard scenePhase == .active else { continue }
                await store.load()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.load() } }
        }
    }

    @ViewBuilder private var content: some View {
        if store.isLoading && store.snapshot == nil {
            ProgressView("正在读取 X 实时信号…")
        } else if let snapshot = store.snapshot {
            ScrollView {
                LazyVStack(spacing: 0) {
                    header(snapshot)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 14)
                    Picker("情绪", selection: $sentiment) {
                        ForEach(Sentiment.allCases) { item in Text(item.title).tag(item) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                    let visibleItems = snapshot.items.filter { $0.sentiment == sentiment.rawValue }
                    if visibleItems.isEmpty {
                        ContentUnavailableView(
                            "暂无\(sentiment.title)信号",
                            systemImage: "waveform.path.ecg",
                            description: Text("新 X 动态入库后会自动更新")
                        )
                        .padding(.top, 56)
                    } else {
                        ForEach(visibleItems) { item in
                            if let post = store.post(for: item) {
                                NewsCardView(post: post, onOpen: { open(item) })
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                    .modifier(ConditionalTapGestureModifier(isEnabled: true) {
                                        open(item)
                                    })
                                    .task(id: item.id) { await store.translateIfNeeded(item) }
                                Divider().opacity(0.6)
                            }
                        }
                    }
                }
                .padding(.bottom, 24)
            }
        } else {
            ContentUnavailableView {
                Label("噪音流暂不可用", systemImage: "wifi.exclamationmark")
            } description: {
                Text(store.errorMessage ?? "请稍后重试")
            } actions: {
                Button("重新加载") { Task { await store.load(showLoading: true) } }
            }
        }
    }

    private func header(_ snapshot: GoogleNoiseSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("X 实时公司信号")
                        .font(.title2.bold())
                    Text("关键词预筛 · Qwen Flash 分类")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label("自动更新", systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            }
            HStack(spacing: 10) {
                metric("正面", snapshot.stats.positive, .green)
                metric("负面", snapshot.stats.negative, .red)
                metric("相关", snapshot.stats.relevant, .blue)
            }
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 0.7)
        }
    }

    private func metric(_ title: String, _ value: Int, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value, format: .number).font(.title3.bold()).foregroundStyle(color)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func open(_ item: GoogleNoiseItem) {
        selectedPost = store.post(for: item)
    }
}
