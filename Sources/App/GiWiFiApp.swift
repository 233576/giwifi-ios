import SwiftUI

@main
struct GiWiFiApp: App {
    @StateObject private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .onAppear { store.restore() }
                .onChange(of: scenePhase) { phase in
                    if phase == .background {
                        store.stopAuto()
                    }
                }
        }
    }
}
