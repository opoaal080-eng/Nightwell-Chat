import SwiftUI
import Foundation
import Security
import Charts

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

struct ProbeSample: Identifiable {
    let id = UUID()
    let time: Date
    let ms: Int
}

struct ProbeStatus {
    let available: Bool
    let statusText: String
    // Network TTFB excludes initial DNS, TCP, and TLS setup.
    let ttfbMs: Int?
    // Entire HTTPS request, including connection setup and body transfer.
    let totalMs: Int?
    let dnsMs: Int?
    let tcpMs: Int?
    let tlsMs: Int?
    let reusedConnection: Bool
    let checkedAt: Date
}

// URLSessionTaskMetrics exposes the actual request phases.
// A shared URLSession allows keep-alive reuse across refreshes.
final class ProbeMetricsCollector: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var latest: URLSessionTaskMetrics?

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didFinishCollecting metrics: URLSessionTaskMetrics) {
        lock.lock()
        latest = metrics
        lock.unlock()
    }

    func take() -> URLSessionTaskMetrics? {
        lock.lock()
        defer { lock.unlock() }
        return latest
    }
}

private func durationMs(_ start: Date?, _ end: Date?) -> Int? {
    guard let start, let end else { return nil }
    return max(0, Int(end.timeIntervalSince(start) * 1000))
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
    @Published var history: [AdminService: [ProbeSample]] = [:]
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
        // Prevent intermediate caches from presenting a cached response as a network sample.
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let collector = ProbeMetricsCollector()
        let start = Date()
        do {
            let (_, response) = try await URLSession.shared.data(for: request, delegate: collector)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            let ok = (200..<400).contains(http.statusCode)
            let total = max(0, Int(Date().timeIntervalSince(start) * 1000))
            let network = collector.take()?.transactionMetrics.last
            let ttfb = durationMs(network?.requestStartDate, network?.responseStartDate)
            let wasOnline = probes[service]?.available == true
            probes[service] = ProbeStatus(
                available: ok,
                statusText: ok ? "Доступен" : "HTTP \(http.statusCode)",
                ttfbMs: ttfb,
                totalMs: total,
                dnsMs: durationMs(network?.domainLookupStartDate, network?.domainLookupEndDate),
                tcpMs: durationMs(network?.connectStartDate, network?.connectEndDate),
                tlsMs: durationMs(network?.secureConnectionStartDate, network?.secureConnectionEndDate),
                reusedConnection: network?.isReusedConnection ?? false,
                checkedAt: Date()
            )
            if ok {
                var samples = history[service, default: []]
                samples.append(ProbeSample(time: Date(), ms: total))
                history[service] = Array(samples.suffix(80))
            } else if wasOnline && (UserDefaults.standard.object(forKey: "nightwell.admin.alerts") as? Bool ?? true) {
                notice = "\(service.name): сервер начал возвращать HTTP \(http.statusCode)."
            }
        } catch {
            let wasOnline = probes[service]?.available == true
            probes[service] = ProbeStatus(
                available: false,
                statusText: error.localizedDescription,
                ttfbMs: nil,
                totalMs: max(0, Int(Date().timeIntervalSince(start) * 1000)),
                dnsMs: nil, tcpMs: nil, tlsMs: nil,
                reusedConnection: false,
                checkedAt: Date()
            )
            if wasOnline && (UserDefaults.standard.object(forKey: "nightwell.admin.alerts") as? Bool ?? true) {
                notice = "\(service.name): соединение потеряно. \(error.localizedDescription)"
            }
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
    @AppStorage("nightwell.admin.autorefresh") private var autoRefresh = true
    var body: some Scene {
        WindowGroup {
            ZStack {
                Color.black.ignoresSafeArea()
                TabView {
                    NavigationStack { AdminServiceScreen(service: .music) }
                        .tabItem { Label("Музыка", systemImage: "music.note") }
                    NavigationStack { AdminServiceScreen(service: .chat) }
                        .tabItem { Label("Чат", systemImage: "message.fill") }
                    NavigationStack { AdminSettingsScreen() }
                        .tabItem { Label("Настройки", systemImage: "gearshape.fill") }
                }
                .toolbarBackground(.visible, for: .tabBar)
                .toolbarBackground(Color.black.opacity(0.93), for: .tabBar)
            }
            .environmentObject(model)
            .tint(.white)
            .preferredColorScheme(.dark)
            .task {
                await model.refreshAll()
                while !Task.isCancelled {
                    let interval = max(1, UserDefaults.standard.integer(forKey: "nightwell.admin.refreshminutes"))
                    try? await Task.sleep(for: .seconds(Double(interval * 60)))
                    if Task.isCancelled { break }
                    if autoRefresh { await model.refreshAll() }
                }
            }
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

