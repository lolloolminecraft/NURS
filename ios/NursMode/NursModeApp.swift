import SwiftUI
import UserNotifications
import WebKit
import AVKit

struct NMProject: Codable, Hashable, Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let kind: String
    let url: String?

    static let ps4 = NMProject(
        id: "ps4-1400",
        title: "PS4 14.00",
        subtitle: "Джейлбрейк · отслеживание",
        symbol: "gamecontroller.fill",
        kind: "ps4",
        url: nil
    )
}

struct NMProjectFeed: Decodable {
    let projects: [NMProject]
}

struct NMSource: Decodable, Identifiable {
    let name: String
    let url: String
    var id: String { url }
}

struct NMRelease: Decodable {
    let id: String?
    let title: String?
    let source: String?
    let source_url: String?
    let download_url: String?
    let instructions: String?
    let video_url: String?
    let published_at: String?
}

struct NMStatus: Decodable {
    let state: String
    let status_text: String?
    let summary: String?
    let significance: String?
    let last_checked_at: String?
    let status_changed_at: String?
    let checked_sources: [NMSource]?
    let release: NMRelease?
}

enum NMNet {
    static let base = "https://raw.githubusercontent.com/lolloolminecraft/NURS/main/docs"

    static func load<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        var components = URLComponents(string: base + "/" + path)!
        components.queryItems = [URLQueryItem(name: "v", value: String(Int(Date().timeIntervalSince1970)))]
        var request = URLRequest(url: components.url!)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        let (bytes, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: bytes)
    }
}

@MainActor
final class NMStore: ObservableObject {
    @Published var projects: [NMProject] = [.ps4]
    @Published var status: NMStatus?
    @Published var isLoading = false
    @Published var networkError: String?
    @Published var importantChange: String?
    @Published var routeToPS4 = false

    var currentState: String { status?.state ?? "waiting" }

    var statusLabel: String {
        if let explicit = status?.status_text, !explicit.isEmpty { return explicit }
        switch currentState {
        case "released": return "Джейлбрейк выпущен"
        case "exploit": return "Подтверждён частичный эксплойт"
        case "progress", "research", "candidate": return "Подтверждён важный прогресс"
        default: return "Не найден официально"
        }
    }

    var statusColor: Color {
        switch currentState {
        case "released": return .green
        case "exploit", "progress", "research", "candidate": return .orange
        default: return .red
        }
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let updated = try await NMNet.load("status.json", as: NMStatus.self)
            let oldMilestone = UserDefaults.standard.string(forKey: "nm.milestone")
            let milestone = (updated.status_changed_at ?? "") + ":" + updated.state
            status = updated
            networkError = nil

            if oldMilestone == nil {
                UserDefaults.standard.set(milestone, forKey: "nm.milestone")
            } else if oldMilestone != milestone {
                UserDefaults.standard.set(milestone, forKey: "nm.milestone")
                importantChange = updated.status_text ?? "Важное изменение PS4 14.00"
                await scheduleLocalNotice(
                    title: "Nurs-Mode · PS4 14.00",
                    message: updated.status_text ?? "Статус проекта изменился"
                )
            }
        } catch {
            networkError = "Не удалось обновить статус. Попробуй позже."
        }

        do {
            let response = try await NMNet.load("projects.json", as: NMProjectFeed.self)
            var projects: [NMProject] = [.ps4]
            for project in response.projects {
                if project.id == NMProject.ps4.id { continue }
                if project.kind == "web",
                   let link = project.url,
                   let address = URL(string: link),
                   address.scheme == "https",
                   !projects.contains(where: { $0.id == project.id }) {
                    projects.append(project)
                }
            }
            self.projects = projects
        } catch {
            self.projects = [.ps4]
        }
    }

    private func scheduleLocalNotice(title: String, message: String) async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = .default
        content.userInfo = ["project": "ps4"]
        let request = UNNotificationRequest(
            identifier: "nm-status-" + UUID().uuidString,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    func enableLocalNotifications() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func testLocalNotification() async {
        await scheduleLocalNotice(title: "NM · Проверка", message: "Локальные уведомления работают.")
    }
}

final class NMNotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if (response.notification.request.content.userInfo["project"] as? String) == "ps4" {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .nmOpenPS4, object: nil)
            }
        }
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }
}

extension Notification.Name {
    static let nmOpenPS4 = Notification.Name("nmOpenPS4")
}

@main
struct NursModeApp: App {
    @UIApplicationDelegateAdaptor(NMNotificationDelegate.self) private var delegate
    @StateObject private var store = NMStore()

    var body: some Scene {
        WindowGroup {
            NMHome()
                .environmentObject(store)
        }
    }
}

