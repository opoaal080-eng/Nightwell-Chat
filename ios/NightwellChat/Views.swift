import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import QuickLook
import AVKit

private let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
private let appBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"

private let ink = Color.black
private let white = Color.white
private let muted = Color(white: 0.63)
private let glassBlue = Color(red:0.38,green:0.66,blue:1.0)

struct NightwellBackground: View {
    var body:some View {
        ZStack {
            Color(red:0.025,green:0.035,blue:0.065)
            RadialGradient(colors:[glassBlue.opacity(0.22),.clear],center:.topTrailing,startRadius:10,endRadius:450)
            RadialGradient(colors:[Color.purple.opacity(0.12),.clear],center:.bottomLeading,startRadius:30,endRadius:380)
        }.ignoresSafeArea()
    }
}

struct GlassPanel: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(14).background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:24))
            .overlay(RoundedRectangle(cornerRadius:24).stroke(LinearGradient(colors:[white.opacity(0.32),white.opacity(0.04)],startPoint:.topLeading,endPoint:.bottomTrailing),lineWidth:1))
            .shadow(color:.black.opacity(0.20),radius:16,y:8)
    }
}
extension View { func glass() -> some View { modifier(GlassPanel()) } }

struct RootView: View {
    @EnvironmentObject var store: ChatStore
    var body: some View {
        Group {
            if store.token.isEmpty { LoginView() }
            else { InboxView() }
        }
        .tint(.white)
        .background(NightwellBackground())
        .alert("Nightwell Chat",isPresented:Binding(get:{ !store.alertText.isEmpty },set:{ if !$0 { store.alertText = "" } })) {
            Button("ОК",role:.cancel) { store.alertText = "" }
        } message: { Text(store.alertText) }
    }
}

struct Logo: View {
    var compact = false
    var body: some View {
        VStack(spacing:9) {
            Image(systemName:"bubble.left.and.bubble.right.fill")
                .font(.system(size: compact ? 28 : 44,weight:.ultraLight))
                .symbolRenderingMode(.hierarchical)
                .frame(width:compact ? 52 : 88,height:compact ? 52 : 88)
                .background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:compact ? 16 : 28))
                .overlay(RoundedRectangle(cornerRadius:compact ? 16 : 28).stroke(white.opacity(0.17)))
            Text("NIGHTWELL").font(.system(size:compact ? 14 : 23,weight:.light,design:.rounded)).tracking(5)
            if !compact { Text("CHAT").font(.system(size:11,weight:.medium)).tracking(9).foregroundStyle(muted) }
        }.foregroundStyle(white)
    }
}

struct LoginView:View {
    @State private var legacy=false
    var body:some View {
        ScrollView {
            VStack(spacing:20) {
                Logo()
                if legacy {LegacyLoginView()} else {PhoneLoginFields()}
                Button(legacy ? "Вход по номеру" : "Старый аккаунт: логин и пароль") {
                    legacy.toggle()
                }.font(.footnote).foregroundStyle(.gray)
            }.padding(24)
        }.background(NightwellBackground())
        .scrollDismissesKeyboard(.interactively)
    }
}

struct PhoneLoginFields:View {
    @EnvironmentObject var store:ChatStore
    @FocusState private var keyboardVisible:Bool
    @State private var registering=false
    @State private var number=""
    @State private var password=""
    @State private var displayName=""
    @State private var discoverable=false
    var body:some View {
        VStack(spacing:14){
            Text(registering ? "Регистрация" : "Вход по номеру")
                .font(.title2.bold())
            TextField("+79991234567",text:$number)
                .keyboardType(.phonePad).textContentType(.telephoneNumber)
                .textFieldStyle(.roundedBorder)
                .focused($keyboardVisible)
            if registering {
                TextField("Твоё имя",text:$displayName).textFieldStyle(.roundedBorder)
                    .focused($keyboardVisible)
                Toggle("Разрешить поиск по номеру",isOn:$discoverable)
            }
            SecureField("Пароль от 8 символов",text:$password).textFieldStyle(.roundedBorder)
                .focused($keyboardVisible)
            if keyboardVisible {
                Button { keyboardVisible=false } label: {
                    Label("Скрыть клавиатуру",systemImage:"keyboard.chevron.compact.down")
                }.font(.subheadline).frame(maxWidth:.infinity,alignment:.trailing)
            }
            Button(registering ? "Создать аккаунт" : "Войти"){
                Task{await store.loginByPhone(number,password:password,
                    name:registering ? displayName : nil,discoverable:discoverable)}
            }
            .buttonStyle(.borderedProminent)
            .tint(.white).foregroundStyle(.black)
            .disabled(store.loading || number.count<8 || password.count<8 || (registering && displayName.isEmpty))
            Button(registering ? "У меня есть аккаунт" : "Зарегистрироваться"){
                registering.toggle()
            }.font(.footnote)
            Text("SMS не используется. Проверяется формат номера, а не принадлежность SIM-карты.")
                .font(.caption).foregroundStyle(.gray).multilineTextAlignment(.center)
            Text("Nightwell Chat \(appVersion) • вход по телефону")
                .font(.caption2).foregroundStyle(.gray)
        }.padding(18).glass()
    }
}

struct LegacyLoginView: View {
    @EnvironmentObject var store: ChatStore
    @FocusState private var keyboardVisible:Bool
    @State private var register = false
    @State private var username = ""
    @State private var password = ""
    @State private var displayName = ""
    var body: some View {
        ScrollView {
            VStack(spacing:30) {
                Spacer(minLength:70)
                Logo()
                VStack(spacing:16) {
                    Text(register ? "Создать аккаунт" : "С возвращением")
                        .font(.system(size:27,weight:.semibold))
                    TextField("Имя пользователя",text:$username).textInputAutocapitalization(.never)
                        .autocorrectionDisabled().textContentType(.username)
                        .textFieldStyle(.roundedBorder).focused($keyboardVisible)
                    if register { TextField("Отображаемое имя",text:$displayName).textFieldStyle(.roundedBorder).focused($keyboardVisible) }
                    SecureField("Пароль от 8 символов",text:$password)
                        .textContentType(register ? .newPassword : .password).textFieldStyle(.roundedBorder).focused($keyboardVisible)
                    if keyboardVisible {
                        Button("Скрыть клавиатуру") { keyboardVisible=false }
                            .frame(maxWidth:.infinity,alignment:.trailing).font(.caption)
                    }
                    Button {
                        Task { await store.login(username:username,password:password,displayName:register ? displayName : nil) }
                    } label: {
                        Text(register ? "Зарегистрироваться" : "Войти")
                            .frame(maxWidth:.infinity).padding(.vertical,12)
                    }
                    .buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)
                    .disabled(store.loading || username.isEmpty || password.isEmpty)
                    Button(register ? "Уже есть аккаунт? Войти" : "Нет аккаунта? Создать") { register.toggle() }
                        .font(.footnote).foregroundStyle(muted)
                }.glass()
                Text("Приватный сервер Nightwell · HTTPS").font(.caption).foregroundStyle(muted)
            }.padding(24)
        }.background(ink)
    }
}

