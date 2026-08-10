import SwiftUI

@MainActor
private final class GoogleNoiseStore: ObservableObject {
    @Published private(set) var snapshot: GoogleNoiseSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let client = APIClient(baseURL: ServerConfiguration.currentURL)

    func load(showLoading: Bool = false) async {
        if showLoading { isLoading = true }
        defer { isLoading = false }
        do {
            snapshot = try await client.fetchGoogleNoise()
            errorMessage = nil
        } catch {
            errorMessage = "暂时无法读取 X 信号，请稍后重试"
        }
    }
}

struct GoogleNoiseView: View {
    private enum Sentiment: String, CaseIterable, Identifiable {
        case positive, negative
        var id: Self { self }
        var title: String { self == .positive ? "正面" : "负面" }
        var color: Color { self == .positive ? .green : .red }
        var icon: String { self == .positive ? "arrow.up.right" : "arrow.down.right" }
    }

    @StateObject private var store = GoogleNoiseStore()
    @State private var sentiment: Sentiment = .positive
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                content
            }
            .navigationTitle("Google 噪音")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await store.load() }
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
                LazyVStack(spacing: 14) {
                    header(snapshot)
                    Picker("情绪", selection: $sentiment) {
                        ForEach(Sentiment.allCases) { item in Text(item.title).tag(item) }
                    }
                    .pickerStyle(.segmented)

                    let visibleItems = snapshot.items.filter { $0.sentiment == sentiment.rawValue }
                    if visibleItems.isEmpty {
                        ContentUnavailableView(
                            "暂无\(sentiment.title)信号",
                            systemImage: "waveform.path.ecg",
                            description: Text("新 X 动态入库后会自动更新")
                        )
                        .padding(.top, 56)
                    } else {
                        ForEach(visibleItems) { item in noiseCard(item) }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
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
                    Text("透明规则分类 · 未接入大模型")
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

    private func noiseCard(_ item: GoogleNoiseItem) -> some View {
        Button {
            if let url = URL(string: item.sourceURL) { openURL(url) }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    avatar(item)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.authorName.isEmpty ? item.authorHandle : item.authorName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(authorMeta(item))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label(sentiment.title, systemImage: sentiment.icon)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(sentiment.color)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(sentiment.color.opacity(0.1), in: Capsule())
                }
                if !item.title.isEmpty && item.title != item.content {
                    Text(item.title).font(.headline).foregroundStyle(.primary)
                }
                Text(item.content)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(8)
                HStack {
                    Label(item.sentimentTerms.prefix(3).joined(separator: " · "), systemImage: "text.magnifyingglass")
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func avatar(_ item: GoogleNoiseItem) -> some View {
        if let url = URL(string: item.avatarURL), !item.avatarURL.isEmpty {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Circle().fill(Color.secondary.opacity(0.12))
            }
            .frame(width: 38, height: 38)
            .clipShape(Circle())
        } else {
            Circle().fill(Color.blue.opacity(0.12)).frame(width: 38, height: 38)
                .overlay(Text("X").font(.caption.bold()))
        }
    }

    private func authorMeta(_ item: GoogleNoiseItem) -> String {
        let handle = item.authorHandle.isEmpty ? "X 来源" : "@\(item.authorHandle.trimmingCharacters(in: CharacterSet(charactersIn: "@")))"
        guard let value = item.publishedAt,
              let date = ISO8601DateFormatter().date(from: value) else { return handle }
        return "\(handle) · \(date.formatted(.relative(presentation: .named)))"
    }
}
