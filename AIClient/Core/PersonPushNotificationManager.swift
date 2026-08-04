import Combine
import Foundation
import UIKit
import UserNotifications

@MainActor
final class PersonPushNotificationManager: ObservableObject {
    static let shared = PersonPushNotificationManager()
    static let legacySamAltmanID = "1605"

    @Published private(set) var enabledPersonIDs: Set<String>
    @Published private(set) var isUpdating = false
    @Published private(set) var errorMessage: String?

    private let defaults: UserDefaults
    private let session: URLSession
    private let enabledPersonIDsKey = "personPush.enabledPersonIDs"
    private let legacySamAltmanEnabledKey = "personPush.samAltman.enabled"
    private let tokenKey = "personPush.deviceToken"

    init(defaults: UserDefaults = .standard, session: URLSession = .shared) {
        self.defaults = defaults
        self.session = session
        if let storedIDs = defaults.stringArray(forKey: enabledPersonIDsKey) {
            enabledPersonIDs = Set(storedIDs)
        } else if defaults.bool(forKey: legacySamAltmanEnabledKey) {
            enabledPersonIDs = [Self.legacySamAltmanID]
            defaults.set(Array(enabledPersonIDs), forKey: enabledPersonIDsKey)
        } else {
            enabledPersonIDs = []
        }
    }

    func isEnabled(for personID: String) -> Bool {
        enabledPersonIDs.contains(personID)
    }

    func restoreRegistration() async {
        guard !enabledPersonIDs.isEmpty else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized ||
                settings.authorizationStatus == .provisional else {
            let personIDs = enabledPersonIDs
            updateLocalState(enabledPersonIDs: [])
            if let token = defaults.string(forKey: tokenKey), !token.isEmpty {
                for personID in personIDs {
                    try? await updateServerSubscription(
                        token: token,
                        personID: personID,
                        enabled: false
                    )
                }
            }
            return
        }
        UIApplication.shared.registerForRemoteNotifications()
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
            updateLocalState(personID: personID, enabled: false)
            guard let token = defaults.string(forKey: tokenKey), !token.isEmpty else { return }
            do {
                try await updateServerSubscription(
                    token: token,
                    personID: personID,
                    enabled: false
                )
            } catch {
                errorMessage = "本机提醒已关闭；服务器同步将在下次启动时重试"
            }
        }
    }

    func didRegister(deviceToken: Data) async {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        defaults.set(token, forKey: tokenKey)
        guard !enabledPersonIDs.isEmpty else { return }
        var failed = false
        for personID in enabledPersonIDs {
            do {
                try await updateServerSubscription(
                    token: token,
                    personID: personID,
                    enabled: true
                )
            } catch {
                failed = true
            }
        }
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
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
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
