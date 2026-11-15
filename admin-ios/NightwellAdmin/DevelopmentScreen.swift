import SwiftUI
import Charts
import Foundation

// The library is bundled data, so reading plans does not depend on the admin bridge.
struct AdminDevelopmentScreen: View {
    @StateObject private var store = DevelopmentStore()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                introduction
                if let error = store.errorMessage {
                    AdminGlassCard {
                        Label("Не удалось открыть материалы", systemImage: "exclamationmark.triangle")
                            .font(.headline)
                        Text(error).font(.subheadline).foregroundStyle(.secondary)
                        Button("Повторить") { store.reload() }
                            .buttonStyle(.bordered)
                    }
                }
                ForEach(store.documents) { plan in
                    NavigationLink {
                        DevelopmentPlanScreen(plan: plan)
                    } label: {
                        DevelopmentDocumentCard(plan: plan)
                    }
                    .buttonStyle(.plain)
                }
                if store.documents.isEmpty && store.errorMessage == nil {
                    ContentUnavailableView("Материалов пока нет", systemImage: "books.vertical",
                                           description: Text("Здесь появятся планы и исследования проекта."))
                }
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Развитие")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if store.documents.isEmpty { store.reload() }
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 8) {
            AdminEyebrow(text: "Материалы проекта")
            Text("От идеи к следующему шагу")
                .font(.system(.title2, design: .rounded, weight: .semibold))
            Text("Планы, функции, продвижение и экономика — прямо в приложении. Материалы можно читать без сети.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.64))
        }
        .padding(.vertical, 8)
    }
}

private struct DevelopmentDocumentCard: View {
    let plan: DevelopmentPlan

    var body: some View {
        AdminGlassCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.title2)
                    .frame(width: 45, height: 45)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 5) {
                    Text(plan.metadata.title).font(.headline)
                    Text(plan.metadata.subtitle)
                        .font(.subheadline).foregroundStyle(.white.opacity(0.64))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                DevelopmentBadge(text: "План и предложения")
                Text(developmentDate(plan.metadata.planDate))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("\(plan.sections.count) разделов · \(plan.freeBacklog.count + plan.premiumBacklog.count) новых функций и доработок")
                .font(.caption).foregroundStyle(.white.opacity(0.64))
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
    }
}

struct DevelopmentPlanScreen: View {
    let plan: DevelopmentPlan
    @State private var searchText = ""

