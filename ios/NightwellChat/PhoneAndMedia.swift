import Foundation
import SwiftUI
import UIKit
import PhotosUI
import SafariServices
import ContactsUI

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
