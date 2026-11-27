import SwiftUI
import Translation
import NaturalLanguage
import CryptoKit

struct XTranslationInput: Equatable {
    let tweetID: String
    let original: String
    var sourceLanguage: String? = nil
    var replyContext: String? = nil

    var key: String { FeedTranslationCache.xKey(tweetID: tweetID, original: original) }

    var deviceLanguage: String? {
        Self.deviceLanguage(for: original, sourceLanguage: sourceLanguage, replyContext: replyContext)
    }

    static func deviceLanguage(for original: String, sourceLanguage: String?, replyContext: String?) -> String? {
        if let language = XDeviceTranslation.declaredLanguage(sourceLanguage) { return language }
        let sample = LocalTranslatedText.languageSample(String(original.prefix(1_200)))
        let letters = sample.unicodeScalars.filter(CharacterSet.letters.contains)
        // Short Latin replies need a language hint from a substantial parent.
        if (1...12).contains(letters.count), letters.allSatisfy({ $0.value <= 0x024F }) {
            guard let replyContext else { return nil }
            let parent = LocalTranslatedText.languageSample(String(replyContext.prefix(1_200)))
            let parentLetters = parent.unicodeScalars.filter(CharacterSet.letters.contains)
            guard parentLetters.count >= 20, parentLetters.allSatisfy({ $0.value <= 0x024F }) else { return nil }
            return LocalTranslatedText.sourceLanguage(parent)
        }
        return LocalTranslatedText.sourceLanguage(original)
    }
}

/// App-owned text cache. Apple owns the separate, shared on-device language models.
@MainActor
final class FeedTranslationCache {
    static let shared = FeedTranslationCache()
    private struct Entry: Codable { let text: String; let date: Date }
    struct DeviceRequest {
        let sourceLanguage: String?
        let expiresAt: Date
    }

    @Observable final class DisplayState {
        var text: String?
        var deviceRequest: DeviceRequest?
        init(text: String?, deviceRequest: DeviceRequest?) {
            self.text = text
            self.deviceRequest = deviceRequest
        }
    }

    private var entries: [String: Entry] = [:]
    private let displayStates = NSMapTable<NSString, DisplayState>.strongToWeakObjects()
    private var persistTask: Task<Void, Never>?
    private var hasUnsavedEntries = false
    private var availabilityByLanguage: [String: LanguageStatus] = [:]
    private var automaticallyRequestedLanguages = Set<String>()
    @Observable final class LanguageState { var revision = 0 }
    let languageState = LanguageState()

    private enum LanguageReadiness { case installed, downloadable, unsupported }

    private struct LanguageStatus {
        let value: LanguageReadiness
        let checkedAt: Date
    }
    private var failedUntil: [String: Date] = [:]
    private var translating = false
    private var activeXTranslations = Set<String>()
    private var warmingXTranslations = Set<String>()
    private var xDeviceRequests: [String: DeviceRequest] = [:]
    private let xTranslationClock = ContinuousClock()
    private var xTranslationRetryAt: ContinuousClock.Instant?
    private var xPostRetryAt: [String: ContinuousClock.Instant] = [:]
    private let file: URL

