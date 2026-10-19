import SwiftUI
import UserNotifications
import WebKit

struct PS4Release: Codable {
    let id: String?
    let title: String?
    let source: String?
    let source_url: String?
    let download_url: String?
    let instructions: String?
    let video_url: String?
    let published_at: String?
}

struct PS4Status: Codable {
    let state: String
    let release: PS4Release?
    let last_checked_at: String?
}

struct OporaModule: Codable, Identifiable {
    let id: String
    let title: String
    let description: String?
    let url: String
}

struct OporaModules: Codable {
    let modules: [OporaModule]
}

@MainActor
final class OporaData: ObservableObject {
    @Published var status: PS4Status?
    @Published var modules: [OporaModule] = []
    @Published var error: String?
    @Published var busy = false
    @Published var tab = 0

    static let defaultFeed = "https://raw.githubusercontent.com/lolloolminecraft/NURS/main/docs/status.json"

    func check() async {
        if busy { return }
        busy = true
        defer { busy = false }
        let address = UserDefaults.standard.string(forKey: "feed") ?? Self.defaultFeed
        guard let url = URL(string: address), url.scheme == "https" else {
            error = "Адрес источника неверный"
            return
        }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                error = "Не удалось открыть источник. Возможно, GitHub-репозиторий приватный."
                return
            }
            let current = try JSONDecoder().decode(PS4Status.self, from: data)
            let previousID = status?.release?.id
            status = current
            error = nil
            if current.state == "released", let item = current.release, let id = item.id,
               id != previousID, UserDefaults.standard.bool(forKey: "localAlerts") {
                let content = UNMutableNotificationContent()
                content.title = "Опора — PS4 14.00"
                content.body = item.title ?? "Релиз подтверждён"
                content.sound = .default
                let notification = UNNotificationRequest(identifier: id, content: content, trigger: nil)
                try? await UNUserNotificationCenter.current().add(notification)
            }
        } catch {
            self.error = "Источник пока недоступен. Проверь соединение."
        }
        await checkModules()
    }

    func checkModules() async {
        let address = UserDefaults.standard.string(forKey: "modulesFeed") ?? ""
        guard !address.isEmpty else {
            modules = []
            return
        }
        guard let url = URL(string: address), url.scheme == "https" else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            modules = try JSONDecoder().decode(OporaModules.self, from: data).modules.filter {
                URL(string: $0.url)?.scheme == "https"
            }
        } catch { }
    }
}

@main
struct OporaApp: App {
    @StateObject private var data = OporaData()
    var body: some Scene {
        WindowGroup {
            OporaTabs()
                .environmentObject(data)
                .onOpenURL { url in
                    if url.scheme == "opora" { data.tab = 1 }
                }
        }
    }
}

struct OporaTabs: View {
    @EnvironmentObject private var data: OporaData
    @Environment(\.scenePhase) private var phase
    var body: some View {
        TabView(selection: $data.tab) {
            NavigationStack { OporaHome() }
                .tabItem { Label("Главная", systemImage: "house.fill") }
                .tag(0)
            NavigationStack { PS4Page() }
                .tabItem { Label("PS4", systemImage: "gamecontroller.fill") }
                .tag(1)
            NavigationStack { ModulesPage() }
                .tabItem { Label("Разделы", systemImage: "square.grid.2x2.fill") }
                .tag(2)
            NavigationStack { OptionsPage() }
                .tabItem { Label("Настройки", systemImage: "gearshape.fill") }
                .tag(3)
        }
        .tint(.indigo)
        .task { await data.check() }
        .onChange(of: phase) { value in
            if value == .active { Task { await data.check() } }
        }
    }
}

struct OporaHome: View {
    @EnvironmentObject private var data: OporaData
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .font(.system(size: 42))
                        .foregroundStyle(.indigo)
                    Text("Твоя личная лаборатория")
                        .font(.title2.bold())
                    Text("Эксперименты, новости и будущие функции в одном месте.")
                        .foregroundStyle(.secondary)
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.indigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 23))

                Button { data.tab = 1 } label: {
                    HStack(spacing: 15) {
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.indigo)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("PS4 14.00").font(.headline)
                            Text(data.status?.state == "released" ? "Релиз подтверждён" : "Ожидаем джейлбрейк")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .padding(18)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                }
                .buttonStyle(.plain)
                Text("Другие возможности добавим позже.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Опора")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { Task { await data.check() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
    }
}

