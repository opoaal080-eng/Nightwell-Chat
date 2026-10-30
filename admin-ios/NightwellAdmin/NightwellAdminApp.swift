import SwiftUI
import Foundation
import Security

enum AdminService: String, CaseIterable, Identifiable {
    case music, chat
    var id: String { rawValue }
    var name: String { self == .music ? "Nightwell Music" : "Nightwell Chat" }
    var symbol: String { self == .music ? "music.note.list" : "bubble.left.and.bubble.right" }
    var publicURL: URL {
        URL(string: self == .music ? "https://music.nightwell.fun" : "https://chat.nightwell.fun/health")!
    }
    var browserURL: URL {
        URL(string: self == .music ? "https://music.nightwell.fun" : "https://chat.nightwell.fun/docs")!
    }
    var port: Int { self == .music ? 8080 : 8009 }
}

struct ProbeStatus {
    let available: Bool
    let statusText: String
    let latencyMs: Int?
    let checkedAt: Date
}

struct RemoteService: Codable {
    let running: Bool
    let can_start: Bool
    let can_stop: Bool
    let can_restart: Bool
    let can_backup: Bool
    let can_update: Bool
    let local_port: Int
    let public_url: String
}

struct AdminStatus: Decodable {
    let version: String
    let services: [String: RemoteService]
}

struct AdminActionResult: Decodable {
    let ok: Bool
    let message: String
}

struct AdminLogResult: Decodable {
    let lines: [String]
}

enum TokenVault {
    private static let account = "nightwell.admin.token"
    static func read() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var object: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &object) == errSecSuccess,
              let bytes = object as? Data,
              let value = String(data: bytes, encoding: .utf8) else { return "" }
        return value
    }
    static func write(_ value: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var attrs = query
        attrs[kSecValueData as String] = Data(value.utf8)
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attrs as CFDictionary, nil)
    }
}

@MainActor final class AdminModel: ObservableObject {
    @Published var probes: [AdminService: ProbeStatus] = [:]
    @Published var admin: AdminStatus?
    @Published var adminError = ""
    @Published var notice = ""
    @Published var loading = false
    @Published var logText = ""
    @Published var showLogs = false
    @Published var endpoint: String {
        didSet {
            UserDefaults.standard.set(endpoint, forKey: "nightwell.admin.endpoint")
            admin = nil
        }
    }
    @Published var token: String {
        didSet {
            TokenVault.write(token.trimmingCharacters(in: .whitespacesAndNewlines))
            admin = nil
        }
    }

    init() {
        endpoint = UserDefaults.standard.string(forKey: "nightwell.admin.endpoint") ?? "https://admin.nightwell.fun"
        token = TokenVault.read()
    }

    func probe(_ service: AdminService) async {
        var request = URLRequest(url: service.publicURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 9
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let start = Date()
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            let ok = (200..<400).contains(http.statusCode)
            let time = Int(Date().timeIntervalSince(start) * 1000)
            probes[service] = ProbeStatus(available: ok, statusText: ok ? "Доступен" : "HTTP \(http.statusCode)",
                                            latencyMs: time, checkedAt: Date())
        } catch {
            probes[service] = ProbeStatus(available: false,
                                           statusText: error.localizedDescription, latencyMs: nil, checkedAt: Date())
        }
    }

    func refreshAll() async {
        async let music: Void = probe(.music)
        async let chat: Void = probe(.chat)
        _ = await (music, chat)
        await refreshAdmin()
    }

