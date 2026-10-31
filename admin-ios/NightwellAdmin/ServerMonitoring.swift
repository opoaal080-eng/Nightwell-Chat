import SwiftUI
import Foundation
import Security
import Charts

// The hardware monitor has a separate secret from the bridge's control key.
enum MonitorTokenVault {
    private static let account = "nightwell.admin.monitor.token"

    static func read() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else { return "" }
        return token
    }

    static func write(_ value: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var attributes = query
        attributes[kSecValueData as String] = Data(trimmed.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }
}

struct MonitorCPU: Decodable {
    let model: String
    let usage_percent: Double
    let physical_cores: Int?
    let logical_cores: Int?
    let per_core_percent: [Double]
}

struct MonitorMemory: Decodable {
    let total_bytes: Int64
    let used_bytes: Int64
    let available_bytes: Int64
    let percent: Double
}

struct MonitorDisk: Decodable {
    let name: String
    let mount: String
    let total_bytes: Int64
    let used_bytes: Int64
    let free_bytes: Int64
    let percent: Double
}

struct MonitorDiskIO: Decodable {
    let read_bytes_per_sec: Double?
    let write_bytes_per_sec: Double?
}

struct MonitorNetwork: Decodable {
    let rx_bytes_per_sec: Double?
    let tx_bytes_per_sec: Double?
    let total_received_bytes: Int64
    let total_sent_bytes: Int64
}

struct MonitorGPU: Decodable {
    let name: String
    let usage_percent: Double?
    let memory_used_bytes: Int64?
    let memory_total_bytes: Int64?
    let temperature_c: Double?
}

struct MonitorTemperature: Decodable {
    let name: String
    let temperature_c: Double
}

struct SystemMonitorSnapshot: Decodable {
    let timestamp: Int
    let hostname: String
    let os: String
    let uptime_seconds: Int
    let cpu: MonitorCPU
    let memory: MonitorMemory
    let disks: [MonitorDisk]
    let disk_io: MonitorDiskIO?
    let network: MonitorNetwork
    let gpu: [MonitorGPU]
    let temperatures: [MonitorTemperature]
    let services: [String: Bool]
}

struct MonitorSample: Identifiable {
    let id = UUID()
    let time: Date
    let cpu: Double
    let memory: Double
}

@MainActor
final class ServerMonitoringModel: ObservableObject {
    @Published private(set) var latest: SystemMonitorSnapshot?
    @Published private(set) var samples: [MonitorSample] = []
    @Published private(set) var updatedAt: Date?
    @Published private(set) var loading = false
    @Published private(set) var error = ""

    func refresh(using admin: AdminModel) async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            var request = try admin.authorizedRequest("v1/system/metrics")
            let monitorToken = MonitorTokenVault.read()
            if !monitorToken.isEmpty {
                request.setValue("Bearer \(monitorToken)", forHTTPHeaderField: "Authorization")
            }
            request.timeoutInterval = 12
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            guard http.statusCode == 200 else {
                let message: String
                switch http.statusCode {
                case 401: message = "Неверный ключ мониторинга. Проверь его в настройках."
                case 404: message = "Маршрут мониторинга не настроен в Caddy."
                case 502, 503, 504: message = "Windows-агент не отвечает. Проверь его запуск."
                default: message = "Ошибка сервера: HTTP \(http.statusCode)"
                }
                throw NSError(domain: "Monitor", code: http.statusCode,
                              userInfo: [NSLocalizedDescriptionKey: message])
            }
            let snapshot = try JSONDecoder().decode(SystemMonitorSnapshot.self, from: data)
            latest = snapshot
            updatedAt = Date(timeIntervalSince1970: TimeInterval(snapshot.timestamp))
            samples.append(MonitorSample(time: Date(), cpu: snapshot.cpu.usage_percent,
                                         memory: snapshot.memory.percent))
            samples = Array(samples.suffix(120))
            error = ""
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private enum MonitorFormat {
    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, value), countStyle: .file)
    }

    static func speed(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return bytes(Int64(max(0, value))) + "/с"
    }

    static func percent(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return String(format: "%.1f%%", value)
    }

    static func temperature(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return String(format: "%.1f °C", value)
    }

    static func uptime(_ seconds: Int) -> String {
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let minutes = (seconds % 3600) / 60
        return days > 0 ? "\(days) д \(hours) ч \(minutes) мин" : "\(hours) ч \(minutes) мин"
    }
}

private struct MonitorUsageTile: View {
    let title: String
    let value: Double
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.65))
            Text(MonitorFormat.percent(value))
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
            ProgressView(value: min(100, max(0, value)), total: 100)
                .tint(value >= 90 ? .red : value >= 75 ? .orange : .white)
            Text(detail).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                .lineLimit(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 17))
    }
}

