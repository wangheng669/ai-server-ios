import SwiftUI

struct ServerSetupView: View {
    @AppStorage("serverURL") private var serverURL = ServerConfiguration.defaultURL.absoluteString
    @State private var status: ConnectionStatus = .notChecked
    @State private var isChecking = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("服务器地址", text: $serverURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()

                    LabeledContent("连接状态") {
                        if isChecking {
                            ProgressView()
                        } else {
                            Text(status.title).foregroundStyle(status.color)
                        }
                    }
                } header: {
                    Text("AI Server")
                } footer: {
                    Text("此设备将通过该地址读取新闻数据。")
                }

                Button("检查连接") {
                    Task { await checkConnection() }
                }
                .disabled(isChecking)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("服务器设置")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func checkConnection() async {
        guard let url = ServerAddressValidator.normalizedURL(serverURL) else {
            status = .invalidAddress
            return
        }
        serverURL = url.absoluteString
        isChecking = true
        defer { isChecking = false }
        do {
            let client = APIClient(baseURL: url)
            try await client.checkHealth()
            status = .ready
        } catch {
            status = .failed(error.localizedDescription)
        }
    }
}

private enum ConnectionStatus {
    case notChecked
    case ready
    case invalidAddress
    case failed(String)

    var title: String {
        switch self {
        case .notChecked: "尚未检查"
        case .ready: "连接正常"
        case .invalidAddress: "地址格式无效"
        case .failed(let message): message
        }
    }

    var color: Color {
        switch self {
        case .notChecked: .secondary
        case .ready: .green
        case .invalidAddress, .failed: .red
        }
    }
}

enum ServerAddressValidator {
    static func normalizedURL(_ address: String) -> URL? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "https",
              components.host != nil else {
            return nil
        }
        components.path = components.path == "/" ? "" : components.path
        return components.url
    }

    static func isValid(_ address: String) -> Bool {
        normalizedURL(address) != nil
    }
}

#Preview {
    ServerSetupView()
}