    func refreshAdmin() async {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            admin = nil
            adminError = "Укажи адрес и ключ управления в настройках."
            return
        }
        do {
            let req = try authorizedRequest("v1/status")
            let (data, response) = try await URLSession.shared.data(for: req)
            try checkResponse(response, data)
            admin = try JSONDecoder().decode(AdminStatus.self, from: data)
            adminError = ""
        } catch {
            admin = nil
            adminError = error.localizedDescription
        }
    }

    private func authorizedRequest(_ path: String, method: String = "GET") throws -> URLRequest {
        let address = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let base = URL(string: address),
              base.scheme == "https", base.host != nil, base.user == nil,
              base.password == nil else {
            throw NSError(domain: "Nightwell", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Для управления нужен адрес HTTPS."])
        }
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = method
        req.timeoutInterval = 25
        req.setValue("Bearer \(token.trimmingCharacters(in: .whitespacesAndNewlines))",
                     forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        return req
    }

    private func checkResponse(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            let summary = String(data: data, encoding: .utf8) ?? ""
            let message: String
            if http.statusCode == 401 { message = "Неверный ключ администратора." }
            else if http.statusCode == 409 { message = "Действие не настроено на сервере." }
            else { message = "HTTP \(http.statusCode): \(String(summary.prefix(150)))" }
            throw NSError(domain: "Nightwell", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    func run(_ action: String, for service: AdminService) async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let req = try authorizedRequest("v1/services/\(service.rawValue)/\(action)", method: "POST")
            let (data, response) = try await URLSession.shared.data(for: req)
            try checkResponse(response, data)
            let result = try JSONDecoder().decode(AdminActionResult.self, from: data)
            notice = result.message
            await refreshAdmin()
            await probe(service)
        } catch { notice = error.localizedDescription }
    }

    func loadLogs(_ service: AdminService) async {
        do {
            let req = try authorizedRequest("v1/services/\(service.rawValue)/logs")
            let (data, response) = try await URLSession.shared.data(for: req)
            try checkResponse(response, data)
            let result = try JSONDecoder().decode(AdminLogResult.self, from: data)
            logText = result.lines.isEmpty ? "Лог пока пуст." : result.lines.joined(separator: "\n")
            showLogs = true
        } catch { notice = error.localizedDescription }
    }
}

@main struct NightwellAdminApp: App {
    @StateObject private var model = AdminModel()
    var body: some Scene {
        WindowGroup {
            TabView {
                NavigationStack { ServiceScreen(service: .music) }
                    .tabItem { Label("Музыка", systemImage: "music.note") }
                NavigationStack { ServiceScreen(service: .chat) }
                    .tabItem { Label("Чат", systemImage: "message") }
                NavigationStack { AdminSettingsScreen() }
                    .tabItem { Label("Настройки", systemImage: "gearshape") }
            }
            .environmentObject(model)
            .tint(.white)
            .preferredColorScheme(.dark)
            .task { await model.refreshAll() }
            .alert("Nightwell Admin",
                   isPresented: Binding(get: { !model.notice.isEmpty },
                                        set: { if !$0 { model.notice = "" } })) {
                Button("ОК") { model.notice = "" }
            } message: {
                Text(model.notice)
            }
            .sheet(isPresented: $model.showLogs) {
                NavigationStack {
                    ScrollView {
                        Text(model.logText)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled).padding()
                    }
                    .navigationTitle("Логи сервера")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Готово") { model.showLogs = false }
                        }
                    }
                }
                .preferredColorScheme(.dark)
            }
        }
    }
}

struct AdminPanel<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) { content }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(white: 0.10), in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.10)))
    }
}

struct ServiceScreen: View {
    @EnvironmentObject var model: AdminModel
    let service: AdminService
    @State private var pendingAction: String?
    @State private var confirmAction = false