    private var sections: [DevelopmentSection] {
        plan.sections.filter { $0.matches(searchText) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if searchText.isEmpty {
                    overview
                    shortcuts
                }
                AdminEyebrow(text: searchText.isEmpty ? "Все разделы" : "Найдено разделов: \(sections.count)")
                if sections.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
                ForEach(sections) { section in
                    NavigationLink {
                        DevelopmentSectionScreen(section: section)
                    } label: {
                        DevelopmentSectionRow(section: section)
                    }
                    .buttonStyle(.plain)
                }
                if searchText.isEmpty { sources }
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("План развития")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Найти в тексте плана")
    }

    private var overview: some View {
        AdminGlassCard {
            AdminEyebrow(text: developmentDate(plan.metadata.planDate))
            Text(plan.metadata.title)
                .font(.system(.title2, design: .rounded, weight: .semibold))
            Text(plan.metadata.subtitle).font(.subheadline)
            Text(plan.metadata.importantNotice)
                .font(.caption).foregroundStyle(.white.opacity(0.64))
                .fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], alignment: .leading, spacing: 8) {
                DevelopmentPlanNumber(value: "\(plan.metadata.horizons.developmentWeeks)", title: "недели разработки")
                DevelopmentPlanNumber(value: "\(plan.metadata.horizons.marketingDays)", title: "дней продвижения")
                DevelopmentPlanNumber(value: "\(plan.freeBacklog.count + plan.premiumBacklog.count)", title: "предложений функций")
            }
        }
    }

    private var shortcuts: some View {
        AdminGlassCard {
            AdminEyebrow(text: "План в графике")
            NavigationLink {
                DevelopmentRoadmapScreen(plan: plan)
            } label: {
                DevelopmentNavigationRow(title: "Дорожная карта", subtitle: "Этапы, задачи и зависимости", symbol: "calendar")
            }
            Divider().overlay(.white.opacity(0.08))
            NavigationLink {
                DevelopmentBacklogScreen(plan: plan)
            } label: {
                DevelopmentNavigationRow(title: "Новые функции", subtitle: "Free / Premium и приоритеты", symbol: "square.grid.2x2")
            }
            if let matrix = plan.sections.first(where: { $0.sourcePage == 3 }) {
                Divider().overlay(.white.opacity(0.08))
                NavigationLink {
                    DevelopmentSectionScreen(section: matrix)
                } label: {
                    DevelopmentNavigationRow(title: "Free и Premium", subtitle: "Целевая матрица доступа", symbol: "rectangle.split.2x1")
                }
            }
            Divider().overlay(.white.opacity(0.08))
            NavigationLink {
                DevelopmentMarketingScreen(plan: plan)
            } label: {
                DevelopmentNavigationRow(title: "Продвижение", subtitle: "Календарь на \(plan.metadata.horizons.marketingDays) дней", symbol: "megaphone")
            }
            if let metrics = plan.sections.first(where: { $0.sourcePage == 16 }) {
                Divider().overlay(.white.opacity(0.08))
                NavigationLink {
                    DevelopmentSectionScreen(section: metrics)
                } label: {
                    DevelopmentNavigationRow(title: "Метрики и воронка", subtitle: "Определения и события измерения", symbol: "line.3.horizontal.decrease")
                }
            }
            Divider().overlay(.white.opacity(0.08))
            NavigationLink {
                DevelopmentEconomicsScreen(plan: plan)
            } label: {
                DevelopmentNavigationRow(title: "Бюджет и экономика", subtitle: "Расчётные сценарии и калькулятор", symbol: "chart.bar.xaxis")
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }

    @ViewBuilder private var sources: some View {
        let linked = plan.sources.filter { source in
            guard let raw = source.url, let url = URL(string: raw) else { return false }
            return url.scheme == "https"
        }
        if !linked.isEmpty {
            AdminGlassCard {
                AdminEyebrow(text: "Источники")
                ForEach(linked) { source in
                    if let raw = source.url, let url = URL(string: raw) {
                        Link(destination: url) {
                            Label(source.title, systemImage: "arrow.up.right.square")
                                .font(.subheadline).multilineTextAlignment(.leading)
                        }
                    }
                }
            }
        }
    }
}

private struct DevelopmentPlanNumber: View {
    let value: String
    let title: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(.system(.title2, design: .rounded, weight: .semibold))
                .monospacedDigit()
            Text(title).font(.caption2).foregroundStyle(.white.opacity(0.64))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 13))
    }
}

private struct DevelopmentNavigationRow: View {
    let title: String
    let subtitle: String
    let symbol: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.title3).frame(width: 27)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.white.opacity(0.56))
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}

private struct DevelopmentSectionRow: View {
    let section: DevelopmentSection
    var body: some View {
        AdminGlassCard {
            HStack(alignment: .top, spacing: 12) {
                Text(String(format: "%02d", section.sourcePage))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.44))
                    .padding(.top, 3)
                VStack(alignment: .leading, spacing: 5) {
                    Text(section.title.replacingOccurrences(of: "\n", with: " "))
                        .font(.subheadline.weight(.semibold))
                    if let lead = section.lead, !lead.isEmpty {
                        Text(lead).font(.caption).foregroundStyle(.white.opacity(0.56))
                            .lineLimit(3)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2).foregroundStyle(.secondary).padding(.top, 4)
            }
        }
        .foregroundStyle(.white)
    }
}

private struct DevelopmentSectionScreen: View {
    let section: DevelopmentSection
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 17) {
                AdminEyebrow(text: section.eyebrow)
                Text(section.title.replacingOccurrences(of: "\n", with: " "))
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                if let lead = section.lead, !lead.isEmpty {
                    Text(lead).font(.subheadline).foregroundStyle(.white.opacity(0.64))
                }
                ForEach(Array(section.blocks.enumerated()), id: \.offset) { _, block in
                    DevelopmentBlockView(block: block)
                }
            }
            .padding(16)
            .padding(.bottom, 28)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Раздел \(section.sourcePage)")
        .navigationBarTitleDisplayMode(.inline)
        .textSelection(.enabled)
    }
}

