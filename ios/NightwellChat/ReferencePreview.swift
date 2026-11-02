#if DEBUG
import SwiftUI

enum ReferencePreview {
    static var enabled:Bool {ProcessInfo.processInfo.arguments.contains("--reference-preview")}
    static let names=["Nightwell Music","Друзья","Михаил","Анна","Разработка","Алексей","Мария","Команда"]
    static var people:[[String:Any]] {(1...8).map {["id":$0,"username":"user\($0)","display_name":names[$0-1],"has_avatar":false]}}
    static var chats:[[String:Any]] {(1...8).map {i in ["id":i,"kind":i%2==0 ? "group":"direct","title":names[i-1],"other_user":i%2==0 ? (NSNull() as Any):(people[i-1] as Any),"owner_id":99,"unread":i==4 ? 6:0,"last_message":["id":i,"body":["Дополнение к обновлению","Привет! Как дела?","Встречаемся сегодня","Спасибо за помощь"][i%4],"sender_id":i,"created_at":"2026-11-02 00:15:00"]]}}
    static var messages:[[String:Any]] {(1...8).map {i in ["id":i,"chat_id":2,"sender_id":i%3+1,"sender_name":["Михаил","Алексей","Анна"][i%3],"body":["Привет!","Посмотрели новый интерфейс?","Да, выглядит отлично","Давайте обсудим вечером","Хорошо, договорились"][i%5],"reply_to":i==4 ? (2 as Any):(NSNull() as Any),"created_at":"2026-11-02 00:15:00","edited_at":NSNull(),"deleted":0,"reactions":i==3 ? [["emoji":"❤️","count":2]]:[],"attachment":NSNull()]}}
    static func data(_ path:String) throws -> Data {
        let value:Any
        if path=="/chats" {value=chats}
        else if path.contains("/details"){value=["members":people,"role":"owner","kind":"group","muted":false]}
        else if path.contains("/messages"){value=messages}
        else if path=="/calls/history"{value=(1...12).map{i -> [String:Any] in ["id":"call\(i)","person":people[i%8],"outgoing":i%3==0,"missed":i%4==0,"created_at":1793571000-i*86400,"status":"ended"]}}
        else if path=="/calls/pending" {value=[] as [Int]}
        else if path.hasPrefix("/users"){value=people}
        else if path=="/me" {value=["id":99,"username":"mikhail","display_name":"Михаил","has_avatar":false]}
        else {value=["ok":true]}
        return try JSONSerialization.data(withJSONObject:value)
    }
    static func chat()->Conversation {try! JSONDecoder().decode([Conversation].self,from:data("/chats"))[1]}
}
struct ReferencePreviewEntry:View {
    @StateObject private var store:ChatStore
    private let screen:String
    init(){
        let s=ChatStore();s.token="preview";s.me=Person(id:99,username:"mikhail",display_name:"Михаил",has_avatar:false)
        s.chats=(try? JSONDecoder().decode([Conversation].self,from:ReferencePreview.data("/chats"))) ?? []
        _store=StateObject(wrappedValue:s)
        screen=ProcessInfo.processInfo.arguments.last ?? "chats"
    }
    var body:some View {
        Group {
            if screen=="chat" {NavigationStack{ChatView(chat:ReferencePreview.chat())}}
            else if screen=="group" {ReferenceGroupProfile(chat:ReferencePreview.chat(),onLeave:{})}
            else {InboxView(initialTab:screen=="contacts" ? 0:(screen=="calls" ? 1:2))}
        }.environmentObject(store).preferredColorScheme(.dark)
    }
}
#endif
