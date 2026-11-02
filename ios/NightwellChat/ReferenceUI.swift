import SwiftUI

let referenceBlue=Color(red:0.30,green:0.53,blue:0.97)
let referenceGray=Color(white:0.56)

struct ReferenceGlass:ViewModifier {
    var radius:CGFloat=28
    @ViewBuilder func body(content:Content)->some View {
        if #available(iOS 26.0,*) {
            content.glassEffect(.regular,in:RoundedRectangle(cornerRadius:radius))
        } else {
            content.background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:radius))
                .overlay(RoundedRectangle(cornerRadius:radius).stroke(.white.opacity(0.18),lineWidth:0.7))
        }
    }
}
struct ReferenceIcon:View {
    let symbol:String
    var blue=false
    var action:()->Void
    var body:some View {Button(action:action){Image(systemName:symbol).font(.system(size:23,weight:.regular)).frame(width:44,height:44)}
        .foregroundStyle(.white).background(blue ? referenceBlue : .clear,in:Circle()).modifier(ReferenceGlass(radius:22)).buttonStyle(.plain)}
}
struct ReferenceAvatar:View {
    @EnvironmentObject var store:ChatStore
    let person:Person?
    let title:String
    var size:CGFloat=40
    @State private var image:UIImage?
    private var color:Color {let value=title.unicodeScalars.reduce(0){$0+Int($1.value)};return [Color.purple,Color.blue,Color.teal,Color.orange][value%4]}
    var body:some View {
        ZStack {
            Circle().fill(LinearGradient(colors:[color.opacity(0.65),color],startPoint:.top,endPoint:.bottom))
            if let image {Image(uiImage:image).resizable().scaledToFill()}
            else {Text(title.split(separator:" ").prefix(2).compactMap{$0.first}.map(String.init).joined()).font(.system(size:size*0.37,weight:.medium)).foregroundStyle(.white)}
        }.frame(width:size,height:size).clipShape(Circle())
        .task(id:"\(person?.id ?? 0)-\(store.eventVersion)") {
            guard let person,person.has_avatar == true else{return}
            if let bytes=await store.loadAvatar(person.id) {image=UIImage(data:bytes)}
        }
    }
}
struct ReferenceSegments:View {
    let titles:[String]
    @Binding var selected:Int
    var body:some View {
        HStack(spacing:0){ForEach(titles.indices,id:\.self){index in
            Button {selected=index} label:{Text(titles[index]).font(.system(size:17,weight:.medium)).lineLimit(1).frame(maxWidth:.infinity).padding(.vertical,9)
                .background(selected==index ? Color.white.opacity(0.17):.clear,in:Capsule())}
        }}.padding(3).foregroundStyle(.white).modifier(ReferenceGlass()).buttonStyle(.plain)
    }
}
struct ReferenceTabBar:View {
    @Binding var selection:Int
    private let titles=["Контакты","Звонки","Чаты","Настройки"]
    private let icons=["person.crop.circle.fill","phone.fill","bubble.left.and.bubble.right.fill","gearshape"]
    var body:some View {
        HStack(spacing:0){ForEach(0..<4){i in
            Button {selection=i} label:{VStack(spacing:4){Image(systemName:icons[i]).font(.system(size:26,weight:.regular));Text(titles[i]).font(.system(size:11,weight:.semibold))}
                .foregroundStyle(selection==i ? referenceBlue:.white).frame(maxWidth:.infinity).frame(height:58)
                .background(selection==i ? Color.white.opacity(0.13):.clear,in:Capsule())}
                .accessibilityIdentifier("tab_\(i)")
        }}.padding(4).modifier(ReferenceGlass(radius:36)).buttonStyle(.plain)
            .padding(.horizontal,20).padding(.bottom,7)
    }
}
struct InboxView:View {
    @EnvironmentObject var store:ChatStore
    @State private var tab=2
    @State private var selected:Conversation?
    @State private var people=false
    @State private var group=false
    @State private var filter=0
    @State private var editing=false
    @State private var query=""
    @AppStorage("pinnedChats") private var pinned=""
    init(initialTab:Int=2){_tab=State(initialValue:initialTab)}
    private var filtered:[Conversation] {
        store.chats.filter{(filter==0 || $0.kind=="direct") && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query))}
            .sorted{isPinned($0.id) && !isPinned($1.id)}
    }
    private func isPinned(_ id:Int)->Bool {pinned.split(separator:",").contains(Substring("\(store.me?.id ?? 0):\(id)"))}
    private func togglePin(_ id:Int){let key="\(store.me?.id ?? 0):\(id)";var ids=Set(pinned.split(separator:",").map(String.init));if ids.contains(key){ids.remove(key)}else{ids.insert(key)};pinned=ids.sorted().joined(separator:",")}
    var body:some View {
        NavigationStack {
            ZStack(alignment:.bottom){
                Color.black.ignoresSafeArea()
                Group {
                    switch tab {
                    case 0: ReferenceContactsView {selected=$0}
                    case 1: ReferenceCallsView {selected=$0}
                    case 3: ReferenceSettingsView()
                    default: chatList
                    }
                }.frame(maxWidth:.infinity,maxHeight:.infinity)
                ReferenceTabBar(selection:$tab)
            }.toolbar(.hidden,for:.navigationBar)
                .navigationDestination(item:$selected){ChatView(chat:$0)}
                .sheet(isPresented:$people){PeopleView {people=false;selected=$0}}
                .sheet(isPresented:$group){GroupView {group=false;selected=$0}}
                .task {await store.reloadChats()}
                .onChange(of:store.eventVersion){_,_ in Task{await store.reloadChats()}}
        }.tint(referenceBlue)
    }
    private var chatList:some View {
        VStack(spacing:0){
            HStack(spacing:12){
                Button(editing ? "Готово":"Изм."){editing.toggle()}.font(.system(size:17,weight:.medium)).padding(.horizontal,14).frame(height:44).modifier(ReferenceGlass())
                Spacer();Text("Чаты").font(.system(size:17,weight:.semibold));Spacer()
                ReferenceIcon(symbol:"plus.circle.dashed"){group=true}
                ReferenceIcon(symbol:"square.and.pencil",blue:true){people=true}
            }.foregroundStyle(.white).padding(.horizontal,16).padding(.top,8).padding(.bottom,10)
            ReferenceSegments(titles:["Все","Personal"],selected:$filter).padding(.horizontal,16).padding(.bottom,5)
            if editing {HStack {Image(systemName:"magnifyingglass");TextField("Поиск",text:$query)}.padding(10).background(Color(white:0.10),in:Capsule()).padding(.horizontal,16)}
            ScrollView {
                LazyVStack(spacing:0){
                    ForEach(filtered){chat in
                        HStack(spacing:10){
                            if editing {Button {togglePin(chat.id)} label:{Image(systemName:isPinned(chat.id) ? "pin.fill":"pin").foregroundStyle(referenceBlue)}}
                            Button {selected=chat} label:{ReferenceChatRow(chat:chat,pinned:isPinned(chat.id))}.buttonStyle(.plain)
                        }.padding(.horizontal,16)
                        .background(isPinned(chat.id) ? Color(white:0.115):.black)
                        .contextMenu {Button(isPinned(chat.id) ? "Открепить":"Закрепить",systemImage:"pin"){togglePin(chat.id)}}
                    }
                    if filtered.isEmpty {Text("Пока нет чатов").foregroundStyle(referenceGray).padding(.top,80)}
                }.padding(.bottom,90)
            }.refreshable{await store.reloadChats()}
        }
    }
}
struct ReferenceChatRow:View {
    @EnvironmentObject var store:ChatStore
    let chat:Conversation
    let pinned:Bool
    var body:some View {
        HStack(alignment:.top,spacing:10){
            ReferenceAvatar(person:chat.other_user,title:chat.title,size:60).padding(.vertical,8)
            VStack(alignment:.leading,spacing:4){
                HStack(alignment:.firstTextBaseline){Text(chat.title).font(.system(size:17,weight:.semibold)).lineLimit(1).foregroundStyle(.white);Spacer(minLength:4)
                    Text(referenceDate(chat.last_message?.created_at ?? "")).font(.system(size:13)).foregroundStyle(referenceGray)}
                HStack(alignment:.top){Text(chat.last_message?.body.isEmpty == false ? chat.last_message!.body : (chat.last_message == nil ? "Новый чат":"Вложение"))
                    .font(.system(size:16)).foregroundStyle(referenceGray).lineLimit(2).frame(maxWidth:.infinity,alignment:.leading)
                    VStack(spacing:6){if chat.unread>0 {Text("\(chat.unread)").font(.system(size:12,weight:.semibold)).foregroundStyle(.black).padding(.horizontal,6).padding(.vertical,2).background(referenceGray,in:Capsule())};if pinned {Image(systemName:"pin.fill").font(.system(size:14)).foregroundStyle(referenceGray)}}
                }
            }.padding(.top,8).frame(height:76,alignment:.top).overlay(alignment:.bottom){Rectangle().fill(Color.white.opacity(0.10)).frame(height:0.5)}
        }.contentShape(Rectangle())
    }
}
func referenceDate(_ value:String)->String {
    let parser=DateFormatter();parser.locale=Locale(identifier:"en_US_POSIX");parser.timeZone=TimeZone(secondsFromGMT:0);parser.dateFormat="yyyy-MM-dd HH:mm:ss"
    guard let date=parser.date(from:value) else{return ""}
    let format=DateFormatter();format.locale=Locale(identifier:"ru_RU");format.dateFormat=Calendar.current.isDateInToday(date) ? "HH:mm":"dd.MM"
    return format.string(from:date)
}
struct ReferenceContactsView:View {
    @EnvironmentObject var store:ChatStore
    let onOpen:(Conversation)->Void
    @State private var query=""
    @State private var people:[Person]=[]
    @State private var add=false
    @State private var alphabetical=true
    private var contacts:[Person]{
        var unique=[Int:Person]();for chat in store.chats {if let p=chat.other_user {unique[p.id]=p}};for p in people {unique[p.id]=p}
        let list=unique.values.filter{query.isEmpty || $0.display_name.localizedCaseInsensitiveContains(query) || $0.username.localizedCaseInsensitiveContains(query)}
        return list.sorted{alphabetical ? $0.display_name.localizedStandardCompare($1.display_name) == .orderedAscending : $0.id>$1.id}
    }
    var body:some View {
        VStack(spacing:0){
            HStack {Menu {Button("По имени"){alphabetical=true};Button("Сначала новые"){alphabetical=false}} label:{Text("Сортировка").font(.system(size:17)).padding(.horizontal,13).frame(height:44).modifier(ReferenceGlass())}
                Spacer(minLength:8);Text("Контакты").font(.system(size:17,weight:.semibold));Spacer(minLength:8);ReferenceIcon(symbol:"plus"){add=true}
            }.foregroundStyle(.white).padding(.horizontal,16).padding(.top,8)
            HStack {Image(systemName:"magnifyingglass");TextField("Поиск",text:$query).textInputAutocapitalization(.never)}.font(.system(size:18)).foregroundStyle(referenceGray).padding(12).background(Color(white:0.10),in:Capsule()).padding(.horizontal,16).padding(.top,10).padding(.bottom,15)
            ScrollView {LazyVStack(spacing:0){
                ShareLink(item:URL(string:"https://chat.nightwell.fun")!){HStack(spacing:22){Image(systemName:"person.badge.plus").font(.system(size:25)).frame(width:40);Text("Пригласить").font(.system(size:18));Spacer()}.foregroundStyle(referenceBlue).padding(.vertical,13)}
                ForEach(contacts){person in Button {Task{if let c=await store.openDirect(person){onOpen(c)}}} label:{ReferencePersonRow(person:person,subtitle:person.online == true ? "в сети":"не в сети")}.buttonStyle(.plain)}
            }.padding(.horizontal,16).padding(.bottom,90)}
        }.sheet(isPresented:$add){PeopleView {add=false;onOpen($0)}}
            .task(id:query){guard query.count>1 else{people=[];return};try? await Task.sleep(for:.milliseconds(300));guard !Task.isCancelled else{return};people=await store.find(query)}
    }
}
struct ReferencePersonRow:View {
    let person:Person
    var subtitle:String
    var body:some View {HStack(spacing:10){ReferenceAvatar(person:person,title:person.display_name,size:40)
        VStack(alignment:.leading,spacing:2){Text(person.display_name).font(.system(size:18)).foregroundStyle(.white).lineLimit(1);Text(subtitle).font(.system(size:14)).foregroundStyle(person.online == true ? referenceBlue:referenceGray).lineLimit(1);Divider().overlay(Color.white.opacity(0.08)).padding(.top,6)}
    }.padding(.top,5).frame(minHeight:54).contentShape(Rectangle())}
}
struct CallHistoryItem:Decodable,Identifiable {let id:String;let person:Person;let outgoing:Bool;let missed:Bool;let created_at:Int;let status:String}
struct ChatDetails:Decodable {let members:[Person];let role:String;let kind:String;let muted:Bool?}
struct ReferenceCallsView:View {
    @EnvironmentObject var store:ChatStore
    let onOpen:(Conversation)->Void
    @State private var filter=0
    @State private var history:[CallHistoryItem]=[]
    @State private var pending:[VoiceCall]=[]
    @State private var add=false
    @State private var editing=false
    @State private var callURL:URL?
    @State private var showCall=false
    @AppStorage("hiddenCalls") private var hidden=""
    private var visible:[CallHistoryItem]{history.filter{(filter==0 || $0.missed) && !hidden.split(separator:",").contains(Substring($0.id))}}
    var body:some View {VStack(spacing:0){
        HStack(spacing:14){Button(editing ? "Готово":"Изм."){editing.toggle()}.padding(.horizontal,13).frame(height:44).modifier(ReferenceGlass());Spacer(minLength:0);ReferenceSegments(titles:["Все","Пропущ."],selected:$filter).frame(maxWidth:200);Spacer(minLength:0);ReferenceIcon(symbol:"phone.badge.plus"){add=true}}.foregroundStyle(.white).padding(.horizontal,16).padding(.top,8).padding(.bottom,10)
        ScrollView {LazyVStack(alignment:.leading,spacing:0){
            Button {add=true} label:{HStack(spacing:18){Image(systemName:"phone.badge.plus").font(.system(size:27)).frame(width:40);Text("Новый звонок").font(.system(size:18))}.foregroundStyle(referenceBlue).padding(.vertical,15)}
            Divider().padding(.leading,44)
            ForEach(pending){call in HStack {Text(call.caller_name ?? "Входящий звонок");Spacer();Button("Ответить"){Task{if let c=await store.acceptCall(id:call.id),let u=store.voiceURL(c){callURL=u;showCall=true};await reload()}};Button {Task{await store.declineCall(id:call.id);await reload()}} label:{Image(systemName:"phone.down.fill").foregroundStyle(.red)}}.padding(.vertical,12)}
            Text("НЕДАВНИЕ ЗВОНКИ").font(.system(size:13)).foregroundStyle(referenceGray).padding(.vertical,9)
            ForEach(visible){item in HStack(spacing:10){
                if editing {Button {hidden += ","+item.id} label:{Image(systemName:"minus.circle.fill").foregroundStyle(.red)}}
                Image(systemName:item.outgoing ? "phone.arrow.up.right.fill":"phone.fill").font(.system(size:12)).foregroundStyle(referenceGray).frame(width:9)
                ReferenceAvatar(person:item.person,title:item.person.display_name,size:40)
                VStack(alignment:.leading,spacing:2){Text(item.person.display_name).font(.system(size:18)).foregroundStyle(item.missed ? Color(red:0.90,green:0.34,blue:0.26):.white).lineLimit(1);Text(item.missed ? "Пропущенный":(item.outgoing ? "Исходящий":"Входящий")).font(.system(size:14)).foregroundStyle(referenceGray)}
                Spacer(minLength:0);Text(Date(timeIntervalSince1970:Double(item.created_at)),format:.dateTime.day().month()).font(.system(size:14)).foregroundStyle(referenceGray)
                Button {Task{if let c=await store.openDirect(item.person){onOpen(c)}}} label:{Image(systemName:"info.circle").font(.system(size:24)).foregroundStyle(referenceBlue)}
            }.padding(.vertical,7).overlay(alignment:.bottom){Divider().padding(.leading,70)}.contentShape(Rectangle()).onTapGesture{Task{await start(item.person)}}}
            if history.isEmpty && pending.isEmpty {Text("Здесь появятся твои звонки").foregroundStyle(referenceGray).padding(.top,30)}
        }.padding(.horizontal,16).padding(.bottom,90)}.refreshable{await reload()}
    }.task{await reload()}.onChange(of:store.eventVersion){_,_ in Task{await reload()}}
        .sheet(isPresented:$add){PeopleView {chat in add=false;if let person=chat.other_user {Task{await start(person)}}}}
        .sheet(isPresented:$showCall,onDismiss:{Task{await reload()}}){if let callURL {SafariCallView(url:callURL)}}}
    private func reload() async {do{history=try await store.request("/calls/history")}catch{store.alertText=error.localizedDescription};pending=await store.pendingCalls()}
    private func start(_ person:Person) async {guard await store.openDirect(person) != nil else{return};if let call=await store.makeCall(to:person.id),let u=store.voiceURL(call){callURL=u;showCall=true}}
}
struct ReferenceSettingsView:View {
    @EnvironmentObject var store:ChatStore
    var body:some View {ScrollView {VStack(spacing:18){
        ReferenceAvatar(person:store.me,title:store.me?.display_name ?? "N",size:100).padding(.top,24)
        Text(store.me?.display_name ?? "Nightwell").font(.system(size:30,weight:.semibold))
        Text("@"+(store.me?.username ?? "")).foregroundStyle(referenceGray)
        VStack(spacing:0){
            settingsLink("Изменить профиль",icon:"person.crop.circle",destination:EditProfileView())
            settingsLink("Телефон и приватность",icon:"lock",destination:PhoneLinkView())
            settingsLink("Данные и память",icon:"externaldrive",destination:DataSettingsView())
            settingsLink("Оформление",icon:"paintbrush",destination:AppearanceSettingsView())
            Button {if let u=URL(string:UIApplication.openSettingsURLString){UIApplication.shared.open(u)}} label:{Label("Уведомления и звуки",systemImage:"bell").frame(maxWidth:.infinity,alignment:.leading).padding(16)}
        }.background(Color(white:0.115),in:RoundedRectangle(cornerRadius:24))
        NavigationLink {SettingsView()} label:{Text("Все настройки").frame(maxWidth:.infinity).padding(16).background(Color(white:0.115),in:RoundedRectangle(cornerRadius:20))}
    }.padding(.horizontal,16).padding(.bottom,100)}}
    private func settingsLink<V:View>(_ title:String,icon:String,destination:V)->some View {NavigationLink {destination} label:{HStack {Image(systemName:icon).frame(width:24);Text(title);Spacer();Image(systemName:"chevron.right").font(.caption).foregroundStyle(referenceGray)}.padding(16)}.overlay(alignment:.bottom){Divider().padding(.leading,55)}}
}

