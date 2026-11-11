import Combine
import Foundation
import UIKit
import UserNotifications

@MainActor
final class PersonPushNotificationManager: ObservableObject {
    static let shared = PersonPushNotificationManager()

    @Published private(set) var enabledPersonIDs: Set<String>
    @Published private(set) var isUpdating = false
    @Published private(set) var errorMessage: String?

    private let defaults: UserDefaults
    private let session: URLSession
    private let enabledPersonIDsKey = "personPush.enabledPersonIDs"
    private let registrationTokensKey = "personPush.registrationTokens"
    private let tokenKey = "personPush.deviceToken"
    // A failed registration response can leave either the old or the new token active.
    private var registrationTokens: [String: [String]]
    private var subscriptionRequests: [String: (id: UUID, task: Task<Void, Error>)] = [:]

    init(defaults: UserDefaults = .standard, session: URLSession = .shared) {
        self.defaults = defaults
        self.session = session
        enabledPersonIDs = Set(defaults.stringArray(forKey: enabledPersonIDsKey) ?? [])
        registrationTokens = defaults.dictionary(forKey: registrationTokensKey) as? [String: [String]] ?? [:]
    }

    func isEnabled(for personID: String) -> Bool {
        enabledPersonIDs.contains(personID)
    }

    func restoreRegistration() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            do {
                if try await center.requestAuthorization(options: [.alert, .badge, .sound]) {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            } catch {
                errorMessage = "通知权限申请失败，请稍后再试"
            }
        case .authorized, .provisional, .ephemeral:
            UIApplication.shared.registerForRemoteNotifications()
        case .denied:
            for personID in enabledPersonIDs { rememberCurrentTokenIfNeeded(for: personID) }
            updateLocalState(enabledPersonIDs: [])
        @unknown default:
            break
        }
        await retryPendingDisables()
    }

    func setEnabled(_ enabled: Bool, for personID: String) async {
        guard !isUpdating else { return }
        isUpdating = true
        errorMessage = nil
        defer { isUpdating = false }

        if enabled {
            do {
                let granted = try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .badge, .sound])
                guard granted else {
                    errorMessage = "请在系统设置中允许“焦点”发送通知"
                    updateLocalState(personID: personID, enabled: false)
                    return
                }
                updateLocalState(personID: personID, enabled: true)
                if let token = defaults.string(forKey: tokenKey), !token.isEmpty {
                    do {
                        try await updateServerSubscription(
                            token: token,
                            personID: personID,
                            enabled: true
                        )
                    } catch {
                        errorMessage = "通知设备注册失败，请稍后重新开启"
                        updateLocalState(personID: personID, enabled: false)
                        return
                    }
                }
                UIApplication.shared.registerForRemoteNotifications()
            } catch {
                errorMessage = "通知权限申请失败，请稍后再试"
                updateLocalState(personID: personID, enabled: false)
            }
        } else {
            rememberCurrentTokenIfNeeded(for: personID)
            updateLocalState(personID: personID, enabled: false)
            do {
                try await syncDisabledSubscription(for: personID)
            } catch {
                errorMessage = "本机提醒已关闭；服务器同步将在下次启动时重试"
            }
        }
    }

    func didRegister(deviceToken: Data) async {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        for personID in enabledPersonIDs { rememberCurrentTokenIfNeeded(for: personID) }
        defaults.set(token, forKey: tokenKey)
        var failed = false
        do {
            try await registerNotificationDevice(token: token)
        } catch {
            failed = true
        }
        for personID in enabledPersonIDs {
            guard defaults.string(forKey: tokenKey) == token else { return }
            guard enabledPersonIDs.contains(personID) else { continue }
            do {
                try await updateServerSubscription(
                    token: token,
                    personID: personID,
                    enabled: true
                )
            } catch {
                if enabledPersonIDs.contains(personID) { failed = true }
            }
        }
        guard defaults.string(forKey: tokenKey) == token else { return }
        if failed {
            errorMessage = "通知设备注册失败，请稍后重新开启"
        } else {
            errorMessage = nil
        }
    }

    func didFailToRegister() {
        errorMessage = "无法向 Apple 注册这台设备的通知"
    }

    private func updateLocalState(personID: String, enabled: Bool) {
        var updated = enabledPersonIDs
        if enabled {
            updated.insert(personID)
        } else {
            updated.remove(personID)
        }
        updateLocalState(enabledPersonIDs: updated)
    }

    private func updateLocalState(enabledPersonIDs: Set<String>) {
        self.enabledPersonIDs = enabledPersonIDs
        defaults.set(enabledPersonIDs.sorted(), forKey: enabledPersonIDsKey)
    }

    private func rememberCurrentTokenIfNeeded(for personID: String) {
        guard registrationTokens[personID] == nil,
              let token = defaults.string(forKey: tokenKey) else { return }
        rememberRegistrationToken(token, for: personID)
    }

    private func rememberRegistrationToken(_ token: String, for personID: String) {
        let tokens = registrationTokens[personID] ?? []
        guard !token.isEmpty, !tokens.contains(token) else { return }
        setRegistrationTokens(tokens + [token], for: personID)
    }

    private func setRegistrationTokens(_ tokens: [String], for personID: String) {
        let value: [String]? = tokens.isEmpty ? nil : tokens
        guard registrationTokens[personID] != value else { return }
        registrationTokens[personID] = value
        defaults.set(registrationTokens, forKey: registrationTokensKey)
    }

    private func retryPendingDisables() async {
        let pending = Set(registrationTokens.keys).subtracting(enabledPersonIDs)
        for personID in pending {
            try? await syncDisabledSubscription(for: personID)
        }
    }

    private func syncDisabledSubscription(for personID: String) async throws {
        var failure: Error?
        for token in registrationTokens[personID] ?? [] {
            guard !enabledPersonIDs.contains(personID) else { break }
            guard registrationTokens[personID]?.contains(token) == true else { continue }
            do {
                try await updateServerSubscription(token: token, personID: personID, enabled: false)
            } catch {
                failure = error
            }
        }
        if let failure { throw failure }
    }

    private func updateServerSubscription(
        token: String,
        personID: String,
        enabled: Bool
    ) async throws {
        let url = ServerConfiguration.currentURL
            .appending(path: "api/ios/v1/ios/push/subscriptions")
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            SubscriptionRequest(
                deviceToken: token,
                deviceID: deviceIdentifier,
                personID: personID,
                enabled: enabled,
                environment: Self.apnsEnvironment
            )
        )
        if enabled { rememberRegistrationToken(token, for: personID) }
        let previous = subscriptionRequests[personID]?.task
        let id = UUID()
        let task = Task { [session, request] in
            // Token updates and user actions for a person must reach the server in order.
            _ = try? await previous?.value
            if enabled { rememberRegistrationToken(token, for: personID) }
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                throw SubscriptionError.invalidResponse
            }
            if enabled {
                if subscriptionRequests[personID]?.id == id { setRegistrationTokens([token], for: personID) }
            } else {
                let remaining = registrationTokens[personID]?.filter { $0 != token } ?? []
                setRegistrationTokens(remaining, for: personID)
            }
        }
        subscriptionRequests[personID] = (id, task)
        defer {
            if subscriptionRequests[personID]?.id == id { subscriptionRequests[personID] = nil }
        }
        try await task.value
    }

    private func registerNotificationDevice(token: String) async throws {
        let url = ServerConfiguration.currentURL.appending(path: "api/ios/v1/ios/push/device")
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            NotificationDeviceRequest(
                token: token,
                deviceID: deviceIdentifier,
                environment: Self.apnsEnvironment
            )
        )
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 204 else {
            throw SubscriptionError.invalidResponse
        }
    }

    private var deviceIdentifier: String {
        if let identifier = UIDevice.current.identifierForVendor?.uuidString {
            return identifier.lowercased()
        }
        let key = "personPush.installationID"
        if let existing = defaults.string(forKey: key), !existing.isEmpty {
            return existing
        }
        let created = UUID().uuidString.lowercased()
        defaults.set(created, forKey: key)
        return created
    }

    private static var apnsEnvironment: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }
}

private struct NotificationDeviceRequest: Encodable {
    let token: String
    let deviceID: String
    let environment: String

    enum CodingKeys: String, CodingKey {
        case token, environment
        case deviceID = "device_id"
    }
}

private struct SubscriptionRequest: Encodable {
    let deviceToken: String
    let deviceID: String
    let personID: String
    let enabled: Bool
    let environment: String

    enum CodingKeys: String, CodingKey {
        case enabled, environment
        case deviceToken = "device_token"
        case deviceID = "device_id"
        case personID = "person_id"
    }
}

private enum SubscriptionError: Error {
    case invalidResponse
}
