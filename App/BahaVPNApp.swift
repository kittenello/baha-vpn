import SwiftUI

@main struct BahaVPNApp: App {
    @StateObject private var store = ClientStore()
    @StateObject private var tunnel = TunnelController()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store).environmentObject(tunnel)
                .preferredColorScheme(.dark)
                .task { store.seedPreview(); await store.refreshAll(onlyDue: true) }
                .onChange(of: phase) { _, value in
                    if value == .active { Task { await store.refreshAll(onlyDue: true) } }
                }
        }
    }
}
