import SwiftUI
import WebKit
import Observation

struct LearningDetailView: View {
    let topic: LearningTopic
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var webState = LearningWebState()

    var body: some View {
        VStack(spacing: 0) {
            detailBar
            Divider().opacity(0.5)
            ZStack {
                LearningArticleWebView(url: topic.url, state: webState)
                if webState.isLoading {
                    ProgressView()
                        .controlSize(.large)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(uiColor: .systemBackground))
                } else if let error = webState.errorMessage {
                    ContentUnavailableView {
                        Label("内容载入失败", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("在富途查看") { openURL(topic.url) }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(uiColor: .systemBackground))
                }
            }
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private var detailBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer()
            Text(topic.category)
                .font(.system(size: 17, weight: .semibold))
            Spacer()
            Button { openURL(topic.url) } label: {
                Image(systemName: "safari")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("在富途查看原文")
        }
        .padding(.horizontal, 6)
        .frame(height: 50)
    }
}

@MainActor
@Observable
private final class LearningWebState {
    var isLoading = true
    var errorMessage: String?
}

private struct LearningArticleWebView: UIViewRepresentable {
    let url: URL
    let state: LearningWebState

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: Self.styleScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground
        webView.underPageBackgroundColor = .systemBackground
        webView.isOpaque = true
        webView.load(request)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard webView.url != url, !webView.isLoading else { return }
        webView.load(request)
    }

    private var request: URLRequest {
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
        return request
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let state: LearningWebState

        init(state: LearningWebState) {
            self.state = state
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            Task { @MainActor in
                state.isLoading = true
                state.errorMessage = nil
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript(LearningArticleWebView.styleScript)
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--learning-video-preview") {
                webView.evaluateJavaScript("document.querySelector('.play-btn')?.click()")
            }
            #endif
            Task { @MainActor in state.isLoading = false }
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            fail(error)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            fail(error)
        }

        private func fail(_ error: Error) {
            Task { @MainActor in
                state.isLoading = false
                state.errorMessage = error.localizedDescription
            }
        }
    }

    private static let styleScript = #"""
    (() => {
      const styleId = 'ai-learning-native-style';
      if (document.getElementById(styleId)) return;
      const style = document.createElement('style');
      style.id = styleId;
      style.textContent = `
        html, body {
          width: 100% !important;
          min-width: 0 !important;
          margin: 0 !important;
          padding: 0 !important;
          background: #fff !important;
          color: #111 !important;
          font-family: -apple-system, BlinkMacSystemFont, "PingFang SC", sans-serif !important;
          overflow-x: hidden !important;
        }
        body > :not(#app):not(script):not(style) { display: none !important; }
        #app, .detail-page, .course-detail-content, .course-detail,
        .course-detail__main, .course-detail__main__left,
        .course-detail__article, .course-detail__content {
          display: block !important;
          width: 100% !important;
          min-width: 0 !important;
          max-width: none !important;
          margin: 0 !important;
          box-sizing: border-box !important;
          background: #fff !important;
        }
        .boundary, .course-detail__header, .bread-wrap, .tool-box,
        .course-detail__main__right, .course-detail__side,
        .detail-page__side, footer, header, nav, aside,
        [class*="download"], [class*="floating"], [class*="cookie"],
        [class*="recommend"], [class*="comment"], [class*="abstract"] {
          display: none !important;
        }
        .course-detail__article { padding: 24px 20px 44px !important; }
        .course-detail__title {
          margin: 0 0 12px !important;
          font-size: 34px !important;
          line-height: 1.22 !important;
          letter-spacing: -0.5px !important;
          font-weight: 750 !important;
          color: #111 !important;
        }
        .course-detail__more {
          display: flex !important;
          margin: 0 0 20px !important;
          color: #7c7c86 !important;
          font-size: 14px !important;
        }
        .course-detail__more--right { display: none !important; }
        .video-wrapper {
          display: block !important;
          width: 100% !important;
          height: auto !important;
          aspect-ratio: 16 / 9 !important;
          margin: 0 0 28px !important;
          border-radius: 20px !important;
          overflow: hidden !important;
          background: #111 !important;
        }
        .course__video, .video-wrap {
          display: block !important;
          width: 100% !important;
          height: 100% !important;
          min-height: 0 !important;
          margin: 0 !important;
          border-radius: 0 !important;
          overflow: hidden !important;
          background: #111 !important;
        }
        .video-wrap video { width: 100% !important; height: 100% !important; object-fit: contain !important; }
        .section-article {
          width: 100% !important;
          max-width: none !important;
          color: #1c1c1e !important;
          font-size: 17px !important;
          line-height: 1.82 !important;
          overflow-wrap: anywhere !important;
        }
        .section-article h2 {
          position: relative !important;
          margin: 34px 0 14px !important;
          padding-left: 14px !important;
          color: #111 !important;
          font-size: 24px !important;
          line-height: 1.35 !important;
          font-weight: 720 !important;
        }
        .section-article h2::before {
          content: "" !important;
          position: absolute !important;
          left: 0 !important;
          top: 5px !important;
          bottom: 5px !important;
          width: 4px !important;
          border-radius: 3px !important;
          background: #6754e8 !important;
        }
        .section-article p, .section-article li {
          margin: 0 0 18px !important;
          color: #2c2c2e !important;
          font-size: 17px !important;
          line-height: 1.82 !important;
        }
        .section-article img {
          display: block !important;
          width: 100% !important;
          max-width: 100% !important;
          height: auto !important;
          margin: 22px 0 !important;
          border-radius: 14px !important;
        }
        .section-article table { display: block !important; max-width: 100% !important; overflow-x: auto !important; }
        a { color: #6754e8 !important; }
      `;
      document.head.appendChild(style);
      const viewport = document.querySelector('meta[name="viewport"]') || document.createElement('meta');
      viewport.name = 'viewport';
      viewport.content = 'width=device-width, initial-scale=1, maximum-scale=5';
      if (!viewport.parentNode) document.head.appendChild(viewport);
    })();
    """#
}
