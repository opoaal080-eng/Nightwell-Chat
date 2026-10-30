import Foundation
import SwiftUI
import Security

struct Person: Codable, Identifiable, Hashable {
    let id: Int
    let username: String
    let display_name: String
    let has_avatar: Bool?
}
struct AuthResponse: Decodable {
    let access_token: String
    let user: Person
}
struct LastMessage: Decodable, Hashable {
    let id: Int
    let body: String
    let sender_id: Int
    let created_at: String
}
struct Conversation: Decodable, Identifiable, Hashable {
    let id: Int
    let kind: String
    let title: String
    let other_user: Person?
    let owner_id: Int?
    let unread: Int
    let last_message: LastMessage?
}
struct Reaction: Decodable, Identifiable {
    let emoji: String
    let count: Int
    var id: String { emoji }
}
struct ChatAttachment: Decodable, Identifiable {
    let id: Int
    let filename: String
    let content_type: String
    let byte_size: Int
}
struct ChatMessage: Decodable, Identifiable {
    let id: Int
    let chat_id: Int
    let sender_id: Int
    let sender_name: String
    let body: String
    let reply_to: Int?
    let created_at: String
    let edited_at: String?
    let deleted: Int
    let reactions: [Reaction]
    let attachment: ChatAttachment?
}
struct EmptyResult: Decodable { let ok: Bool }
struct ErrorResponse: Decodable { let detail: String? }
struct LoginPayload: Encodable { let username: String; let password: String }
struct RegisterPayload: Encodable { let username: String; let password: String; let display_name: String }
struct MessagePayload: Encodable { let body: String; let reply_to: Int? }
struct GroupPayload: Encodable { let title: String; let user_ids: [Int] }
struct ReactionPayload: Encodable { let emoji: String }
struct ReadPayload: Encodable { let message_id: Int }
struct ProfilePayload: Encodable { let display_name: String }
struct PhonePasswordPayload: Encodable { let phone: String; let password: String }
struct PhoneRegistrationPayload: Encodable {
    let phone: String
    let password: String
    let display_name: String
    let discoverable: Bool
}
struct PhoneLinkPayload: Encodable { let phone: String; let password: String; let discoverable: Bool }
struct PhoneStatus: Decodable { let phone: String?; let discoverable: Bool }
struct PhoneVisibilityPayload: Encodable { let discoverable: Bool }


private enum SecureToken {
    static let account = "nightwell.chat.session"
    static func load() -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account, kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func save(_ value: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
             kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        if !value.isEmpty {
            var attrs = query
            attrs[kSecValueData as String] = Data(value.utf8)
            attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(attrs as CFDictionary, nil)
        }
    }
}

enum NetworkError: LocalizedError {
    case invalidURL, unauthorized, server(String)
    var errorDescription: String? {
        switch self {
        case .invalidURL: "Проверь адрес сервера (HTTPS)"
        case .unauthorized: "Сессия истекла, войди заново"
        case .server(let text): text
        }
    }
}

@MainActor final class ChatStore: ObservableObject {
    @Published var token: String = SecureToken.load()
    @Published var me: Person?
    @Published var chats: [Conversation] = []
    @Published var eventVersion = 0
    @Published var alertText = ""
    @Published var loading = false
    @Published var phoneStatus: PhoneStatus?
    @Published var serverURL = UserDefaults.standard.string(forKey: "nightwell.server") ?? "https://chat.nightwell.fun"
    private var socket: URLSessionWebSocketTask?
    private var socketJob: Task<Void, Never>?