struct ChatWallpaper:View {
    private let symbols=["paperplane","gift","moon.stars","leaf","star","music.note","balloon","cup.and.saucer","heart","lightbulb","cloud","carrot","sparkles","fish","sun.max","gamecontroller"]
    var body:some View {
        GeometryReader {geometry in
            ZStack {Color.black
                Canvas {context,size in
                    for row in 0..<Int(size.height/65)+2 {
                        for column in 0..<Int(size.width/65)+2 {
                            let index=(row*7+column*3)%symbols.count
                            var tile=context
                            tile.translateBy(x:CGFloat(column)*65+CGFloat(row%2)*25,y:CGFloat(row)*65+16)
                            tile.rotate(by:.degrees(Double((row*31+column*47)%80)-40))
                            if let icon=tile.resolveSymbol(id:index){tile.draw(icon,at:.zero)}
                        }
                    }
                } symbols: {ForEach(symbols.indices,id:\.self){i in Image(systemName:symbols[i]).font(.system(size:i%3==0 ? 39:30,weight:.ultraLight)).foregroundStyle(Color(red:0.33,green:0.23,blue:0.47).opacity(0.48)).tag(i)}}
                LinearGradient(colors:[Color.purple.opacity(0.06),.clear,Color.blue.opacity(0.035)],startPoint:.topLeading,endPoint:.bottomTrailing)
            }.frame(width:geometry.size.width,height:geometry.size.height)
        }.ignoresSafeArea()
    }
}
struct ReferenceChatHeader:View {
    @Environment(\.dismiss) var dismiss
    let chat:Conversation
    let subtitle:String
    let openProfile:()->Void
    var body:some View {HStack(spacing:15){
        ReferenceIcon(symbol:"chevron.left"){dismiss()}
        Spacer(minLength:0)
        Button(action:openProfile){VStack(spacing:1){Text(chat.title).font(.system(size:17,weight:.semibold)).lineLimit(1);Text(subtitle).font(.system(size:12)).foregroundStyle(referenceGray).lineLimit(1)}.padding(.horizontal,16).frame(height:44).modifier(ReferenceGlass())}.buttonStyle(.plain)
        Spacer(minLength:0)
        Button(action:openProfile){ReferenceAvatar(person:chat.other_user,title:chat.title,size:42).overlay(Circle().stroke(.white.opacity(0.16),lineWidth:2))}
    }.foregroundStyle(.white).padding(.horizontal,16).padding(.top,8).padding(.bottom,8)}
}
struct ReferenceReply:View {
    let message:ChatMessage?
    var body:some View {if let message {HStack(spacing:7){RoundedRectangle(cornerRadius:2).fill(referenceBlue).frame(width:3)
        VStack(alignment:.leading,spacing:2){Text(message.sender_name).font(.system(size:13,weight:.semibold)).foregroundStyle(referenceBlue);Text(message.body.isEmpty ? "Вложение":message.body).font(.system(size:14)).foregroundStyle(.white).lineLimit(2)}.padding(.vertical,5);Spacer(minLength:0)
    }.padding(.trailing,7).background(referenceBlue.opacity(0.10),in:RoundedRectangle(cornerRadius:5))}}
}
struct ReferenceGroupProfile:View {
    @EnvironmentObject var store:ChatStore
    @Environment(\.dismiss) var dismiss
    let chat:Conversation
    let onLeave:()->Void
    @State private var details:ChatDetails?
    @State private var messages:[ChatMessage]=[]
    @State private var section=0
    @State private var searching=false
    @State private var query=""
    @State private var add=false
    @State private var people:[Person]=[]
    @State private var personQuery=""
    @State private var confirmLeave=false
    @State private var fileURL:URL?
    @State private var callURL:URL?
    @State private var showCall=false
    @AppStorage("mutedChats") private var muted=""
    @AppStorage("savedMessages") private var saved=""
    private var key:String {"\(store.me?.id ?? 0):\(chat.id)"}
    private var isMuted:Bool {muted.split(separator:",").contains(Substring(key))}
    private var filteredMessages:[ChatMessage]{messages.filter{m in
        let matching=query.isEmpty || m.body.localizedCaseInsensitiveContains(query) || (m.attachment?.filename.localizedCaseInsensitiveContains(query) ?? false)
        guard matching && m.deleted==0 else{return false}
        if searching {return true}
        if section==2 {return saved.split(separator:",").contains(Substring("\(store.me?.id ?? 0):\(m.id)"))}
        guard let a=m.attachment else{return false}
        let media=a.content_type.hasPrefix("image/") || a.content_type.hasPrefix("video/")
        return section==1 ? media:!media
    }}
    var body:some View {
        NavigationStack {
            ScrollView {VStack(spacing:18){
                ReferenceAvatar(person:chat.other_user,title:chat.title,size:100).padding(.top,20)
                VStack(spacing:2){Text(chat.title).font(.system(size:32,weight:.semibold));Text(chat.kind=="group" ? "\(details?.members.count ?? 0) участников, \(details?.members.filter{$0.online == true}.count ?? 0) в сети":"@\(chat.other_user?.username ?? "")").font(.system(size:17)).foregroundStyle(referenceGray)}
                actionRow.padding(.top,18)
                ScrollView(.horizontal,showsIndicators:false){ReferenceSegments(titles:["Участники","Медиа","Избранное","Файлы"],selected:$section).frame(width:440)}.padding(.top,6)
                if searching {HStack{Image(systemName:"magnifyingglass");TextField("Поиск в переписке",text:$query);Button {searching=false;query=""} label:{Image(systemName:"xmark.circle.fill")}}.padding(12).background(Color(white:0.12),in:Capsule())}
                VStack(spacing:0){
                    if section==0 && !searching {
                        if details?.role=="owner" && chat.kind=="group" {Button {add=true} label:{Label("Добавить участников",systemImage:"person.badge.plus").font(.system(size:18)).frame(maxWidth:.infinity,alignment:.leading).padding(16)}}
                        ForEach(details?.members ?? []){p in ReferencePersonRow(person:p,subtitle:p.online == true ? "в сети":"не в сети").padding(.horizontal,14)}
                    } else {
                        ForEach(filteredMessages){message in Button {Task{if let a=message.attachment{fileURL=await store.downloadFile(a)}}} label:{HStack(spacing:12){if let a=message.attachment,a.content_type.hasPrefix("image/"){PrivateImage(attachment:a.id).frame(width:55,height:55).clipped()}else{Image(systemName:message.attachment == nil ? "bubble.left":"doc").frame(width:35)};VStack(alignment:.leading,spacing:4){Text(message.body.isEmpty ? message.attachment?.filename ?? "Вложение":message.body).lineLimit(2);Text(referenceDate(message.created_at)).font(.caption).foregroundStyle(referenceGray)};Spacer()}.padding(14)}.foregroundStyle(.white);Divider().padding(.leading,60)}
                        if filteredMessages.isEmpty {Text("Пока пусто").foregroundStyle(referenceGray).frame(maxWidth:.infinity).padding(28)}
                    }
                }.padding(.bottom,8).background(Color(white:0.115),in:RoundedRectangle(cornerRadius:25))
            }.padding(.horizontal,16).padding(.bottom,30)}
            .background(Color.black).toolbar(.hidden,for:.navigationBar)
            .overlay(alignment:.topLeading){ReferenceIcon(symbol:"chevron.left"){dismiss()}.padding(.leading,16).padding(.top,8)}
        }.tint(referenceBlue).task{await load()}
            .sheet(isPresented:$add){NavigationStack{List{TextField("Имя или @ник",text:$personQuery).onSubmit{Task{people=await store.find(personQuery)}};ForEach(people){p in Button(p.display_name){Task{do{struct Add:Encodable{let user_id:Int};let _:EmptyResult=try await store.request("/chats/\(chat.id)/members",method:"POST",body:Add(user_id:p.id));add=false;await load()}catch{store.alertText=error.localizedDescription}}}}}.navigationTitle("Добавить участников").toolbar{ToolbarItem(placement:.topBarTrailing){Button("Готово"){add=false}}}}}
            .confirmationDialog("Покинуть группу?",isPresented:$confirmLeave,titleVisibility:.visible){Button("Покинуть",role:.destructive){Task{do{let _:EmptyResult=try await store.request("/chats/\(chat.id)/membership",method:"DELETE");await store.reloadChats();dismiss();onLeave()}catch{store.alertText=error.localizedDescription}}}}
            .quickLookPreview($fileURL)
            .sheet(isPresented:$showCall){if let callURL{SafariCallView(url:callURL)}}
    }
    private var actionRow:some View {HStack(spacing:8){
        action(isMuted ? "bell.slash":"bell","звук"){Task{do{struct Preference:Encodable{let muted:Bool};let next = !isMuted;let _:EmptyResult=try await store.request("/chats/\(chat.id)/notifications",method:"PATCH",body:Preference(muted:next));setMuted(next)}catch{store.alertText=error.localizedDescription}}}
        action("magnifyingglass","поиск"){searching.toggle()}
        if chat.kind=="group" {action("rectangle.portrait.and.arrow.right","покинуть"){confirmLeave=true}}
        else {action("phone","звонок"){Task{if let p=chat.other_user,let c=await store.makeCall(to:p.id),let u=store.voiceURL(c){callURL=u;showCall=true}}}}
        ShareLink(item:chat.title){VStack(spacing:8){Image(systemName:"ellipsis").font(.system(size:26));Text("ещё").font(.system(size:13))}.frame(maxWidth:.infinity).frame(height:58).background(Color(white:0.115),in:RoundedRectangle(cornerRadius:18))}
    }}
    private func action(_ symbol:String,_ title:String,perform:@escaping()->Void)->some View{Button(action:perform){VStack(spacing:8){Image(systemName:symbol).font(.system(size:25));Text(title).font(.system(size:13))}.frame(maxWidth:.infinity).frame(height:58).background(Color(white:0.115),in:RoundedRectangle(cornerRadius:18))}.buttonStyle(.plain)}
    private func setMuted(_ enabled:Bool){var keys=Set(muted.split(separator:",").map(String.init));if enabled{keys.insert(key)}else{keys.remove(key)};muted=keys.sorted().joined(separator:",")}
    private func load() async {
        do {details=try await store.request("/chats/\(chat.id)/details");setMuted(details?.muted ?? false)
            var collected:[ChatMessage]=[];var before:Int?=nil
            repeat {let page:[ChatMessage]=try await store.request("/chats/\(chat.id)/messages?limit=100"+(before.map{"&before=\($0)"} ?? ""));collected=page+collected;if page.count<100 {break};before=page.first?.id;if Task.isCancelled{return}} while before != nil
            messages=collected
        }catch{store.alertText=error.localizedDescription}
    }
}
