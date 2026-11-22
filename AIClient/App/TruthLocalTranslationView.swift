import SwiftUI
import Translation
import NaturalLanguage
import CryptoKit

/// App-owned text cache. Apple owns the separate, shared on-device language models.
@MainActor
final class FeedTranslationCache {
    static let shared = FeedTranslationCache()
    private struct Entry: Codable { let text: String; let date: Date }
    @Observable final class DisplayState {
        var text: String?
        init(text: String?) { self.text = text }
    }

    private var entries: [String: Entry] = [:]
    private let displayStates = NSMapTable<NSString, DisplayState>.strongToWeakObjects()
    private var persistTask: Task<Void, Never>?
    private var hasUnsavedEntries = false
    private var availabilityByLanguage: [String: LanguageStatus] = [:]
    @Observable final class LanguageState { var revision = 0 }
    let languageState = LanguageState()

    private enum LanguageReadiness { case installed, downloadable, unsupported }

    private struct LanguageStatus {
        let value: LanguageReadiness
        let checkedAt: Date
    }
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
    func displayState(for key: String) -> DisplayState {
        if let state = displayStates.object(forKey: key as NSString) { return state }
        let state = DisplayState(text: text(key))
        displayStates.setObject(state, forKey: key as NSString)
        return state
    }
    func canAttempt(_ key: String) -> Bool { failedUntil[key, default: .distantPast] < Date() }
    func failed(_ key: String) {
        let now = Date()
        if failedUntil.count > 400 { failedUntil = failedUntil.filter { $0.value > now } }
        failedUntil[key] = now.addingTimeInterval(600)
    }
    func retry(_ key: String) { failedUntil[key] = nil }

    // Serialize work across visible feed rows and the detail sheet. Waiting is cancellable.
    func acquire() async throws {
        while translating { try await Task.sleep(for: .milliseconds(150)) }
        try Task.checkCancellation()
        translating = true
    }
    func release() { translating = false }
    @available(iOS 18.0, *)
    func availability(for language: String) async -> LanguageAvailability.Status {
        if let saved = availabilityByLanguage[language], Date().timeIntervalSince(saved.checkedAt) < 30 {
            switch saved.value {
            case .installed: return .installed
            case .downloadable: return .supported
            case .unsupported: return .unsupported
            }
        }
        let status = await LanguageAvailability().status(
            from: Locale.Language(identifier: language), to: Locale.Language(identifier: "zh-Hans")
        )
        if !Task.isCancelled {
            let value: LanguageReadiness = status == .installed ? .installed : status == .supported ? .downloadable : .unsupported
            availabilityByLanguage[language] = LanguageStatus(value: value, checkedAt: Date())
        }
        return status
    }

    func languageWasInstalled(_ language: String) {
        availabilityByLanguage[language] = LanguageStatus(value: .installed, checkedAt: Date())
        languageState.revision += 1
    }