struct NMHome: View {
    @EnvironmentObject private var store: NMStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: NMProject?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    NMHeader()
                    HStack {
                        Text("Мои проекты")
                            .font(.title2.bold())
                        Spacer()
                        Text(String(store.projects.count))
                            .font(.subheadline.bold())
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.projects) { project in
                        Button {
                            selection = project
                        } label: {
                            NMProjectTile(project: project, store: store)
                        }
                        .buttonStyle(.plain)
                    }
                    Text("Новые проекты появятся здесь без повторной установки приложения.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(18)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Nurs-Mode")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    NavigationLink {
                        NMSettings()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        if store.isLoading {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
            .navigationDestination(item: $selection) { project in
                if project.kind == "ps4" {
                    NMPS4Detail()
                } else if let link = project.url, let url = URL(string: link) {
                    NMWebProject(url: url)
                        .navigationTitle(project.title)
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
            .task { await store.refresh() }
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .active { Task { await store.refresh() } }
            }
            .onReceive(NotificationCenter.default.publisher(for: .nmOpenPS4)) { _ in
                selection = .ps4
            }
        }
        .tint(.indigo)
    }
}

struct NMHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 39))
                    .foregroundStyle(.white)
                Spacer()
                Text("NM")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
            }
            Text("Твоя лаборатория")
                .font(.title2.bold())
                .foregroundStyle(.white)
            Text("Проекты, эксперименты и полезные инструменты в одном приложении.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [.indigo, Color(red: 0.21, green: 0.15, blue: 0.55)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24)
        )
    }
}

struct NMProjectTile: View {
    let project: NMProject
    @ObservedObject var store: NMStore

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: project.symbol)
                .font(.title2)
                .foregroundStyle(.indigo)
                .frame(width: 53, height: 53)
                .background(.indigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 15))
            VStack(alignment: .leading, spacing: 6) {
                Text(project.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(project.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if project.kind == "ps4" {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(store.statusColor)
                            .frame(width: 7, height: 7)
                        Text(store.statusLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.bold())
                .foregroundStyle(.tertiary)
        }
        .padding(15)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

struct NMPS4Detail: View {
    @EnvironmentObject private var store: NMStore
    @State private var expanded = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("PS4 · прошивка 14.00")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        expanded.toggle()
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 9) {
                            Circle()
                                .fill(store.statusColor)
                                .frame(width: 11, height: 11)
                            Text(store.statusLabel)
                                .font(.title3.bold())
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                                .foregroundStyle(.secondary)
                        }
                        Text(store.status?.summary ?? "Официальный рабочий релиз ещё не подтверждён.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                        Divider()
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Последняя проверка ChatGPT")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Text(NMDate.format(store.status?.last_checked_at))
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                        }
                    }
                    .padding(18)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 21))
                }
                .buttonStyle(.plain)

                if let failure = store.networkError {
                    Label(failure, systemImage: "wifi.exclamationmark")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }

                if expanded {
                    if store.currentState == "released", let release = store.status?.release {
                        NMReleaseDetail(release: release)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Что известно").font(.headline)
                            Text(store.status?.summary ?? "Подтверждённого релиза пока нет.")
                                .font(.subheadline)
                            if store.currentState != "waiting" {
                                Text("Это не означает, что готовый джейлбрейк опубликован.")
                                    .font(.footnote)
                                    .foregroundStyle(.orange)
                            }
                        }
                        .nmCard()
                    }
                    if let sources = store.status?.checked_sources, !sources.isEmpty {
                        VStack(alignment: .leading, spacing: 13) {
                            Text("Проверенные источники").font(.headline)
                            ForEach(sources) { source in
                                if let url = NMDate.https(source.url) {
                                    Button {
                                        openURL(url)
                                    } label: {
                                        Label(source.name, systemImage: "arrow.up.right")
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                        }
                        .nmCard()
                    }
                    if let changed = store.status?.status_changed_at {
                        Text("Статус обновлён: " + NMDate.format(changed))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    Task { await store.refresh() }
                } label: {
                    HStack {
                        Spacer()
                        if store.isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Label("Обновить данные", systemImage: "arrow.clockwise")
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.isLoading)

                Text("Статус определяет ежечасная задача ChatGPT. Видео и отдельные слухи сами по себе не означают готовый джейлбрейк.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(18)
        }
        .navigationTitle("PS4 14.00")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
        .refreshable { await store.refresh() }
        .onAppear {
            expanded = store.currentState == "released"
        }
        .onChange(of: store.currentState) { state in
            if state == "released" { expanded = true }
        }
        .alert("Важное изменение", isPresented: Binding(
            get: { store.importantChange != nil },
            set: { if !$0 { store.importantChange = nil } }
        )) {
            Button("Понятно") {
                store.importantChange = nil
                expanded = true
            }
        } message: {
            Text(store.importantChange ?? "")
        }
    }
}

struct NMReleaseDetail: View {
    let release: NMRelease
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(release.title ?? "Релиз PS4 14.00")
                .font(.title3.bold())
            if let published = release.published_at {
                Text("Опубликовано: " + NMDate.format(published))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let link = NMDate.https(release.download_url) {
                Button {
                    openURL(link)
                } label: {
                    Label("Скачать у автора", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderedProminent)
            }
            if let link = NMDate.https(release.source_url) {
                Button {
                    openURL(link)
                } label: {
                    Label("Официальный источник", systemImage: "link")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
            }
            if let instruction = release.instructions, !instruction.isEmpty {
                Divider()
                Text("Инструкция").font(.headline)
                Text(instruction)
                    .font(.subheadline)
                    .textSelection(.enabled)
            }
        }
        .nmCard()
        if let video = NMDate.https(release.video_url) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Видео автора").font(.headline)
                NMEmbeddedVideo(url: video)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                Button {
                    openURL(video)
                } label: {
                    Label("Открыть оригинал видео", systemImage: "arrow.up.right")
                        .font(.footnote)
                }
            }
            .nmCard()
        }
    }
}

struct NMEmbeddedVideo: View {
    let url: URL

    var body: some View {
        if let id = Self.youtubeID(url) {
            NMYouTubeView(videoID: id)
        } else if ["mp4", "m4v", "mov"].contains(url.pathExtension.lowercased()) {
            VideoPlayer(player: AVPlayer(url: url))
        } else {
            NMWebProject(url: url)
        }
    }

    static func youtubeID(_ url: URL) -> String? {
        let host = (url.host ?? "").lowercased()
        let parts = url.pathComponents.filter { $0 != "/" }
        var id: String?
        if host == "youtu.be" || host == "www.youtu.be" {
            id = parts.first
        } else if ["youtube.com", "www.youtube.com", "m.youtube.com"].contains(host) {
            if parts.first == "watch" {
                id = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "v" })?.value
            } else if ["shorts", "live", "embed"].contains(parts.first ?? "") && parts.count > 1 {
                id = parts[1]
            }
        }
        guard let id, id.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil else {
            return nil
        }
        return id
    }
}

