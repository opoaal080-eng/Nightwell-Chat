import SwiftUI
import Charts

private enum AdminStyle {
    static let background = Color.black
    static let surface = Color(red: 0.085, green: 0.085, blue: 0.091)
    static let soft = Color.white.opacity(0.64)
    static let green = Color(red: 0.28, green: 0.91, blue: 0.58)
}

struct AdminGlassCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) { content }
            .padding(17)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color(white: 0.13), AdminStyle.surface, Color(white: 0.055)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.20), .white.opacity(0.025)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.23), radius: 15, y: 7)
    }
}

struct AdminEyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .tracking(0.65)
            .foregroundStyle(AdminStyle.soft)
    }
}

struct AdminInfoRow: View {
    let title: String
    let value: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title).foregroundStyle(.white.opacity(0.56))
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white.opacity(0.92))
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .font(.system(size: 13))
    }
}

struct AdminMetric: View {
    let title: String
    let value: Int?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11)).foregroundStyle(AdminStyle.soft)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value.map(String.init) ?? "—")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
                if value != nil {
                    Text("мс").font(.system(size: 10)).foregroundStyle(AdminStyle.soft)
                }
            }.foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 7)
        .padding(.horizontal, 9)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 11))
    }
}

struct AdminHistoryChart: View {
    let samples: [ProbeSample]
    var height: CGFloat = 62

    var body: some View {
        Group {
            if samples.count >= 2 {
                Chart(samples) { sample in
                    AreaMark(
                        x: .value("Время", sample.time),
                        yStart: .value("Ноль", 0),
                        yEnd: .value("Задержка", sample.ms)
                    )
                    .foregroundStyle(.linearGradient(
                        colors: [.white.opacity(0.16), .white.opacity(0.005)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    LineMark(x: .value("Время", sample.time),
                             y: .value("Задержка", sample.ms))
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round))
                        .foregroundStyle(.white.opacity(0.91))
                }
                .chartYScale(domain: 0...max(100, (samples.map(\.ms).max() ?? 100) + 40))
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: height)
                .accessibilityLabel("История времени HTTPS-запросов")
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "waveform.path")
                        .font(.system(size: 22, weight: .ultraLight))
                    Text("История появится после нескольких проверок")
                        .font(.caption2)
                }
                .foregroundStyle(.white.opacity(0.40))
                .frame(maxWidth: .infinity)
                .frame(height: height)
            }
        }
    }
}

struct AdminPrimaryButton: View {
    let title: String
    let symbol: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: symbol)
                Spacer()
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .opacity(0)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .padding(.horizontal, 14)
            .background(
                Capsule().fill(.linearGradient(
                    colors: [Color(white: 0.33), Color(white: 0.14), Color(white: 0.22)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 1))
        }.buttonStyle(.plain)
    }
}