struct ServerMonitoringScreen: View {
    @EnvironmentObject private var admin: AdminModel
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var monitor = ServerMonitoringModel()
    @AppStorage("nightwell.admin.monitor.autorefresh") private var autoRefresh = true
    @State private var visible = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                summary
                if let snapshot = monitor.latest {
                    cpuAndMemory(snapshot)
                    history
                    gpu(snapshot)
                    storage(snapshot)
                    connectivity(snapshot)
                    sensors(snapshot)
                    serviceStatus(snapshot)
                }
                Text("Измерения поступают с Windows-компьютера, а не с iPhone. История хранится только в текущем сеансе. Данные обновляются каждые 3 секунды, пока экран открыт.")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Сервер")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await monitor.refresh(using: admin) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(.white.opacity(0.87))
                }
                .disabled(monitor.loading)
            }
        }
        .refreshable { await monitor.refresh(using: admin) }
        .onAppear { visible = true }
        .onDisappear { visible = false }
        .task {
            await monitor.refresh(using: admin)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                if Task.isCancelled { break }
                if visible && autoRefresh && scenePhase == .active {
                    await monitor.refresh(using: admin)
                }
            }
        }
    }

    private var summary: some View {
        AdminGlassCard {
            HStack(spacing: 11) {
                Image(systemName: "server.rack")
                    .font(.system(size: 26))
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 4) {
                    Text(monitor.latest?.hostname ?? "Компьютер Nightwell")
                        .font(.system(size: 17, weight: .semibold))
                    HStack(spacing: 5) {
                        Circle()
                            .fill(monitor.error.isEmpty && monitor.latest != nil ? .green : .orange)
                            .frame(width: 7, height: 7)
                        Text(monitor.error.isEmpty && monitor.latest != nil ? "Мониторинг работает" : "Нет свежих данных")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }
                Spacer()
                if monitor.loading {
                    ProgressView().tint(.white)
                }
            }
            if let snapshot = monitor.latest {
                AdminInfoRow(title: "Система", value: snapshot.os)
                AdminInfoRow(title: "Время работы", value: MonitorFormat.uptime(snapshot.uptime_seconds))
                if let updated = monitor.updatedAt {
                    AdminInfoRow(title: "Данные на", value: updated.formatted(date: .omitted, time: .standard))
                }
            }
            if !monitor.error.isEmpty {
                Text(monitor.error)
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                if MonitorTokenVault.read().isEmpty && admin.token.isEmpty {
                    Text("Сначала укажи ключ мониторинга в настройках.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
    }

    private func cpuAndMemory(_ snapshot: SystemMonitorSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            AdminEyebrow(text: "Нагрузка")
            HStack(alignment: .top, spacing: 9) {
                MonitorUsageTile(title: "Процессор", value: snapshot.cpu.usage_percent,
                                 detail: "\(snapshot.cpu.logical_cores ?? 0) потоков")
                MonitorUsageTile(title: "Оперативная память", value: snapshot.memory.percent,
                                 detail: "\(MonitorFormat.bytes(snapshot.memory.used_bytes)) из \(MonitorFormat.bytes(snapshot.memory.total_bytes))")
            }
            AdminGlassCard {
                Text(snapshot.cpu.model)
                    .font(.system(size: 13, weight: .medium))
                AdminInfoRow(title: "Физические ядра", value: snapshot.cpu.physical_cores.map(String.init) ?? "—")
                AdminInfoRow(title: "Логические потоки", value: snapshot.cpu.logical_cores.map(String.init) ?? "—")
                if !snapshot.cpu.per_core_percent.isEmpty {
                    AdminEyebrow(text: "По ядрам")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                              spacing: 8) {
                        ForEach(snapshot.cpu.per_core_percent.indices, id: \.self) { index in
                            VStack(alignment: .leading, spacing: 5) {
                                Text("№ \(index + 1)")
                                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                                Text(MonitorFormat.percent(snapshot.cpu.per_core_percent[index]))
                                    .font(.system(size: 11, design: .monospaced))
                                    .minimumScaleFactor(0.7).lineLimit(1)
                                ProgressView(value: snapshot.cpu.per_core_percent[index], total: 100)
                                    .tint(.white.opacity(0.8))
                            }
                            .padding(7)
                            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
                        }
                    }
                }
            }
        }
    }

    private var history: some View {
        AdminGlassCard {
            AdminEyebrow(text: "История загрузки")
            HStack(spacing: 16) {
                Label("CPU", systemImage: "circle.fill").foregroundStyle(.orange)
                Label("RAM", systemImage: "circle.fill").foregroundStyle(.white)
            }
            .font(.system(size: 11))
            if monitor.samples.count > 1 {
                Chart(monitor.samples) { sample in
                    LineMark(x: .value("Время", sample.time), y: .value("CPU", sample.cpu))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(.orange)
                    LineMark(x: .value("Время", sample.time), y: .value("RAM", sample.memory))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(.white)
                }
                .chartYScale(domain: 0...100)
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(values: [0, 50, 100])
                }
                .frame(height: 170)
            } else {
                Text("График появится после двух измерений.")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
                    .frame(maxWidth: .infinity, minHeight: 125)
            }
        }
    }

    private func gpu(_ snapshot: SystemMonitorSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            AdminEyebrow(text: "Видеокарта")
            AdminGlassCard {
                if snapshot.gpu.isEmpty {
                    Text("Датчики GPU недоступны. Для NVIDIA нужен nvidia-smi в PATH.")
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
                }
                ForEach(snapshot.gpu.indices, id: \.self) { i in
                    let item = snapshot.gpu[i]
                    Text(item.name).font(.system(size: 14, weight: .semibold))
                    AdminInfoRow(title: "Загрузка", value: MonitorFormat.percent(item.usage_percent))
                    if let used = item.memory_used_bytes, let total = item.memory_total_bytes {
                        AdminInfoRow(title: "Видеопамять", value:
                            "\(MonitorFormat.bytes(used)) / \(MonitorFormat.bytes(total))")
                    }
                    AdminInfoRow(title: "Температура", value: MonitorFormat.temperature(item.temperature_c))
                    if i + 1 < snapshot.gpu.count { Divider().overlay(.white.opacity(0.1)) }
                }
            }
        }
    }

    private func storage(_ snapshot: SystemMonitorSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            AdminEyebrow(text: "Накопители")
            AdminGlassCard {
                if snapshot.disks.isEmpty {
                    Text("Накопители недоступны").foregroundStyle(.white.opacity(0.6))
                }
                ForEach(snapshot.disks.indices, id: \.self) { i in
                    let item = snapshot.disks[i]
                    HStack {
                        Text(item.mount).font(.system(size: 13, weight: .medium))
                        Spacer()
                        Text(MonitorFormat.percent(item.percent))
                            .font(.system(size: 12, design: .monospaced))
                    }
                    ProgressView(value: item.percent, total: 100)
                        .tint(item.percent >= 90 ? .orange : .white)
                    AdminInfoRow(title: "Занято / всего", value:
                        "\(MonitorFormat.bytes(item.used_bytes)) / \(MonitorFormat.bytes(item.total_bytes))")
                    if i + 1 < snapshot.disks.count { Divider().overlay(.white.opacity(0.1)) }
                }
                Divider().overlay(.white.opacity(0.08))
                AdminInfoRow(title: "Чтение", value: MonitorFormat.speed(snapshot.disk_io?.read_bytes_per_sec))
                AdminInfoRow(title: "Запись", value: MonitorFormat.speed(snapshot.disk_io?.write_bytes_per_sec))
            }
        }
    }

    private func connectivity(_ snapshot: SystemMonitorSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            AdminEyebrow(text: "Сетевой трафик")
            AdminGlassCard {
                AdminInfoRow(title: "Получение", value: MonitorFormat.speed(snapshot.network.rx_bytes_per_sec))
                AdminInfoRow(title: "Отправка", value: MonitorFormat.speed(snapshot.network.tx_bytes_per_sec))
                Divider().overlay(.white.opacity(0.08))
                AdminInfoRow(title: "Получено с запуска", value: MonitorFormat.bytes(snapshot.network.total_received_bytes))
                AdminInfoRow(title: "Отправлено с запуска", value: MonitorFormat.bytes(snapshot.network.total_sent_bytes))
            }
        }
    }

    private func sensors(_ snapshot: SystemMonitorSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            AdminEyebrow(text: "Температуры")
            AdminGlassCard {
                if snapshot.temperatures.isEmpty {
                    Text("Windows не предоставляет эти датчики напрямую. Для температуры процессора можно запустить LibreHardwareMonitor с WMI.")
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.64))
                }
                ForEach(snapshot.temperatures.indices, id: \.self) { i in
                    let item = snapshot.temperatures[i]
                    AdminInfoRow(title: item.name, value: MonitorFormat.temperature(item.temperature_c))
                }
            }
        }
    }

    private func serviceStatus(_ snapshot: SystemMonitorSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            AdminEyebrow(text: "Локальные порты сервисов")
            AdminGlassCard {
                serviceRow("Nightwell Music", port: 8080, online: snapshot.services["music"] == true)
                Divider().overlay(.white.opacity(0.08))
                serviceRow("Nightwell Chat", port: 8009, online: snapshot.services["chat"] == true)
                Text("Здесь проверяется прослушивание порта на Windows, а не полная работоспособность приложения.")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.48))
            }
        }
    }

    private func serviceRow(_ name: String, port: Int, online: Bool) -> some View {
        HStack {
            Circle().fill(online ? .green : .orange).frame(width: 7, height: 7)
            Text(name).font(.system(size: 12))
            Spacer()
            Text(":\(port) · \(online ? "слушает" : "нет ответа")")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}
