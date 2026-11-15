import Foundation

struct ContentTestFailure: Error, CustomStringConvertible {
    let description: String
}

@main
struct DevelopmentDataTests {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw ContentTestFailure(description: message) }
    }

    static func expectInvalid(_ object: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        let library = try JSONDecoder().decode(DevelopmentLibrary.self, from: data)
        do {
            try library.validate()
        } catch { return }
        throw ContentTestFailure(description: "Invalid content was accepted")
    }

    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw ContentTestFailure(description: "Pass the development-library.json path")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let library = try JSONDecoder().decode(DevelopmentLibrary.self, from: data)
        try library.validate()
        guard let plan = library.documents.first(where: { $0.id == "nightwell-development-2026-11-15" }) else {
            throw ContentTestFailure(description: "The original strategy document is missing")
        }
        try require(plan.sections.count == 20, "All 20 strategy sections must remain readable")
        try require(plan.freeBacklog.map(\.id) == (1...8).map { String(format: "F%02d", $0) }, "Free backlog is incomplete")
        try require(plan.premiumBacklog.map(\.id) == (1...8).map { String(format: "P%02d", $0) }, "Premium backlog is incomplete")
        try require(plan.roadmap.first?.startWeek == 1 && plan.roadmap.last?.endWeek == 24, "Roadmap range")
        try require(plan.marketing90days.first?.startDay == 1 && plan.marketing90days.last?.endDay == 90, "Marketing range")
        try require(plan.sources.compactMap(\.url).count >= 5, "Source links were lost")
        try require(plan.sections.contains { $0.matches("файлы сохраняются после срока") }, "Offline policy must remain searchable")
        try require(plan.sections.contains { $0.matches("Together") }, "Experimental feature caveats must remain searchable")
        try require(plan.sections.allSatisfy { $0.matches("   ") }, "Whitespace search should preserve sections")
        let contribution = DevelopmentEconomics.contribution(price: 150, margin: 0.75, renewal: 0.7, periods: 3)
        try require(abs(contribution - 246.375) < 0.000001, "Compound renewal calculation")
        try require(DevelopmentEconomics.contribution(price: 150, margin: 0.75, renewal: 1, periods: 3) == 337.5, "Full renewal")
        try require(DevelopmentEconomics.contribution(price: 150, margin: 0.75, renewal: 0, periods: 3) == 112.5, "No renewal")
        try require(DevelopmentEconomics.contribution(price: 150, margin: 0, renewal: 0.7, periods: 3) == 0, "Zero margin")
        try require(DevelopmentEconomics.contribution(price: -150, margin: 0.75, renewal: 0.7, periods: 3) == 0, "Invalid inputs")
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        object["schemaVersion"] = 99
        try expectInvalid(object)
        object["schemaVersion"] = 1
        if let documents = object["documents"] as? [[String: Any]], let first = documents.first {
            object["documents"] = [first, first]
            try expectInvalid(object)
        }
        print("Development content OK: \(plan.sections.count) sections, \(plan.features.count) features; scenario calculations and validation passed.")
    }
}