struct NMYouTubeView: UIViewRepresentable {
    let videoID: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let web = WKWebView(frame: .zero, configuration: config)
        web.scrollView.isScrollEnabled = false
        web.isOpaque = false
        web.backgroundColor = .black
        let html = """
        <html><head><meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>body{margin:0;background:#000}iframe{position:absolute;width:100%;height:100%;border:0}</style>
        </head><body><iframe src="https://www.youtube-nocookie.com/embed/\(videoID)?playsinline=1"
        allow="accelerometer; encrypted-media; gyroscope; picture-in-picture; web-share"
        allowfullscreen></iframe></body></html>
        """
        web.loadHTMLString(html, baseURL: URL(string: "https://www.youtube-nocookie.com"))
        return web
    }

    func updateUIView(_ view: WKWebView, context: Context) {}
}

struct NMWebProject: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView()
        web.allowsBackForwardNavigationGestures = true
        web.load(URLRequest(url: url))
        return web
    }

    func updateUIView(_ view: WKWebView, context: Context) {}
}

struct NMSettings: View {
    @EnvironmentObject private var store: NMStore
    @State private var granted = false

    var body: some View {
        Form {
            Section("Уведомления") {
                Button("Разрешить локальные уведомления") {
                    Task { granted = await store.enableLocalNotifications() }
                }
                Button("Проверить уведомление") {
                    Task {
                        granted = await store.enableLocalNotifications()
                        if granted { await store.testLocalNotification() }
                    }
                }
                Text("Удалённые push при закрытом приложении требуют Apple Push Notifications и подходящей подписи. Бесплатная установка через Sideloadly не включает этот канал автоматически.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Обновление") {
                Button("Обновить проекты и новости") {
                    Task { await store.refresh() }
                }
                Text("Карточки проектов, ссылки, видео и статусы NM загружает из GitHub. Новый веб-проект можно добавить без нового IPA.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Приложение") {
                LabeledContent("Название", value: "Nurs-Mode")
                LabeledContent("Версия", value: "1.0")
                Text("Новые нативные функции iPhone потребуют новой сборки IPA.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Настройки")
    }
}

struct NMDate {
    static func format(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "Ещё не сообщалось" }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let normal = ISO8601DateFormatter()
        normal.formatOptions = [.withInternetDateTime]
        guard let date = fractional.date(from: value) ?? normal.date(from: value) else { return value }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    static func https(_ value: String?) -> URL? {
        guard let value, let url = URL(string: value), url.scheme == "https" else { return nil }
        return url
    }
}

extension View {
    func nmCard() -> some View {
        self
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}