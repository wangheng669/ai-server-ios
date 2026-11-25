import OSLog
import SwiftUI
import UIKit

struct FocusUpdateTip: View {
    private var updateLogger: Logger {
        Logger(subsystem: Bundle.main.bundleIdentifier ?? "AIServerClient", category: "UpdateCheck")
    }

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("focus.requestedUpdateRelease") private var requestedUpdateRelease = ""
    @State private var availableUpdate: AvailableUpdate?
    @State private var dismissedReleaseID: String?
    @State private var completedUpdateVersion: String?
    @State private var installerPresentation: InstallerPresentation?
    @State private var showsInstallOptions = false
    @State private var updateUnavailable = false

    private enum UpdateCheckFailure: Error {
        case invalidManifest
        case server(Int)
        case network(URLError.Code)

        var isTransient: Bool {
            switch self {
            case .server(500), .server(502), .server(503), .server(504),
                 .network(.timedOut), .network(.networkConnectionLost), .network(.secureConnectionFailed),
                 .network(.notConnectedToInternet), .network(.cannotConnectToHost),
                 .network(.cannotFindHost), .network(.dnsLookupFailed):
                return true
            default:
                return false
            }
        }
    }

    private enum InstallerPresentation: Equatable {
        case requesting, waitingForConfirmation
    }

    private struct AvailableUpdate {
        let version: String
        let build: Int
        let installURL: URL

        var releaseID: String { "\(version)+\(build)" }
    }

    private struct PublishedVersion: Decodable {
        let version: String
        let build: Int
        let package: String

        func installURL(in channel: URL) -> URL? {
            let prefix = "build-\(version)-\(build)-"
            let identifier = package.dropFirst(prefix.count)
            guard package.hasPrefix(prefix), identifier.utf8.count == 16,
                  identifier.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
                  var components = URLComponents(string: "itms-services://") else { return nil }
            let manifest = channel.appendingPathComponent(package, isDirectory: true).appendingPathComponent("manifest.plist")
            components.queryItems = [
                URLQueryItem(name: "action", value: "download-manifest"),
                URLQueryItem(name: "url", value: manifest.absoluteString)
            ]
            return components.url
        }
    }

    private var visibleUpdate: AvailableUpdate? {
        guard let availableUpdate, availableUpdate.releaseID != dismissedReleaseID else { return nil }
        return availableUpdate
    }

    var body: some View {
        VStack(spacing: 0) {
            if let update = visibleUpdate {
                updateContent(update)
                    .padding(.horizontal, 16)
                    .transition(.opacity)
                    .accessibilityIdentifier("focus-update-tip")
            } else if let completedUpdateVersion {
                Text("已更新至 \(completedUpdateVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                    .transition(.opacity)
                    .accessibilityIdentifier("focus-update-completed")
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: visibleUpdate?.releaseID)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: completedUpdateVersion)
        .onAppear(perform: showCompletedUpdate)
        .alert("无法发起安装", isPresented: $updateUnavailable) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("无法打开 iOS 安装入口，请稍后重试。")
        }
        .alert("已发起安装", isPresented: $showsInstallOptions, presenting: visibleUpdate) { update in
            Button("重新发起") { requestInstallation(update) }
            Button("关闭", role: .cancel) {}
        } message: { _ in
            Text("如果没有看到系统安装弹窗，可以重新发起。已确认安装时，请在主屏幕查看焦点图标的进度。")
        }
        .task(id: completedUpdateVersion) {
            guard completedUpdateVersion != nil else { return }
            do { try await Task.sleep(for: .seconds(6)) }
            catch { return }
            completedUpdateVersion = nil
        }
        .task(id: installerPresentation) {
            guard installerPresentation == .waitingForConfirmation else { return }
            do { try await Task.sleep(for: .seconds(15)) }
            catch { return }
            installerPresentation = nil
        }
        .task(id: scenePhase == .active, priority: .utility) {
            guard scenePhase == .active, let entry = installEntryURL, let installed = installedRelease else { return }
            let channel = entry.deletingLastPathComponent()
            while !Task.isCancelled {
                await checkForUpdate(in: channel, installedOrder: installed.order)
                do { try await Task.sleep(for: .seconds(300)) }
                catch { return }
            }
        }
    }

