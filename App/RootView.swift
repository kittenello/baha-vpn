import SwiftUI

enum ImportDestination: String, Identifiable {
    case profile, subscription
    var id: String { rawValue }
}

struct RootView: View {
    @EnvironmentObject var store: ClientStore
    @EnvironmentObject var tunnel: TunnelController
    @State private var tab = 0
    @State private var destination: ImportDestination?
    @State private var pending = ""

    var body: some View {
        TabView(selection: $tab) {
            HomeView(add: { pending = ""; destination = .profile })
                .tabItem { Label("главная", systemImage: "house") }.tag(0)
            ServersView().tabItem { Label("серверы", systemImage: "list.bullet") }.tag(1)
            SettingsView().tabItem { Label("настройки", systemImage: "gearshape") }.tag(2)
        }
        .tint(Design.accent)
        .sheet(item: $destination) { value in
            ImportView(mode: value, initialText: pending)
        }
        .onOpenURL { url in
            pending = url.absoluteString
            destination = .profile
        }
        .alert("ошибка", isPresented: Binding(get: { store.error != nil || tunnel.error != nil }, set: { if !$0 { store.error = nil; tunnel.error = nil } })) {
            Button("понятно", role: .cancel) { store.error = nil; tunnel.error = nil }
        } message: { Text(store.error ?? tunnel.error ?? "") }
        .overlay(alignment: .top) {
            if let notice = store.notice {
                Text(notice).font(.subheadline).padding(14).background(.ultraThinMaterial, in: Capsule()).padding(.top, 6)
                    .onTapGesture { store.notice = nil }
                    .task(id: notice) { try? await Task.sleep(for: .seconds(3)); if store.notice == notice { store.notice = nil } }
            }
        }
    }
}
