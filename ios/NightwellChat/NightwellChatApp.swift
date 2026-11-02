import SwiftUI

@main
struct NightwellChatApp: App {
    @StateObject private var store = ChatStore()
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ReferencePreview.enabled {ReferencePreviewEntry()} else {normalRoot}
            #else
            normalRoot
            #endif
        }
    }
    private var normalRoot:some View {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .task { await store.bootstrap() }
    }
}