struct InboxView: View {
    @EnvironmentObject var store: ChatStore
    @State private var findPeople = false
    @State private var group = false
    @State private var settings = false
    @State private var calls = false
    @State private var selected: Conversation?
    @State private var chatFilter = 0
    @State private var query = ""
    @State private var editing = false
    @State private var checked: Set<Int> = []
    private let accent = Color(red:0.34,green:0.50,blue:0.94)

    private var filteredChats: [Conversation] {
        let term = query.trimmingCharacters(in:.whitespacesAndNewlines)
        return store.chats.filter {
            (chatFilter == 0 || $0.kind != "group") &&
            (term.isEmpty || $0.title.localizedCaseInsensitiveContains(term) ||
             ($0.other_user?.username.localizedCaseInsensitiveContains(term) ?? false) ||
             ($0.last_message?.body.localizedCaseInsensitiveContains(term) ?? false))
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing:0) {
                    if filteredChats.isEmpty {
                        ContentUnavailableView(query.isEmpty ? "Пока нет переписок" : "Ничего не найдено",
                            systemImage:"bubble.left.and.bubble.right",
                            description:Text(query.isEmpty ? "Найди пользователя и начни общение" : "Попробуй другое имя или текст"))
                            .padding(.top,36)
                    }
                    ForEach(filteredChats) { chat in
                        Button {
                            if editing {
                                if checked.contains(chat.id) { checked.remove(chat.id) }
                                else { checked.insert(chat.id) }
                            } else { selected = chat }
                        } label: { inboxRow(chat) }
                        .buttonStyle(.plain)
                        Rectangle().fill(Color.white.opacity(0.09)).frame(height:0.5)
                            .padding(.leading,70)
                    }
                }.padding(.horizontal,16)
            }
            .background(Color.black.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden,for:.navigationBar)
            .safeAreaInset(edge:.top,spacing:0) { inboxHeader }
            .safeAreaInset(edge:.bottom,spacing:0) { inboxDock }
            .navigationDestination(item:$selected) { ChatView(chat:$0).toolbar(.visible,for:.navigationBar) }
            .sheet(isPresented:$findPeople) { PeopleView { chat in findPeople=false; selected=chat } }
            .sheet(isPresented:$group) { GroupView { chat in group=false; selected=chat } }
            .sheet(isPresented:$settings) { SettingsView() }
            .sheet(isPresented:$calls) { IncomingCallsView() }
            .refreshable { await store.reloadChats() }
            .task { await store.reloadChats() }
            .onChange(of:store.eventVersion) { _,_ in Task { await store.reloadChats() } }
        }
    }

    private var inboxHeader: some View {
        VStack(spacing:10) {
            ZStack {
                Text("Чаты").font(.system(size:17,weight:.semibold))
                HStack(spacing:12) {
                    Button {
                        withAnimation(.easeInOut(duration:0.2)) { editing.toggle(); checked.removeAll() }
                    } label: {
                        Text(editing ? "Готово" : "Изм.")
                            .font(.system(size:17,weight:.semibold))
                            .padding(.horizontal,15).frame(height:44)
                            .background(Color(white:0.12),in:Capsule())
                            .overlay(Capsule().stroke(Color.white.opacity(0.12)))
                    }
                    Spacer()
                    Button { group=true } label: {
                        Image(systemName:"plus.circle.dashed").font(.system(size:23))
                            .frame(width:44,height:44)
                            .background(Color(white:0.12),in:Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.12)))
                    }.accessibilityLabel("Создать группу")
                    Button { findPeople=true } label: {
                        Image(systemName:"square.and.pencil").font(.system(size:23))
                            .frame(width:44,height:44).background(accent,in:Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.2)))
                    }.accessibilityLabel("Новый чат")
                }
            }.padding(.bottom,1)
            HStack(spacing:0) {
                filterButton("Все",index:0)
                filterButton("Personal",index:1)
            }
            .padding(3).background(Color(white:0.12),in:Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.18)))
            HStack(spacing:10) {
                Image(systemName:"magnifyingglass").font(.system(size:20)).foregroundStyle(Color.gray)
                TextField("Поиск чатов",text:$query)
                    .font(.system(size:17)).textInputAutocapitalization(.never).autocorrectionDisabled()
                if !query.isEmpty {
                    Button { query="" } label: { Image(systemName:"xmark.circle.fill").foregroundStyle(.gray) }
                        .accessibilityLabel("Очистить поиск")
                }
            }.padding(.horizontal,12).frame(height:42)
                .background(Color(white:0.095),in:Capsule())
            if editing {
                Button("Прочитать выбранные (\(checked.count))") {
                    let ids = checked
                    Task {
                        for chat in store.chats where ids.contains(chat.id) {
                            if let last = chat.last_message {
                                await store.markRead(chatID:chat.id,messageID:last.id)
                            }
                        }
                        await store.reloadChats()
                        checked.removeAll()
                        editing=false
                    }
                }.font(.subheadline).disabled(checked.isEmpty).padding(.vertical,4)
            }
        }
        .foregroundStyle(.white).buttonStyle(.plain)
        .padding(.horizontal,16).padding(.top,10).padding(.bottom,4)
        .background(Color.black)
    }

    private func filterButton(_ title:String,index:Int) -> some View {
        Button { withAnimation(.easeInOut(duration:0.2)) { chatFilter=index } } label: {
            Text(title).font(.system(size:17,weight:.medium))
                .frame(maxWidth:.infinity).frame(height:38)
                .background(chatFilter == index ? Color(white:0.27) : Color.clear,in:Capsule())
        }
    }

    private func inboxRow(_ chat:Conversation) -> some View {
        HStack(alignment:.top,spacing:10) {
            if editing {
                Image(systemName:checked.contains(chat.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(accent).padding(.top,20)
            }
            InboxAvatar(person:chat.other_user,title:chat.title)
            VStack(alignment:.leading,spacing:3) {
                HStack(alignment:.firstTextBaseline) {
                    Text(chat.title).font(.system(size:18,weight:.semibold)).lineLimit(1)
                    Spacer(minLength:8)
                    Text(inboxDate(chat.last_message?.created_at))
                        .font(.system(size:13)).foregroundStyle(Color(white:0.53))
                }
                HStack(alignment:.top) {
                    Text(preview(chat)).font(.system(size:17))
                        .foregroundStyle(Color(white:0.53)).lineLimit(1)
                    Spacer(minLength:4)
                    if chat.unread > 0 {
                        Text("\(chat.unread)").font(.system(size:12,weight:.semibold))
                            .padding(.horizontal,7).padding(.vertical,2)
                            .background(accent,in:Capsule())
                    }
                }
            }.padding(.top,1)
        }.foregroundStyle(.white).padding(.vertical,8)
            .frame(maxWidth:.infinity,minHeight:76,alignment:.topLeading)
            .contentShape(Rectangle())
    }

    private func preview(_ chat:Conversation) -> String {
        guard let last=chat.last_message else { return chat.kind == "group" ? "Новая группа" : "Новый чат" }
        return last.body.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? "Вложение" : last.body
    }

    private func inboxDate(_ raw:String?) -> String {
        guard let raw else { return "" }
        let iso=ISO8601DateFormatter()
        iso.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
        var date=iso.date(from:raw)
        if date == nil {
            iso.formatOptions=[.withInternetDateTime]
            date=iso.date(from:raw)
        }
        if date == nil {
            let sql=DateFormatter()
            sql.locale=Locale(identifier:"en_US_POSIX")
            sql.timeZone=TimeZone(secondsFromGMT:0)
            for format in ["yyyy-MM-dd'T'HH:mm:ss.SSSSSS","yyyy-MM-dd'T'HH:mm:ss","yyyy-MM-dd HH:mm:ss"] {
                sql.dateFormat=format
                if let parsed=sql.date(from:raw) { date=parsed; break }
            }
        }
        guard let date else { return "" }
        let formatter=DateFormatter()
        formatter.locale=Locale(identifier:"ru_RU")
        formatter.dateFormat="dd.MM"
        return formatter.string(from:date)
    }

    private var inboxDock: some View {
        HStack(spacing:0) {
            dockButton("Контакты",icon:"person.crop.circle.fill",active:false) { findPeople=true }
            dockButton("Звонки",icon:"phone.fill",active:false) { calls=true }
            dockButton("Чаты",icon:"bubble.left.and.bubble.right.fill",active:true) { }
            dockButton("Настройки",icon:"gearshape",active:false) { settings=true }
        }.padding(4).background(Color(white:0.12),in:Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.16)))
            .padding(.horizontal,20).padding(.top,6).padding(.bottom,5)
            .background(Color.black)
    }

    private func dockButton(_ title:String,icon:String,active:Bool,action:@escaping () -> Void) -> some View {
        Button(action:action) {
            VStack(spacing:4) {
                Image(systemName:icon).font(.system(size:27,weight:.medium)).frame(height:31)
                Text(title).font(.system(size:11,weight:.medium)).lineLimit(1).minimumScaleFactor(0.75)
            }.foregroundStyle(active ? accent : Color.white)
                .frame(maxWidth:.infinity).frame(height:56)
                .background(active ? Color(white:0.23) : Color.clear,in:Capsule())
                .contentShape(Capsule())
        }.buttonStyle(.plain)
            .accessibilityAddTraits(active ? .isSelected : [])
    }
}

