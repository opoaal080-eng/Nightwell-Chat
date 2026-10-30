import SwiftUI
import Contacts

// The complete address book stays on this device. Only a tapped number
// is sent to the exact-match /users/by-phone API endpoint.
struct LocalPhoneNumber: Identifiable, Sendable {
    let id: String
    let name: String
    let number: String
}

@MainActor
final class LocalContactsModel: ObservableObject {
    @Published var numbers: [LocalPhoneNumber] = []
    @Published var error = ""
    @Published var loading = false

    func load() async {
        loading = true
        defer { loading = false }
        let store = CNContactStore()
        do {
            let status = CNContactStore.authorizationStatus(for: .contacts)
            if status == .denied || status == .restricted {
                error = "Доступ к контактам запрещён. Его можно включить в настройках iPhone."
                return
            }
            if status == .notDetermined {
                let accepted = try await store.requestAccess(for: .contacts)
                if !accepted {
                    error = "Доступ к контактам не предоставлен"
                    return
                }
            }
            let values = try await Task.detached(priority: .userInitiated) { () throws -> [LocalPhoneNumber] in
                let contactStore = CNContactStore()
                let keys: [CNKeyDescriptor] = [CNContactGivenNameKey as CNKeyDescriptor,
                    CNContactFamilyNameKey as CNKeyDescriptor,
                    CNContactPhoneNumbersKey as CNKeyDescriptor]
                let request = CNContactFetchRequest(keysToFetch: keys)
                var result: [LocalPhoneNumber] = []
                try contactStore.enumerateContacts(with: request) { contact, _ in
                    let fullName = [contact.givenName, contact.familyName]
                        .filter { !$0.isEmpty }.joined(separator: " ")
                    for (i, phone) in contact.phoneNumbers.enumerated() {
                        result.append(LocalPhoneNumber(
                            id: "\(contact.identifier)-\(i)",
                            name: fullName.isEmpty ? "Без имени" : fullName,
                            number: phone.value.stringValue))
                    }
                }
                return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            }.value
            numbers = values
        } catch {
            self.error = "Не удалось прочитать контакты: \(error.localizedDescription)"
        }
    }
}

struct LocalContactsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = LocalContactsModel()
    @State private var filter = ""
    let onSelect: (String) -> Void

    private var visible: [LocalPhoneNumber] {
        guard !filter.isEmpty else { return model.numbers }
        return model.numbers.filter {
            $0.name.localizedCaseInsensitiveContains(filter) || $0.number.contains(filter)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if model.loading { ProgressView("Загружаем контакты на iPhone") }
                if !model.error.isEmpty {
                    Text(model.error).foregroundStyle(.secondary)
                }
                ForEach(visible) { contact in
                    Button { onSelect(contact.number) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(contact.name).foregroundStyle(.white)
                            Text(contact.number).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(.black)
            .searchable(text: $filter, prompt: "Имя или номер")
            .navigationTitle("Контакты iPhone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Закрыть") { dismiss() } } }
        }.tint(.white).task { await model.load() }
    }
}
