import Foundation
import SwiftUI
import UIKit
import PhotosUI
import SafariServices
import ContactsUI
import Contacts

struct PhoneContactPicker: UIViewControllerRepresentable {
    var select: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(select: select) }
    func makeUIViewController(context:Context) -> CNContactPickerViewController {
        let picker=CNContactPickerViewController()
        picker.displayedPropertyKeys=[CNContactPhoneNumbersKey]
        picker.predicateForEnablingContact=NSPredicate(format:"phoneNumbers.@count > 0")
        picker.delegate=context.coordinator
        return picker
    }
    func updateUIViewController(_ picker:CNContactPickerViewController,context:Context) {}
    final class Coordinator:NSObject,CNContactPickerDelegate {
        let select:(String)->Void
        init(select:@escaping (String)->Void){self.select=select}
        func contactPicker(_ picker:CNContactPickerViewController,didSelect contactProperty:CNContactProperty) {
            if let number=contactProperty.value as? CNPhoneNumber { select(number.stringValue) }
        }
        func contactPicker(_ picker:CNContactPickerViewController,didSelect contact:CNContact) {
            if let number=contact.phoneNumbers.first?.value.stringValue {select(number)}
        }
    }
}

struct PrivateImage: View {
    @EnvironmentObject private var store:ChatStore
    let attachment:Int
    @State private var image:UIImage?
    var body:some View {
        Group {
            if let image {
                Image(uiImage:image).resizable().scaledToFit().frame(maxWidth:230,maxHeight:260)
            } else {
                ProgressView().tint(.white).frame(width:160,height:100)
            }
        }.task(id:attachment) {
            if let data=try? await store.authorizedData("/attachments/\(attachment)") {
                image=UIImage(data:data)
            }
        }
    }
}

struct AvatarCircle: View {
    @EnvironmentObject private var store:ChatStore
    let person:Person?
    let fallback:String
    @State private var image:UIImage?
    var body:some View {
        Group {
            if let image {
                Image(uiImage:image).resizable().scaledToFill()
            } else {
                Text(String(fallback.prefix(1)).uppercased())
                    .font(.title2).foregroundStyle(.white)
            }
        }
        .frame(width:56,height:56)
        .background(.white.opacity(0.12),in:Circle())
        .clipShape(Circle())
        .task(id:"\(person?.id ?? 0)-\(store.eventVersion)") {
            image=nil
            if let p=person,p.has_avatar == true,
               let bytes=await store.loadAvatar(p.id) { image=UIImage(data:bytes) }
        }
    }
}

struct EditProfileView: View {
    @EnvironmentObject private var store:ChatStore
    @State private var picked:PhotosPickerItem?
    @State private var name=""
    var body:some View {
        Form {
            Section("Аватар") {
                HStack {
                    AvatarCircle(person:store.me,fallback:store.me?.display_name ?? "N")
                    PhotosPicker("Выбрать фото",selection:$picked,matching:.images)
                }
            }
            Section("Имя") {
                TextField("Имя",text:$name)
                Button("Сохранить") {Task {await store.saveProfile(name)}}
            }
            Section("Телефон") {
                NavigationLink("Привязка и приватность"){PhoneLinkView()}
            }
        }.navigationTitle("Мой профиль")
        .onAppear{name=store.me?.display_name ?? ""}
        .onChange(of:picked){_,item in
            Task {
                guard let bytes=try? await item?.loadTransferable(type:Data.self),
                      let img=UIImage(data:bytes),
                      let jpg=img.jpegData(compressionQuality:0.86) else{return}
                await store.updateAvatar(jpg)
            }
        }
    }
}