struct AdminActionSquare: View {
    let label: String
    let symbol: String
    let enabled: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 9) {
                Image(systemName: symbol).font(.system(size: 21, weight: .regular))
                Text(label).font(.system(size: 11, weight: .medium))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(enabled ? Color.white : Color.white.opacity(0.34))
            .frame(maxWidth: .infinity)
            .frame(height: 66)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.white.opacity(enabled ? 0.16 : 0.065), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

struct AdminServiceScreen: View {
    @EnvironmentObject private var model: AdminModel
    let service: AdminService

    @AppStorage("nightwell.admin.showttfb") private var showTTFB = true
    @AppStorage("nightwell.admin.showtotal") private var showTotal = true
    @State private var chosenAction: String?
    @State private var confirmation = false

    private var probe: ProbeStatus? { model.probes[service] }
    private var remote: RemoteService? { model.admin?.services[service.rawValue] }
    private var history: [ProbeSample] { model.history[service, default: []] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 21) {
                statusCard
                metricCard
                informationCard
                controlsCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 34)
        }
        .scrollIndicators(.hidden)
        .background(AdminStyle.background.ignoresSafeArea())
        .navigationTitle(service == .music ? "Музыка" : "Чат")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await model.probe(service); await model.refreshAdmin() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(.white.opacity(0.84))
                }
            }
        }
        .refreshable {
            await model.probe(service)
            await model.refreshAdmin()
        }
        .confirmationDialog("Управление \(service.name)", isPresented: $confirmation,
                            titleVisibility: .visible) {
            if let action = chosenAction {
                Button(actionLabel(action), role: action == "stop" ? .destructive : nil) {
                    Task { await model.run(action, for: service) }
                }
            }
            Button("Отмена", role: .cancel) { chosenAction = nil }
        } message: {
            Text("Команда будет отправлена на Windows-сервер через защищённый Nightwell Admin Bridge.")
        }
    }

    private var statusCard: some View {
        AdminGlassCard {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13)
                        .fill(Color.white.opacity(0.055))
                        .frame(width: 46, height: 46)
                    Image(systemName: service.symbol)
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.92))
                }
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Image(systemName: probe?.available == true ?
                              "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundStyle(probe?.available == true ? AdminStyle.green : .orange)
                        Text(probe == nil ? "Проверяем…" :
                             probe?.available == true ? "Онлайн" : "Недоступен")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    Text(probe == nil ? "Подключение к сервису" :
                         probe?.available == true ? "Сервис отвечает на HTTPS-запросы" :
                         probe?.statusText ?? "Нет ответа")
                        .font(.system(size: 11)).foregroundStyle(AdminStyle.soft)
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
                if let date = probe?.checkedAt {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Проверено").font(.system(size: 10))
                            .foregroundStyle(AdminStyle.soft)
                        Text(date.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                    }
                }
            }
        }
    }

    private var metricCard: some View {
        AdminGlassCard {
            HStack {
                AdminEyebrow(text: "Сеть и задержка")
                Spacer()
                NavigationLink {
                    AdminDiagnosticsScreen(initialService: service)
                } label: {
                    HStack(spacing: 4) {
                        Text("Подробно")
                        Image(systemName: "chevron.right").font(.system(size: 9))
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.78))
                }
            }
            HStack(spacing: 7) {
                AdminMetric(title: "TCP", value: probe?.tcpMs)
                if showTTFB { AdminMetric(title: "TTFB", value: probe?.ttfbMs) }
                if showTotal { AdminMetric(title: "Полное", value: probe?.totalMs) }
            }
            AdminHistoryChart(samples: history)
            HStack {
                Text("История HTTPS-запросов")
                Spacer()
                if let last = history.last {
                    Text(last.time.formatted(date: .omitted, time: .shortened))
                }
            }.font(.system(size: 10)).foregroundStyle(.white.opacity(0.48))
        }
    }

    private var informationCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            AdminEyebrow(text: "Информация")
                .padding(.horizontal, 3)
            AdminGlassCard {
                AdminInfoRow(title: "Домен", value: service.publicURL.host ?? "—")
                Divider().overlay(.white.opacity(0.055))
                AdminInfoRow(title: "Локальный порт", value: "\(service.port)")
                Divider().overlay(.white.opacity(0.055))
                AdminInfoRow(title: "Протокол", value: "HTTPS (Caddy)")
                Divider().overlay(.white.opacity(0.055))
                AdminInfoRow(title: "Последняя проверка", value:
                    probe?.checkedAt.formatted(date: .omitted, time: .shortened) ?? "—")
                Link(destination: service.browserURL) {
                    HStack {
                        Image(systemName: "arrow.up.right")
                        Text("Открыть сервис").font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption2)
                    }
                    .foregroundStyle(.white)
                    .padding(.top, 5)
                }
            }
        }
    }

    private var controlsCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            AdminEyebrow(text: "Управление")
                .padding(.horizontal, 3)
            AdminGlassCard {
                if model.admin == nil {
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: "lock.shield")
                        Text("Подключи Nightwell Admin Bridge в настройках, чтобы управлять сервером.")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(AdminStyle.soft)
                } else {
                    HStack(spacing: 8) {
                        Circle().fill(remote?.running == true ? AdminStyle.green : .orange)
                            .frame(width: 7, height: 7)
                        Text(remote?.running == true ? "Процесс запущен" : "Процесс остановлен")
                            .font(.system(size: 11)).foregroundStyle(AdminStyle.soft)
                    }
                }
                HStack(spacing: 9) {
                    AdminActionSquare(label: "Перезапуск", symbol: "arrow.clockwise",
                        enabled: remote?.can_restart == true && !model.loading) {
                        propose("restart")
                    }
                    AdminActionSquare(label: "Остановить", symbol: "stop.square",
                        enabled: remote?.can_stop == true && !model.loading) {
                        propose("stop")
                    }
                    AdminActionSquare(label: "Логи", symbol: "doc.text",
                        enabled: model.admin != nil) {
                        Task { await model.loadLogs(service) }
                    }
                }
                HStack(spacing: 9) {
                    AdminActionSquare(label: "Запустить", symbol: "play.rectangle",
                        enabled: remote?.can_start == true && !model.loading) {
                        propose("start")
                    }
                    AdminActionSquare(label: "Резервная копия", symbol: "externaldrive",
                        enabled: remote?.can_backup == true && !model.loading) {
                        propose("backup")
                    }
                    AdminActionSquare(label: "Обновить", symbol: "arrow.down.app",
                        enabled: remote?.can_update == true && !model.loading) {
                        propose("update")
                    }
                }
                Text("Команды доступны только после настройки прав на Windows. Nightwell Music и Chat управляются отдельно.")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.43))
            }
        }
    }

    private func propose(_ action: String) {
        chosenAction = action
        confirmation = true
    }

    private func actionLabel(_ action: String) -> String {
        switch action {
        case "start": return "Запустить"
        case "stop": return "Остановить"
        case "restart": return "Перезапустить"
        case "backup": return "Создать резервную копию"
        case "update": return "Установить обновление"
        default: return "Подтвердить"
        }
    }
}

