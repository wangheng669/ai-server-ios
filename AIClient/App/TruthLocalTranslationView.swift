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
        LocalTranslatedText(original: post.originalDisplayContent,
                            serverChinese: post.truthChineseContent, detail: detail)
    }
}

/// Translation is presentation-only: the original Post, links and article blocks stay intact.
struct LocalTranslatedText: View {
    let original: String
    var serverChinese: String? = nil
    var detail = false
    var enabled = true

    static func sourceLanguage(_ text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage,
              language != .simplifiedChinese, language != .traditionalChinese,
              language != .undetermined else { return nil }
        return language.rawValue
    }

    private var existingChinese: String? {
        guard let serverChinese,
              serverChinese.unicodeScalars.contains(where: { (0x4E00...0x9FFF).contains(Int($0.value)) }) else { return nil }
        return serverChinese
    }

    var body: some View {
        if #available(iOS 18.0, *), enabled, let language = Self.sourceLanguage(original) {
            TruthDeviceTranslatedText(original: original, serverChinese: existingChinese,
                                      detail: detail, sourceIdentifier: language)
                .id(language + ":" + original)
        } else {
            Text(existingChinese ?? original)
            if detail, existingChinese != nil, existingChinese != original {
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
    @ObservedObject private var cache = TruthTranslationCache.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var configuration: TranslationSession.Configuration?
    @State private var needsDownload = false
    @State private var failed = false
    @State private var permitDownload = false
    private var source: Locale.Language { Locale.Language(identifier: sourceIdentifier) }
    private let target = Locale.Language(identifier: "zh-Hans")
    private var key: String { TruthTranslationCache.key(original, language: sourceIdentifier) }
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
            if phase == .active, configuration == nil { Task { await prepare() } }
            else if phase == .background { configuration = nil }
        }
        .translationTask(configuration) { session in
            let requestKey = key
            let requestText = original
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
