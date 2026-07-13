import SwiftUI

@main
struct AIServerClientApp: App {
    init() {
        URLCache.shared = URLCache(memoryCapacity: 48_000_000, diskCapacity: 240_000_000)
    }

    var body: some Scene { WindowGroup { NewsFeedView() } }
}