    private func updateContent(_ update: AvailableUpdate) -> some View {
        let alreadyRequested = requestedUpdateRelease == update.releaseID
        let canStartInstall = !alreadyRequested && installerPresentation == nil
        return HStack(spacing: 4) {
            Text(alreadyRequested ? "已发起安装 \(update.version)" : "新版 \(update.version)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                if alreadyRequested {
                    showsInstallOptions = true
                } else {
                    requestInstallation(update)
                }
            } label: {
                Group {
                    switch installerPresentation {
                    case .requesting:
                        Text("发起中")
                    case .waitingForConfirmation:
                        Text("等待确认")
                    case nil:
                        Text(alreadyRequested ? "安装说明" : "更新")
                    }
                }
                .font(.caption.weight(canStartInstall ? .semibold : .regular))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .foregroundStyle(canStartInstall ? TodayBriefStyle.accent : TodayBriefStyle.secondary)
                .background(canStartInstall ? TodayBriefStyle.accent.opacity(0.08) : .clear, in: Capsule())
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(installerPresentation != nil)
            .accessibilityIdentifier("focus-install-update")
            Button {
                dismissedReleaseID = update.releaseID
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭更新提示")
        }
    }

    private var installEntryURL: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "FocusDirectInstallURL") as? String,
              let url = URL(string: value), url.scheme == "https", url.host != nil else { return nil }
        return url
    }

    private func numericVersion(_ version: String, build: Int) -> [Int]? {
        let fields = version.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(fields.count), build > 0,
              fields.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }) else { return nil }
        let numbers = fields.compactMap { Int($0) }
        guard numbers.count == fields.count else { return nil }
        return numbers + Array(repeating: 0, count: 3 - numbers.count) + [build]
    }

    private var installedRelease: (version: String, order: [Int])? {
        guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              let buildString = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
              let build = Int(buildString), let order = numericVersion(version, build: build) else { return nil }
        return (version, order)
    }

    private func showCompletedUpdate() {
        let parts = requestedUpdateRelease.split(separator: "+", omittingEmptySubsequences: false)
        guard parts.count == 2, let build = Int(parts[1]),
              let requested = numericVersion(String(parts[0]), build: build),
              let installed = installedRelease,
              !installed.order.lexicographicallyPrecedes(requested) else { return }
        requestedUpdateRelease = ""
        completedUpdateVersion = installed.version
    }

    @MainActor
    private func checkForUpdate(in channel: URL, installedOrder: [Int]) async {
        let start = ProcessInfo.processInfo.systemUptime
        do {
            let published: PublishedVersion
            do {
                published = try await fetchPublishedVersion(in: channel)
            } catch let failure as UpdateCheckFailure where failure.isTransient {
                updateLogger.info("Retrying update check after \(String(describing: failure), privacy: .public)")
                try await Task.sleep(for: .milliseconds(250))
                published = try await fetchPublishedVersion(in: channel)
            }
            try Task.checkCancellation()
            guard let remote = numericVersion(published.version, build: published.build),
                  let installURL = published.installURL(in: channel) else {
                throw UpdateCheckFailure.invalidManifest
            }
            if installedOrder.lexicographicallyPrecedes(remote) {
                availableUpdate = AvailableUpdate(version: published.version, build: published.build, installURL: installURL)
            } else {
                availableUpdate = nil
            }
            let elapsed = ProcessInfo.processInfo.systemUptime - start
            updateLogger.info("Update check completed in \(elapsed, format: .fixed(precision: 3)) seconds")
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            let elapsed = ProcessInfo.processInfo.systemUptime - start
            updateLogger.error("Update check failed after \(elapsed, format: .fixed(precision: 3)) seconds: \(String(describing: error), privacy: .public)")
        }
    }

    private func fetchPublishedVersion(in channel: URL) async throws -> PublishedVersion {
        let url = channel.appendingPathComponent("latest.json").appending(queryItems: [
            .init(name: "check", value: UUID().uuidString)
        ])
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 4)
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await withThrowingTaskGroup(of: (Data, URLResponse).self) { group in
                group.addTask { [request] in
                    try await URLSession.shared.data(for: request)
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(4))
                    throw URLError(.timedOut)
                }
                defer { group.cancelAll() }
                guard let result = try await group.next() else { throw CancellationError() }
                return result
            }
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw UpdateCheckFailure.network(error.code)
        }
        guard let response = response as? HTTPURLResponse else { throw UpdateCheckFailure.invalidManifest }
        guard response.statusCode == 200 else { throw UpdateCheckFailure.server(response.statusCode) }
        guard let published = try? JSONDecoder().decode(PublishedVersion.self, from: data) else {
            throw UpdateCheckFailure.invalidManifest
        }
        return published
    }

    private func requestInstallation(_ update: AvailableUpdate) {
        guard installerPresentation == nil else { return }
        installerPresentation = .requesting
        UIApplication.shared.open(update.installURL) { opened in
            if opened {
                requestedUpdateRelease = update.releaseID
                installerPresentation = .waitingForConfirmation
            } else {
                installerPresentation = nil
                updateUnavailable = true
            }
        }
    }
}