struct AdminSettingsScreen: View {
    @EnvironmentObject private var model: AdminModel

    @AppStorage("nightwell.admin.autorefresh") private var autoRefresh = true
    @AppStorage("nightwell.admin.refreshminutes") private var refreshMinutes = 1
    @AppStorage("nightwell.admin.alerts") private var alerts = true
    @AppStorage("nightwell.admin.showttfb") private var showTTFB = true
    @AppStorage("nightwell.admin.showtotal") private var showTotal = true

    @State private var showToken = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 21) {
                group("СЕРВЕР") {
                    NavigationLink {
                        AdminConnectionScreen()
                    } label: {
                        settingsRow("Адрес сервера", symbol: "globe",
                                    accessory: "Управление", navigate: true)
                    }
                    Divider().overlay(.white.opacity(0.04))
                    NavigationLink {
                        AdminConnectionScreen()
                    } label: {
                        settingsRow("Ключ управления", symbol: "key.horizontal",
                                    accessory: model.token.isEmpty ? "Не задан" : "••••••", navigate: true)
                    }
                    Divider().overlay(.white.opacity(0.04))
                    NavigationLink {
                        AdminDiagnosticsScreen()
                    } label: {
                        settingsRow("Проверка соединения", symbol: "shield.lefthalf.filled",
                                    accessory: "", navigate: true)
                    }
                }
                group("ПРОВЕРКА СКОРОСТИ") {
                    HStack {
                        Label("Проверить сейчас", systemImage: "speedometer")
                            .font(.system(size: 13))
                        Spacer()
                        Button("Тестировать") {
                            Task { await model.refreshAll() }
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .buttonStyle(.bordered)
                    }
                    Divider().overlay(.white.opacity(0.04))
                    Toggle("Показывать TTFB", isOn: $showTTFB)
                    Divider().overlay(.white.opacity(0.04))
                    Toggle("Полное время HTTPS", isOn: $showTotal)
                    Divider().overlay(.white.opacity(0.04))
                    Toggle("Автообновление", isOn: $autoRefresh)
                    if autoRefresh {
                        Picker("Интервал (минуты)", selection: $refreshMinutes) {
                            Text("1").tag(1)
                            Text("5").tag(5)
                            Text("10").tag(10)
                        }
                    }
                    Text("Автообновление выполняется, пока приложение открыто. Это не фоновый мониторинг.")
                        .font(.system(size: 11)).foregroundStyle(AdminStyle.soft)
                }
                group("УВЕДОМЛЕНИЯ") {
                    Toggle("Предупреждения о сбоях", isOn: $alerts)
                    Text("Показывает предупреждение внутри приложения, если доступный сервер перестал отвечать.")
                        .font(.system(size: 11)).foregroundStyle(AdminStyle.soft)
                }
                group("О ПРИЛОЖЕНИИ") {
                    AdminInfoRow(title: "Версия", value: "1.2.0 (4)")
                    AdminInfoRow(title: "Сервисы", value: "Music · Chat")
                    AdminInfoRow(title: "Управление", value: "Nightwell Admin")
                }
            }
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 32)
        }
        .background(AdminStyle.background.ignoresSafeArea())
        .scrollIndicators(.hidden)
        .navigationTitle("Настройки")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func group<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            AdminEyebrow(text: label).padding(.horizontal, 3)
            AdminGlassCard { content() }
        }
    }

    private func settingsRow(_ label: String, symbol: String, accessory: String,
                             navigate: Bool) -> some View {
        HStack(spacing: 11) {
            Image(systemName: symbol)
                .frame(width: 22)
                .foregroundStyle(.white.opacity(0.83))
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.white)
            Spacer()
            Text(accessory)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.42))
            if navigate {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.34))
            }
        }
        .frame(minHeight: 24)
    }
}

