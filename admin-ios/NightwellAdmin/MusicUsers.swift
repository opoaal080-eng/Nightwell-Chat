import SwiftUI
import Foundation

// All privileged calls go through the existing authenticated Admin Bridge.
// No Music database credentials or direct account mutations live in the IPA.
private struct ManagedMusicUser: Decodable, Identifiable, Hashable {
    let id: String
    let email: String
    let is_admin: Bool
}

private struct ManagedUsersResult: Decodable {
    let users: [ManagedMusicUser]
}

private struct ManagedPremium: Decodable {
    let active: Bool
    let source: String
    let expires_at: Double?
    let grant_active: Bool
    let grant_until: Double?
}

private struct ManagedUserDetail: Decodable {
    let user: ManagedMusicUser
    let premium: ManagedPremium
}

private struct ManagedMutation: Decodable {
    let ok: Bool
}

private enum MusicManagementAction {
    case role(Bool)
    case grant(Int)
    case revokeGrant

    var title: String {
        switch self {
        case .role(true): return "Выдать права администратора?"
        case .role(false): return "Отозвать права администратора?"
        case .grant(0): return "Выдать бессрочный Premium?"
        case .grant(let days): return "Выдать Premium на \(days) дней?"
        case .revokeGrant: return "Отозвать выданный Premium?"
        }
    }

    var destructive: Bool {
        switch self {
        case .role(false), .revokeGrant: return true
        default: return false
        }
    }
}

struct AdminMusicUsersScreen: View {
    @EnvironmentObject private var model: AdminModel
    @State private var query = ""
    @State private var users: [ManagedMusicUser] = []
    @State private var detail: ManagedUserDetail?
    @State private var selectedID: String?
    @State private var days = 30
    @State private var reason = ""
    @State private var busy = false
    @State private var loaded = false
    @State private var errorText = ""
    @State private var notice = ""
    @State private var pendingAction: MusicManagementAction?

    private var selectedUser: ManagedMusicUser? {
        detail?.user
    }

