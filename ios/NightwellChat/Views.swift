import SwiftUI

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

struct LoginView: View {
    @EnvironmentObject var store: ChatStore
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
                        .textFieldStyle(.roundedBorder)
                    if register { TextField("Отображаемое имя",text:$displayName).textFieldStyle(.roundedBorder) }
                    SecureField("Пароль от 8 символов",text:$password)
                        .textContentType(register ? .newPassword : .password).textFieldStyle(.roundedBorder)
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
                                Circle().fill(.white.opacity(0.12)).frame(width:53,height:53)
                                    .overlay(Text(String(chat.title.prefix(1)).uppercased()).font(.title2).foregroundStyle(.white))
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
            .toolbar {
                ToolbarItem(placement:.topBarLeading) { Button { settings=true } label:{ Image(systemName:"slider.horizontal.3") } }
                ToolbarItemGroup(placement:.topBarTrailing) {
                    Button { group=true } label:{ Image(systemName:"person.3") }
                    Button { findPeople=true } label:{ Image(systemName:"square.and.pencil") }
                }
            }
            .navigationDestination(item:$selected) { ChatView(chat:$0) }
            .sheet(isPresented:$findPeople) { PeopleView { chat in findPeople=false; selected=chat } }
            .sheet(isPresented:$group) { GroupView { chat in group=false; selected=chat } }
            .sheet(isPresented:$settings) { SettingsView() }
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
    let onOpen: (Conversation) -> Void
    var body: some View {
        NavigationStack {
            List {
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
                .navigationTitle("Новый чат").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.topBarLeading) { Button("Закрыть") { dismiss() } } }
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

struct ChatView: View {
    @EnvironmentObject var store: ChatStore
    let chat: Conversation
    @State private var messages: [ChatMessage] = []
    @State private var draft = ""
    @State private var reply: ChatMessage?
    @State private var editing: ChatMessage?
    @State private var editText = ""
    @State private var older = true
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
            HStack(alignment:.bottom,spacing:10) {
                TextField("Сообщение",text:$draft,axis:.vertical)
                    .lineLimit(1...5).padding(12)
                    .background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:18))
                Button { Task { await submit() } } label: {
                    Image(systemName:"arrow.up").font(.headline)
                        .foregroundStyle(.black).frame(width:42,height:42).background(.white,in:Circle())
                }.disabled(draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
            }.padding(12).background(ink)
        }
        .background(ink)
        .navigationTitle(chat.title)
        .navigationBarTitleDisplayMode(.inline)
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
                    Text("@\(store.me?.username ?? "")").foregroundStyle(muted)
                    TextField("Отображаемое имя",text:$displayName)
                    Button("Сохранить имя") { Task { await store.saveProfile(displayName) } }
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
                .navigationTitle("Настройки").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.topBarTrailing) { Button("Готово") { dismiss() } } }
        }.onAppear { server=store.serverURL; displayName=store.me?.display_name ?? "" }
    }
}
