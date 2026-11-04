import Foundation
import SwiftUI
import UIKit
import PhotosUI
import SafariServices
import WebKit
import ContactsUI
import Contacts
import AVFoundation

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
            if let p=person { image=await store.loadAvatar(p.id).flatMap { UIImage(data:$0) } }
            else { image=nil }
        }
    }
}

struct EditProfileView: View {
    @EnvironmentObject private var store:ChatStore
    @State private var picked:PhotosPickerItem?
    @State private var savingAvatar=false
    @State private var avatarPreview:UIImage?
    @State private var name=""
    @State private var avatarStatus=""
    var body:some View {
        Form {
            Section("Аватар") {
                HStack {
                    if let avatarPreview {
                        Image(uiImage:avatarPreview).resizable().scaledToFill().frame(width:56,height:56).clipShape(Circle())
                    } else {
                        AvatarCircle(person:store.me,fallback:store.me?.display_name ?? "N")
                    }
                    PhotosPicker("Выбрать фото",selection:$picked,matching:.images)
                        .disabled(savingAvatar)
                    if savingAvatar {ProgressView()}
                }
                if !avatarStatus.isEmpty { Text(avatarStatus).font(.caption).foregroundStyle(.secondary) }
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
            guard let item else {return}
            Task {
                savingAvatar=true
                avatarStatus="Сохраняем фото на сервере…"
                defer {savingAvatar=false; picked=nil}
                guard let bytes=try? await item.loadTransferable(type:Data.self),
                      let img=UIImage(data:bytes) else {
                    avatarStatus="Не удалось прочитать фотографию. Выбери её ещё раз."
                    store.alertText=avatarStatus
                    return
                }
                let format=UIGraphicsImageRendererFormat()
                format.scale=1
                format.opaque=true
                let renderer=UIGraphicsImageRenderer(size:CGSize(width:512,height:512),format:format)
                let jpg=renderer.jpegData(withCompressionQuality:0.85) { _ in
                    UIColor.black.setFill()
                    UIRectFill(CGRect(x:0,y:0,width:512,height:512))
                    let scale=max(512/img.size.width,512/img.size.height)
                    let size=CGSize(width:img.size.width*scale,height:img.size.height*scale)
                    img.draw(in:CGRect(x:(512-size.width)/2,y:(512-size.height)/2,width:size.width,height:size.height))
                }
                let saved=await store.updateAvatar(jpg)
                if saved {
                    if let id=store.me?.id,let bytes=await store.loadAvatar(id) {
                        avatarPreview=UIImage(data:bytes)
                    }
                    avatarStatus="Фото сохранено на сервере"
                } else {
                    avatarStatus=store.alertText.isEmpty ? "Фото не сохранилось. Попробуй ещё раз." : store.alertText
                }
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

struct CallPresentation: Identifiable {
    let id = UUID()
    let url: URL
}


@MainActor
final class CallPageState: ObservableObject {
    @Published var loading = true
    @Published var failure: String?
    @Published var closing = false
    @Published var ended = false
    @Published var status = "Подключаем…"
    @Published var muted = false
    var microphoneAllowed = false
    var webReady = false
    var started = false
    weak var webView: WKWebView?
    var timeout: DispatchWorkItem?

    func fail(_ message:String) {
        timeout?.cancel()
        loading = false
        failure = message
    }
    func finishLoading() {
        timeout?.cancel()
        webReady = true
        loading = false
        failure = nil
        startAudioIfReady()
    }
    func startAudioIfReady() {
        guard webReady, microphoneAllowed, !started, !ended else {return}
        started = true
        // startCallAudio is an async JavaScript function and returns a Promise.
        // WKWebView.evaluateJavaScript cannot marshal Promises into Foundation.
        // Return a plain Bool instead and let the native bridge receive call status.
        let script = """
        (() => {
            if (typeof window.startCallAudio !== 'function') return false;
            void window.startCallAudio();
            return true;
        })()
        """
        guard let webView else {started=false;return}
        webView.evaluateJavaScript(script) { [weak self] result, error in
            guard let self else {return}
            if let error {
                self.started = false
                self.fail("Не удалось запустить звонок: \(error.localizedDescription)")
            } else if (result as? Bool) != true {
                self.started = false
                self.fail("Не удалось включить звонок. Обнови файлы сервера Nightwell Chat.")
            }
        }
    }
    func toggleMute() {
        guard started, !ended else {return}
        muted.toggle()
        let flag = muted ? "true" : "false"
        webView?.evaluateJavaScript("window.setCallMuted && window.setCallMuted(\(flag));") { _,_ in }
    }
    func end(_ completion:@escaping () -> Void) {
        guard !closing else { return }
        closing = true
        timeout?.cancel()
        var completed = false
        let finish = {
            guard !completed else { return }
            completed = true
            completion()
        }
        guard let webView else { finish(); return }
        webView.evaluateJavaScript("if(typeof closeCall === 'function') closeCall();") { _,_ in finish() }
        DispatchQueue.main.asyncAfter(deadline:.now()+1,execute:finish)
    }
}

struct CallScreen: View {
    let url:URL
    @EnvironmentObject private var store:ChatStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var page=CallPageState()
    @State private var attempt=0

    private var callID:String {
        let parts=url.pathComponents
        return parts.count>=3 ? parts[parts.count-2] : ""
    }

    var body:some View {
        ZStack {
            Color.black.ignoresSafeArea()
            // WebKit handles WebRTC audio; all visible controls are native SwiftUI.
            SafariCallView(url:url,page:page).id(attempt)
                .frame(width:250,height:200).opacity(0.015)
                .allowsHitTesting(false).accessibilityHidden(true)
            VStack(spacing:22) {
                Text("NIGHTWELL CHAT").tracking(4).font(.system(size:13,weight:.semibold))
                    .foregroundStyle(.gray).padding(.top,45)
                Spacer()
                Image(systemName:"person.crop.circle.fill").font(.system(size:120))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white,Color(white:0.17))
                Text("Голосовой звонок").font(.system(size:28,weight:.semibold))
                Text(page.failure ?? page.status).foregroundStyle(.gray)
                    .font(.system(size:16)).multilineTextAlignment(.center).padding(.horizontal,20)
                if page.loading {ProgressView().tint(.white)}
                if page.failure != nil {
                    Button("Повторить") {
                        page.failure=nil
                        // A timed-out ICE session requires a full page + peer reset.
                        page.loading=true;page.webReady=false;page.started=false
                        attempt += 1
                    }.buttonStyle(.borderedProminent)
                }
                Spacer()
                HStack(spacing:50) {
                    Button {
                        page.toggleMute()
                    } label:{
                        VStack(spacing:10) {
                            Image(systemName:page.muted ? "mic.slash.fill" : "mic.fill")
                                .font(.system(size:27)).frame(width:72,height:72)
                                .background(Color(white:0.22),in:Circle())
                            Text(page.muted ? "Включить" : "Микрофон").font(.caption)
                        }
                    }.disabled(!page.started || page.ended)
                    Button {page.end {dismiss()}} label:{
                        VStack(spacing:10) {
                            Image(systemName:"phone.down.fill").font(.system(size:29))
                                .frame(width:72,height:72).background(.red,in:Circle())
                            Text("Завершить").font(.caption)
                        }
                    }.disabled(page.closing)
                }.buttonStyle(.plain).foregroundStyle(.white).padding(.bottom,62)
            }.frame(maxWidth:.infinity,maxHeight:.infinity)
        }
        .interactiveDismissDisabled()
        .onChange(of:page.ended) {_,value in if value {dismiss()}}
        .onChange(of:store.endedCallID) {_,cid in if cid == callID {dismiss()}}
        .task {
            let allowed = await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in continuation.resume(returning:granted) }
            }
            page.microphoneAllowed = allowed
            if allowed {page.startAudioIfReady()}
            else {page.fail("Разреши микрофон Nightwell Chat в настройках iPhone")}
        }
    }
}

struct SafariCallView:UIViewRepresentable {
    let url:URL
    @ObservedObject var page:CallPageState
    func makeCoordinator()->Coordinator {Coordinator(url:url,page:page)}
    func makeUIView(context:Context)->WKWebView {
        let config=WKWebViewConfiguration()
        config.allowsInlineMediaPlayback=true
        config.mediaTypesRequiringUserActionForPlayback=[]
        config.userContentController.add(context.coordinator,name:"nightwellCall")
        let view=WKWebView(frame:.zero,configuration:config)
        view.uiDelegate=context.coordinator
        view.navigationDelegate=context.coordinator
        view.backgroundColor = .black
        view.scrollView.backgroundColor = .black
        view.isOpaque=false
        view.scrollView.isScrollEnabled=false
        view.scrollView.pinchGestureRecognizer?.isEnabled=false
        page.webView=view
        view.load(URLRequest(url:url,cachePolicy:.reloadIgnoringLocalCacheData,timeoutInterval:25))
        let deadline=DispatchWorkItem { [weak page] in
            guard let page,page.loading else {return}
            page.webView?.stopLoading()
            page.fail("Сервер не загрузил звонок. Проверь обновление сервера.")
        }
        page.timeout=deadline
        DispatchQueue.main.asyncAfter(deadline:.now()+30,execute:deadline)
        return view
    }
    func updateUIView(_ view:WKWebView,context:Context) {}
    static func dismantleUIView(_ view:WKWebView,coordinator:Coordinator) {
        coordinator.page.timeout?.cancel()
        view.stopLoading()
        view.configuration.userContentController.removeScriptMessageHandler(forName:"nightwellCall")
        view.loadHTMLString("",baseURL:nil)
        view.uiDelegate=nil
        view.navigationDelegate=nil
    }
    final class Coordinator:NSObject,WKUIDelegate,WKNavigationDelegate,WKScriptMessageHandler {
        let url:URL
        let page:CallPageState
        init(url:URL,page:CallPageState) {self.url=url;self.page=page}
        func userContentController(_ userContentController:WKUserContentController,didReceive message:WKScriptMessage) {
            guard message.frameInfo.securityOrigin.host == url.host,
                  let data=message.body as? [String:Any],
                  let kind=data["type"] as? String else {return}
            switch kind {
            case "ended": page.ended=true
            case "state":
                if let value=data["message"] as? String {
                    page.status=value
                    if value=="Разговор" {page.failure=nil}
                }
            case "call_error":
                page.fail((data["message"] as? String) ?? "Звонок не подключился. Попробуй ещё раз.")
            case "microphone_error":
                page.started=false
                page.fail((data["message"] as? String) ?? "Не удалось включить микрофон")
            case "microphone_ready":
                page.started=true
                page.failure=nil
            case "mute": page.muted=(data["message"] as? String)=="on"
            default: break
            }
        }
        func webView(_ webView:WKWebView,didFinish navigation:WKNavigation!) {
            webView.evaluateJavaScript("Boolean(document.getElementById('start') && document.getElementById('state') && window.NIGHTWELL_CALL_PAGE_VERSION === '0.11.11')") { [weak self] result,error in
                guard let self else{return}
                if result as? Bool == true {self.page.finishLoading()}
                else {self.page.fail("Устаревшая страница звонка. Обнови сервер Nightwell Chat.")}
            }
        }
        func webView(_ webView:WKWebView,didFailProvisionalNavigation navigation:WKNavigation!,withError error:Error) {failed(error)}
        func webView(_ webView:WKWebView,didFail navigation:WKNavigation!,withError error:Error) {failed(error)}
        private func failed(_ error:Error) {
            guard (error as NSError).code != NSURLErrorCancelled else{return}
            page.fail("Не удалось открыть звонок: \(error.localizedDescription)")
        }
        func webViewWebContentProcessDidTerminate(_ webView:WKWebView) {
            page.fail("Экран звонка остановился. Нажми «Повторить».")
        }
        func webView(_ webView:WKWebView,decidePolicyFor response:WKNavigationResponse,
                     decisionHandler:@escaping (WKNavigationResponsePolicy)->Void) {
            if response.isForMainFrame,let http=response.response as? HTTPURLResponse,!(200..<300).contains(http.statusCode) {
                page.fail("Ошибка открытия звонка: HTTP \(http.statusCode).")
                decisionHandler(.cancel)
            } else {decisionHandler(.allow)}
        }
        func webView(_ webView:WKWebView,decidePolicyFor action:WKNavigationAction,
                     decisionHandler:@escaping (WKNavigationActionPolicy)->Void) {
            guard let target=action.request.url,target.scheme=="https",
                  target.host==url.host,target.port==url.port else {
                decisionHandler(.cancel);return
            }
            decisionHandler(.allow)
        }
        @available(iOS 15.0,*)
        func webView(_ webView:WKWebView,requestMediaCapturePermissionFor origin:WKSecurityOrigin,
                     initiatedByFrame frame:WKFrameInfo,type:WKMediaCaptureType,
                     decisionHandler:@escaping (WKPermissionDecision)->Void) {
            let originPort=origin.port == 0 ? 443 : origin.port
            let expectedPort=url.port ?? 443
            let allowed=origin.protocol=="https" && origin.host==url.host && originPort==expectedPort && page.microphoneAllowed
            decisionHandler(allowed ? .grant : .deny)
        }
    }
}

struct IncomingCallOverlay:View {
    let call:VoiceCall
    @EnvironmentObject private var store:ChatStore
    @State private var acceptedURL:URL?
    @State private var answering=false
    var body:some View {
        Group {
            if let acceptedURL {
                CallScreen(url:acceptedURL)
            } else {
                ZStack {
                    Color.black.ignoresSafeArea()
                    VStack(spacing:24) {
                        Text("NIGHTWELL CHAT").tracking(4).foregroundStyle(.gray)
                        Spacer()
                        Image(systemName:"phone.arrow.down.left.fill")
                            .font(.system(size:66))
                            .frame(width:140,height:140).background(Color(white:0.15),in:Circle())
                        Text(call.caller_name ?? "Входящий звонок").font(.system(size:30,weight:.semibold))
                        Text("Входящий голосовой вызов").foregroundStyle(.gray)
                        if answering {ProgressView().tint(.white)}
                        Spacer()
                        HStack(spacing:55) {
                            Button {
                                Task {await store.declineCall(id:call.id);store.incomingCall=nil}
                            } label:{
                                Image(systemName:"phone.down.fill").font(.system(size:30))
                                    .frame(width:76,height:76).background(.red,in:Circle())
                            }
                            Button {
                                answering=true
                                Task {
                                    if let answer=await store.acceptCall(id:call.id),
                                       let url=store.voiceURL(answer) {acceptedURL=url}
                                    else {store.incomingCall=nil}
                                    answering=false
                                }
                            } label:{
                                Image(systemName:"phone.fill").font(.system(size:30))
                                    .frame(width:76,height:76).background(.green,in:Circle())
                            }.disabled(answering)
                        }.buttonStyle(.plain).foregroundStyle(.white).padding(.bottom,65)
                    }.padding(24)
                }
            }
        }
        .onChange(of:store.endedCallID) {_,cid in if cid == call.id {store.incomingCall=nil}}
        .task {
            while !Task.isCancelled && acceptedURL == nil {
                try? await Task.sleep(for:.seconds(4))
                if Task.isCancelled || acceptedURL != nil {break}
                let pending=await store.pendingCalls()
                if !pending.contains(where:{$0.id==call.id}) {store.incomingCall=nil;break}
            }
        }
    }
}

struct IncomingCallsView:View {
    @EnvironmentObject private var store:ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var calls:[VoiceCall]=[]
    var body:some View {
        NavigationStack {
            List {
                ForEach(calls){call in
                    VStack(alignment:.leading,spacing:12){
                        Text(call.caller_name ?? "Входящий звонок")
                        HStack {
                            Button("Ответить"){
                                Task{
                                    store.incomingCall=call
                                    dismiss()
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