struct PhoneLinkView:View {
    @EnvironmentObject private var store:ChatStore
    @State private var number=""
    @State private var password=""
    @State private var discoverable=false
    var body:some View {
        Form {
            Section("Номер телефона") {
                if let phone=store.phoneStatus?.phone {
                    Text(phone)
                    Toggle("Меня можно найти по номеру",isOn:Binding(
                        get:{store.phoneStatus?.discoverable ?? false},
                        set:{value in Task {await store.discover(value)}}
                    ))
                } else {
                    TextField("+79991234567",text:$number).keyboardType(.phonePad)
                    SecureField("Пароль от аккаунта",text:$password)
                    Toggle("Разрешить поиск по номеру",isOn:$discoverable)
                    Button("Привязать номер") {Task {await store.attachPhone(number,password:password,discoverable:discoverable)}}
                        .disabled(number.count<8 || password.count<8)
                }
                Text("Без SMS подтверждается только формат номера. Для безопасности используй уникальный пароль.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle("Телефон").task{await store.phoneState()}
    }
}

struct SafariCallView:UIViewControllerRepresentable {
    let url:URL
    func makeUIViewController(context:Context)->SFSafariViewController {
        let c=SFSafariViewController(url:url)
        c.preferredControlTintColor = .white
        return c
    }
    func updateUIViewController(_ vc:SFSafariViewController,context:Context){}
}

struct IncomingCallsView:View {
    @EnvironmentObject private var store:ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var calls:[VoiceCall]=[]
    @State private var current:URL?
    @State private var show=false
    var body:some View {
        NavigationStack {
            List {
                ForEach(calls){call in
                    VStack(alignment:.leading,spacing:12){
                        Text(call.caller_name ?? "Входящий звонок")
                        HStack {
                            Button("Ответить"){
                                Task{
                                    if let answer=await store.acceptCall(id:call.id),
                                       let url=store.voiceURL(answer){current=url;show=true}
                                }
                            }
                            Button("Отклонить",role:.destructive){
                                Task{await store.declineCall(id:call.id);await reload()}
                            }
                        }
                    }
                }
            }.navigationTitle("Звонки")
            .toolbar{ToolbarItem(placement:.topBarTrailing){Button("Готово"){dismiss()}}}
            .task{await reload()}
            .refreshable{await reload()}
            .sheet(isPresented:$show){if let current {SafariCallView(url:current)}}
        }
    }
    func reload() async {calls=await store.pendingCalls()}
}


struct PhoneEntry: Identifiable {
    let id:String
    let name:String
    let phone:String
}

// User-triggered local address book access. No contact list is uploaded to the API.
final class PhoneContactsStore: ObservableObject {
    @Published var entries:[PhoneEntry]=[]
    @Published var errorMessage:String?
    @Published var loading=false
    private let store=CNContactStore()

    func requestContacts() {
        switch CNContactStore.authorizationStatus(for:.contacts) {
        case .notDetermined:
            store.requestAccess(for:.contacts) { [weak self] granted, _ in
                DispatchQueue.main.async {
                    if granted { self?.fetchContacts() }
                    else { self?.errorMessage="Доступ к контактам не предоставлен. Разреши его в настройках iPhone." }
                }
            }
        case .denied, .restricted:
            errorMessage="Доступ к контактам ограничен. Разреши его в настройках iPhone."
        default:
            fetchContacts()
        }
    }

    private func fetchContacts() {
        loading=true
        errorMessage=nil
        DispatchQueue.global(qos:.userInitiated).async { [weak self] in
            guard let self else {return}
            var output:[PhoneEntry]=[]
            var failure:String?
            let fields:[CNKeyDescriptor]=[
                CNContactGivenNameKey as CNKeyDescriptor,
                CNContactFamilyNameKey as CNKeyDescriptor,
                CNContactPhoneNumbersKey as CNKeyDescriptor
            ]
            do {
                let request=CNContactFetchRequest(keysToFetch:fields)
                try self.store.enumerateContacts(with:request) { contact, _ in
                    let name=[contact.givenName,contact.familyName]
                        .filter{ !$0.isEmpty }.joined(separator:" ")
                    for (idx,phone) in contact.phoneNumbers.enumerated() {
                        let number=phone.value.stringValue
                        if !number.isEmpty {
                            output.append(PhoneEntry(id:"\(contact.identifier)-\(idx)",
                                name:name.isEmpty ? number : name,phone:number))
                        }
                    }
                }
                output.sort{ $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            } catch {
                failure="Не удалось прочитать контакты: \(error.localizedDescription)"
            }
            DispatchQueue.main.async {
                self.entries=output
                self.errorMessage=failure
                self.loading=false
            }
        }
    }
}

struct PhoneContactsView:View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var contacts=PhoneContactsStore()
    @State private var query=""
    let onPick:(String)->Void

    private var filtered:[PhoneEntry] {
        guard !query.isEmpty else { return contacts.entries }
        return contacts.entries.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.phone.localizedCaseInsensitiveContains(query)
        }
    }

    var body:some View {
        NavigationStack {
            List {
                Section {
                    Text("Выбери контакт для поиска в Nightwell. Адресная книга остаётся на iPhone.")
                        .font(.caption).foregroundStyle(.secondary)
                    if contacts.loading { ProgressView("Читаем контакты…") }
                    if let error=contacts.errorMessage {
                        Text(error).font(.caption)
                        Button("Открыть настройки iPhone") {
                            if let url=URL(string:UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                }
                Section("Контакты (\(filtered.count))") {
                    ForEach(filtered) { entry in
                        Button {
                            onPick(entry.phone)
                            dismiss()
                        } label: {
                            VStack(alignment:.leading,spacing:4) {
                                Text(entry.name).foregroundStyle(.primary)
                                Text(entry.phone).font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical,3)
                        }
                    }
                }
            }
            .searchable(text:$query,prompt:"Имя или номер")
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Контакты iPhone")
            .toolbar {
                ToolbarItem(placement:.topBarTrailing) {
                    Button("Готово"){dismiss()}
                }
            }
        }.onAppear {contacts.requestContacts()}
    }
}