    private func url(_ path: String) throws -> URL {
        guard let host = URL(string: serverURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              host.scheme == "https", host.host != nil,
              let url = URL(string: path, relativeTo: host)?.absoluteURL else { throw NetworkError.invalidURL }
        return url
    }

    func request<T: Decodable>(_ path: String, method: String = "GET", body: (any Encodable)? = nil, authenticated: Bool = true) async throws -> T {
        var req = URLRequest(url: try url(path))
        req.httpMethod = method
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if authenticated { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            req.httpBody = try JSONEncoder().encode(AnyEncodable(body))
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw NetworkError.server("Нет ответа сервера") }
        if !(200..<300).contains(http.statusCode) {
            let detail = (try? JSONDecoder().decode(ErrorResponse.self, from: data).detail) ?? "HTTP \(http.statusCode)"
            if http.statusCode == 401 && authenticated { throw NetworkError.unauthorized }
            throw NetworkError.server(detail)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func protectedData(_ path: String) async throws -> Data {
        var req = URLRequest(url: try url(path))
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NetworkError.server("Не удалось загрузить файл")
        }
        return data
    }

    private func multipart(_ path: String, data: Data, filename: String, mime: String) async throws -> Data {
        let marker = "NW-\(UUID().uuidString)"
        var req = URLRequest(url: try url(path))
        req.httpMethod = "POST"
        req.timeoutInterval = 90
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(marker)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        // File name is normalized by the server as well.
        body = Data("--\(marker)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(filename.replacingOccurrences(of: "\"", with: "_"))\"\r\nContent-Type: \(mime)\r\n\r\n".utf8)
        body.append(data)
        body.append(Data("\r\n--\(marker)--\r\n".utf8))
        req.httpBody = body
        let (result, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw NetworkError.server("Нет ответа") }
        guard (200..<300).contains(http.statusCode) else {
            let detail = (try? JSONDecoder().decode(ErrorResponse.self, from: result).detail) ?? "HTTP \(http.statusCode)"
            throw NetworkError.server(detail)
        }
        return result
    }
    func setAvatar(_ data: Data) async {
        do {
            let _: EmptyResult = try JSONDecoder().decode(EmptyResult.self, from: try await multipart("/me/avatar", data:data, filename:"avatar.jpg", mime:"image/jpeg"))
            me = try await request("/me")
            eventVersion += 1
        } catch { alertText = error.localizedDescription }
    }
    func removeAvatar() async {
        do {
            let _: EmptyResult = try await request("/me/avatar", method:"DELETE")
            me = try await request("/me")
            eventVersion += 1
        } catch { alertText = error.localizedDescription }
    }
    func upload(chatID: Int, data: Data, filename: String, mime: String) async -> Bool {
        do {
            let result = try await multipart("/chats/\(chatID)/attachments", data:data, filename:filename, mime:mime)
            _ = try JSONDecoder().decode(ChatMessage.self, from:result)
            eventVersion += 1
            return true
        } catch { alertText = error.localizedDescription; return false }
    }
    func download(_ attachment: ChatAttachment) async -> URL? {
        do {
            let data = try await protectedData("/attachments/\(attachment.id)")
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("NWChat-\(UUID().uuidString)",isDirectory:true)
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            let name = URL(fileURLWithPath: attachment.filename).lastPathComponent
            let destination = folder.appendingPathComponent(name)
            try data.write(to:destination,options:.atomic)
            return destination
        } catch { alertText = error.localizedDescription; return nil }
    }

    func bootstrap() async {
        guard !token.isEmpty else { return }
        do {
            me = try await request("/me")
            await reloadChats()
            startSocket()
        } catch NetworkError.unauthorized { logout() }
        catch { alertText = error.localizedDescription }
    }

    func login(username: String, password: String, displayName: String? = nil) async {
        loading = true
        defer { loading = false }
        do {
            let result: AuthResponse
            if let displayName {
                result = try await request("/auth/register", method: "POST", body: RegisterPayload(username: username, password: password, display_name: displayName), authenticated: false)
            } else {
                result = try await request("/auth/login", method: "POST", body: LoginPayload(username: username, password: password), authenticated: false)
            }
            token = result.access_token
            SecureToken.save(token)
            me = result.user
            await reloadChats()
            startSocket()
        } catch { alertText = error.localizedDescription }
    }

    func loginByPhone(_ phone: String, password: String, displayName: String?, discoverable: Bool = false) async -> Bool {
        loading = true
        defer { loading = false }
        do {
            let result: AuthResponse
            if let displayName {
                result = try await request("/auth/phone/register", method: "POST",
                    body: PhoneRegistrationPayload(phone: phone, password: password,
                        display_name: displayName, discoverable: discoverable), authenticated: false)
            } else {
                result = try await request("/auth/phone/login", method: "POST",
                    body: PhonePasswordPayload(phone: phone, password: password), authenticated: false)
            }
            token = result.access_token
            SecureToken.save(token)
            me = result.user
            await reloadChats()
            startSocket()
            return true
        } catch { alertText = error.localizedDescription; return false }
    }

    func linkPhone(_ phone: String, password: String, discoverable: Bool) async -> Bool {
        loading = true
        defer { loading = false }
        do {
            let _: EmptyResult = try await request("/me/phone/link", method: "POST",
                body: PhoneLinkPayload(phone: phone, password: password, discoverable: discoverable))
            await loadPhoneStatus()
            return true
        } catch { alertText = error.localizedDescription; return false }
    }

    func loadPhoneStatus() async {
        guard !token.isEmpty else { return }
        do { phoneStatus = try await request("/me/phone") }
        catch { alertText = error.localizedDescription }
    }

    func setDiscoverable(_ value: Bool) async {
        do {
            let _: EmptyResult = try await request("/me/phone/visibility", method: "PATCH",
                body: PhoneVisibilityPayload(discoverable: value))
            await loadPhoneStatus()
        } catch { alertText = error.localizedDescription }
    }

