import SwiftUI
import Translation
import NaturalLanguage
import CryptoKit

/// App-owned text cache. Apple owns the separate, shared on-device language models.
@MainActor
final class FeedTranslationCache: ObservableObject {
    static let shared = FeedTranslationCache()
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

    static func key(_ source: String, language: String) -> String {
        SHA256.hash(data: Data((language + "→zh-Hans:v1:" + source).utf8))
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
    @available(iOS 26.0, *)
    func pretranslateTruth(_ posts: [Post]) async {
        let language = "en"
        var requests: [TranslationSession.Request] = []
        var seen = Set<String>()
        for post in posts.prefix(20) where post.source == "truth" && LocalTranslatedText.chineseText(post.truthChineseContent) == nil {
            let text = post.originalDisplayContent
            let key = Self.key(text, language: language)
            if seen.insert(key).inserted, entries[key] == nil, canAttempt(key),
               LocalTranslatedText.sourceLanguage(text) == language {
                requests.append(.init(sourceText: text, clientIdentifier: key))
            }
        }
        guard !requests.isEmpty else { return }
        let source = Locale.Language(identifier: language)
        let target = Locale.Language(identifier: "zh-Hans")
        guard await LanguageAvailability().status(from: source, to: target) == .installed else { return }
        do {
            try await acquire()
            defer { release() }
            requests.removeAll { request in request.clientIdentifier.flatMap { entries[$0] } != nil }
            guard !requests.isEmpty else { return }
            let session = TranslationSession(installedSource: source, target: target)
            var changed = false
            defer { if changed { persistEntries() } }
            for try await response in session.translate(batch: requests) {
                try Task.checkCancellation()
                let value = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
                if let key = response.clientIdentifier, !value.isEmpty, value != response.sourceText {
                    entries[key] = Entry(text: value, date: Date())
                    changed = true
                }
            }
        } catch {
            // Visible rows can still request their own translation.
        }
    }

    func save(_ text: String, key: String) {
        entries[key] = Entry(text: text, date: Date())
        persistEntries()
    }

    private func persistEntries() {
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
        LocalTranslatedText(original: post.originalDisplayContent,
                            serverChinese: post.truthChineseContent, detail: detail, showsListStatus: !detail)
    }
}

/// Translation is presentation-only: the original Post, links and article blocks stay intact.
struct LocalTranslatedText: View {
    let original: String
    var serverChinese: String? = nil
    var detail = false
    var enabled = true
    var translationOnly = false
    var showsListStatus = false

    static func sourceLanguage(_ text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage,
              language != .simplifiedChinese, language != .traditionalChinese,
              language != .undetermined else { return nil }
        return language.rawValue
    }

    private var existingChinese: String? { Self.chineseText(serverChinese) }

    static func chineseText(_ serverChinese: String?) -> String? {
        guard let serverChinese else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(serverChinese)
        guard recognizer.dominantLanguage == .simplifiedChinese || recognizer.dominantLanguage == .traditionalChinese else { return nil }
        return serverChinese
    }

    var body: some View {
        if #available(iOS 18.0, *), enabled, let language = Self.sourceLanguage(original) {
            TruthDeviceTranslatedText(original: original, serverChinese: existingChinese,
                                      detail: detail, sourceIdentifier: language, translationOnly: translationOnly, showsListStatus: showsListStatus)
                .id(language + ":" + original)
        } else {
            if !translationOnly { Text(existingChinese ?? original) }
            if !translationOnly, detail, existingChinese != nil, existingChinese != original {
                DisclosureGroup("查看原文") { Text(original).textSelection(.enabled) }
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
    let sourceIdentifier: String
    let translationOnly: Bool
    let showsListStatus: Bool
    @ObservedObject private var cache = FeedTranslationCache.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var configuration: TranslationSession.Configuration?
    @State private var needsDownload = false
    @State private var failed = false
    @State private var permitDownload = false
    @State private var unsupported = false
    private var source: Locale.Language { Locale.Language(identifier: sourceIdentifier) }
    private let target = Locale.Language(identifier: "zh-Hans")
    private var key: String { FeedTranslationCache.key(original, language: sourceIdentifier) }
    private var translated: String? { serverChinese ?? cache.text(key) }

    var body: some View {
        VStack(alignment: .leading, spacing: detail ? 12 : 0) {
            if let translated { Text(translated) }
            else if !translationOnly { Text(original) }
            if translated == nil {
                if showsListStatus, needsDownload {
                    Text("点开帖子可下载翻译语言").font(.caption).foregroundStyle(.secondary)
                } else if showsListStatus, failed {
                    Text("本机翻译暂不可用，点开可重试").font(.caption).foregroundStyle(.secondary)
                } else if (showsListStatus || detail), unsupported {
                    Text("此设备不支持这组语言的本机翻译").font(.caption).foregroundStyle(.secondary)
                }
            }
            if detail {
                if translated != nil, !translationOnly {
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
            if phase == .active, configuration == nil { Task { await prepare() } }
            else if phase == .background { configuration = nil }
        }
        .translationTask(configuration) { session in
            let requestKey = key
            let requestText = original
            defer { permitDownload = false }
            do {
                try await cache.acquire()
                defer { cache.release() }
                guard cache.text(requestKey) == nil, cache.canAttempt(requestKey), serverChinese == nil,
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
            } catch is CancellationError {
                return
            } catch {
                if !Task.isCancelled {
                    cache.failed(requestKey)
                    failed = true
                    needsDownload = false
                }
            }
        }
    }

    private func start() {
        if configuration != nil { configuration?.invalidate() }
        else { configuration = .init(source: source, target: target) }
    }

    private func prepare() async {
        guard scenePhase == .active, translated == nil, !original.isEmpty else { return }
        guard cache.canAttempt(key) else { failed = true; return }
        let status = await LanguageAvailability().status(from: source, to: target)
        guard !Task.isCancelled else { return }
        unsupported = status == .unsupported
        switch status {
        case .installed: needsDownload = false; start()
        case .supported: needsDownload = true
        case .unsupported: break
        @unknown default: break
        }
    }
}