    @available(iOS 26.0, *)
    func pretranslate(_ originals: [String]) async {
        var requestsByLanguage: [String: [TranslationSession.Request]] = [:]
        var seen = Set<String>()
        for original in originals {
            guard let language = LocalTranslatedText.sourceLanguage(original) else { continue }
            let key = Self.key(original, language: language)
            guard seen.insert(key).inserted, text(key) == nil, canAttempt(key) else { continue }
            requestsByLanguage[language, default: []].append(.init(sourceText: original, clientIdentifier: key))
        }
        for (language, requests) in requestsByLanguage {
            guard !Task.isCancelled else { return }
            guard await availability(for: language) == .installed else { continue }
            do {
                try await acquire()
                defer { release() }
                let pending = requests.filter { request in
                    guard let key = request.clientIdentifier else { return false }
                    return text(key) == nil && canAttempt(key)
                }
                guard !pending.isEmpty else { continue }
                let session = TranslationSession(
                    installedSource: Locale.Language(identifier: language), target: Locale.Language(identifier: "zh-Hans")
                )
                for try await response in session.translate(batch: pending) {
                    try Task.checkCancellation()
                    if let key = response.clientIdentifier,
                       let value = LocalTranslatedText.validTranslation(response.targetText, original: response.sourceText) {
                        save(value, key: key)
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                // A row can still try its individual request after a batch error.
            }
        }
    }

    func save(_ text: String, key: String) {
        entries[key] = Entry(text: text, date: Date())
        displayStates.object(forKey: key as NSString)?.text = text
        hasUnsavedEntries = true
        guard persistTask == nil else { return }
        persistTask = Task { [weak self] in
            guard let self else { return }
            while hasUnsavedEntries {
                try? await Task.sleep(for: .milliseconds(350))
                hasUnsavedEntries = false
                await persistEntries()
            }
            persistTask = nil
        }
    }

    private func persistEntries() async {
        if entries.count > 400 {
            for key in entries.sorted(by: { $0.value.date > $1.value.date }).dropFirst(400).map(\.key) {
                entries[key] = nil
            }
        }
        let location = file
        let snapshot = entries
        await Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: location, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }.value
    }
}

struct TruthLocalTranslationView: View {
    let post: Post
    var detail = false
    var body: some View {
        LocalTranslatedText(original: post.originalDisplayContent,
                            serverChinese: post.truthChineseContent, detail: detail, field: .body)
    }
}

enum FeedTranslationField: String {
    case title = "标题"
    case summary = "摘要"
    case body = "正文"
    case quote = "引用"
    case reply = "回复"
}

/// Translation is presentation-only: the original Post, links and article blocks stay intact.
struct LocalTranslatedText: View {
    let original: String
    var serverChinese: String? = nil
    var detail = false
    var enabled = true
    var translationOnly = false
    var field: FeedTranslationField? = nil

    private static let recognizedLanguages: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.countLimit = 600
        return cache
    }()

    static func sourceLanguage(_ text: String) -> String? {
        let prefix = String(text.prefix(1_200))
        let key = prefix as NSString
        if let cached = recognizedLanguages.object(forKey: key) {
            return cached.length == 0 ? nil : cached as String
        }
        let language = recognizeLanguage(prefix)
        recognizedLanguages.setObject((language ?? "") as NSString, forKey: key)
        return language
    }

    private static func recognizeLanguage(_ text: String) -> String? {
        let sample = text
            .replacingOccurrences(of: #"https?://\S+|[@$][A-Za-z0-9_]+"#, with: " ", options: .regularExpression)
        guard sample.unicodeScalars.contains(where: CharacterSet.letters.contains) else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        let language = recognizer.dominantLanguage
        switch language {
        case .simplifiedChinese, .traditionalChinese, .undetermined, nil:
            return XPostTextFormatter.containsUntranslatedEnglishPassage(sample) ? "en" : nil
        case .english where hasHan(sample) && !XPostTextFormatter.containsUntranslatedEnglishPassage(sample):
            return nil
        case let language?:
            return language.rawValue
        }
    }

    static func chineseText(_ text: String?) -> String? {
        guard let value = text?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty,
              hasHan(value),
              !XPostTextFormatter.containsUntranslatedEnglishPassage(value) else { return nil }
        return value
    }

    private static func hasHan(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x3400...0x9FFF).contains(Int($0.value)) }
    }

    static func validTranslation(_ text: String, original: String) -> String? {
        guard let value = chineseText(text), value != original.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }
        return value
    }

    var body: some View {
        if let chinese = Self.chineseText(serverChinese), chinese != original {
            if !translationOnly { Text(chinese) }
            if detail, !translationOnly, chinese != original {
                DisclosureGroup("查看原文") { Text(original).textSelection(.enabled) }
                    .font(.callout)
            }
        } else if enabled, let language = Self.sourceLanguage(original) {
            if #available(iOS 18.0, *) {
                FeedDeviceTranslatedText(original: original, detail: detail, sourceIdentifier: language,
                                         translationOnly: translationOnly, field: field)
                    .id(language + ":" + original)
            } else if let field {
                Text("\(field.rawValue)译文暂不可用").foregroundStyle(.secondary)
                if detail { DisclosureGroup("查看原文") { Text(original).textSelection(.enabled) } }
            } else if !translationOnly {
                Text(original)
            }
        } else if !translationOnly {
            Text(original)
        }
    }
}

