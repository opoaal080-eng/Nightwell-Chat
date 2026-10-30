import SwiftUI
import UserNotifications
import UIKit

struct AdminEvent: Codable, Identifiable {
    let id: Int
    let created_at: String
    let service: String
    let kind: String
    let severity: String
    let title: String
    let message: String
}

struct AdminEventsEnvelope: Decodable {
    let events: [AdminEvent]
}

struct AdminPushStatus: Decodable {
    let configured: Bool
    let devices: Int
    let last_error: String
}

@MainActor final class AdminPushManager: ObservableObject {
    static let shared = AdminPushManager()
    @Published var statusText = "Уведомления не настроены"
    @Published var authorized = false
    @Published var apnsRegistered = false
    @Published var pushBackendReady = false

    // Device tokens must be refreshed from APNs, not saved or hard-coded.
    private var currentDeviceToken: String?

    private init() {}

    func resume(endpoint: String, authToken: String) async {
        guard UserDefaults.standard.bool(forKey: "nightwell.admin.pushEnabled") else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorized = (settings.authorizationStatus == .authorized ||
                      settings.authorizationStatus == .provisional)
        if authorized {
            UIApplication.shared.registerForRemoteNotifications()
            await sync(endpoint: endpoint, authToken: authToken)
        }
    }

    func enable(endpoint: String, authToken: String) async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            authorized = granted
            UserDefaults.standard.set(granted, forKey: "nightwell.admin.pushEnabled")
            if granted {
                statusText = "Разрешение получено. Регистрируем iPhone в APNs."
                UIApplication.shared.registerForRemoteNotifications()
                await sync(endpoint: endpoint, authToken: authToken)
            } else {
                statusText = "Уведомления запрещены в настройках iPhone."
            }
        } catch {
            statusText = "Не удалось разрешить уведомления: \(error.localizedDescription)"
        }
    }

    func didReceiveToken(_ data: Data) async {
        currentDeviceToken = data.map { String(format: "%02x", $0) }.joined()
        apnsRegistered = true
        statusText = "Токен APNs получен. Требуется подключение Windows-моста."
        let endpoint = UserDefaults.standard.string(forKey: "nightwell.admin.endpoint")
            ?? "https://admin.nightwell.fun"
        await sync(endpoint: endpoint, authToken: TokenVault.read())
        // Do not log, persist, or display the device token.
    }

    func failedToRegister(_ error: Error) {
        apnsRegistered = false
        statusText = "APNs недоступен: \(error.localizedDescription). Проверь подпись Push Notifications."
    }

    private func request(_ path: String, endpoint: String,
                         authToken: String, method: String,
                         body: [String: String]? = nil) throws -> URLRequest {
        let address = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = authToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: address),
              url.scheme == "https", url.host != nil, !secret.isEmpty else {
            throw NSError(domain: "NightwellPush", code: 1,
                          userInfo: [NSLocalizedDescriptionKey:
                            "Укажи HTTPS-адрес и административный ключ в разделе подключения."])
        }
        var req = URLRequest(url: url.appendingPathComponent(path))
        req.httpMethod = method
        req.timeoutInterval = 15
        req.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return req
    }

    func sync(endpoint: String, authToken: String) async {
        guard authorized else { return }
        guard let currentDeviceToken else {
            statusText = "Получаем токен APNs от Apple."
            return
        }
        do {
            let req = try request("v1/push/register", endpoint: endpoint,
                                  authToken: authToken, method: "POST",
                                  body: ["token": currentDeviceToken])
            let (_, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                statusText = "Windows-мост ещё не поддерживает регистрацию push или ключ неверен."
                return
            }
            let statusRequest = try request("v1/push/status", endpoint: endpoint,
                                            authToken: authToken, method: "GET")
            let (data, _) = try await URLSession.shared.data(for: statusRequest)
            let status = try JSONDecoder().decode(AdminPushStatus.self, from: data)
            pushBackendReady = status.configured
            statusText = status.configured
                ? "Push подключены. Устройств: \(status.devices)"
                : "iPhone зарегистрирован. Для фоновых push нужен ключ APNs на Windows."
        } catch {
            statusText = "Нет подключения к push-серверу: \(error.localizedDescription)"
        }
    }

    func sendTest(endpoint: String, authToken: String) async {
        do {
            let req = try request("v1/push/test", endpoint: endpoint,
                                  authToken: authToken, method: "POST")
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                let msg = String(data: data, encoding: .utf8) ?? ""
                statusText = "Тест не отправлен: \(String(msg.prefix(180)))"
                return
            }
            statusText = "Проверочный push отправлен в очередь APNs."
        } catch {
            statusText = "Ошибка теста: \(error.localizedDescription)"
        }
    }

    func localWarning(title: String, message: String) {
        guard UserDefaults.standard.object(forKey: "nightwell.admin.alerts") as? Bool ?? true
        else { return }
        // When a remote push is configured, avoid double-notifying the same foreground event.
        if apnsRegistered && pushBackendReady &&
            UserDefaults.standard.bool(forKey: "nightwell.admin.pushEnabled") {
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }
}

final class AdminNotificationDelegate: NSObject, UIApplicationDelegate,
                                        UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in
            await AdminPushManager.shared.didReceiveToken(deviceToken)
        }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in
            AdminPushManager.shared.failedToRegister(error)
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}

struct AdminEventsScreen: View {
    @EnvironmentObject var model: AdminModel

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if model.events.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "bell.badge")
                            .font(.system(size: 35))
                        Text("Событий пока нет")
                        Text("После установки Nightwell Admin Bridge здесь появятся сбои, восстановления, предупреждения о задержке и история команд.")
                            .font(.caption).multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.white.opacity(0.62))
                    .padding(30)
                }
                ForEach(model.events) { event in
                    AdminGlassCard {
                        HStack(spacing: 10) {
                            Image(systemName: event.kind == "outage" ? "exclamationmark.triangle.fill"
                                  : event.kind == "recovered" ? "checkmark.circle.fill" : "bell.fill")
                                .foregroundStyle(event.severity == "critical" ? .red
                                                : event.severity == "warning" ? .orange : .green)
                            Text(event.title).font(.system(size: 14, weight: .semibold))
                            Spacer()
                        }
                        Text(event.message)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.72))
                        HStack {
                            Text(event.service.uppercased())
                            Spacer()
                            Text(String(event.created_at.replacingOccurrences(of: "T", with: " ").prefix(19)))
                        }
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.46))
                    }
                }
            }
            .padding(16)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("События серверов")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.refreshEvents() }
        .refreshable { await model.refreshEvents() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await model.refreshEvents() } }
                    label: { Image(systemName: "arrow.clockwise") }
            }
        }
    }
}