struct PS4Page: View {
    @EnvironmentObject private var data: OporaData
    @Environment(\.openURL) private var openURL
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                HStack(spacing: 13) {
                    Image(systemName: data.status?.state == "released" ? "checkmark.seal.fill" : "clock.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(data.status?.state == "released" ? .green : .orange)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(data.status?.state == "released" ? "Релиз подтверждён" : "Ожидаем подтверждение")
                            .font(.headline)
                        Text("PlayStation 4 · прошивка 14.00")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                if let error = data.error {
                    Label(error, systemImage: "wifi.exclamationmark")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                if data.status?.state == "released", let release = data.status?.release {
                    VStack(alignment: .leading, spacing: 15) {
                        Text(release.title ?? "Джейлбрейк PS4 14.00")
                            .font(.title3.bold())
                        if let published = release.published_at, !published.isEmpty {
                            Text("Дата: " + published)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let instruction = release.instructions, !instruction.isEmpty {
                            Text("Инструкция").font(.headline)
                            Text(instruction).textSelection(.enabled)
                        }
                        resource("Оригинальный релиз", release.source_url, "link")
                        resource("Скачать джейлбрейк", release.download_url, "arrow.down.circle")
                        resource("Видео", release.video_url, "play.rectangle")
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                } else {
                    Text("Когда подтвердится настоящий общедоступный джейлбрейк 14.00, здесь появятся источник, скачивание, инструкция и видео.")
                        .foregroundStyle(.secondary)
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                }
                Button { Task { await data.check() } } label: {
                    if data.busy { ProgressView() }
                    else { Label("Проверить статус", systemImage: "arrow.clockwise") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(data.busy)
                if let checked = data.status?.last_checked_at {
                    Text("Проверка: " + checked)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(18)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("PS4 14.00")
        .refreshable { await data.check() }
    }
    @ViewBuilder
    func resource(_ title: String, _ link: String?, _ symbol: String) -> some View {
        if let link, let url = URL(string: link), url.scheme == "https" {
            Button { openURL(url) } label: {
                Label(title, systemImage: symbol)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
        }
    }
}

struct ModulesPage: View {
    @EnvironmentObject private var data: OporaData
    var body: some View {
        List {
            if data.modules.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "square.grid.2x2")
                        .font(.largeTitle).foregroundStyle(.secondary)
                    Text("Пока нет разделов")
                        .font(.headline)
                    Text("Новые эксперименты появятся здесь.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(30)
            } else {
                ForEach(data.modules) { item in
                    NavigationLink(destination: ModuleBrowser(url: item.url).navigationTitle(item.title)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title).font(.headline)
                            if let description = item.description {
                                Text(description).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Эксперименты")
        .refreshable { await data.checkModules() }
    }
}

struct ModuleBrowser: UIViewRepresentable {
    let url: String
    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView()
        if let link = URL(string: url), link.scheme == "https" {
            view.load(URLRequest(url: link))
        }
        return view
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct OptionsPage: View {
    @EnvironmentObject private var data: OporaData
    @AppStorage("feed") private var feed = OporaData.defaultFeed
    @AppStorage("modulesFeed") private var modulesFeed = ""
    @AppStorage("localAlerts") private var localAlerts = false
    var body: some View {
        Form {
            Section("Уведомления") {
                Toggle("Локальные уведомления", isOn: $localAlerts)
                    .onChange(of: localAlerts) { enabled in
                        if enabled {
                            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                                if !granted {
                                    DispatchQueue.main.async { localAlerts = false }
                                }
                            }
                        }
                    }
                Text("При бесплатной подписи Sideloadly удалённые push-уведомления не подключены. Данные проверяются при открытии приложения.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Источник новостей") {
                TextField("Ссылка status.json", text: $feed)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Button("Проверить источник") { Task { await data.check() } }
            }
            Section("Эксперименты") {
                TextField("Адрес modules.json", text: $modulesFeed)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Button("Обновить разделы") { Task { await data.checkModules() } }
            }
            Section("Опора") {
                LabeledContent("Версия", value: "1.0")
                Text("Новости и веб-разделы обновляются через интернет. Изменения нативного кода требуют новой IPA.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Настройки")
    }
}