private struct DevelopmentBlockView: View {
    let block: DevelopmentBlock
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch block.type {
            case "heading":
                Text(block.text ?? "").font(.headline).padding(.top, 6)
            case "callout":
                AdminGlassCard {
                    Text(block.text ?? "").font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            case "table":
                DevelopmentTable(headers: block.headers ?? [], rows: block.rows ?? [])
            default:
                if let text = block.text {
                    Text(text)
                        .font(block.tone == "secondary" ? .caption : .subheadline)
                        .foregroundStyle(block.tone == "secondary" ? .white.opacity(0.56) : .white.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            ForEach(block.links ?? [], id: \.self) { raw in
                if let url = URL(string: raw), url.scheme == "https" {
                    Link(destination: url) {
                        Label(url.host ?? raw, systemImage: "arrow.up.right.square")
                            .font(.caption).multilineTextAlignment(.leading)
                    }
                }
            }
        }
    }
}

// Row cards preserve every table cell while staying readable on a narrow iPhone.
private struct DevelopmentTable: View {
    let headers: [String]
    let rows: [[String]]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                AdminGlassCard {
                    ForEach(Array(row.enumerated()), id: \.offset) { column, value in
                        if !value.isEmpty {
                            VStack(alignment: .leading, spacing: 5) {
                                if column < headers.count, !headers[column].isEmpty {
                                    Text(headers[column])
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.white.opacity(0.52))
                                }
                                Text(value)
                                    .font(column == 0 ? .subheadline.weight(.semibold) : .subheadline)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
    }
}

private enum DevelopmentAccessFilter: String, CaseIterable, Identifiable {
    case all = "Все", free = "Free", premium = "Premium"
    var id: String { rawValue }
}

private struct DevelopmentBacklogScreen: View {
    let plan: DevelopmentPlan
    @State private var searchText = ""
    @State private var access: DevelopmentAccessFilter = .all
    @State private var priority = "Все"

    private var features: [DevelopmentFeature] {
        (plan.freeBacklog + plan.premiumBacklog).filter { feature in
            let accessMatches = access == .all || feature.access == access.rawValue.lowercased()
            let priorityMatches = priority == "Все" || feature.priority.contains(priority)
            let text = [feature.id, feature.title, feature.description, feature.outcomeAndDependencies]
                .joined(separator: " ")
            return accessMatches && priorityMatches &&
                (searchText.isEmpty || text.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                Picker("Доступ", selection: $access) {
                    ForEach(DevelopmentAccessFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }.pickerStyle(.segmented)
                HStack {
                    Text("\(features.count) предложений").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Menu {
                        Picker("Приоритет", selection: $priority) {
                            ForEach(["Все", "P0", "P1", "P2"], id: \.self) { value in
                                Text(value == "Все" ? "Все приоритеты" : value).tag(value)
                            }
                        }
                    } label: {
                        Label(priority == "Все" ? "Приоритет" : priority, systemImage: "line.3.horizontal.decrease")
                            .font(.caption)
                    }
                }
                Text("Это очередь предложений. Приоритет не означает, что функция уже готова; зависимости нужно проверить перед разработкой.")
                    .font(.caption).foregroundStyle(.white.opacity(0.56))
                if features.isEmpty { ContentUnavailableView.search(text: searchText) }
                ForEach(features) { feature in
                    DevelopmentFeatureCard(feature: feature)
                }
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Новые функции")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Найти функцию или зависимость")
    }
}

private struct DevelopmentFeatureCard: View {
    let feature: DevelopmentFeature
    var body: some View {
        AdminGlassCard {
            HStack(spacing: 7) {
                Text(feature.id).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                DevelopmentBadge(text: feature.access == "premium" ? "Premium" : "Free")
                Spacer(minLength: 4)
                DevelopmentBadge(text: feature.priority)
            }
            Text(feature.title).font(.headline)
            Text(feature.description).font(.subheadline).foregroundStyle(.white.opacity(0.82))
            VStack(alignment: .leading, spacing: 5) {
                Text("Результат и зависимости").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(feature.outcomeAndDependencies).font(.subheadline)
            }
            Text(feature.implementationStatus == "unverified" ? "Предложение · реализацию нужно проверить" : "Статус: \(feature.implementationStatus)")
                .font(.caption2).foregroundStyle(.white.opacity(0.46))
        }
        .textSelection(.enabled)
    }
}

private struct DevelopmentTimelineEntry: Identifiable {
    let id: String
    let label: String
    let start: Int
    let end: Int
}

private struct DevelopmentTimelineChart: View {
    let entries: [DevelopmentTimelineEntry]
    let upperBound: Int
    let ticks: [Int]
    let unit: String

    var body: some View {
        Chart(entries) { entry in
            BarMark(
                xStart: .value("Начало", entry.start),
                xEnd: .value("Конец", entry.end + 1),
                y: .value("Этап", entry.label)
            )
            .cornerRadius(4)
            .foregroundStyle(.white.opacity(0.82))
            .accessibilityLabel("\(entry.label): \(unit) \(entry.start)–\(entry.end)")
        }
        .chartXScale(domain: 1...(upperBound + 1))
        .chartYScale(domain: Array(entries.map(\.label).reversed()))
        .chartXAxis {
            AxisMarks(values: ticks) { _ in
                AxisGridLine().foregroundStyle(.white.opacity(0.08))
                AxisValueLabel().foregroundStyle(.white.opacity(0.55))
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisValueLabel().foregroundStyle(.white.opacity(0.64))
            }
        }
        .frame(height: CGFloat(entries.count * 43 + 28))
        .accessibilityLabel("План по этапам. \(unit.capitalized): от 1 до \(upperBound). Полные описания находятся ниже.")
    }
}

private struct DevelopmentRoadmapScreen: View {
    let plan: DevelopmentPlan
    private var entries: [DevelopmentTimelineEntry] {
        plan.roadmap.map {
            DevelopmentTimelineEntry(id: $0.id, label: $0.label, start: $0.startWeek, end: $0.endWeek)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 17) {
                AdminGlassCard {
                    AdminEyebrow(text: "План · недели 1–\(plan.metadata.horizons.developmentWeeks)")
                    Text("Последовательность разработки").font(.headline)
                    Text("Недели от старта работ. Это план, а не измеренный прогресс выполнения.")
                        .font(.caption).foregroundStyle(.secondary)
                    DevelopmentTimelineChart(entries: entries, upperBound: plan.metadata.horizons.developmentWeeks,
                                             ticks: developmentTimelineTicks(limit: plan.metadata.horizons.developmentWeeks, divisions: 4), unit: "недели")
                }
                ForEach(plan.roadmap) { phase in
                    AdminGlassCard {
                        DevelopmentBadge(text: phase.label)
                        Text(phase.title).font(.headline)
                        Text(phase.development).font(.subheadline)
                        Divider().overlay(.white.opacity(0.08))
                        Text("Результат и условие перехода").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(phase.marketingAndExitCriteria).font(.subheadline)
                        if !phase.dependencies.isEmpty {
                            Text("Зависимости").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            ForEach(Array(phase.dependencies.enumerated()), id: \.offset) { _, dependency in
                                Text("• \(dependency)").font(.caption)
                            }
                        }
                    }
                }
                if let section = plan.sections.first(where: { $0.sourcePage == 10 }) {
                    NavigationLink("Все допущения и распределение ресурса") {
                        DevelopmentSectionScreen(section: section)
                    }.font(.subheadline).padding(.vertical, 8)
                }
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Дорожная карта")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DevelopmentMarketingScreen: View {
    let plan: DevelopmentPlan
    private var entries: [DevelopmentTimelineEntry] {
        plan.marketing90days.map {
            DevelopmentTimelineEntry(id: $0.id, label: $0.label, start: $0.startDay, end: $0.endDay)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 17) {
                AdminGlassCard {
                    AdminEyebrow(text: "План · \(plan.metadata.horizons.marketingDays) дней")
                    Text("Продвижение по готовности продукта").font(.headline)
                    DevelopmentTimelineChart(entries: entries, upperBound: plan.metadata.horizons.marketingDays,
                                             ticks: developmentTimelineTicks(limit: plan.metadata.horizons.marketingDays, divisions: 3), unit: "дни")
                    Text("Календарь — предложение. Запуски зависят от готовности функций; подробные условия указаны в этапах ниже.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(plan.marketing90days) { phase in
                    AdminGlassCard {
                        DevelopmentBadge(text: phase.label)
                        Text(phase.actions).font(.subheadline)
                        Text("Результат").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(phase.outcomes).font(.subheadline)
                    }
                }
                AdminEyebrow(text: "Подробности продвижения")
                ForEach(plan.sections.filter { (12...15).contains($0.sourcePage) }) { section in
                    NavigationLink {
                        DevelopmentSectionScreen(section: section)
                    } label: {
                        DevelopmentSectionRow(section: section)
                    }.buttonStyle(.plain)
                }
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Продвижение")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DevelopmentBudgetSegment: Identifiable {
    let id: String
    let label: String
    let amount: Double
}

private struct DevelopmentEconomicsScreen: View {
    let plan: DevelopmentPlan
    @State private var price: Double
    @State private var margin: Double
    @State private var renewal: Double
    @State private var cac: Double
    @State private var conversion: Double

    init(plan: DevelopmentPlan) {
        self.plan = plan
        _price = State(initialValue: plan.economics.price)
        _margin = State(initialValue: plan.economics.contributionMarginRate)
        _renewal = State(initialValue: plan.economics.renewalProbabilityPerPeriod)
        _cac = State(initialValue: plan.economics.proposedCacCeiling)
        _conversion = State(initialValue: plan.economics.registrationToPaidConversion)
    }

    private var segments: [DevelopmentBudgetSegment] {
        (plan.budgets.first(where: { $0.id == "B" })?.allocation ?? []).enumerated().map {
            DevelopmentBudgetSegment(id: "\($0.offset)", label: $0.element.label, amount: $0.element.amount)
        }
    }
    private var periods: Int { plan.economics.periods }
    private var contributions: [Double] {
        (0..<periods).map { price * margin * pow(renewal, Double($0)) }
    }
    private var total: Double {
        DevelopmentEconomics.contribution(price: price, margin: margin, renewal: renewal, periods: periods)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 17) {
                budgetCard
                calculator
                if let section = plan.sections.first(where: { $0.sourcePage == 18 }) {
                    NavigationLink("Полный расчёт, ограничения и правила остановки") {
                        DevelopmentSectionScreen(section: section)
                    }.font(.subheadline).padding(.vertical, 8)
                }
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Бюджет и экономика")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var budgetCard: some View {
        AdminGlassCard {
            AdminEyebrow(text: "Расчётные сценарии")
            Text("Лимиты продвижения в месяц").font(.headline)
            Text("Это варианты будущего бюджета, а не фактические расходы. Разработка, труд и инфраструктура считаются отдельно.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(plan.budgets) { budget in
                VStack(alignment: .leading, spacing: 5) {
                    Text(budget.title).font(.subheadline.weight(.semibold))
                    Text(budget.description).font(.subheadline)
                    Text(budget.allocationAndConditions).font(.caption).foregroundStyle(.secondary)
                }
                if budget.id != plan.budgets.last?.id { Divider().overlay(.white.opacity(0.08)) }
            }
            if !segments.isEmpty {
                Text("Распределение сценария B").font(.subheadline.weight(.semibold))
                DevelopmentBudgetChart(segments: segments)
            }
        }
    }

    private var calculator: some View {
        AdminGlassCard {
            AdminEyebrow(text: "Калькулятор · расчётный сценарий")
            Text("Экономика первых \(periods) периодов").font(.headline)
            Text("Параметры можно менять для сравнения. Это не текущая цена, фактическая маржа или прогноз выручки Nightwell.")
                .font(.caption).foregroundStyle(.secondary)
            DevelopmentSlider(title: "Цена за \(plan.economics.periodDays) дней", value: $price, range: 0...max(1000, plan.economics.price * 2),
                              step: 10, formatted: developmentMoney(price))
            DevelopmentSlider(title: "Маржа после переменных затрат", value: $margin, range: 0...1,
                              step: 0.01, formatted: developmentPercent(margin))
            DevelopmentSlider(title: "Вероятность продления", value: $renewal, range: 0...1,
                              step: 0.01, formatted: developmentPercent(renewal))
            DevelopmentSlider(title: "Потолок CAC плательщика", value: $cac, range: 0...max(1000, plan.economics.proposedCacCeiling * 2),
                              step: 10, formatted: developmentMoney(cac))
            DevelopmentSlider(title: "Регистрация → покупка", value: $conversion, range: 0...max(0.20, plan.economics.registrationToPaidConversion),
                              step: 0.005, formatted: developmentPercent(conversion))
            Divider().overlay(.white.opacity(0.08))
            DevelopmentContributionChart(contributions: contributions)
            DevelopmentValueRow(title: "Маржинальный доход до привлечения", value: developmentMoney(total))
            DevelopmentValueRow(title: "Остаток после выбранного CAC", value: developmentMoney(total - cac))
            DevelopmentValueRow(title: "Допустимая стоимость регистрации", value: developmentMoney(cac * conversion))
            Text("Доход периода = цена × маржа × вероятность продления в степени номера периода минус один. Остаток после CAC должен также покрывать фиксированные расходы. \(developmentPercent(plan.economics.contributionMarginRate)) в исходном сценарии — допущение, не комиссия Lava.")
                .font(.caption2).foregroundStyle(.white.opacity(0.52))
            Button("Сбросить сценарий") { resetScenario() }
                .font(.subheadline).buttonStyle(.bordered)
        }
    }

    private func resetScenario() {
        price = plan.economics.price
        margin = plan.economics.contributionMarginRate
        renewal = plan.economics.renewalProbabilityPerPeriod
        cac = plan.economics.proposedCacCeiling
        conversion = plan.economics.registrationToPaidConversion
    }
}

private struct DevelopmentBudgetChart: View {
    let segments: [DevelopmentBudgetSegment]
    private var shades: [Color] {
        [Color(white: 0.95), Color(white: 0.73), Color(white: 0.52), Color(white: 0.32)]
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Chart(segments) { segment in
                BarMark(x: .value("Сумма", segment.amount), y: .value("Сценарий", "B"))
                    .foregroundStyle(by: .value("Назначение", segment.label))
                    .accessibilityLabel("\(segment.label): \(developmentMoney(segment.amount))")
            }
            .chartForegroundStyleScale(domain: segments.map(\.label), range: shades)
            .chartLegend(.hidden)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 38)
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle().fill(shades[index % shades.count]).frame(width: 7, height: 7)
                    Text(segment.label).font(.caption)
                    Spacer(minLength: 5)
                    Text(developmentMoney(segment.amount)).font(.caption).monospacedDigit()
                }
            }
        }
    }
}

private struct DevelopmentContributionChart: View {
    let contributions: [Double]
    var body: some View {
        Chart(Array(contributions.enumerated()), id: \.offset) { entry in
            BarMark(x: .value("Период", entry.offset + 1), y: .value("Вклад, ₽", entry.element))
                .foregroundStyle(.white.opacity(0.8))
                .cornerRadius(4)
                .accessibilityLabel("Период \(entry.offset + 1): \(developmentMoney(entry.element))")
        }
        .chartXAxis {
            AxisMarks(values: Array(1...contributions.count)) { _ in
                AxisValueLabel().foregroundStyle(.white.opacity(0.64))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(.white.opacity(0.08))
                AxisValueLabel().foregroundStyle(.white.opacity(0.52))
            }
        }
        .frame(height: 155)
        .accessibilityLabel("Условный маржинальный доход по периодам. Все значения расчётные.")
    }
}

private struct DevelopmentSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let formatted: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.caption)
                Spacer(minLength: 5)
                Text(formatted).font(.caption.weight(.semibold)).monospacedDigit()
            }
            Slider(value: $value, in: range, step: step)
                .tint(.white.opacity(0.82))
                .accessibilityLabel(title)
                .accessibilityValue(formatted)
        }
    }
}

private struct DevelopmentValueRow: View {
    let title: String
    let value: String
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
            }
        }
    }
}