private struct InboxAvatar: View {
    @EnvironmentObject var store: ChatStore
    let person:Person?
    let title:String
    @State private var image:UIImage?
    private var avatarColor: Color {
        let palette:[Color] = [.orange,.purple,.cyan,.pink,.green,.blue]
        let seed=title.unicodeScalars.reduce(0) { ($0 + Int($1.value)) % 997 }
        return palette[seed % palette.count]
    }
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors:[avatarColor.opacity(0.65),avatarColor],
                                         startPoint:.top,endPoint:.bottom))
            if let image {
                Image(uiImage:image).resizable().scaledToFill()
            } else {
                Text(String(title.prefix(1))).font(.system(size:29,weight:.medium)).foregroundStyle(.white)
            }
        }.frame(width:60,height:60).clipShape(Circle())
            .task(id:"\(person?.id ?? 0)-\(person?.has_avatar ?? false)-\(store.eventVersion)") {
                if let person { image=await store.loadAvatar(person.id).flatMap { UIImage(data:$0) } }
                else { image=nil }
            }
    }
}

struct PeopleView: View {
    @EnvironmentObject var store: ChatStore
    @Environment(\.dismiss) var dismiss
    @State private var query = ""
    @State private var people: [Person] = []
    @State private var number=""
    @State private var matched:Person?
    @State private var picked=false
    @State private var contacts=false
    @FocusState private var searchFocused:Bool
    let onOpen: (Conversation) -> Void
    var body: some View {
        NavigationStack {
            List {
                Section("Поиск по телефону") {
                    HStack {
                        TextField("+79991234567",text:$number).keyboardType(.phonePad).focused($searchFocused)
                        Button("Найти"){Task {matched=await store.searchPhone(number);picked=true}}
                    }
                    Button { searchFocused=false; contacts=true } label: {
                        Label("Открыть контакты iPhone",systemImage:"person.crop.rectangle.stack")
                    }
                    if let matched {
                        Button(matched.display_name){Task{if let chat=await store.openDirect(matched){onOpen(chat)}}}
                    } else if picked {
                        Text("Не найден или скрыл номер").font(.caption).foregroundStyle(.gray)
                    }
                    Text("Отправляем на сервер только выбранный номер, не всю адресную книгу.")
                        .font(.caption).foregroundStyle(.gray)
                }
                HStack {
                    TextField("Поиск по имени или @нику",text:$query).textInputAutocapitalization(.never)
                        .autocorrectionDisabled().onSubmit { Task { people=await store.find(query) } }
                    Button { Task { people=await store.find(query) } } label:{ Image(systemName:"magnifyingglass") }
                }
                ForEach(people) { person in
                    Button { Task { if let chat=await store.openDirect(person) { onOpen(chat) } } } label: {
                        VStack(alignment:.leading) { Text(person.display_name).foregroundStyle(.white)
                            Text("@\(person.username)").foregroundStyle(muted).font(.caption) }
                    }
                }
            }.scrollContentBackground(.hidden).background(ink)
                .scrollDismissesKeyboard(.interactively)
                .navigationTitle("Новый чат").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.topBarLeading) { Button("Закрыть") { dismiss() } } }
        }
        .sheet(isPresented:$contacts) {
            PhoneContactsView { selected in
                number=selected
                contacts=false
                Task { matched=await store.searchPhone(selected);picked=true }
            }
        }
    }
}

