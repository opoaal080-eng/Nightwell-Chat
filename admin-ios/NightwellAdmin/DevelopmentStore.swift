import SwiftUI

@MainActor
final class DevelopmentStore: ObservableObject {
    @Published private(set) var documents: [DevelopmentPlan] = []
    @Published private(set) var errorMessage: String?
    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
        reload()
    }

    func reload() {
        do {
            guard let url = bundle.url(forResource: "development-library", withExtension: "json",
                                       subdirectory: "DevelopmentResources") else {
                throw DevelopmentContentError.invalid("Материалы развития не включены в эту сборку.")
            }
            let library = try JSONDecoder().decode(DevelopmentLibrary.self, from: Data(contentsOf: url))
            try library.validate()
            documents = library.documents
            errorMessage = nil
        } catch {
            documents = []
            errorMessage = "Не удалось открыть материалы. \(error.localizedDescription)"
        }
    }
}
