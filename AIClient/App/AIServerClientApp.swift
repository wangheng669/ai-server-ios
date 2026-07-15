import SwiftUI

@main
struct AIServerClientApp: App {
    init() {
        URLCache.shared = URLCache(memoryCapacity: 48_000_000, diskCapacity: 240_000_000)
    }

    var body: some Scene { WindowGroup { EditorialRootView() } }
}

private struct EditorialRootView: View {
    @State private var selectedTab: RootTab = {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--market-preview") ? .market : .observation
        #else
        .observation
        #endif
    }()
    @Environment(\.openURL) private var openURL
    @State private var marketShowsDetail = false
    @State private var feedShowsDetail = false

    var body: some View {
        TabView(selection: $selectedTab) {
            NewsFeedView(showsDetail: $feedShowsDetail)
                .tag(RootTab.observation)

            MarketView(showsDetail: $marketShowsDetail)
                .tag(RootTab.market)
        }
        .toolbar(.hidden, for: .tabBar)
        .overlay(alignment: .bottom) {
            if !marketShowsDetail && !feedShowsDetail {
                EditorialTabBar(selected: selectedTab) { tab in
                    if tab == .events {
                        open("events")
                    } else {
                        selectedTab = tab
                    }
                }
            }
        }
    }

    private func open(_ path: String) {
        guard let url = URL(string: path, relativeTo: ServerConfiguration.currentURL)?.absoluteURL else { return }
        openURL(url)
    }
}