struct GroupView: View {
    @EnvironmentObject var store: ChatStore
    @Environment(\.dismiss) var dismiss
    @State private var title = ""
    @State private var query = ""
    @State private var people: [Person] = []
    @State private var chosen: Set<Int> = []
    let onOpen: (Conversation) -> Void
    var body: some View {
        NavigationStack {
            List {
                TextField("Название группы",text:$title)
                HStack {
                    TextField("Найти участников",text:$query).textInputAutocapitalization(.never).onSubmit { Task { people=await store.find(query) } }
                    Button { Task { people=await store.find(query) } } label:{ Image(systemName:"magnifyingglass") }
                }
                ForEach(people) { person in
                    Button { if chosen.contains(person.id) { chosen.remove(person.id) } else { chosen.insert(person.id) } } label: {
                        HStack { Text(person.display_name).foregroundStyle(.white); Spacer();
                            if chosen.contains(person.id) { Image(systemName:"checkmark.circle.fill") } }
                    }
                }
            }.scrollContentBackground(.hidden).background(ink)
                .navigationTitle("Новая группа").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement:.topBarLeading) { Button("Закрыть") { dismiss() } }
                    ToolbarItem(placement:.topBarTrailing) {
                        Button("Создать") { Task { if let chat=await store.createGroup(title:title,users:Array(chosen)) { onOpen(chat) } } }
                            .disabled(title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                    }
                }
        }
    }
}

struct VoiceWaveform:View {
    private let heights: [CGFloat] = [5,25,7,17,11,11,17,7,25,5,13,5,25,7,17,11,11,17,7,25,5,13,5,25,7,17,11,11]
    var body:some View {
        HStack(alignment:.center,spacing:3) {
            ForEach(0..<28,id:\.self) { index in
                Capsule()
                    .fill(Color.white.opacity(0.8))
                    .frame(width:3,height:heights[index])
            }
        }
        .frame(height:32)
    }
}

final class CirclePlayerView:UIView {
    override static var layerClass:AnyClass {AVPlayerLayer.self}
    var videoLayer:AVPlayerLayer {layer as! AVPlayerLayer}
}
struct InlineCirclePlayer:UIViewRepresentable {
    let player:AVPlayer
    func makeUIView(context:Context)->CirclePlayerView {
        let view=CirclePlayerView()
        view.backgroundColor = .black
        view.videoLayer.videoGravity = .resizeAspectFill
        view.videoLayer.player=player
        return view
    }
    func updateUIView(_ view:CirclePlayerView,context:Context){
        view.videoLayer.player=player
    }
    static func dismantleUIView(_ view:CirclePlayerView,coordinator:()){
        view.videoLayer.player=nil
    }
}
struct VideoCircleBubble:View {
    @EnvironmentObject var store:ChatStore
    let file:ChatAttachment
    @State private var player:AVPlayer?
    @State private var loading=false
    @State private var playing=false
    @State private var observer:NSObjectProtocol?
    var body:some View {
        Button {
            Task {await toggle()}
        } label: {
            ZStack {
                Circle().fill(.white.opacity(0.12))
                if let player {
                    InlineCirclePlayer(player:player)
                        .frame(width:190,height:190)
                        .clipShape(Circle())
                }
                if loading {ProgressView().tint(.white)}
                else if !playing {
                    Image(systemName:"play.circle.fill")
                        .font(.system(size:46)).foregroundStyle(.white)
                        .shadow(radius:8)
                }
            }
            .frame(width:190,height:190)
            .clipShape(Circle())
            .overlay(Circle().stroke(.white.opacity(0.16),lineWidth:1))
        }
        .buttonStyle(.plain)
        .onDisappear {stop()}
    }
    @MainActor private func toggle() async {
        if playing {
            player?.pause()
            playing=false
            return
        }
        if let player {player.play();playing=true;return}
        guard !loading else{return}
        loading=true
        defer {loading=false}
        guard let url=await store.downloadFile(file) else{return}
        let p=AVPlayer(url:url)
        player=p
        observer=NotificationCenter.default.addObserver(
            forName:.AVPlayerItemDidPlayToEndTime,object:p.currentItem,queue:.main
        ){_ in p.seek(to:.zero);p.play()}
        p.play()
        playing=true
    }
    private func stop(){
        player?.pause()
        player=nil
        playing=false
        if let observer {NotificationCenter.default.removeObserver(observer);self.observer=nil}
    }
}

