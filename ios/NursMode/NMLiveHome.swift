import SwiftUI
import WebKit

/// NM Live: the user interface is fetched from the owner's public GitHub repository.
/// New screens and web projects can be delivered without replacing the IPA.
/// The signed iOS capabilities, background tasks and App Intents remain native.
struct NMRoot: View {
    @AppStorage("nm.useLiveInterface") private var useLiveInterface = true

    var body: some View {
        Group {
            if useLiveInterface {
                NMLiveHome()
            } else {
                NMHome()
            }
        }
    }
}

struct NMLiveHome: View {
    @EnvironmentObject private var store: NMStore
    @Environment(\.scenePhase) private var phase
    @AppStorage("nm.useLiveInterface") private var useLiveInterface = true
    @State private var remoteHTML = UserDefaults.standard.string(forKey: "nm.live.cachedHTML") ?? ""
    @State private var isLoading = false
    @State private var error: String?
    @State private var route: [NMProject] = []
    @State private var showSettings = false
    @State private var lastUpdated: Date?

    private let htmlPath = NMNet.base + "/nm-live.html"

    var body: some View {
        NavigationStack(path: $route) {
            Group {
                if !remoteHTML.isEmpty {
                    NMLiveWebView(html: remoteHTML, onRoute: navigate)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    VStack(spacing: 18) {
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.indigo)
                        Text("Nurs-Mode")
                            .font(.title.bold())
                        Text(error ?? "Загружаем NM Live…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        if isLoading { ProgressView() }
                        Button("Повторить") {
                            Task { await reload() }
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Открыть встроенный интерфейс") {
                            useLiveInterface = false
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(20)
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(for: NMProject.self) { project in
                if project.kind == "ps4" {
                    NMPS4Detail()
                } else if let link = project.url, let url = URL(string: link), url.scheme == "https" {
                    NMWebProject(url: url)
                        .navigationTitle(project.title)
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
            .navigationDestination(isPresented: $showSettings) {
                NMSettings()
            }
            .task {
                async let load: Void = reload()
                async let projectRefresh: Void = store.refresh()
                _ = await (load, projectRefresh)
            }
            .onChange(of: phase) { value in
                if value == .active {
                    Task {
                        await reload()
                        await store.refresh()
                    }
                }
                if value == .background { NMBackgroundMonitor.schedule() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .nmOpenPS4)) { _ in
                route = [.ps4]
            }
        }
        .tint(.indigo)
    }

    private func navigate(_ destination: String) {
        if destination == "settings" {
            showSettings = true
        } else if destination == "ps4" {
            route = [.ps4]
        } else if destination == "refresh" {
            Task {
                await reload()
                await store.refresh()
            }
        } else if destination.hasPrefix("project:") {
            let identifier = String(destination.dropFirst("project:".count))
            if let project = store.projects.first(where: { $0.id == identifier }) {
                route = [project]
            }
        }
    }

    @MainActor
    private func reload() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let endpoint = URL(string: htmlPath + "?v=" + String(Int(Date().timeIntervalSince1970)))!
            var request = URLRequest(url: endpoint)
            request.timeoutInterval = 20
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (bytes, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  bytes.count < 900_000,
                  let html = String(data: bytes, encoding: .utf8),
                  html.contains("<title>NM Live</title>"),
                  html.contains("window.nmRefresh") else {
                throw URLError(.cannotParseResponse)
            }

            if remoteHTML != html {
                remoteHTML = html
                UserDefaults.standard.set(html, forKey: "nm.live.cachedHTML")
            }
            error = nil
            lastUpdated = Date()
        } catch {
            self.error = "Сервер обновлений недоступен. Попробуй позже."
            // Keep the last known working HTML instead of replacing it.
        }
    }
}

struct NMLiveWebView: UIViewRepresentable {
    let html: String
    let onRoute: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onRoute: onRoute)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let browser = WKWebView(frame: .zero, configuration: config)
        browser.navigationDelegate = context.coordinator
        browser.isOpaque = false
        browser.backgroundColor = UIColor(red: 9 / 255, green: 13 / 255, blue: 24 / 255, alpha: 1)
        browser.scrollView.backgroundColor = browser.backgroundColor
        browser.scrollView.contentInsetAdjustmentBehavior = .never
        load(html, into: browser, coordinator: context.coordinator)
        return browser
    }

    func updateUIView(_ browser: WKWebView, context: Context) {
        context.coordinator.onRoute = onRoute
        if context.coordinator.lastHTML != html {
            load(html, into: browser, coordinator: context.coordinator)
        }
    }

    private func load(_ markup: String, into browser: WKWebView, coordinator: Coordinator) {
        coordinator.lastHTML = markup
        browser.loadHTMLString(markup, baseURL: URL(string: NMNet.base + "/"))
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML: String?
        var onRoute: (String) -> Void

        init(onRoute: @escaping (String) -> Void) {
            self.onRoute = onRoute
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            if url.scheme == "nm" {
                let destination: String
                if url.host == "project" {
                    let identifier = String(url.path.dropFirst()).removingPercentEncoding ?? ""
                    destination = "project:" + identifier
                } else {
                    destination = url.host ?? ""
                }
                decisionHandler(.cancel)
                DispatchQueue.main.async { self.onRoute(destination) }
                return
            }

            if navigationAction.targetFrame?.isMainFrame != false,
               navigationAction.navigationType == .linkActivated,
               url.scheme == "https" || url.scheme == "http" {
                decisionHandler(.cancel)
                DispatchQueue.main.async { UIApplication.shared.open(url) }
                return
            }
            decisionHandler(.allow)
        }
    }
}
