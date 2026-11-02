import SwiftUI

struct NightwellSticker:Identifiable {
    let emoji:String
    let title:String
    var id:String{emoji}
    static let pack:[NightwellSticker]=[
        .init(emoji:"🔥",title:"ОГОНЬ"),.init(emoji:"😎",title:"НА ВАЙБЕ"),
        .init(emoji:"🫶",title:"ОБНЯЛ"),.init(emoji:"💀",title:"НУ ВСЁ"),
        .init(emoji:"🚀",title:"ПОГНАЛИ"),.init(emoji:"🥹",title:"ОТ ДУШИ"),
        .init(emoji:"🫠",title:"Я ПОПЛЫЛ"),.init(emoji:"⚡️",title:"ЗАРЯЖЕН"),
        .init(emoji:"🤝",title:"В ДЕЛЕ"),.init(emoji:"🎉",title:"ЭТО ПОБЕДА"),
        .init(emoji:"👀",title:"СМОТРЮ"),.init(emoji:"🌙",title:"НОЧНОЙ РЕЖИМ")]
    static func find(_ body:String)->NightwellSticker?{pack.first{$0.emoji==body}}
    static func isEmoji(_ body:String)->Bool {
        let text=body.trimmingCharacters(in:.whitespacesAndNewlines)
        return !text.isEmpty && text.count<=3 && text.allSatisfy {character in
            character.unicodeScalars.contains{$0.properties.isEmojiPresentation || $0.value==0xFE0F}
        }
    }
}
struct AnimatedGlyph:View {
    let text:String
    var size:CGFloat=52
    var sticker=false
    @AppStorage("messageAnimations") private var enabled=true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible=false
    private var moving:Bool{enabled && !reduceMotion && visible}
    var body:some View {
        TimelineView(.animation(minimumInterval:1.0/24,paused:!moving)){timeline in
            let phase=moving ? timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy:3)*2*Double.pi/3:0
            Text(text).font(.system(size:size))
                .scaleEffect(1+CGFloat(sin(phase))*0.045)
                .rotationEffect(.degrees(sticker ? sin(phase)*5:0))
                .offset(y:moving ? CGFloat(sin(phase))*3:0)
        }.onAppear{visible=true}.onDisappear{visible=false}
        .accessibilityLabel(text)
    }
}
struct NightwellStickerView:View {
    let sticker:NightwellSticker
    var compact=false
    var body:some View {
        VStack(spacing:compact ? 3:7){
            AnimatedGlyph(text:sticker.emoji,size:compact ? 42:78,sticker:true)
            Text(sticker.title).font(.system(size:compact ? 8:12,weight:.black,design:.rounded)).tracking(1).foregroundStyle(.white)
        }.frame(width:compact ? 90:154,height:compact ? 88:150)
        .background {
            RoundedRectangle(cornerRadius:compact ? 22:36)
                .fill(LinearGradient(colors:[referenceBlue.opacity(0.30),Color.purple.opacity(0.20),Color(white:0.10)],startPoint:.topLeading,endPoint:.bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius:compact ? 22:36).stroke(.white.opacity(0.12),lineWidth:1))
        }.accessibilityElement(children:.combine)
    }
}
struct ExpressiveMessageBody:View {
    let message:ChatMessage
    var body:some View {
        Group {
            if message.deleted != 0 {Text("Сообщение удалено").font(.system(size:15)).foregroundStyle(referenceGray).italic()}
            else if message.visual=="sticker",let sticker=NightwellSticker.find(message.body){NightwellStickerView(sticker:sticker)}
            else if NightwellSticker.isEmoji(message.body){AnimatedGlyph(text:message.body).padding(.vertical,5)}
            else {Text(message.body).font(.system(size:17)).foregroundStyle(.white)}
        }.contentTransition(.opacity)
    }
}
struct ExpressivePicker:View {
    let busy:Bool
    let insertEmoji:(String)->Void
    let sendSticker:(NightwellSticker)->Void
    @State private var section=0
    private let emojis=["😀","😂","🥹","😎","🫠","😍","🤯","😭","🫶","❤️","🔥","⚡️","💀","👀","🤝","🎉","🚀","🌙","👍","✨","🤍","💜","😴","🥳"]
    var body:some View {
        VStack(spacing:14){
            ReferenceSegments(titles:["Эмодзи","Стикеры"],selected:$section).padding(.horizontal,16).padding(.top,20)
            ScrollView {
                if section==0 {
                    LazyVGrid(columns:Array(repeating:GridItem(.flexible()),count:6),spacing:15){ForEach(emojis,id:\.self){emoji in
                        Button {insertEmoji(emoji);UISelectionFeedbackGenerator().selectionChanged()} label:{Text(emoji).font(.system(size:30)).frame(height:42)}
                    }}.padding(.horizontal,14)
                }else{
                    Text("NIGHTWELL · НАСТРОЕНИЕ").font(.system(size:11,weight:.bold)).tracking(2).foregroundStyle(referenceGray)
                    LazyVGrid(columns:Array(repeating:GridItem(.flexible()),count:3),spacing:12){ForEach(NightwellSticker.pack){sticker in
                        Button {sendSticker(sticker)} label:{NightwellStickerView(sticker:sticker,compact:true)}.disabled(busy).accessibilityLabel("Отправить стикер: "+sticker.title)
                    }}.padding(.horizontal,16)
                }
            }
        }.background(Color(white:0.06)).presentationDetents([.height(370),.large]).presentationDragIndicator(.visible)
    }
}