final class CircleCaptureController: UIViewController, AVCaptureFileOutputRecordingDelegate {
    var onVideo:((URL)->Void)?
    var onClose:(()->Void)?
    var autoStart=false
    private var pendingStart=false
    private var segments:[URL]=[]
    private var switching=false
    private var cancelled=false
    var stopWhenReady=false
    private let session=AVCaptureSession()
    private let output=AVCaptureMovieFileOutput()
    private let preview=AVCaptureVideoPreviewLayer()
    private let record=UIButton(type:.system)
    private let flip=UIButton(type:.system)
    private let flash=UIButton(type:.system)
    private var torchEnabled=false
    private let timer=UILabel()
    private var cameraPosition:AVCaptureDevice.Position = .front
    private var started:Date?
    private var ticker:Timer?
    override func viewDidLoad(){
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isOpaque=false
        preview.session=session
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        let close=UIButton(type:.system)
        close.setTitle("Отмена",for:.normal)
        close.setTitleColor(.white,for:.normal)
        close.addTarget(self,action:#selector(cancel),for:.touchUpInside)
        view.addSubview(close)
        close.frame=CGRect(x:20,y:60,width:90,height:44)
        flip.setTitle("⟳",for:.normal)
        flip.titleLabel?.font = .systemFont(ofSize:32)
        flip.tintColor = .white
        flip.addTarget(self,action:#selector(switchCamera),for:.touchUpInside)
        view.addSubview(flip)
        flash.setImage(UIImage(systemName:"bolt.slash.fill"),for:.normal)
        flash.tintColor = .white
        flash.addTarget(self,action:#selector(toggleFlash),for:.touchUpInside)
        view.addSubview(flash)
        record.backgroundColor = .white
        record.layer.borderColor=UIColor.systemRed.cgColor
        record.layer.borderWidth=5
        record.addTarget(self,action:#selector(toggleRecording),for:.touchUpInside)
        view.addSubview(record)
        timer.textColor = .white
        timer.textAlignment = .center
        timer.font = .monospacedDigitSystemFont(ofSize:18,weight:.medium)
        timer.text="00:00 / 01:00"
        view.addSubview(timer)
        AVCaptureDevice.requestAccess(for:.video){[weak self] granted in
            guard granted else{return}
            AVCaptureDevice.requestAccess(for:.audio){_ in
                DispatchQueue.main.async {self?.configure()}
            }
        }
    }
    override func viewDidLayoutSubviews(){
        super.viewDidLayoutSubviews()
        let side=min(view.bounds.width-44,360.0)
        let y=(view.bounds.height-side)/2-50
        preview.frame=CGRect(x:(view.bounds.width-side)/2,y:y,width:side,height:side)
        preview.cornerRadius=side/2
        preview.masksToBounds=true
        record.frame=CGRect(x:(view.bounds.width-76)/2,y:y+side+42,width:76,height:76)
        record.layer.cornerRadius=38
        let controlsY=view.bounds.height-view.safeAreaInsets.bottom-145
        flip.frame=CGRect(x:view.bounds.width-88,y:controlsY,width:60,height:54)
        flash.frame=CGRect(x:28,y:controlsY,width:60,height:54)
        timer.frame=CGRect(x:0,y:y-44,width:view.bounds.width,height:30)
    }
    private func configure(){
        session.beginConfiguration()
        session.sessionPreset = .medium
        for input in session.inputs {session.removeInput(input)}
        guard let device=AVCaptureDevice.default(.builtInWideAngleCamera,for:.video,position:cameraPosition),
              let input=try? AVCaptureDeviceInput(device:device),session.canAddInput(input) else {
            session.commitConfiguration();return
        }
        session.addInput(input)
        if !session.outputs.contains(output) && session.canAddOutput(output){session.addOutput(output)}
        if let mic=AVCaptureDevice.default(for:.audio),let audio=try? AVCaptureDeviceInput(device:mic),session.canAddInput(audio){
            session.addInput(audio)
        }
        output.maxRecordedDuration=CMTime(seconds:60,preferredTimescale:600)
        flash.isEnabled=device.hasTorch
        if !device.hasTorch {torchEnabled=false}
        updateFlashIcon()
        session.commitConfiguration()
        // Lock capture and preview to portrait independently of device rotation.
        if let connection=output.connection(with:.video),connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
        if let connection=preview.connection,connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
        DispatchQueue.global(qos:.userInitiated).async {[weak self] in
            guard let self else{return}
            self.session.startRunning()
            DispatchQueue.main.async {
                if self.autoStart && !self.output.isRecording && self.segments.isEmpty {
                    self.autoStart=false
                    self.toggleRecording()
                }
            }
        }
    }
    private func updateFlashIcon(){
        flash.setImage(UIImage(systemName:torchEnabled ? "bolt.fill" : "bolt.slash.fill"),for:.normal)
        flash.tintColor = torchEnabled ? .systemYellow : .white
    }
    @objc private func toggleFlash(){
        guard let device=AVCaptureDevice.default(.builtInWideAngleCamera,for:.video,position:cameraPosition),
              device.hasTorch else {return}
        do {
            try device.lockForConfiguration()
            let enable = !torchEnabled
            device.torchMode = enable ? .on : .off
            device.unlockForConfiguration()
            torchEnabled=enable
            updateFlashIcon()
        } catch {torchEnabled=false;updateFlashIcon()}
    }
    @objc private func switchCamera(){
        torchEnabled=false
        updateFlashIcon()
        if output.isRecording {
            switching=true
            output.stopRecording()
        } else {
            cameraPosition=cameraPosition == .front ? .back : .front
            configure()
        }
    }
    var isRecordingCircle:Bool {output.isRecording}
    func finishCircle(){if output.isRecording {output.stopRecording()}}
    @objc private func toggleRecording(){
        if output.isRecording {output.stopRecording();return}
        let url=FileManager.default.temporaryDirectory.appendingPathComponent("circle_\(UUID().uuidString).mov")
        if let connection=output.connection(with:.video),connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
        output.startRecording(to:url,recordingDelegate:self)
        if stopWhenReady {
            DispatchQueue.main.asyncAfter(deadline:.now()+0.35) { [weak self] in
                guard let self,self.output.isRecording else{return}
                self.output.stopRecording()
            }
        }
        started=Date()
        record.backgroundColor = .systemRed
        ticker?.invalidate()
        ticker=Timer.scheduledTimer(withTimeInterval:0.2,repeats:true){[weak self] _ in
            guard let self,let started=self.started else{return}
            let elapsed=min(60,Int(Date().timeIntervalSince(started)))
            self.timer.text=String(format:"%02d:%02d / 01:00",elapsed/60,elapsed%60)
        }
    }
    @objc private func cancel(){
        cancelled=true
        ticker?.invalidate()
        if output.isRecording {
            output.stopRecording()
        } else {
            cleanup()
            onClose?()
        }
    }
    private func cleanup(){
        DispatchQueue.global(qos:.userInitiated).async {[weak self] in self?.session.stopRunning()}
    }
    private func finishSegments(){
        let clips=segments
        guard !clips.isEmpty else {onClose?();return}
        if clips.count == 1 {
            onVideo?(clips[0])
            onClose?()
            return
        }
        let composition=AVMutableComposition()
        guard let videoTrack=composition.addMutableTrack(withMediaType:.video,preferredTrackID:kCMPersistentTrackID_Invalid) else {
            onClose?();return
        }
        let audioTrack=composition.addMutableTrack(withMediaType:.audio,preferredTrackID:kCMPersistentTrackID_Invalid)
        var cursor=CMTime.zero
        for url in clips {
            let asset=AVURLAsset(url:url)
            guard let source=asset.tracks(withMediaType:.video).first else {continue}
            let range=CMTimeRange(start:.zero,duration:asset.duration)
            do {
                try videoTrack.insertTimeRange(range,of:source,at:cursor)
                if cursor == .zero { videoTrack.preferredTransform = source.preferredTransform }
                if let audio=asset.tracks(withMediaType:.audio).first {
                    try? audioTrack?.insertTimeRange(range,of:audio,at:cursor)
                }
                cursor=CMTimeAdd(cursor,asset.duration)
            } catch {continue}
        }
        let result=FileManager.default.temporaryDirectory.appendingPathComponent("video_circle_\(UUID().uuidString).mov")
        guard let exporter=AVAssetExportSession(asset:composition,presetName:AVAssetExportPresetHighestQuality) else {
            onClose?();return
        }
        exporter.outputURL=result
        exporter.outputFileType = .mov
        exporter.exportAsynchronously { [weak self] in
            DispatchQueue.main.async {
                if exporter.status == .completed {self?.onVideo?(result)}
                self?.onClose?()
            }
        }
    }
    func fileOutput(_ output:AVCaptureFileOutput,didFinishRecordingTo url:URL,from connections:[AVCaptureConnection],error:Error?){
        if error == nil && !cancelled {segments.append(url)}
        if cancelled {
            cleanup()
            onClose?()
            return
        }
        if switching {
            switching=false
            cameraPosition=cameraPosition == .front ? .back : .front
            configure()
            DispatchQueue.main.asyncAfter(deadline:.now()+0.45) { [weak self] in
                guard let self else{return}
                self.toggleRecording()
            }
            return
        }
        ticker?.invalidate()
        cleanup()
        finishSegments()
    }
}
struct VideoCircleRecorder:UIViewControllerRepresentable {
    let onVideo:(URL)->Void
    let onClose:()->Void
    var autoStart=false
    var stopRequested=false
    func makeUIViewController(context:Context)->CircleCaptureController {
        let controller=CircleCaptureController()
        controller.onVideo=onVideo
        controller.onClose=onClose
        controller.autoStart=autoStart
        controller.stopWhenReady=stopRequested
        return controller
    }
    func updateUIViewController(_ controller:CircleCaptureController,context:Context){
        if stopRequested && !controller.stopWhenReady {
            controller.stopWhenReady=true
            if controller.isRecordingCircle {controller.finishCircle()}
        }
    }
}

struct ChatView: View {
    @EnvironmentObject var store: ChatStore
    let chat: Conversation
    @State private var messages: [ChatMessage] = []
    @State private var draft = ""
    @State private var reply: ChatMessage?
    @State private var editing: ChatMessage?
    @State private var editText = ""
    @State private var older = true
    @State private var pickedPhoto:PhotosPickerItem?
    @State private var uploading=false
    @StateObject private var voiceRecorder = NightwellVoiceRecorder()
    @FocusState private var composerFocused:Bool
    @State private var showingFilePicker=false
    @State private var showingPhotoPicker=false
    @State private var recordingModeVideo=false
    @State private var startCircleImmediately=false
    @State private var stopCircleRequested=false
    @State private var mediaPressing=false
    @State private var mediaLongPress=false
    @State private var mediaHoldStarted=false
    @State private var showingVideoRecorder=false
    @State private var preview:URL?
    @State private var audioPlayer: AVPlayer?
    @State private var playingAudioID: Int?
    @State private var audioEndObserver:NSObjectProtocol?
    @State private var activeCall: CallPresentation?
    @State private var pendingProfileCall: CallPresentation?
    @State private var showingContactProfile=false
    @ViewBuilder
    private func messageRow(_ message: ChatMessage) -> some View {
        HStack {
            if message.sender_id == store.me?.id { Spacer(minLength:45) }
            VStack(alignment:message.sender_id == store.me?.id ? .trailing : .leading,spacing:4) {
                if chat.kind == "group" && message.sender_id != store.me?.id {
                    Text(message.sender_name).font(.caption.bold()).foregroundStyle(muted)
                }
                if message.deleted == 0,let file=message.attachment, file.filename.hasPrefix("video_circle.") {
                    VideoCircleBubble(file:file)
                } else if message.deleted == 0,let file=message.attachment {
                    Button {
                        Task {
                            if file.content_type.hasPrefix("audio/") {
                                if playingAudioID == file.id {
                                    audioPlayer?.pause()
                                    audioPlayer = nil
                                    playingAudioID = nil
                                } else if let url = await store.downloadFile(file) {
                                    audioPlayer?.pause()
                                    let newPlayer=AVPlayer(url: url)
                                    audioPlayer = newPlayer
                                    playingAudioID = file.id
                                    if let audioEndObserver {NotificationCenter.default.removeObserver(audioEndObserver)}
                                    audioEndObserver=NotificationCenter.default.addObserver(forName:.AVPlayerItemDidPlayToEndTime,object:newPlayer.currentItem,queue:.main){_ in
                                        newPlayer.seek(to:.zero)
                                        playingAudioID=nil
                                    }
                                    newPlayer.play()
                                }
                            } else {
                                preview = await store.downloadFile(file)
                            }
                        }
                    } label: {
                        if file.content_type.hasPrefix("image/"){
                            PrivateImage(attachment:file.id)
                        } else if file.content_type.hasPrefix("audio/") {
                            HStack(spacing:10) { Image(systemName:playingAudioID == file.id ? "pause.circle.fill" : "play.circle.fill").font(.title2); VoiceWaveform() }
                        } else if file.content_type.hasPrefix("video/") {
                            Label("Видеосообщение",systemImage:"play.rectangle.fill")
                        } else {
                            Label(file.filename,systemImage:"doc.fill")
                        }
                    }.buttonStyle(.plain)
                }
                if message.deleted != 0 || !message.body.isEmpty {
                    Text(message.deleted != 0 ? "Сообщение удалено" : message.body)
                    .foregroundStyle(message.deleted != 0 ? muted : white)
                    .font(.body)
                }
                HStack(spacing:6) {
                    if message.edited_at != nil { Text("изм.") }
                    Text(String(message.created_at.dropFirst(11).prefix(5)))
                }.font(.system(size:10)).foregroundStyle(muted)
                if !message.reactions.isEmpty {
                    HStack { ForEach(message.reactions) { reaction in
                        Text("\(reaction.emoji) \(reaction.count)").font(.caption)
                            .padding(5).background(.white.opacity(0.1),in:Capsule())
                            .transition(.scale(scale:0.7).combined(with:.opacity))
                    } }
                    .animation(.spring(response:0.3,dampingFraction:0.65),value:message.reactions.count)
                }
            }
            .padding(message.attachment?.content_type.hasPrefix("image/") == true || message.attachment?.filename.hasPrefix("video_circle.") == true ? 0 : 11)
            .background((message.attachment?.content_type.hasPrefix("image/") == true || message.attachment?.filename.hasPrefix("video_circle.") == true) ? Color.clear : (message.sender_id == store.me?.id ? glassBlue.opacity(0.25) : white.opacity(0.10)),in:RoundedRectangle(cornerRadius:20))
            .contextMenu {
                if message.deleted == 0 {
                    Button("Ответить",systemImage:"arrowshape.turn.up.left") { reply=message }
                    Button("🤍") { Task { await store.react(message.id,emoji:"🤍") } }
                    Button("👍") { Task { await store.react(message.id,emoji:"👍") } }
                    if message.sender_id == store.me?.id {
                        Button("Изменить",systemImage:"pencil") { editing=message; editText=message.body }
                        Button("Удалить",systemImage:"trash",role:.destructive) { Task { await store.delete(message.id); await reload() } }
                    }
                }
            }
            if message.sender_id != store.me?.id { Spacer(minLength:45) }
        }
        .transition(.asymmetric(
            insertion:.opacity.combined(with:.move(edge:.bottom)).combined(with:.scale(scale:0.96)),
            removal:.opacity
        ))
        .id(message.id)
    }
    var body: some View {
        VStack(spacing:0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing:11) {
                        if older && !messages.isEmpty {
                            Button("Загрузить ранние") { Task { await loadOlder() } }
                                .font(.caption).foregroundStyle(muted).padding(10)
                        }
                        ForEach(messages) { message in
                            messageRow(message)
                        }
                    }.padding(.horizontal,14).padding(.top,12).padding(.bottom,100)
                }
                .defaultScrollAnchor(.bottom)
                .scrollDismissesKeyboard(.interactively)
                .onTapGesture { composerFocused=false }
                .animation(.spring(response:0.32,dampingFraction:0.82),value:messages.last?.id)
                .onChange(of:messages.last?.id) { _,_ in
                    if let id=messages.last?.id { withAnimation(.easeOut(duration:0.2)) { proxy.scrollTo(id,anchor:.bottom) } }
                }
            }
            .padding(.bottom,-74)
            // Messages continue underneath the floating transparent composer.
            if let reply {
                HStack {
                    VStack(alignment:.leading) { Text("Ответ \(reply.sender_name)").font(.caption.bold()); Text(reply.body).lineLimit(1).font(.caption).foregroundStyle(muted) }
                    Spacer()
                    Button { self.reply=nil } label:{ Image(systemName:"xmark") }
                }.padding(.horizontal,16).padding(.top,8)
            }
            if uploading {
                HStack(spacing:8) { ProgressView().tint(.white); Text("Загрузка медиа…").font(.caption) }
                    .padding(.horizontal,16).padding(.top,6)
            }
            HStack(alignment:.bottom,spacing:10) {
                Menu {
                    Button("Фото",systemImage:"photo") { showingPhotoPicker=true }
                    Button("Файл",systemImage:"paperclip") { showingFilePicker=true }
                } label: {
                    Image(systemName:"paperclip").font(.title2)
                        .frame(width:48,height:48)
                        .background(.ultraThinMaterial,in:Circle())
                        .overlay(Circle().stroke(.white.opacity(0.16)))
                }.disabled(uploading)
                TextField("Сообщение",text:$draft,axis:.vertical)
                    .focused($composerFocused)
                    .lineLimit(1...5).padding(.horizontal,16).padding(.vertical,13)
                    .frame(minHeight:48)
                    .background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:24))
                    .overlay(RoundedRectangle(cornerRadius:24).stroke(.white.opacity(0.16)))
                if !draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {
                    Button { Task { await submit() } } label: {
                        Image(systemName:"arrow.up").font(.headline)
                            .foregroundStyle(.black).frame(width:48,height:48).background(.white,in:Circle())
                    }
                } else {
                    Image(systemName:voiceRecorder.isRecording ? "stop.circle.fill" : (recordingModeVideo ? "video.circle.fill" : "mic.fill"))
                        .font(.title2).frame(width:48,height:48)
                        .background(.ultraThinMaterial,in:Circle())
                        .overlay(Circle().stroke(.white.opacity(0.16)))
                        .contentShape(Circle())
                        .gesture(DragGesture(minimumDistance:0)
                            .onChanged { _ in
                                if !mediaPressing {
                                    mediaPressing=true
                                    mediaLongPress=false
                                    DispatchQueue.main.asyncAfter(deadline:.now()+0.35) {
                                        guard mediaPressing && !uploading else{return}
                                        mediaLongPress=true
                                        if recordingModeVideo {
                                            startCircleImmediately=true
                                            stopCircleRequested=false
                                            showingVideoRecorder=true
                                        } else {
                                            Task {await voiceRecorder.start()
                                                if let error=voiceRecorder.errorMessage {store.alertText=error}
                                            }
                                        }
                                    }
                                }
                            }
                            .onEnded { _ in
                                mediaPressing=false
                                if mediaLongPress {
                                    mediaLongPress=false
                                    if recordingModeVideo {
                                        stopCircleRequested=true
                                    } else {
                                        Task {
                                            try? await Task.sleep(nanoseconds:250_000_000)
                                            if let file=voiceRecorder.finish(),let data=try? Data(contentsOf:file) {
                                                uploading=true
                                                let success=await store.sendFile(chatID:chat.id,bytes:data,filename:"voice.m4a",mime:"audio/mp4")
                                                try? FileManager.default.removeItem(at:file)
                                                if success {await reload()}
                                                uploading=false
                                            }
                                        }
                                    }
                                } else {
                                    recordingModeVideo.toggle()
                                }
                            })
                    .accessibilityLabel(recordingModeVideo ? "Видеокружок, удерживайте для записи" : "Голосовое сообщение, удерживайте для записи")
                    .allowsHitTesting(!uploading)
                }
            }
            .padding(.horizontal,10).padding(.vertical,8)
            .padding(.bottom,5)
        }
        .background(NightwellBackground())
        .navigationTitle(chat.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented:$showingContactProfile,onDismiss: {
            if let pendingProfileCall { activeCall=pendingProfileCall; self.pendingProfileCall=nil }
        }) {
            NavigationStack {
                ScrollView {
                    VStack(spacing:16) {
                        if let person=chat.other_user {
                            AvatarCircle(person:person,fallback:chat.title)
                                .frame(width:104,height:104)
                            Text(person.display_name).font(.title2.bold())
                            Text("@"+person.username).foregroundStyle(.secondary)
                            Button {
                                Task {
                                    if let call=await store.makeCall(to:person.id),
                                       let url=store.voiceURL(call) {
                                        pendingProfileCall=CallPresentation(url:url)
                                        showingContactProfile=false
                                    }
                                }
                            } label: {
                                Label("Позвонить",systemImage:"phone.fill")
                                    .frame(maxWidth:.infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .padding(.top,8)
                        } else {
                            Text(chat.title).font(.title2.bold())
                        }
                        Button("Вернуться в переписку") { showingContactProfile=false }
                            .buttonStyle(.borderedProminent)
                    }.frame(maxWidth:.infinity).padding(24)
                }
                .background(NightwellBackground())
                .navigationTitle("Профиль")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement:.topBarLeading) {
                        Button { showingContactProfile=false } label: {
                            Label("Назад",systemImage:"chevron.left")
                        }
                    }
                    ToolbarItem(placement:.topBarTrailing) {
                        Button("Готово") { showingContactProfile=false }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement:.principal) {
                Button { showingContactProfile=true } label: {
                    HStack(spacing:7) {
                        if let person=chat.other_user {
                            AvatarCircle(person:person,fallback:chat.title)
                                .frame(width:30,height:30)
                        }
                        Text(chat.title).font(.headline).lineLimit(1)
                    }
                }.buttonStyle(.plain)
                .accessibilityLabel("Открыть профиль собеседника")
            }
            ToolbarItem(placement:.topBarTrailing){
                if let person=chat.other_user {
                    Button {
                        Task {
                            if let call=await store.makeCall(to:person.id),
                               let url=store.voiceURL(call){
                                activeCall=CallPresentation(url:url)
                            }
                        }
                    } label:{Image(systemName:"phone")}
                }
            }
        }
        .fullScreenCover(item:$activeCall) { call in CallScreen(url:call.url) }
        .fullScreenCover(isPresented:$showingVideoRecorder){
            VideoCircleRecorder(onVideo: { url in
                Task {
                    guard let data=try? Data(contentsOf:url) else {
                        store.alertText="Не удалось прочитать видео"
                        return
                    }
                    guard data.count<=50*1024*1024 else {
                        store.alertText="Видео больше 50 МБ. Запиши более короткое сообщение."
                        return
                    }
                    uploading=true
                    let success=await store.sendFile(chatID:chat.id,bytes:data,filename:"video_circle.mov",mime:"video/quicktime")
                    if success {await reload()}
                    uploading=false
                }
            }, onClose: { showingVideoRecorder=false; stopCircleRequested=false }, autoStart:startCircleImmediately, stopRequested:stopCircleRequested).ignoresSafeArea()
        }
        .photosPicker(isPresented:$showingPhotoPicker,selection:$pickedPhoto,matching:.images)
        .fileImporter(isPresented:$showingFilePicker,allowedContentTypes:[.item]){
            result in
            guard case .success(let file)=result else{return}
            Task{
                let security=file.startAccessingSecurityScopedResource()
                defer {if security{file.stopAccessingSecurityScopedResource()}}
                guard let data=try? Data(contentsOf:file),data.count<=50*1024*1024 else {
                    store.alertText="Размер файла не должен превышать 50 МБ";return
                }
                uploading=true
                let success=await store.sendFile(chatID:chat.id,bytes:data,filename:file.lastPathComponent,mime:UTType(filenameExtension:file.pathExtension)?.preferredMIMEType ?? "application/octet-stream")
                if success {await reload()}
                uploading=false
            }
        }
        .onChange(of:pickedPhoto){_,item in
            Task{
                guard let data=try? await item?.loadTransferable(type:Data.self),
                    let image=UIImage(data:data),let jpg=image.jpegData(compressionQuality:0.86) else{return}
                uploading=true
                let success=await store.sendFile(chatID:chat.id,bytes:jpg,filename:"photo.jpg",mime:"image/jpeg")
                pickedPhoto=nil
                if success {await reload()}
                uploading=false
            }
        }
        .onDisappear { audioPlayer?.pause(); audioPlayer = nil; playingAudioID = nil; if let audioEndObserver {NotificationCenter.default.removeObserver(audioEndObserver)}; voiceRecorder.cancel() }
        .onChange(of:playingAudioID) { _, activeID in
            if activeID == nil { audioPlayer?.pause() }
        }
        .quickLookPreview($preview)
        .task { await reload() }
        .onChange(of:store.eventVersion) { _,_ in Task { await reload() } }
        .alert("Изменить сообщение",isPresented:Binding(get:{editing != nil},set:{if !$0 { editing=nil }})) {
            TextField("Сообщение",text:$editText)
            Button("Сохранить") { if let id=editing?.id { Task { await store.edit(id,text:editText); await reload() } }; editing=nil }
            Button("Отмена",role:.cancel) { editing=nil }
        }
    }
    private func reload() async {
        let data=await store.messages(chat.id)
        messages=data
        if let last=data.last { await store.markRead(chatID:chat.id,messageID:last.id) }
    }
    private func loadOlder() async {
        guard let first=messages.first else { return }
        let earlier=await store.messages(chat.id,before:first.id)
        older = earlier.count >= 50
        messages=earlier+messages
    }
    private func submit() async {
        let text=draft.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft=""
        let sent=await store.send(chat.id,text:text,reply:reply?.id)
        if sent == nil { draft=text }
        reply=nil
        await reload()
        await store.reloadChats()
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: ChatStore
    @Environment(\.dismiss) var dismiss
    @State private var server = ""
    @State private var displayName = ""
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing:12) {
                        AvatarCircle(person:store.me,fallback:store.me?.display_name ?? "N")
                            .scaleEffect(1.5).frame(height:105)
                        Text(store.me?.display_name ?? "Nightwell").font(.system(size:28,weight:.semibold))
                        Text(store.me?.username ?? "").foregroundStyle(.secondary)
                    }.frame(maxWidth:.infinity)
                }
                Section {
                    NavigationLink {EditProfileView()} label:{Label("Изменить фотографию",systemImage:"camera.fill").foregroundStyle(.blue)}
                }
                Section("Профиль") {
                    NavigationLink {
                        EditProfileView()
                    } label: {
                        HStack(spacing:12) {
                            AvatarCircle(person:store.me,fallback:store.me?.display_name ?? "N")
                            VStack(alignment:.leading,spacing:3) {
                                Text("Аватар и имя")
                                Text("Нажми, чтобы загрузить фото").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Text("@\(store.me?.username ?? "")").foregroundStyle(muted)
                    TextField("Отображаемое имя",text:$displayName)
                    Button("Сохранить имя") { Task { await store.saveProfile(displayName) } }
                }
                Section("Телефон") {
                    NavigationLink("Привязка номера и поиск"){PhoneLinkView()}
                    Text("Вход и регистрация по номеру доступны после выхода из аккаунта. Сначала привяжи номер к текущему профилю, чтобы сохранить чаты.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Приложение") {
                    HStack { Image(systemName:"bell.badge.fill").foregroundStyle(.red); Text("Уведомления и звуки"); Spacer(); Text("Системные").foregroundStyle(.secondary) }
                    HStack { Image(systemName:"lock.fill").foregroundStyle(.gray); Text("Конфиденциальность") }
                    HStack { Image(systemName:"externaldrive.fill").foregroundStyle(.green); Text("Данные и память") }
                    HStack { Image(systemName:"circle.lefthalf.filled").foregroundStyle(.cyan); Text("Оформление"); Spacer(); Text("Тёмное").foregroundStyle(.secondary) }
                }
                Section("Версия") {
                    Text("Nightwell Chat \(appVersion) (\(appBuild))")
                }
                Section("Сервер") {
                    TextField("https://chat.nightwell.fun",text:$server)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    Button("Изменить сервер и выйти") { store.saveServer(server); dismiss() }
                    Text("Используй только свой сервер с действительным TLS-сертификатом.")
                        .font(.caption).foregroundStyle(muted)
                }
                Section { Button("Выйти из аккаунта",role:.destructive) { store.logout(); dismiss() } }
            }.scrollContentBackground(.hidden).background(Color.black.ignoresSafeArea())
                .environment(\.defaultMinListRowHeight,54)
                .scrollDismissesKeyboard(.interactively)
                .navigationTitle("Настройки").navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.ultraThinMaterial,for:.navigationBar)
                .toolbar { ToolbarItem(placement:.topBarTrailing) { Button("Готово") { dismiss() } } }
        }.onAppear { server=store.serverURL; displayName=store.me?.display_name ?? "" }
    }
}

import AVFoundation

@MainActor
final class NightwellVoiceRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var errorMessage: String?
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?

    func start() async {
        let allowed = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard allowed else {
            errorMessage = "Разреши доступ к микрофону в настройках iPhone"
            return
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try AVAudioSession.sharedInstance().setActive(true)
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("m4a")
            let options: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64000
            ]
            let newRecorder = try AVAudioRecorder(url: destination, settings: options)
            guard newRecorder.record() else {
                errorMessage = "Не удалось начать запись"
                return
            }
            recorder = newRecorder
            recordingURL = destination
            isRecording = true
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func finish() -> URL? {
        guard isRecording else { return nil }
        recorder?.stop()
        recorder = nil
        isRecording = false
        return recordingURL
    }

    func cancel() {
        recorder?.stop()
        recorder?.deleteRecording()
        recorder = nil
        recordingURL = nil
        isRecording = false
    }
}