    private init() {
        file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("truth-local-translations-v1.json")
        if let data = try? Data(contentsOf: file),
           let saved = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = saved
        }
    }

    nonisolated static func key(_ source: String, language: String) -> String {
        SHA256.hash(data: Data((language + "→zh-Hans:v1:" + source).utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
    func text(_ key: String) -> String? { entries[key]?.text }

    nonisolated static func xKey(tweetID: String, original: String) -> String {
        key(original, language: "x/" + tweetID)
    }

    func cachedXTranslation(tweetID: String, original: String) -> String? {
        text(Self.xKey(tweetID: tweetID, original: original))
            .flatMap { LocalTranslatedText.validTranslation($0, original: original) }
    }

    func translateXPost(
        tweetID: String,
        original: String,
        sourceLanguage: String? = nil,
        replyContext: String? = nil,
        using fetch: (String) async throws -> XTranslation
    ) async throws -> String {
        let key = Self.xKey(tweetID: tweetID, original: original)
        if #available(iOS 26.0, *), text(key) == nil {
            let keys = warmXTranslations([.init(
                tweetID: tweetID, original: original, sourceLanguage: sourceLanguage, replyContext: replyContext
            )])
            await waitForXTranslations(keys, upTo: .milliseconds(150))
        }
        let retryDeadline = xTranslationClock.now.advanced(by: .seconds(45))
        while true {
            try Task.checkCancellation()
            if let saved = text(key), let value = LocalTranslatedText.validTranslation(saved, original: original) {
                return value
            }
            guard canAttempt(key) else { throw APIError.invalidResponse }

            let now = xTranslationClock.now
            let nextRequest = max(xPostRetryAt[tweetID] ?? now, xTranslationRetryAt ?? now)
            if nextRequest > now {
                requestXDeviceTranslation(key: key, sourceLanguage: sourceLanguage)
                guard nextRequest <= retryDeadline else { throw APIError.invalidResponse }
                await waitForXTranslations([key], upTo: now.duration(to: nextRequest))
                try Task.checkCancellation()
                if let saved = text(key), let value = LocalTranslatedText.validTranslation(saved, original: original) {
                    return value
                }
                try await xTranslationClock.sleep(until: nextRequest)
                continue
            }
            if activeXTranslations.count >= 2 || activeXTranslations.contains(tweetID) {
                try await Task.sleep(for: .milliseconds(150))
                continue
            }

            do {
                xPostRetryAt[tweetID] = nil
                activeXTranslations.insert(tweetID)
                defer { activeXTranslations.remove(tweetID) }
                let response = try await fetch(tweetID)
                try Task.checkCancellation()
                if let translated = cachedXTranslation(tweetID: tweetID, original: original) { return translated }
                guard response.tweetId == tweetID else { throw APIError.invalidResponse }
                guard response.status != "not_required",
                      let value = LocalTranslatedText.validTranslation(response.text, original: original) else {
                    requestXDeviceTranslation(key: key, sourceLanguage: response.sourceLanguage)
                    throw APIError.invalidResponse
                }
                save(value, key: key)
                return value
            } catch let deferral as XTranslationDeferral {
                requestXDeviceTranslation(key: key, sourceLanguage: sourceLanguage)
                let retryAt = xTranslationClock.now.advanced(by: .seconds(deferral.seconds))
                if deferral.isPostSpecific {
                    if xPostRetryAt.count > 400 { xPostRetryAt = xPostRetryAt.filter { $0.value > now } }
                    xPostRetryAt[tweetID] = max(xPostRetryAt[tweetID] ?? retryAt, retryAt)
                } else {
                    xTranslationRetryAt = max(xTranslationRetryAt ?? retryAt, retryAt)
                }
            } catch {
                guard !Task.isCancelled else { throw CancellationError() }
                if let apiError = error as? APIError, case .httpStatus(let status) = apiError,
                   [404, 502, 503, 504].contains(status) {
                    requestXDeviceTranslation(key: key)
                }
                if !warmingXTranslations.contains(key) { failed(key) }
                throw error
            }
        }
    }

    private func requestXDeviceTranslation(key: String, sourceLanguage: String? = nil) {
        let now = Date()
        if let request = xDeviceRequests[key], request.expiresAt > now,
           request.sourceLanguage != nil || sourceLanguage == nil { return }
        if xDeviceRequests.count > 400 { xDeviceRequests = xDeviceRequests.filter { $0.value.expiresAt > now } }
        let request = DeviceRequest(sourceLanguage: sourceLanguage, expiresAt: now.addingTimeInterval(600))
        xDeviceRequests[key] = request
        displayStates.object(forKey: key as NSString)?.deviceRequest = request
    }

    func displayState(for key: String) -> DisplayState {
        if let state = displayStates.object(forKey: key as NSString) { return state }
        let request = xDeviceRequests[key].flatMap { $0.expiresAt > Date() ? $0 : nil }
        let state = DisplayState(text: text(key), deviceRequest: request)
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
    func availability(for language: String, refresh: Bool = false) async -> LanguageAvailability.Status {
        if !refresh, let saved = availabilityByLanguage[language], Date().timeIntervalSince(saved.checkedAt) < 30 {
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

    func requestDownloadAutomatically(for language: String) -> Bool {
        automaticallyRequestedLanguages.insert(language).inserted
    }

    func languageWasInstalled(_ language: String) {
        let requestedDownload = automaticallyRequestedLanguages.remove(language) != nil
        guard requestedDownload || availabilityByLanguage[language]?.value != .installed else { return }
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
            await pretranslate(requests, language: language)
        }
    }

    @available(iOS 26.0, *)
    @discardableResult
    func warmXTranslations(_ inputs: [XTranslationInput]) -> [String] {
        var requestsByLanguage: [String: [TranslationSession.Request]] = [:]
        var keys: [String] = []
        for input in inputs {
            let key = input.key
            guard text(key) == nil, canAttempt(key) else { continue }
            if warmingXTranslations.contains(key) {
                keys.append(key)
                continue
            }
            let original = input.original
            guard !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !XPostTextFormatter.shouldWaitForFullText(original),
                  let language = input.deviceLanguage else { continue }
            if let cached = text(Self.key(original, language: language)),
               let translated = LocalTranslatedText.validTranslation(cached, original: original) {
                save(translated, key: key)
                continue
            }
            if let status = availabilityByLanguage[language], status.value != .installed,
               Date().timeIntervalSince(status.checkedAt) < 30 { continue }
            warmingXTranslations.insert(key)
            requestsByLanguage[language, default: []].append(.init(sourceText: original, clientIdentifier: key))
            keys.append(key)
        }
        for (language, requests) in requestsByLanguage {
            Task(priority: .utility) {
                await pretranslate(requests, language: language)
                warmingXTranslations.subtract(requests.compactMap(\.clientIdentifier))
            }
        }
        return keys
    }

    func waitForXTranslations(_ keys: [String], upTo budget: Duration) async {
        let deadline = xTranslationClock.now.advanced(by: budget)
        while !Task.isCancelled, xTranslationClock.now < deadline,
              keys.contains(where: { text($0) == nil && warmingXTranslations.contains($0) }) {
            try? await xTranslationClock.sleep(until: min(deadline, xTranslationClock.now.advanced(by: .milliseconds(25))))
        }
    }

    @available(iOS 26.0, *)
    private func pretranslate(_ requests: [TranslationSession.Request], language: String) async {
        guard await availability(for: language) == .installed else { return }
        do {
            try await acquire()
            defer { release() }
            let pending = requests.filter { request in
                guard let key = request.clientIdentifier else { return false }
                return text(key) == nil && canAttempt(key)
            }
            guard !pending.isEmpty else { return }
            let session = TranslationSession(
                installedSource: Locale.Language(identifier: language), target: Locale.Language(identifier: "zh-Hans")
            )
            for try await response in session.translate(batch: pending) {
                try Task.checkCancellation()
                if let key = response.clientIdentifier,
                   text(key) == nil,
                   let value = LocalTranslatedText.validTranslation(response.targetText, original: response.sourceText) {
                    save(value, key: key)
                }
            }
        } catch {
            // A row can still try its individual request after a batch error.
        }
    }

    func save(_ text: String, key: String) {
        entries[key] = Entry(text: text, date: Date())
        xDeviceRequests[key] = nil
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
    var openOriginal: (() -> Void)?
    var showsOriginalText = false

    var body: some View {
        if post.isTruthMediaPlaceholder {
            FeedTranslationText(text: Text("此帖没有正文"), openOriginal: openOriginal)
                .foregroundStyle(.secondary)
        } else if let chinese = LocalTranslatedText.chineseText(post.truthChineseContent)
                    ?? LocalTranslatedText.chineseText(post.originalDisplayContent) {
            FeedTranslationText(text: Text(chinese), openOriginal: openOriginal)
        } else {
            LocalTranslatedText(
                original: post.originalDisplayContent, detail: true,
                translationOnly: !showsOriginalText, field: .body, openOriginal: openOriginal,
                preservesOriginal: showsOriginalText
            )
        }
    }
}

private struct FeedTranslationText: View {
    let text: Text
    let openOriginal: (() -> Void)?

    var body: some View {
        if let openOriginal {
            Button(action: openOriginal) {
                text
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("在应用内打开原文网站")
        } else {
            text
        }
    }
}

enum FeedTranslationField: String {
    case title = "标题"
    case summary = "摘要"
    case body = "正文"
    case reply = "回复"
    case quote = "引用"
}

struct FeedReaderTranslationText: View {
    let original: String?
    let chinese: String?
    let field: FeedTranslationField
    let isActive: Bool
    var showsTranslationControls = true
    var sourceLanguageHint: String? = nil

    var body: some View {
        let originalChinese = sourceLanguageHint == nil ? LocalTranslatedText.chineseText(original) : nil
        if let text = LocalTranslatedText.chineseText(chinese) ?? originalChinese {
            Text(text)
        } else if let original, !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if isActive {
                LocalTranslatedText(
                    original: original, detail: showsTranslationControls, translationOnly: true, field: field,
                    sourceLanguageHint: sourceLanguageHint
                )
            } else {
                Text("\(field.rawValue)待翻译").foregroundStyle(.secondary)
            }
        }
    }
}

/// Translation is presentation-only: the original Post, links and article blocks stay intact.
struct LocalTranslatedText: View {
    let original: String
    var serverChinese: String? = nil
    var detail = false
    var enabled = true
    var translationOnly = false
    var field: FeedTranslationField? = nil
    var openOriginal: (() -> Void)?
    var preservesOriginal = false
    var sourceLanguageHint: String? = nil

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

    static func languageSample(_ text: String) -> String {
        text.replacingOccurrences(of: #"https?://\S+|[@$][A-Za-z0-9_]+"#, with: " ", options: .regularExpression)
    }

    private static func recognizeLanguage(_ text: String) -> String? {
        let sample = languageSample(text)
        guard sample.unicodeScalars.contains(where: CharacterSet.letters.contains) else { return nil }
        let containsKana = XPostTextFormatter.containsJapaneseKana(sample)
        let hasEnglishPassage = XPostTextFormatter.containsUntranslatedEnglishPassage(sample)
        if hasHan(sample), sample.unicodeScalars.allSatisfy(isHanLatinOrNonletter) {
            return hasEnglishPassage ? "en" : nil
        }
        let recognizer = NLLanguageRecognizer()
        if containsKana { recognizer.languageConstraints = [.japanese, .simplifiedChinese, .traditionalChinese] }
        recognizer.processString(sample)
        switch recognizer.dominantLanguage {
        case .simplifiedChinese, .traditionalChinese:
            return hasEnglishPassage ? "en" : nil
        case .undetermined, nil:
            return containsKana ? "ja" : hasEnglishPassage ? "en" : nil
        case let language?:
            return language.rawValue
        }
    }

    static func chineseText(_ text: String?) -> String? {
        guard let value = text?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty,
              hasHan(value),
              !XPostTextFormatter.containsUntranslatedEnglishPassage(value) else { return nil }
        if XPostTextFormatter.containsJapaneseKana(value), sourceLanguage(value) == "ja" { return nil }
        return value
    }

    private static func hasHan(_ text: String) -> Bool {
        text.unicodeScalars.contains(where: isHan)
    }

    private static func isHan(_ scalar: Unicode.Scalar) -> Bool {
        (0x3400...0x9FFF).contains(scalar.value) || (0xF900...0xFAFF).contains(scalar.value)
    }

    private static func isHanLatinOrNonletter(_ scalar: Unicode.Scalar) -> Bool {
        isHan(scalar) || scalar.value <= 0x024F || !CharacterSet.letters.contains(scalar)
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
        } else if enabled, let language = sourceLanguageHint ?? Self.sourceLanguage(original) {
            if #available(iOS 18.0, *) {
                FeedDeviceTranslatedText(original: original, detail: detail, sourceIdentifier: language,
                                         translationOnly: translationOnly, field: field, openOriginal: openOriginal,
                                         preservesOriginal: preservesOriginal)
                    .id(language + ":" + original)
            } else if preservesOriginal {
                Text(original).textSelection(.enabled)
            } else if let field {
                FeedTranslationText(text: Text("\(field.rawValue)译文暂不可用"), openOriginal: openOriginal)
                    .foregroundStyle(.secondary)
                if detail, !translationOnly { DisclosureGroup("查看原文") { Text(original).textSelection(.enabled) } }
            } else if !translationOnly {
                Text(original)
            }
        } else if !translationOnly {
            Text(original)
        } else if let field {
            FeedTranslationText(text: Text("\(field.rawValue)译文暂不可用"), openOriginal: openOriginal)
                .foregroundStyle(.secondary)
        }
    }
}

struct XDeviceTranslation: View {
    let original: String
    let key: String
    let sourceLanguage: String?
    let replyContext: String?
    let showsControls: Bool
    let onTranslation: ((String) -> Void)?
    init(
        tweetID: String, original: String, sourceLanguage: String? = nil, replyContext: String? = nil,
        showsControls: Bool = false, onTranslation: ((String) -> Void)? = nil
    ) {
        self.original = original
        self.sourceLanguage = sourceLanguage
        self.replyContext = replyContext
        self.showsControls = showsControls
        self.onTranslation = onTranslation
        key = FeedTranslationCache.xKey(tweetID: tweetID, original: original)
    }

    static func declaredLanguage(_ value: String?) -> String? {
        guard let language = value?.lowercased(), !language.isEmpty,
              !["und", "zxx", "qam", "qme", "qst"].contains(language),
              !language.hasPrefix("zh") else { return nil }
        return language
    }

    var body: some View {
        Driver(key: key, original: original, sourceLanguage: sourceLanguage,
               replyContext: replyContext, showsControls: showsControls, onTranslation: onTranslation)
            .id(key)
    }

    private struct Driver: View {
        let key: String
        let original: String
        let sourceLanguage: String?
        let replyContext: String?
        let showsControls: Bool
        let onTranslation: ((String) -> Void)?
        @State private var display: FeedTranslationCache.DisplayState

        init(key: String, original: String, sourceLanguage: String?, replyContext: String?,
             showsControls: Bool, onTranslation: ((String) -> Void)?) {
            self.key = key
            self.original = original
            self.sourceLanguage = sourceLanguage
            self.replyContext = replyContext
            self.showsControls = showsControls
            self.onTranslation = onTranslation
            _display = State(initialValue: FeedTranslationCache.shared.displayState(for: key))
        }

        var body: some View {
            Group {
                if #available(iOS 18.0, *), display.text == nil, let request = display.deviceRequest,
                   let language = deviceLanguage(request.sourceLanguage) {
                    FeedDeviceTranslatedText(
                        original: original, detail: showsControls, sourceIdentifier: language,
                        translationOnly: true, field: nil, rendersText: false
                    ) { translation in
                        guard display.text == nil else { return }
                        FeedTranslationCache.shared.save(translation, key: key)
                    }
                    .id(language)
                }
            }
            .onChange(of: display.text, initial: true) { _, text in
                if let text { onTranslation?(text) }
            }
        }

        private func deviceLanguage(_ providerLanguage: String?) -> String? {
            XTranslationInput.deviceLanguage(
                for: original,
                sourceLanguage: XDeviceTranslation.declaredLanguage(providerLanguage) ?? sourceLanguage,
                replyContext: replyContext
            )
        }
    }
}

@available(iOS 18.0, *)
private struct FeedDeviceTranslatedText: View {
    private enum Phase { case preparing, translating, needsDownload, unavailable, failed }

    private struct PreparationID: Equatable {
        let scenePhase: ScenePhase
        let languageRevision: Int
    }

    let original: String
    let detail: Bool
    let sourceIdentifier: String
    let translationOnly: Bool
    let field: FeedTranslationField?
    let rendersText: Bool
    let openOriginal: (() -> Void)?
    let onTranslation: ((String) -> Void)?
    let preservesOriginal: Bool
    private let key: String
    @State private var display: FeedTranslationCache.DisplayState
    @Environment(\.scenePhase) private var scenePhase
    @State private var configuration: TranslationSession.Configuration?
    @State private var phase = Phase.preparing

    private let cache = FeedTranslationCache.shared
    private var source: Locale.Language { Locale.Language(identifier: sourceIdentifier) }
    private let target = Locale.Language(identifier: "zh-Hans")

    init(
        original: String, detail: Bool, sourceIdentifier: String, translationOnly: Bool,
        field: FeedTranslationField?, rendersText: Bool = true, openOriginal: (() -> Void)? = nil,
        preservesOriginal: Bool = false, onTranslation: ((String) -> Void)? = nil
    ) {
        self.original = original
        self.detail = detail
        self.sourceIdentifier = sourceIdentifier
        self.translationOnly = translationOnly
        self.field = field
        self.rendersText = rendersText
        self.openOriginal = openOriginal
        self.onTranslation = onTranslation
        self.preservesOriginal = preservesOriginal
        key = FeedTranslationCache.key(original, language: sourceIdentifier)
        _display = State(initialValue: FeedTranslationCache.shared.displayState(for: key))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: detail ? 8 : 0) {
            if rendersText {
                if let translated = display.text {
                    FeedTranslationText(text: Text(translated), openOriginal: openOriginal)
                } else if preservesOriginal {
                    Text(original).textSelection(.enabled)
                } else if let field {
                    FeedTranslationText(text: Text(status(for: field)), openOriginal: openOriginal)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("feed-translation-status")
                } else if !translationOnly {
                    Text(original)
                }
            }

            if detail {
                if display.text == nil, phase == .needsDownload {
                    Button("下载翻译语言包", action: start)
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
                if !translationOnly, display.text != nil || (field != nil && !preservesOriginal) {
                    DisclosureGroup("查看原文") { Text(original).textSelection(.enabled) }
                        .font(.callout)
                }
            }
        }
        .task(id: PreparationID(scenePhase: scenePhase, languageRevision: cache.languageState.revision)) {
            await prepare()
        }
        .onChange(of: display.text, initial: true) { _, text in
            if let text { onTranslation?(text) }
        }
        .onChange(of: scenePhase) { _, next in
            if next == .background {
                configuration = nil
                if phase == .translating { phase = .preparing }
            }
        }
        .translationTask(configuration) { session in
            do {
                try await cache.acquire()
                defer { cache.release() }
                guard display.text == nil, scenePhase != .background else { return }
                let response = try await session.translate(original)
                try Task.checkCancellation()
                cache.languageWasInstalled(sourceIdentifier)
                guard let result = LocalTranslatedText.validTranslation(response.targetText, original: original) else {
                    cache.failed(key)
                    phase = .failed
                    return
                }
                cache.save(result, key: key)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, display.text == nil else { return }
                let status = await cache.availability(for: sourceIdentifier, refresh: true)
                guard !Task.isCancelled else { return }
                if status == .supported {
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
        case .needsDownload: detail ? "\(field.rawValue)待下载语言包" : "\(field.rawValue)待翻译 · 点开下载语言包"
        case .unavailable, .failed: detail ? "\(field.rawValue)译文暂不可用" : "\(field.rawValue)译文暂不可用 · 点开查看"
        }
    }

    private func start() {
        phase = .translating
        if configuration != nil { configuration?.invalidate() }
        else { configuration = .init(source: source, target: target) }
    }

    private func prepare() async {
        guard scenePhase == .active, display.text == nil, !original.isEmpty, phase != .translating else { return }
        guard cache.canAttempt(key) else { phase = .failed; return }
        let status = await cache.availability(for: sourceIdentifier, refresh: phase == .needsDownload)
        guard !Task.isCancelled, scenePhase == .active, display.text == nil, phase != .translating else { return }
        switch status {
        case .installed:
            start()
        case .supported:
            if detail, cache.requestDownloadAutomatically(for: sourceIdentifier) {
                start()
            } else {
                phase = .needsDownload
            }
        case .unsupported: phase = .unavailable
        @unknown default: phase = .unavailable
        }
    }
}