private struct DevelopmentBadge: View {
    let text: String
    var body: some View {
        Text(text).font(.caption2.weight(.medium))
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(.white.opacity(0.075), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.6))
    }
}

private func developmentMoney(_ value: Double) -> String {
    value.formatted(.currency(code: "RUB").precision(.fractionLength(0...2)).locale(Locale(identifier: "ru_RU")))
}

private func developmentPercent(_ value: Double) -> String {
    value.formatted(.percent.precision(.fractionLength(0...1)).locale(Locale(identifier: "ru_RU")))
}

private func developmentDate(_ value: String) -> String {
    let parser = DateFormatter()
    parser.locale = Locale(identifier: "en_US_POSIX")
    parser.timeZone = TimeZone(secondsFromGMT: 0)
    parser.dateFormat = "yyyy-MM-dd"
    guard let date = parser.date(from: value) else { return value }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ru_RU")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "d MMMM yyyy"
    return formatter.string(from: date)
}

private func developmentTimelineTicks(limit: Int, divisions: Int) -> [Int] {
    guard limit > 0, divisions > 0 else { return [1] }
    let values = [1] + (1...divisions).map {
        max(1, Int((Double(limit) * Double($0) / Double(divisions)).rounded()))
    }
    return Array(Set(values)).sorted()
}