    func findByPhone(_ phone: String) async -> Person? {
        guard let escaped = phone.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "+&=?#"))) else { return nil }
        do {
            let result: Person? = try await request("/users/by-phone?phone=\(escaped)")
            return result
        } catch { alertText = error.localizedDescription; return nil }
    }

    func logout() {
        socketJob?.cancel()
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        socketJob = nil
        token = ""
        SecureToken.save("")
        chats = []
        me = nil
        phoneStatus = nil
    }

    func reloadChats() async {
        do { chats = try await request("/chats") }
        catch { alertText = error.localizedDescription }
    }
    func find(_ query: String) async -> [Person] {
        guard !query.isEmpty, let escaped = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return [] }
        do { return try await request("/users?q=\(escaped)") }
        catch { alertText = error.localizedDescription; return [] }
    }
    func openDirect(_ person: Person) async -> Conversation? {
        do {
            let chat: Conversation = try await request("/chats/direct/\(person.id)",method: "POST")
            await reloadChats()
            return chat
        } catch { alertText = error.localizedDescription; return nil }
    }
    func createGroup(title: String, users: [Int]) async -> Conversation? {
        do {
            let chat: Conversation = try await request("/chats/groups",method: "POST",body: GroupPayload(title: title,user_ids: users))
            await reloadChats()
            return chat
        } catch { alertText = error.localizedDescription; return nil }
    }
    func messages(_ chatID: Int, before: Int? = nil) async -> [ChatMessage] {
        do { return try await request("/chats/\(chatID)/messages" + (before.map { "?before=\($0)" } ?? "")) }
        catch { alertText = error.localizedDescription; return [] }
    }
    func send(_ chatID: Int, text: String, reply: Int? = nil) async -> ChatMessage? {
        do { return try await request("/chats/\(chatID)/messages",method: "POST",body: MessagePayload(body: text,reply_to: reply)) }
        catch { alertText = error.localizedDescription; return nil }
    }
    func edit(_ messageID: Int, text: String) async {
        do { let _: ChatMessage = try await request("/messages/\(messageID)",method: "PATCH",body: MessagePayload(body: text,reply_to: nil)) }
        catch { alertText = error.localizedDescription }
    }
    func delete(_ messageID: Int) async {
        do { let _: EmptyResult = try await request("/messages/\(messageID)",method: "DELETE") }
        catch { alertText = error.localizedDescription }
    }
    func react(_ messageID: Int, emoji: String) async {
        do { let _: ChatMessage = try await request("/messages/\(messageID)/reactions",method: "POST",body: ReactionPayload(emoji: emoji)) }
        catch { alertText = error.localizedDescription }
    }
    func markRead(chatID: Int, messageID: Int) async {
        do { let _: EmptyResult = try await request("/chats/\(chatID)/read",method: "POST",body: ReadPayload(message_id: messageID)) }
        catch { /* non-critical */ }
    }
    func saveProfile(_ name: String) async {
        do { me = try await request("/me",method: "PATCH",body: ProfilePayload(display_name: name)) }
        catch { alertText = error.localizedDescription }
    }
    func saveServer(_ value: String) {
        guard let parsed = URL(string:value), parsed.scheme == "https", parsed.host != nil else {
            alertText = "Адрес должен начинаться с https://"; return
        }
        serverURL = value.trimmingCharacters(in:.whitespacesAndNewlines).trimmingCharacters(in:CharacterSet(charactersIn:"/"))
        UserDefaults.standard.set(serverURL,forKey:"nightwell.server")
        logout()
    }

    private func startSocket() {
        socketJob?.cancel()
        socket?.cancel(with: .normalClosure, reason: nil)
        socketJob = Task { [weak self] in
            while let self, !Task.isCancelled, !self.token.isEmpty {
                do {
                    var req = URLRequest(url: try self.url("/ws"))
                    req.url = URL(string: req.url!.absoluteString.replacingOccurrences(of: "https://", with: "wss://"))
                    req.setValue("Bearer \(self.token)",forHTTPHeaderField:"Authorization")
                    let ws = URLSession.shared.webSocketTask(with:req)
                    self.socket = ws
                    ws.resume()
                    while !Task.isCancelled {
                        let response = try await ws.receive()
                        if case .string(let message) = response, message.contains("\"type\"") {
                            self.eventVersion += 1
                        }
                    }
                } catch { /* reconnect */ }
                if Task.isCancelled { break }
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }
}

private struct AnyEncodable: Encodable {
    let encodeValue: (Encoder) throws -> Void
    init(_ value: any Encodable) { self.encodeValue = value.encode }
    func encode(to encoder: Encoder) throws { try encodeValue(encoder) }
}
