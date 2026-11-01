import SwiftUI
import Foundation

private struct ServerUpdateSchedule: Decodable {
    let mode: String
    let time: String
    let weekday: Int
    let last_slot: String?
}

private struct ServerUpdateProgress: Decodable {
    let state: String
    let message: String
    let updated_at: String
}

private struct ServerUpdateEnvelope: Decodable {
    let schedules: [String: ServerUpdateSchedule]
    let status: [String: ServerUpdateProgress]
    let timezone: String?
}

struct ServerUpdateSchedulingScreen: View {
    @EnvironmentObject private var admin: AdminModel
    let service: AdminService

    @State private var mode = "off"
    @State private var hour = 3
    @State private var minute = 30
    @State private var weekday = 0
    @State private var busy = false
    @State private var notification = ""
    @State private var progressText = ""
    @State private var serverTimezone = ""

    private let dayNames = ["Понедельник", "Вторник", "Среда", "Четверг",
                            "Пятница", "Суббота", "Воскресенье"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                AdminGlassCard {
                    Text("Способ обновления")
                        .font(.system(size: 14, weight: .semibold))
                    Picker("Режим", selection: $mode) {
                        Text("Вручную").tag("off")
                        Text("Каждый день").tag("daily")
                        Text("Раз в неделю").tag("weekly")
                    }
                    .pickerStyle(.menu)
                    .tint(.white)
                    if mode != "off" {
                        HStack(spacing: 14) {
                            Picker("Часы", selection: $hour) {
                                ForEach(0..<24, id: \.self) { value in
                                    Text(String(format: "%02d", value)).tag(value)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(.white)
                            Picker("Минуты", selection: $minute) {
                                ForEach(0..<60, id: \.self) { value in
                                    Text(String(format: "%02d", value)).tag(value)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(.white)
                        }
                        if mode == "weekly" {
                            Picker("День недели", selection: $weekday) {
                                ForEach(dayNames.indices, id: \.self) { index in
                                    Text(dayNames[index]).tag(index)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(.white)
                        }
                    }
                    Text("Расписание использует местное время Windows-сервера" +
                         (serverTimezone.isEmpty ? "." : " (\(serverTimezone))."))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                    Button {
                        Task { await save() }
                    } label: {
                        HStack {
                            Spacer()
                            Label("Сохранить расписание", systemImage: "checkmark.circle")
                            Spacer()
                        }
                        .padding(13)
                        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(busy)
                }

                AdminGlassCard {
                    Text("Ручное обновление")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Нажми, чтобы сейчас проверить Git или подготовленный ZIP. Если обновление найдено, сервер автоматически остановится, обновится и снова запустится.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.67))
                    Button {
                        Task { await runNow() }
                    } label: {
                        HStack {
                            Spacer()
                            Label("Проверить и обновить сейчас", systemImage: "arrow.down.circle")
                            Spacer()
                        }
                        .padding(13)
                        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(busy)
                }

                AdminGlassCard {
                    Text("Последнее состояние").font(.system(size: 14, weight: .semibold))
                    Text(progressText.isEmpty ? "Обновления ещё не запускались" : progressText)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.75))
                    if !notification.isEmpty {
                        Text(notification)
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                    }
                    Button {
                        Task { await load() }
                    } label: {
                        Label("Обновить статус", systemImage: "arrow.clockwise")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(busy)
                }
                Text("Источники: Git с настроенным upstream или ZIP Nightwell-Update.zip в папке NightwellUpdater/incoming. Без новой версии сервер не перезапускается. Автоматический запуск возможен, пока Admin Bridge работает.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.48))
                    .padding(.horizontal, 3)
            }
            .padding(16)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Обновления " + (service == .music ? "Music" : "Chat"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let request = try admin.authorizedRequest("v1/updates")
            let (data, response) = try await URLSession.shared.data(for: request)
            try check(response)
            let info = try JSONDecoder().decode(ServerUpdateEnvelope.self, from: data)
            if let schedule = info.schedules[service.rawValue] {
                mode = schedule.mode
                let timeParts = schedule.time.split(separator: ":")
                if timeParts.count == 2 {
                    hour = Int(timeParts[0]) ?? 3
                    minute = Int(timeParts[1]) ?? 30
                }
                weekday = schedule.weekday
            }
            if let status = info.status[service.rawValue] {
                progressText = status.message
                if !status.updated_at.isEmpty {
                    progressText += "\n" + status.updated_at
                }
            }
            serverTimezone = info.timezone ?? ""
            notification = ""
        } catch {
            notification = "Ошибка получения расписания: \(error.localizedDescription)"
        }
    }

    private func save() async {
        busy = true
        defer { busy = false }
        do {
            var request = try admin.authorizedRequest(
                "v1/updates/\(service.rawValue)/schedule", method: "POST")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "mode": mode,
                "time": String(format: "%02d:%02d", hour, minute),
                "weekday": weekday
            ])
            let (_, response) = try await URLSession.shared.data(for: request)
            try check(response)
            notification = "Расписание сохранено на Windows-сервере."
        } catch {
            notification = "Не удалось сохранить: \(error.localizedDescription)"
        }
    }

    private func runNow() async {
        busy = true
        defer { busy = false }
        do {
            let request = try admin.authorizedRequest(
                "v1/services/\(service.rawValue)/update", method: "POST")
            let (data, response) = try await URLSession.shared.data(for: request)
            try check(response)
            if let doc = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = doc["message"] as? String {
                notification = message
            } else {
                notification = "Проверка обновления запущена."
            }
            progressText = "Проверка обновления запущена. Нажми «Обновить статус» для результата."
        } catch {
            notification = "Ошибка обновления: \(error.localizedDescription)"
        }
    }

    private func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "NightwellUpdate", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey:
                            "HTTP \(http.statusCode). Проверь Admin Bridge версии 1.1 и настройки управления."])
        }
    }
}
