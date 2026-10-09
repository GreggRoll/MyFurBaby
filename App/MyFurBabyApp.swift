import SwiftUI

@main struct MyFurBabyApp: App {
    @State private var store = FurStore()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            RootView().environment(store).tint(FurTheme.pink).preferredColorScheme(.light)
                .task { await store.start() }
                .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await store.refresh() } } }
        }
    }
}