@available(iOS 18.0, *)
private struct FeedDeviceTranslatedText: View {
    private enum Phase { case preparing, translating, needsDownload, unavailable, failed }

    let original: String
    let detail: Bool
    let sourceIdentifier: String
    let translationOnly: Bool
    let field: FeedTranslationField?
    private let key: String
    @State private var display: FeedTranslationCache.DisplayState
    @Environment(\.scenePhase) private var scenePhase
    @State private var configuration: TranslationSession.Configuration?
    @State private var phase = Phase.preparing
    @State private var permitsDownload = false

    private let cache = FeedTranslationCache.shared
    private var source: Locale.Language { Locale.Language(identifier: sourceIdentifier) }
    private let target = Locale.Language(identifier: "zh-Hans")

    init(original: String, detail: Bool, sourceIdentifier: String, translationOnly: Bool, field: FeedTranslationField?) {
        self.original = original
        self.detail = detail
        self.sourceIdentifier = sourceIdentifier
        self.translationOnly = translationOnly
        self.field = field
        key = FeedTranslationCache.key(original, language: sourceIdentifier)
        _display = State(initialValue: FeedTranslationCache.shared.displayState(for: key))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: detail ? 8 : 0) {
            if let translated = display.text {
                Text(translated)
            } else if let field {
                Text(status(for: field))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("feed-translation-status")
            } else if !translationOnly {
                Text(original)
            }

            if detail {
                if display.text == nil, phase == .needsDownload {
                    Button("启用本机翻译") {
                        permitsDownload = true
                        start()
                    }
                    .font(.callout)
                    .accessibilityIdentifier("feed-translation-enable")
                } else if display.text == nil, phase == .failed {
                    Button("重试翻译") {
                        cache.retry(key)
                        phase = .preparing
                        Task { await prepare() }
                    }
                    .font(.callout)
                }
                if !translationOnly, field != nil || display.text != nil {
                    DisclosureGroup("查看原文") { Text(original).textSelection(.enabled) }
                        .font(.callout)
                }
            }
        }
        .task(id: cache.languageState.revision) { await prepare() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, configuration == nil { Task { await prepare() } }
            else if phase == .background { configuration = nil }
        }
        .translationTask(configuration) { session in
            defer { permitsDownload = false }
            do {
                try await cache.acquire()
                defer { cache.release() }
                guard display.text == nil, cache.canAttempt(key), scenePhase == .active else { return }
                if permitsDownload {
                    try await session.prepareTranslation()
                    cache.languageWasInstalled(sourceIdentifier)
                }
                phase = .translating
                let response = try await session.translate(original)
                try Task.checkCancellation()
                guard let result = LocalTranslatedText.validTranslation(response.targetText, original: original) else {
                    cache.failed(key)
                    phase = .failed
                    return
                }
                cache.save(result, key: key)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                if permitsDownload, await cache.availability(for: sourceIdentifier) == .supported {
                    phase = .needsDownload
                } else {
                    cache.failed(key)
                    phase = .failed
                }
            }
        }
    }

    private func status(for field: FeedTranslationField) -> String {
        switch phase {
        case .preparing, .translating: "\(field.rawValue)翻译中"
        case .needsDownload: detail ? "\(field.rawValue)待翻译" : "\(field.rawValue)待翻译 · 点开启用"
        case .unavailable, .failed: detail ? "\(field.rawValue)译文暂不可用" : "\(field.rawValue)译文暂不可用 · 点开查看"
        }
    }

    private func start() {
        if configuration != nil { configuration?.invalidate() }
        else { configuration = .init(source: source, target: target) }
    }

    private func prepare() async {
        guard scenePhase == .active, display.text == nil, !original.isEmpty, !permitsDownload else { return }
        guard cache.canAttempt(key) else { phase = .failed; return }
        let status = await cache.availability(for: sourceIdentifier)
        guard !Task.isCancelled, display.text == nil, !permitsDownload else { return }
        switch status {
        case .installed: phase = .translating; start()
        case .supported: phase = .needsDownload
        case .unsupported: phase = .unavailable
        @unknown default: phase = .unavailable
        }
    }
}
