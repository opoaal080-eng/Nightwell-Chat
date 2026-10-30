import SwiftUI

@main
struct NightwellChatApp: App {
    @StateObject private var store = ChatStore()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .task { await store.bootstrap() }
        }
    }
}
