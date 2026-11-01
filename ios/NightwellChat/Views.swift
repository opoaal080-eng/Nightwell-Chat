import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import QuickLook
import AVKit

private let ink = Color.black
private let white = Color.white
private let muted = Color(white: 0.63)

struct GlassPanel: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(14).background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:22))
            .overlay(RoundedRectangle(cornerRadius:22).stroke(white.opacity(0.14),lineWidth:1))
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
        .background(ink.ignoresSafeArea())
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
        }.background(Color.black)
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
            Text("Nightwell Chat 0.7 • вход по телефону")
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
    var body: some View {
        NavigationStack {
            ZStack {
                ink.ignoresSafeArea()
                if store.chats.isEmpty {
                    ContentUnavailableView("Пока нет переписок",systemImage:"bubble.left.and.bubble.right",description:Text("Найди пользователя и начни общение"))
                } else {
                    List(store.chats) { chat in
                        Button { selected=chat } label: {
                            HStack(spacing:13) {
                                AvatarCircle(person:chat.other_user,fallback:chat.title)
                                VStack(alignment:.leading,spacing:5) {
                                    HStack {
                                        Text(chat.title).font(.headline).foregroundStyle(.white)
                                        Spacer()
                                        if chat.unread > 0 { Text("\(chat.unread)").font(.caption.bold()).foregroundStyle(.black)
                                            .padding(.horizontal,8).padding(.vertical,4).background(.white,in:Capsule()) }
                                    }
                                    Text(chat.last_message?.body ?? (chat.kind == "group" ? "Новая группа" : "Новый чат"))
                                        .font(.subheadline).foregroundStyle(muted).lineLimit(1)
                                }
                            }.padding(.vertical,6)
                        }.listRowBackground(Color(white:0.065))
                    }.scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Чаты")
            .safeAreaInset(edge:.bottom) {
                HStack(spacing:20) {
                    Button { findPeople=true } label: {
                        Label("Контакты",systemImage:"person.2")
                    }
                    Spacer()
                    Button { settings=true } label: {
                        Label("Профиль",systemImage:"person.crop.circle")
                    }
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal,24).padding(.vertical,12)
                .frame(maxWidth:.infinity)
                .background(.ultraThinMaterial)
            }
            .toolbar {
                ToolbarItem(placement:.topBarLeading) { Button { settings=true } label:{ Image(systemName:"slider.horizontal.3") } }
                ToolbarItemGroup(placement:.topBarTrailing) {
                    Button { calls=true } label:{ Image(systemName:"phone.arrow.up.right") }
                    Button { group=true } label:{ Image(systemName:"person.3") }
                    Button { findPeople=true } label:{ Image(systemName:"square.and.pencil") }
                }
            }
            .navigationDestination(item:$selected) { ChatView(chat:$0) }
            .sheet(isPresented:$findPeople) { PeopleView { chat in findPeople=false; selected=chat } }
            .sheet(isPresented:$group) { GroupView { chat in group=false; selected=chat } }
            .sheet(isPresented:$settings) { SettingsView() }
            .sheet(isPresented:$calls){IncomingCallsView()}
            .refreshable { await store.reloadChats() }
            .task { await store.reloadChats() }
            .onChange(of:store.eventVersion) { _,_ in Task { await store.reloadChats() } }
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
    private let timer=UILabel()
    private var cameraPosition:AVCaptureDevice.Position = .front
    private var started:Date?
    private var ticker:Timer?
    override func viewDidLoad(){
        super.viewDidLoad()
        view.backgroundColor = .black
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
        flip.frame=CGRect(x:view.bounds.width-88,y:y+side+54,width:60,height:54)
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
        session.commitConfiguration()
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
    @objc private func switchCamera(){
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
        exporter.outputFileType=.mov
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
    @State private var showingVideoRecorder=false
    @State private var preview:URL?
    @State private var audioPlayer: AVPlayer?
    @State private var playingAudioID: Int?
    @State private var showingCall=false
    @State private var callURL:URL?
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
                                                        audioPlayer = AVPlayer(url: url)
                                                        playingAudioID = file.id
                                                        audioPlayer?.play()
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
                                    Text(message.deleted != 0 ? "Сообщение удалено" : message.body)
                                        .foregroundStyle(message.deleted != 0 ? muted : white)
                                        .font(.body)
                                    HStack(spacing:6) {
                                        if message.edited_at != nil { Text("изм.") }
                                        Text(message.created_at.count >= 16 ? String(message.created_at.suffix(from:message.created_at.index(message.created_at.startIndex,offsetBy:11)).prefix(5)) : "")
                                    }.font(.system(size:10)).foregroundStyle(muted)
                                    if !message.reactions.isEmpty {
                                        HStack { ForEach(message.reactions) { reaction in
                                            Text("\(reaction.emoji) \(reaction.count)").font(.caption)
                                                .padding(5).background(.white.opacity(0.1),in:Capsule())
                                        } }
                                    }
                                }
                                .padding(11)
                                .background(message.sender_id == store.me?.id ? white.opacity(0.21) : white.opacity(0.08),in:RoundedRectangle(cornerRadius:17))
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
                            }.id(message.id)
                        }
                    }.padding(.horizontal,14).padding(.vertical,12)
                }
                .defaultScrollAnchor(.bottom)
                .scrollDismissesKeyboard(.interactively)
                .onTapGesture { composerFocused=false }
                .onChange(of:messages.last?.id) { _,_ in
                    if let id=messages.last?.id { withAnimation(.easeOut(duration:0.2)) { proxy.scrollTo(id,anchor:.bottom) } }
                }
            }
            Divider().overlay(white.opacity(0.15))
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
                    Button("Видеокружок",systemImage:"video.circle") { showingVideoRecorder=true }
                } label: {
                    Image(systemName:"paperclip").font(.title2)
                        .frame(width:38,height:42)
                }.disabled(uploading)
                TextField("Сообщение",text:$draft,axis:.vertical)
                    .focused($composerFocused)
                    .lineLimit(1...5).padding(12)
                    .background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:18))
                if !draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {
                    Button { Task { await submit() } } label: {
                        Image(systemName:"arrow.up").font(.headline)
                            .foregroundStyle(.black).frame(width:42,height:42).background(.white,in:Circle())
                    }
                } else {
                    Button {
                        if recordingModeVideo {
                            startCircleImmediately=false
                            stopCircleRequested=false
                            showingVideoRecorder=true
                        } else {
                            Task {
                                if voiceRecorder.isRecording {
                                    if let file=voiceRecorder.finish(),let data=try? Data(contentsOf:file) {
                                        uploading=true
                                        let success=await store.sendFile(chatID:chat.id,bytes:data,filename:"voice.m4a",mime:"audio/mp4")
                                        try? FileManager.default.removeItem(at:file)
                                        if success {await reload()}
                                        uploading=false
                                    }
                                } else {
                                    await voiceRecorder.start()
                                    if let error=voiceRecorder.errorMessage {store.alertText=error}
                                }
                            }
                        }
                    } label: {
                        Image(systemName:voiceRecorder.isRecording ? "stop.circle.fill" : (recordingModeVideo ? "video.circle.fill" : "mic.fill"))
                            .font(.title2).frame(width:42,height:42)
                    }
                    .simultaneousGesture(TapGesture(count:2).onEnded {recordingModeVideo.toggle()})
                    .simultaneousGesture(DragGesture(minimumDistance:0)
                        .onChanged { _ in
                            if !mediaPressing {
                                mediaPressing=true
                                mediaLongPress=false
                                DispatchQueue.main.asyncAfter(deadline:.now()+0.45) {
                                    if mediaPressing && recordingModeVideo && !uploading {
                                        mediaLongPress=true
                                        startCircleImmediately=true
                                        stopCircleRequested=false
                                        showingVideoRecorder=true
                                    }
                                }
                            }
                        }
                        .onEnded { _ in
                            mediaPressing=false
                            if mediaLongPress {
                                stopCircleRequested=true
                                mediaLongPress=false
                            }
                        })
                    .disabled(uploading)
                }
            }.padding(12).background(ink)
        }
        .background(ink)
        .navigationTitle(chat.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement:.topBarTrailing){
                if let person=chat.other_user {
                    Button {
                        Task {
                            if let call=await store.makeCall(to:person.id),
                               let url=store.voiceURL(call){
                                callURL=url;showingCall=true
                            }
                        }
                    } label:{Image(systemName:"phone")}
                }
            }
        }
        .sheet(isPresented:$showingCall){if let callURL {SafariCallView(url:callURL)}}
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
        .onDisappear { audioPlayer?.pause(); audioPlayer = nil; playingAudioID = nil; voiceRecorder.cancel() }
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
                Section("Версия") {
                    Text("Nightwell Chat 0.7")
                }
                Section("Сервер") {
                    TextField("https://chat.nightwell.fun",text:$server)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    Button("Изменить сервер и выйти") { store.saveServer(server); dismiss() }
                    Text("Используй только свой сервер с действительным TLS-сертификатом.")
                        .font(.caption).foregroundStyle(muted)
                }
                Section { Button("Выйти из аккаунта",role:.destructive) { store.logout(); dismiss() } }
            }.scrollContentBackground(.hidden).background(ink)
                .scrollDismissesKeyboard(.interactively)
                .navigationTitle("Настройки").navigationBarTitleDisplayMode(.inline)
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