    private var remote: RemoteService? { model.admin?.services[service.rawValue] }
    private var probe: ProbeStatus? { model.probes[service] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    Image(systemName: service.symbol)
                        .font(.system(size: 32, weight: .light))
                        .frame(width: 72, height: 72)
                        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 20))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(service.name).font(.title2.bold())
                        Text("Nightwell • Сервер").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }.padding(.top, 10)

                AdminPanel {
                    Text("ПУБЛИЧНЫЙ СЕРВИС").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Image(systemName: probe?.available == true ? "checkmark.circle.fill" : "exclamationmark.circle")
                            .foregroundStyle(probe?.available == true ? .green : .orange)
                        Text(probe?.statusText ?? "Проверка…")
                            .font(.headline)
                        Spacer()
                        if let ms = probe?.latencyMs {
                            Text("\(ms) мс").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Divider().overlay(.white.opacity(0.1))
                    infoRow("HTTPS", service.publicURL.host ?? "")
                    infoRow("Локальный порт", "\(service.port)")
                    if let date = probe?.checkedAt {
                        infoRow("Проверено", date.formatted(date: .omitted, time: .shortened))
                    }
                    Link(destination: service.browserURL) {
                        Label("Открыть сервис", systemImage: "arrow.up.right")
                            .font(.subheadline.weight(.medium))
                    }
                }

                AdminPanel {
                    Text("УПРАВЛЕНИЕ").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    HStack {
                        Label(model.admin == nil ? "Нет подключения к админ-серверу" :
                                (remote?.running == true ? "Процесс запущен" : "Процесс остановлен"),
                              systemImage: remote?.running == true ? "checkmark.circle" : "info.circle")
                            .font(.subheadline)
                        Spacer()
                    }
                    if model.admin == nil {
                        Text(model.adminError.isEmpty ? "Добавь ключ в настройках для управления." : model.adminError)
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    HStack(spacing: 10) {
                        actionButton("Запустить", symbol: "play.fill", action: "start", enabled: remote?.can_start == true)
                        actionButton("Остановить", symbol: "stop.fill", action: "stop", enabled: remote?.can_stop == true)
                    }
                    actionButton("Перезапустить", symbol: "arrow.clockwise", action: "restart",
                                 enabled: remote?.can_restart == true)
                    actionButton("Создать резервную копию", symbol: "externaldrive", action: "backup",
                                 enabled: remote?.can_backup == true)
                    actionButton("Установить обновление", symbol: "square.and.arrow.down", action: "update",
                                 enabled: remote?.can_update == true)
                    Button {
                        Task { await model.loadLogs(service) }
                    } label: {
                        Label("Посмотреть логи", systemImage: "doc.text")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.admin == nil)
                    Text("Кнопки доступны только для команд, которые заранее разрешены на твоём Windows-сервере.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Button {
                    Task {
                        await model.probe(service)
                        await model.refreshAdmin()
                    }
                } label: {
                    Label("Обновить состояние", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(.black)
            }.padding(18)
        }
        .background(.black)
        .navigationTitle(service == .music ? "Музыка" : "Чат")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await model.probe(service)
            await model.refreshAdmin()
        }
        .confirmationDialog("Подтвердить действие", isPresented: $confirmAction,
                            titleVisibility: .visible) {
            if let action = pendingAction {
                Button(action == "stop" ? "Остановить сервис" :
                        action == "update" ? "Установить обновление" :
                        action == "restart" ? "Перезапустить сервис" :
                        action == "backup" ? "Создать копию" : "Запустить сервис") {
                    Task { await model.run(action, for: service) }
                }
            }
            Button("Отмена", role: .cancel) { pendingAction = nil }
        } message: {
            Text("Действие будет выполнено на Windows-компьютере с Nightwell \(service == .chat ? "Chat" : "Music").")
        }
    }

    private func infoRow(_ caption: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.monospaced()).multilineTextAlignment(.trailing)
        }.font(.subheadline)
    }

    private func actionButton(_ title: String, symbol: String, action: String, enabled: Bool) -> some View {
        Button {
            pendingAction = action
            confirmAction = true
        } label: {
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .disabled(!enabled || model.loading)
    }
}

struct AdminSettingsScreen: View {
    @EnvironmentObject var model: AdminModel
    @State private var showToken = false

    var body: some View {
        Form {
            Section {
                Label("Nightwell Admin", systemImage: "shield.lefthalf.filled")
                    .font(.headline)
                Text("Отдельная панель управления двумя сервисами на твоём Windows-сервере.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section("Подключение к Windows") {
                TextField("https://admin.nightwell.fun", text: $model.endpoint)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                HStack {
                    if showToken {
                        TextField("Административный ключ", text: $model.token)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                    } else {
                        SecureField("Административный ключ", text: $model.token)
                            .textInputAutocapitalization(.never)
                    }
                    Button {
                        showToken.toggle()
                    } label: { Image(systemName: showToken ? "eye.slash" : "eye") }
                }
                Button {
                    Task { await model.refreshAdmin() }
                } label: { Label("Проверить подключение", systemImage: "network") }
                if let admin = model.admin {
                    Label("Админ-сервер подключён, версия \(admin.version)", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if !model.adminError.isEmpty {
                    Text(model.adminError).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Безопасность") {
                Text("Ключ сохраняется в защищённом хранилище iPhone. Управление доступно только через HTTPS и только после установки Nightwell Admin Bridge на Windows.")
                    .font(.footnote)
                Text("Не отправляй ключ в переписку и не публикуй его в GitHub.")
                    .font(.footnote)
            }
            Section("Приложение") {
                LabeledContent("Версия", value: "1.0.0")
                LabeledContent("Сервисы", value: "Music · Chat")
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Настройки")
    }
}
