import Foundation

// Content is kept separately from the views so subsequent strategy documents can
// be added to DevelopmentResources/development-library.json without a new screen.
struct DevelopmentLibrary: Decodable {
    let schemaVersion: Int
    let documents: [DevelopmentPlan]

    func validate() throws {
        guard schemaVersion == 1 else {
            throw DevelopmentContentError.invalid("Неподдерживаемая версия материалов.")
        }
        guard Set(documents.map(\.id)).count == documents.count else {
            throw DevelopmentContentError.invalid("Повторяется идентификатор материала.")
        }
        for document in documents { try document.validate() }
    }
}

enum DevelopmentContentError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}

struct DevelopmentPlan: Decodable, Identifiable {
    let metadata: DevelopmentMetadata
    let sections: [DevelopmentSection]
    let freeBacklog: [DevelopmentFeature]
    let premiumBacklog: [DevelopmentFeature]
    let roadmap: [DevelopmentPhase]
    let marketing90days: [DevelopmentMarketingPhase]
    let budgets: [DevelopmentBudget]
    let economics: DevelopmentEconomics
    let sources: [DevelopmentSource]
    var id: String { metadata.id }

    var features: [DevelopmentFeature] { freeBacklog + premiumBacklog }

    func validate() throws {
        let identifiers = sections.map(\.id)
        guard !metadata.id.isEmpty, !metadata.title.isEmpty,
              !sections.isEmpty, Set(identifiers).count == identifiers.count else {
            throw DevelopmentContentError.invalid("Проверьте название и разделы материала.")
        }
        guard Set(features.map(\.id)).count == features.count,
              Set(roadmap.map(\.id)).count == roadmap.count,
              Set(marketing90days.map(\.id)).count == marketing90days.count,
              Set(budgets.map(\.id)).count == budgets.count,
              Set(sources.map(\.id)).count == sources.count else {
            throw DevelopmentContentError.invalid("Повторяются идентификаторы карточек.")
        }
        for section in sections {
            for block in section.blocks {
                guard ["paragraph", "callout", "heading", "table"].contains(block.type) else {
                    throw DevelopmentContentError.invalid("Неизвестный формат блока материала.")
                }
                if block.type == "table" {
                    guard let headers = block.headers, !headers.isEmpty,
                          let rows = block.rows,
                          rows.allSatisfy({ $0.count == headers.count }) else {
                        throw DevelopmentContentError.invalid("Неполные столбцы таблицы.")
                    }
                } else if block.text == nil {
                    throw DevelopmentContentError.invalid("В блоке отсутствует текст.")
                }
            }
        }
        guard roadmap.allSatisfy({
            $0.startWeek > 0 && $0.endWeek >= $0.startWeek &&
                $0.endWeek <= metadata.horizons.developmentWeeks
        }), marketing90days.allSatisfy({
            $0.startDay > 0 && $0.endDay >= $0.startDay &&
                $0.endDay <= metadata.horizons.marketingDays
        }) else {
            throw DevelopmentContentError.invalid("Этап выходит за горизонт плана.")
        }
        for budget in budgets {
            guard budget.minAmount >= 0, budget.maxAmount >= budget.minAmount else {
                throw DevelopmentContentError.invalid("Некорректный диапазон бюджета.")
            }
            if let allocation = budget.allocation {
                guard allocation.allSatisfy({ $0.amount >= 0 }),
                      abs(allocation.reduce(0) { $0 + $1.amount } - budget.maxAmount) < 0.01 else {
                    throw DevelopmentContentError.invalid("Распределение бюджета не сходится с итогом.")
                }
            }
        }
        guard economics.price > 0,
              (0...1).contains(economics.contributionMarginRate),
              (0...1).contains(economics.renewalProbabilityPerPeriod),
              (0...1).contains(economics.registrationToPaidConversion),
              economics.proposedCacCeiling >= 0,
              (1...120).contains(economics.periods), economics.periodDays > 0 else {
            throw DevelopmentContentError.invalid("Некорректные параметры расчётного сценария.")
        }
    }
}

struct DevelopmentMetadata: Decodable {
    let id: String
    let title: String
    let subtitle: String
    let planDate: String
    let importantNotice: String
    let horizons: DevelopmentHorizons
}

struct DevelopmentHorizons: Decodable {
    let developmentWeeks: Int
    let marketingDays: Int
}

struct DevelopmentSection: Decodable, Identifiable {
    let id: String
    let sourcePage: Int
    let eyebrow: String
    let title: String
    let lead: String?
    let blocks: [DevelopmentBlock]

    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        let text = [title, lead ?? ""] + blocks.flatMap {
            [$0.text ?? ""] + ($0.headers ?? []) + ($0.rows ?? []).flatMap { $0 }
        }
        return text.contains { $0.localizedStandardContains(query) }
    }
}

struct DevelopmentBlock: Decodable {
    let type: String
    let text: String?
    let tone: String?
    let headers: [String]?
    let rows: [[String]]?
    let links: [String]?
}

struct DevelopmentFeature: Decodable, Identifiable {
    let id: String
    let title: String
    let description: String
    let access: String
    let priority: String
    let outcomeAndDependencies: String
    let planningStatus: String
    let implementationStatus: String
}

struct DevelopmentPhase: Decodable, Identifiable {
    let id: String
    let label: String
    let title: String
    let startWeek: Int
    let endWeek: Int
    let development: String
    let marketingAndExitCriteria: String
    let dependencies: [String]
}

struct DevelopmentMarketingPhase: Decodable, Identifiable {
    let id: String
    let label: String
    let startDay: Int
    let endDay: Int
    let actions: String
    let outcomes: String
}

struct DevelopmentBudget: Decodable, Identifiable {
    let id: String
    let title: String
    let minAmount: Double
    let maxAmount: Double
    let description: String
    let allocationAndConditions: String
    let allocation: [DevelopmentBudgetPart]?
}

struct DevelopmentBudgetPart: Decodable {
    let label: String
    let amount: Double
}

struct DevelopmentEconomics: Decodable {
    let price: Double
    let contributionMarginRate: Double
    let renewalProbabilityPerPeriod: Double
    let registrationToPaidConversion: Double
    let proposedCacCeiling: Double
    let periods: Int
    let periodDays: Int

    static func contribution(price: Double, margin: Double, renewal: Double, periods: Int) -> Double {
        guard price.isFinite, margin.isFinite, renewal.isFinite,
              price >= 0, (0...1).contains(margin), (0...1).contains(renewal),
              (1...120).contains(periods) else { return 0 }
        return price * margin * (0..<periods).reduce(0) { $0 + pow(renewal, Double($1)) }
    }
}

struct DevelopmentSource: Decodable, Identifiable {
    let id: String
    let title: String
    let url: String?
}
