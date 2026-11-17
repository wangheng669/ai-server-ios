import SwiftUI
import Translation
import NaturalLanguage
import CryptoKit

/// App-owned text cache. Apple owns the separate, shared on-device language models.
@MainActor
private final class TruthTranslationCache: ObservableObject {
    static let shared = TruthTranslationCache()
    private struct Entry: Codable { let text: String; let date: Date }
    @Published private var entries: [String: Entry] = [:]
    private var failedUntil: [String: Date] = [:]
    private var translating = false
    private let file: URL

    private init() {
        file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("truth-local-translations-v1.json")
        if let data = try? Data(contentsOf: file),
           let saved = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = saved
        }
    }

    static func key(_ source: String) -> String {
        SHA256.hash(data: Data(("en→zh-Hans:v1:" + source).utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
    func text(_ key: String) -> String? { entries[key]?.text }
    func canAttempt(_ key: String) -> Bool { failedUntil[key, default: .distantPast] < Date() }
    func failed(_ key: String) { failedUntil[key] = Date().addingTimeInterval(600) }
    func retry(_ key: String) { failedUntil[key] = nil }

    // Serialize work across visible feed rows and the detail sheet. Waiting is cancellable.
    func acquire() async throws {
        while translating { try await Task.sleep(for: .milliseconds(150)) }
        try Task.checkCancellation()
        translating = true
    }
    func release() { translating = false }
    func save(_ text: String, key: String) {
        entries[key] = Entry(text: text, date: Date())
        if entries.count > 400 {
            for key in entries.sorted(by: { $0.value.date > $1.value.date }).dropFirst(400).map(\.key) {
                entries[key] = nil
            }
        }
        if let data = try? JSONEncoder().encode(entries) {
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }
}

struct TruthLocalTranslationView: View {
    let post: Post
    var detail = false
    var body: some View {
        if #available(iOS 18.0, *) {
            TruthDeviceTranslatedText(original: post.originalDisplayContent,
                                      serverChinese: post.truthChineseContent, detail: detail)
        } else {
            Text(post.truthChineseContent ?? post.originalDisplayContent)
            if detail, post.truthChineseContent != nil {
                DisclosureGroup("查看原文") { Text(post.originalDisplayContent).textSelection(.enabled) }
                    .font(.callout)
            }
        }
    }
}

@available(iOS 18.0, *)
private struct TruthDeviceTranslatedText: View {
    let original: String
    let serverChinese: String?
    let detail: Bool
    @ObservedObject private var cache = TruthTranslationCache.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var configuration: TranslationSession.Configuration?
    @State private var needsDownload = false
    @State private var failed = false
    @State private var permitDownload = false
    private let source = Locale.Language(identifier: "en")
    private let target = Locale.Language(identifier: "zh-Hans")
    private var key: String { TruthTranslationCache.key(original) }
    private var translated: String? { serverChinese ?? cache.text(key) }

    var body: some View {
        VStack(alignment: .leading, spacing: detail ? 12 : 0) {
            Text(translated ?? original)
            if detail {
                if translated != nil {
                    DisclosureGroup("查看原文") { Text(original).textSelection(.enabled) }
                        .font(.callout)
                } else if needsDownload {
                    Button("下载语言后在本机自动翻译") {
                        permitDownload = true
                        start()
                    }
                    .font(.callout)
                } else if failed {
                    Button("本机翻译暂不可用，重试") {
                        cache.retry(key)
                        failed = false
                        Task { await prepare() }
                    }
                    .font(.callout)
                }
            }
        }
        .task(id: key) { await prepare() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await prepare() } }
            else { configuration = nil }
        }
        .translationTask(configuration) { session in
            let requestKey = key
            let requestText = original
            do {
                try await cache.acquire()
                defer { cache.release() }
                guard cache.text(requestKey) == nil, serverChinese == nil,
                      scenePhase == .active else { return }
                // A language download can only be requested by the explicit detail button.
                if permitDownload { try await session.prepareTranslation() }
                else {
                    guard await LanguageAvailability().status(from: source, to: target) == .installed else {
                        needsDownload = true
                        return
                    }
                }
                let response = try await session.translate(requestText)
                try Task.checkCancellation()
                let result = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !result.isEmpty else { throw CancellationError() }
                cache.save(result, key: requestKey)
                needsDownload = false
                failed = false
            } catch {
                if !Task.isCancelled {
                    cache.failed(requestKey)
                    failed = true
                    needsDownload = false
                }
            }
            permitDownload = false
        }
    }

    private func start() {
        if configuration != nil { configuration?.invalidate() }
        else { configuration = .init(source: source, target: target) }
    }

    private func prepare() async {
        guard scenePhase == .active, translated == nil, !original.isEmpty else { return }
        guard cache.canAttempt(key) else { failed = true; return }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(original)
        guard recognizer.dominantLanguage == .english else { return }
        let status = await LanguageAvailability().status(from: source, to: target)
        guard !Task.isCancelled else { return }
        switch status {
        case .installed: needsDownload = false; start()
        case .supported: needsDownload = true
        case .unsupported: break
        @unknown default: break
        }
    }
}