struct AdminConnectionScreen: View {
    @EnvironmentObject private var model: AdminModel
    @State private var revealToken = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                AdminGlassCard {
                    AdminEyebrow(text: "Подключение к Windows")
                    TextField("https://admin.nightwell.fun", text: $model.endpoint)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .font(.system(size: 13))
                        .padding(13)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    HStack(spacing: 8) {
                        Group {
                            if revealToken {
                                TextField("Ключ администратора", text: $model.token)
                            } else {
                                SecureField("Ключ администратора", text: $model.token)
                            }
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 13))
                        Button {
                            revealToken.toggle()
                        } label: {
                            Image(systemName: revealToken ? "eye.slash" : "eye")
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    .padding(13)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    AdminPrimaryButton(title: "Проверить подключение", symbol: "network") {
                        Task { await model.refreshAdmin() }
                    }
                    if let admin = model.admin {
                        Label("Подключено, версия \(admin.version)", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else if !model.adminError.isEmpty {
                        Text(model.adminError)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.64))
                    }
                }
                AdminGlassCard {
                    AdminEyebrow(text: "Безопасность")
                    Text("Ключ хранится в Keychain iPhone. Команды запуска и обновления доступны только через HTTPS после настройки Windows-моста.")
                        .font(.system(size: 12))
                        .foregroundStyle(AdminStyle.soft)
                    Text("Не публикуй ключ в GitHub и не пересылай его в чаты.")
                        .font(.system(size: 12))
                        .foregroundStyle(AdminStyle.soft)
                }
            }.padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Подключение")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AdminDiagnosticsScreen: View {
    @EnvironmentObject private var model: AdminModel
    @State private var selected: AdminService
    @State private var running = false

    init(initialService: AdminService = .music) {
        _selected = State(initialValue: initialService)
    }

    private var probe: ProbeStatus? { model.probes[selected] }
    private var history: [ProbeSample] { model.history[selected, default: []] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker("Сервис", selection: $selected) {
                    Text("Музыка").tag(AdminService.music)
                    Text("Чат").tag(AdminService.chat)
                }
                .pickerStyle(.segmented)

                AdminGlassCard {
                    AdminEyebrow(text: "Результаты (последняя проверка)")
                    diagnosticsRow("DNS", probe?.dnsMs)
                    diagnosticsRow("TCP", probe?.tcpMs)
                    diagnosticsRow("TLS", probe?.tlsMs)
                    diagnosticsRow("TTFB", probe?.ttfbMs)
                    diagnosticsRow("Полный запрос", probe?.totalMs)
                    HStack {
                        Text("Статус").font(.system(size: 13))
                        Spacer()
                        Text(probe == nil ? "Не проверен" :
                                probe?.available == true ? "Доступен" : "Нет ответа")
                            .foregroundStyle(probe?.available == true ? AdminStyle.green : .orange)
                            .font(.system(size: 12, weight: .medium))
                    }
                    Text("Пустые значения DNS, TCP и TLS означают, что iOS использовала существующее соединение или не предоставила метрики.")
                        .font(.system(size: 11)).foregroundStyle(AdminStyle.soft)
                }

                AdminGlassCard {
                    AdminEyebrow(text: "История HTTPS-запросов")
                    AdminHistoryChart(samples: history, height: 170)
                    HStack {
                        Text("Прошлые проверки")
                        Spacer()
                        Text("Сейчас")
                    }.font(.system(size: 10)).foregroundStyle(AdminStyle.soft)
                    Text("График строится по реальным запросам текущего сеанса.")
                        .font(.system(size: 11)).foregroundStyle(AdminStyle.soft)
                }

                AdminPrimaryButton(title: running ? "Выполняется проверка…" : "Запустить тест · 5 запросов",
                                   symbol: "arrow.clockwise") {
                    guard !running else { return }
                    running = true
                    Task {
                        for i in 0..<5 {
                            if Task.isCancelled { break }
                            await model.probe(selected)
                            if i < 4 { try? await Task.sleep(for: .milliseconds(300)) }
                        }
                        running = false
                    }
                }
                .disabled(running)

                Text("Это время HTTPS-запросов с iPhone, а не ICMP-пинг. Показатели зависят от Wi-Fi/LTE, DNS, TLS, маршрута и нагрузки сервера.")
                    .font(.system(size: 11))
                    .foregroundStyle(AdminStyle.soft)
                    .padding(.horizontal, 5)
            }.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Диагностика")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func diagnosticsRow(_ name: String, _ value: Int?) -> some View {
        HStack {
            Text(name).font(.system(size: 13)).foregroundStyle(.white.opacity(0.75))
            Spacer()
            Text(value.map { "\($0) мс" } ?? "—")
                .monospacedDigit()
                .font(.system(size: 13, weight: .medium, design: .rounded))
        }
        .padding(.vertical, 3)
    }
}
