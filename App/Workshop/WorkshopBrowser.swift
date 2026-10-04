import AppKit
import LivepaperWorkshop
import Observation
import SwiftUI
import WebKit

/// The Workshop window's web view: Steam's own Workshop pages, which need no
/// login and no API key to browse. It stays on Steam Community
/// over https; any other page opens in the user's browser, and scripts, files
/// and Steam's own links are not followed (`WorkshopLink.navigation`).
///
/// On an item's page it reads what the page says (`WorkshopItemPage`) from the
/// page's HTML once it has loaded, for the Get button and the row's title.
/// Nothing is injected into the page, and nothing it runs reaches the app.
@MainActor @Observable
final class WorkshopBrowser: NSObject {
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    private(set) var isLoading = false
    /// The item whose page is open, if it is one.
    private(set) var item: WorkshopItemID?
    /// What that page says, once it has loaded.
    private(set) var page: WorkshopItemPage?

    @ObservationIgnored let webView: WKWebView
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        // Key-value observation of a web view calls back on the main thread.
        observations = [
            webView.observe(\.canGoBack) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.canGoBack = view.canGoBack }
            },
            webView.observe(\.canGoForward) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.canGoForward = view.canGoForward }
            },
            webView.observe(\.isLoading) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.isLoading = view.isLoading }
            },
            webView.observe(\.url) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.urlChanged(view.url) }
            },
        ]
    }

    /// Opens the Workshop's front page, the first time only.
    func start() {
        guard webView.url == nil else { return }
        webView.load(URLRequest(url: WorkshopLink.front))
    }

    func goHome() {
        webView.load(URLRequest(url: WorkshopLink.front))
    }

    func goBack() {
        webView.goBack()
    }

    func goForward() {
        webView.goForward()
    }

    func reload() {
        webView.reload()
    }

    private func urlChanged(_ url: URL?) {
        let item = url.flatMap(WorkshopLink.item(in:))
        if item != self.item {
            self.item = item
            page = nil
        }
    }

    /// Reads what an item's page says, from its HTML, once it has loaded.
    private func readPage() {
        guard let item else { return }
        Task {
            guard let html = try? await webView.evaluateJavaScript("document.documentElement.outerHTML") as? String,
                  self.item == item else { return }
            page = WorkshopItemPage(html: html)
        }
    }
}

extension WorkshopBrowser: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        // Frames inside a page (a video in an item's description) are the page's own affair.
        guard action.targetFrame?.isMainFrame ?? true, let url = action.request.url else { return .allow }
        switch WorkshopLink.navigation(to: url) {
        case .inWindow:
            return .allow
        case .inBrowser:
            NSWorkspace.shared.open(url)
            return .cancel
        case .refused:
            return .cancel
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        readPage()
    }
}

extension WorkshopBrowser: WKUIDelegate {
    /// A link that asks for a new window opens here, or in the browser, by the same rule.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for action: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let url = action.request.url else { return nil }
        switch WorkshopLink.navigation(to: url) {
        case .inWindow: webView.load(action.request)
        case .inBrowser: NSWorkspace.shared.open(url)
        case .refused: break
        }
        return nil
    }
}

/// The web view, in SwiftUI.
struct WorkshopWebView: NSViewRepresentable {
    let browser: WorkshopBrowser

    func makeNSView(context: Context) -> WKWebView {
        browser.webView
    }

    func updateNSView(_ view: WKWebView, context: Context) {}
}
