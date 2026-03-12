import SwiftUI
import WebKit

struct HTMLOrbRendererView: View {
    let state: OrbState
    let size: CGFloat

    var body: some View {
        if HTMLOrbView.hasBundledHTML {
            HTMLOrbView(state: state.htmlState)
                .frame(width: size, height: size)
                .clipShape(Circle())
                .allowsHitTesting(false)
        } else {
            OrbView(state: state, size: size)
        }
    }
}

private struct HTMLOrbView: UIViewRepresentable {
    let state: OrbHTMLState

    static var hasBundledHTML: Bool {
        Bundle.main.url(forResource: "orb", withExtension: "html") != nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.isUserInteractionEnabled = false

        context.coordinator.webView = webView
        context.coordinator.pendingState = state

        if let htmlURL = Bundle.main.url(forResource: "orb", withExtension: "html") {
            webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
        }

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.pendingState = state
        context.coordinator.applyPendingStateIfPossible()
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        var isReady = false
        var pendingState: OrbHTMLState = .neutral

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let script = """
            (function() {
              const style = document.createElement('style');
              style.innerHTML = `
                html, body {
                  background: transparent !important;
                  overflow: hidden !important;
                }
                .app-container {
                  justify-content: center !important;
                  width: 100vw !important;
                  height: 100vh !important;
                }
                .ui-layer {
                  display: none !important;
                }
                .orb-wrapper {
                  width: 100% !important;
                  height: 100% !important;
                  transform-origin: center center !important;
                }
                .orb, .orb-glass {
                  width: 100% !important;
                  height: 100% !important;
                }
              `;
              document.head.appendChild(style);
              document.body.style.background = 'transparent';
              document.documentElement.style.background = 'transparent';
              if (typeof setState === 'function') {
                setState('\(pendingState.rawValue)');
              }
            })();
            """

            webView.evaluateJavaScript(script) { [weak self] _, _ in
                self?.isReady = true
                self?.applyPendingStateIfPossible()
            }
        }

        func applyPendingStateIfPossible() {
            guard isReady, let webView else { return }
            let script = "if (typeof setState === 'function') { setState('\(pendingState.rawValue)'); }"
            webView.evaluateJavaScript(script, completionHandler: nil)
        }
    }
}