    private var canManage: Bool { model.admin != nil && !model.token.isEmpty }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 17) {
                heading
                searchPanel
                if !errorText.isEmpty {
                    AdminGlassCard {
                        Label(errorText, systemImage: "exclamationmark.triangle")
                            .font(.system(size: 13))
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !notice.isEmpty {
                    AdminGlassCard {
                        Label(notice, systemImage: "checkmark.circle")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.82))
                    }
                }
                if loaded { usersPanel }
                if let current = detail {
                    detailsPanel(current)
                    rolePanel(current)
                    premiumPanel(current)
                }
                Text("Все изменения выполняет сервер Nightwell Music через защищённый Admin Bridge. Отзыв выданного Premium не отменяет оплаченную подписку Lava.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.52))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 5)
            }
            .padding(16)
            .padding(.bottom, 35)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Пользователи музыки")
        .navigationBarTitleDisplayMode(.inline)
        .tint(.white)
        .task { if model.admin == nil { await model.refreshAdmin() } }
        .confirmationDialog(pendingAction?.title ?? "Подтвердить действие",
                            isPresented: Binding(
                                get: { pendingAction != nil },
                                set: { if !$0 { pendingAction = nil } }
                            ), titleVisibility: .visible) {
            if let action = pendingAction {
                Button("Подтвердить", role: action.destructive ? .destructive : nil) {
                    Task { await perform(action) }
                }
            }
            Button("Отмена", role: .cancel) { pendingAction = nil }
        } message: {
            Text("Действие применяется к выбранному аккаунту. Оно будет записано в журнал.")
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 8) {
            AdminEyebrow(text: "Nightwell Music · доступ")
            Text("Управление аккаунтами")
                .font(.system(size: 25, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Text("Ищи зарегистрированного пользователя по почте или ID, затем управляй его ролью и Premium.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.61))
        }
        .padding(.vertical, 5)
    }

    private var searchPanel: some View {
        AdminGlassCard {
            Label("Поиск аккаунта", systemImage: "person.crop.circle.badge.magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
            TextField("Email или ID аккаунта", text: $query)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.emailAddress)
                .submitLabel(.search)
                .onSubmit { Task { await search() } }
                .font(.system(size: 15))
                .padding(13)
                .background(.white.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            Button {
                Task { await search() }
            } label: {
                Label(busy ? "Проверяем…" : "Найти пользователя", systemImage: "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 45)
                    .background(.white.opacity(0.15),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(busy || !canManage || query.trimmingCharacters(in: .whitespacesAndNewlines).count < 3)
            .opacity(busy || !canManage ? 0.48 : 1)
            if !canManage {
                Text("Сначала подключи Admin Bridge в настройках приложения.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
    }

    private var usersPanel: some View {
        AdminGlassCard {
            AdminEyebrow(text: "Результаты · \(users.count)")
            if users.isEmpty {
                Text("Пользователи не найдены.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
            }
            ForEach(users) { user in
                Button {
                    Task { await loadUser(user.id) }
                } label: {
                    HStack(spacing: 11) {
                        Image(systemName: user.is_admin ? "checkmark.shield" : "person.crop.circle")
                            .font(.system(size: 19))
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(user.email)
                                .font(.system(size: 14, weight: .medium))
                                .lineLimit(1)
                            Text(user.is_admin ? "Администратор музыки" : "Пользователь")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.56))
                        }
                        Spacer(minLength: 5)
                        Image(systemName: selectedID == user.id ? "checkmark.circle.fill" : "chevron.right")
                            .foregroundStyle(.white.opacity(0.72))
                    }
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.white.opacity(selectedID == user.id ? 0.13 : 0.06),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(busy)
            }
        }
    }

    private func detailsPanel(_ value: ManagedUserDetail) -> some View {
        AdminGlassCard {
            AdminEyebrow(text: "Выбранный аккаунт")
            Text(value.user.email)
                .font(.system(size: 17, weight: .semibold))
                .textSelection(.enabled)
            Text("ID: \(value.user.id)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))
                .textSelection(.enabled)
            AdminInfoRow(title: "Роль", value: value.user.is_admin ? "Администратор" : "Пользователь")
            AdminInfoRow(title: "Premium", value: value.premium.active ? "Активен" : "Неактивен")
            if value.premium.active {
                AdminInfoRow(title: "Источник", value: sourceLabel(value.premium.source))
                if let expires = value.premium.expires_at {
                    AdminInfoRow(title: "Действует до",
                                 value: Date(timeIntervalSince1970: expires)
                                    .formatted(date: .abbreviated, time: .shortened))
                }
            }
        }
    }

    private func rolePanel(_ value: ManagedUserDetail) -> some View {
        AdminGlassCard {
            AdminEyebrow(text: "Права администратора")
            Text("Администратор Nightwell Music получает серверные права управления контентом.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.65))
            Button {
                pendingAction = .role(!value.user.is_admin)
            } label: {
                actionLabel(value.user.is_admin ? "Отозвать админку" : "Выдать админку",
                            symbol: value.user.is_admin ? "person.crop.circle.badge.minus" : "checkmark.shield")
            }
            .buttonStyle(.plain)
            .disabled(busy)
        }
    }

    private func premiumPanel(_ value: ManagedUserDetail) -> some View {
        AdminGlassCard {
            AdminEyebrow(text: "Nightwell Premium")
            Text(value.premium.grant_active ? "Ручной Premium выдан" : "Ручного Premium нет")
                .font(.system(size: 14, weight: .medium))
            if value.premium.grant_active, let grant = value.premium.grant_until {
                Text("Ручной доступ до \(Date(timeIntervalSince1970: grant).formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.65))
            }
            Picker("Срок", selection: $days) {
                Text("7 дней").tag(7)
                Text("30 дней").tag(30)
                Text("90 дней").tag(90)
                Text("365 дней").tag(365)
                Text("Бессрочно").tag(0)
            }
            .pickerStyle(.menu)
            .tint(.white)
            TextField("Причина выдачи или отзыва", text: $reason)
                .font(.system(size: 13))
                .padding(13)
                .background(.white.opacity(0.07),
                            in: RoundedRectangle(cornerRadius: 15))
            Button {
                pendingAction = .grant(days)
            } label: {
                actionLabel("Выдать / продлить Premium", symbol: "star.fill")
            }
            .buttonStyle(.plain)
            .disabled(busy || reason.trimmingCharacters(in: .whitespacesAndNewlines).count < 3)
            if value.premium.grant_active {
                Button {
                    pendingAction = .revokeGrant
                } label: {
                    actionLabel("Отозвать ручной Premium", symbol: "xmark.shield")
                }
                .buttonStyle(.plain)
                .disabled(busy || reason.trimmingCharacters(in: .whitespacesAndNewlines).count < 3)
            }
            Text("Оплаченный Premium через Lava не отключается. Выдача вручную добавляет отдельное право доступа.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.54))
        }
    }

    private func actionLabel(_ title: String, symbol: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: symbol).frame(width: 23)
            Text(title).font(.system(size: 14, weight: .semibold))
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption)
        }
        .foregroundStyle(.white)
        .padding(13)
        .background(.white.opacity(0.11),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func sourceLabel(_ source: String) -> String {
        switch source {
        case "admin": return "Выдан администратором"
        case "direct", "paid": return "Личная подписка"
        case "family": return "Семейная подписка"
        default: return source == "free" ? "Бесплатный" : "Premium"
        }
    }

    @MainActor private func call<T: Decodable>(_ path: String, method: String = "GET",
                                                 payload: [String: Any]? = nil,
                                                 query: String? = nil) async throws -> T {
        var req = try model.authorizedRequest(path, method: method)
        if let query {
            guard var url = URLComponents(url: req.url!, resolvingAgainstBaseURL: false) else {
                throw URLError(.badURL)
            }
            url.queryItems = [URLQueryItem(name: "query", value: query)]
            guard let encoded = url.url else { throw URLError(.badURL) }
            req.url = encoded
        }
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if let payload {
            req.httpBody = try JSONSerialization.data(withJSONObject: payload)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            let hint: String
            switch http.statusCode {
            case 401: hint = "Неверный ключ Admin Bridge."
            case 403: hint = "Недостаточно прав для управления пользователями."
            case 404: hint = "Модуль управления пользователями не установлен на Admin Bridge."
            case 409: hint = "Операция запрещена, например нельзя убрать последнего администратора."
            case 502, 503, 504: hint = "Сервер Nightwell Music или модуль управления недоступен."
            default:
                let detail = String(data: data, encoding: .utf8) ?? ""
                hint = "HTTP \(http.statusCode): \(detail.prefix(200))"
            }
            throw NSError(domain: "NightwellAdmin", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: hint])
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    @MainActor private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3, canManage, !busy else { return }
        busy = true
        errorText = ""
        notice = ""
        defer { busy = false }
        do {
            let response: ManagedUsersResult = try await call("v1/music/users", query: trimmed)
            users = response.users
            loaded = true
            if let selectedID, !users.contains(where: { $0.id == selectedID }) {
                self.selectedID = nil
                detail = nil
            }
        } catch {
            errorText = error.localizedDescription
            loaded = false
        }
    }

    @MainActor private func loadUser(_ id: String) async {
        guard !busy, id.range(of: "^[0-9a-fA-F]{32}$", options: .regularExpression) != nil else { return }
        busy = true
        errorText = ""
        defer { busy = false }
        do {
            let response: ManagedUserDetail = try await call("v1/music/users/" + id)
            guard response.user.id == id else { throw URLError(.badServerResponse) }
            selectedID = id
            detail = response
        } catch {
            errorText = error.localizedDescription
        }
    }

    @MainActor private func perform(_ action: MusicManagementAction) async {
        pendingAction = nil
        guard !busy, let selectedID, let current = selectedUser, current.id == selectedID else { return }
        busy = true
        errorText = ""
        notice = ""
        defer { busy = false }
        let comment = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let path: String
            let payload: [String: Any]
            switch action {
            case .role(let promote):
                path = "v1/music/users/" + selectedID + "/role"
                payload = ["is_admin": promote, "reason": comment.isEmpty ? "Nightwell Admin: роль" : comment]
            case .grant(let duration):
                guard comment.count >= 3 else {
                    throw NSError(domain: "NightwellAdmin", code: 422,
                                  userInfo: [NSLocalizedDescriptionKey: "Укажи причину выдачи Premium."])
                }
                path = "v1/music/users/" + selectedID + "/premium"
                payload = ["days": duration, "reason": comment]
            case .revokeGrant:
                guard comment.count >= 3 else {
                    throw NSError(domain: "NightwellAdmin", code: 422,
                                  userInfo: [NSLocalizedDescriptionKey: "Укажи причину отзыва Premium."])
                }
                path = "v1/music/users/" + selectedID + "/premium/revoke"
                payload = ["reason": comment]
            }
            let result: ManagedMutation = try await call(path, method: "POST", payload: payload)
            guard result.ok else { throw URLError(.badServerResponse) }
            let refreshed: ManagedUserDetail = try await call("v1/music/users/" + selectedID)
            detail = refreshed
            users = users.map { $0.id == selectedID ? refreshed.user : $0 }
            notice = "Права аккаунта обновлены."
        } catch {
            errorText = error.localizedDescription
        }
    }
}
