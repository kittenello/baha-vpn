import SwiftUI
import BahaCore

struct ServersView: View {
    @EnvironmentObject var store: ClientStore
    @EnvironmentObject var tunnel: TunnelController
    @State private var search = ""
    @State private var favorites = false
    @State private var destination: ImportDestination?
    @State private var deleting: ServerProfile?

    private var filtered: [ServerProfile] {
        store.state.profiles.filter { (!favorites || $0.isFavorite) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.host.localizedCaseInsensitiveContains(search)) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Picker("фильтр", selection: $favorites) { Text("все").tag(false); Text("избранное").tag(true) }.pickerStyle(.segmented)
                    NavigationLink { SubscriptionsView() } label: {
                        HStack { Label("подписки", systemImage: "rectangle.stack"); Spacer(); Text("\(store.state.subscriptions.count)").foregroundStyle(.secondary); Image(systemName: "chevron.right").font(.caption) }.cardStyle()
                    }.buttonStyle(.plain)
                    if filtered.isEmpty {
                        EmptyState(title: "серверов пока нет", text: "добавь ссылку или подписку, либо измени фильтр", symbol: "network")
                        Button("добавить сервер") { destination = .profile }.buttonStyle(.borderedProminent)
                    } else {
                        ForEach(groups, id: \.id) { group in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(group.title).font(.caption).foregroundStyle(.secondary).padding(.leading, 4)
                                VStack(spacing: 0) {
                                    ForEach(group.profiles) { profile in
                                        row(profile)
                                        if profile.id != group.profiles.last?.id { Divider().padding(.leading, 48) }
                                    }
                                }.background(Design.card, in: RoundedRectangle(cornerRadius: 18))
                            }
                        }
                    }
                    Button {
                        Task { await store.checkLatency() }
                    } label: {
                        HStack { if store.checkingLatency { ProgressView() }; Label("проверить задержку", systemImage: "waveform.path") }.frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered).disabled(store.checkingLatency || store.state.profiles.isEmpty)
                    Text("задержка tcp до сервера; доступность впн проверяется подключением").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.padding(20)
            }
            .searchable(text: $search, prompt: "поиск")
            .navigationTitle("серверы").pageBackground()
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { destination = .profile } label: { Image(systemName: "plus") }.accessibilityLabel("добавить сервер") } }
            .sheet(item: $destination) { ImportView(mode: $0) }
            .alert("удалить сервер?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("удалить", role: .destructive) { if let deleting { store.removeProfile(deleting.id) }; deleting = nil }
                Button("отмена", role: .cancel) { deleting = nil }
            } message: { Text("\(deleting?.name ?? ""). сервер из подписки может вернуться при обновлении") }
        }
    }

    private var groups: [(id: String, title: String, profiles: [ServerProfile])] {
        var result: [(id: String, title: String, profiles: [ServerProfile])] = []
        let local = filtered.filter { $0.subscriptionID == nil }
        if !local.isEmpty { result.append(("local", "личные", local)) }
        for subscription in store.state.subscriptions {
            let profiles = filtered.filter { $0.subscriptionID == subscription.id }
            if !profiles.isEmpty { result.append((subscription.id.uuidString, subscription.name, profiles)) }
        }
        return result
    }

    private func row(_ profile: ServerProfile) -> some View {
        HStack(spacing: 12) {
            Button { store.select(profile) } label: {
                HStack(spacing: 12) {
                    Image(systemName: store.state.selectedID == profile.id ? "checkmark.circle.fill" : "mappin.circle")
                        .foregroundStyle(store.state.selectedID == profile.id ? Design.accent : .secondary)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(profile.name).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                        Text(profile.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if let latency = store.latency[profile.id] {
                        Text(latency < 0 ? "—" : "\(latency) мс").font(.caption.monospacedDigit()).foregroundStyle(latency < 0 ? .secondary : Design.accent)
                    }
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(tunnel.running)
            Button { store.favorite(profile.id) } label: { Image(systemName: profile.isFavorite ? "star.fill" : "star").foregroundStyle(profile.isFavorite ? Design.accent : .secondary) }
                .buttonStyle(.plain).accessibilityLabel(profile.isFavorite ? "убрать из избранного" : "в избранное")
            Menu {
                Button("скопировать ссылку", systemImage: "doc.on.doc") { UIPasteboard.general.string = profile.link; store.notice = "ссылка скопирована" }
                Button("удалить", systemImage: "trash", role: .destructive) { deleting = profile }.disabled(tunnel.running)
            } label: { Image(systemName: "ellipsis").padding(.vertical, 8) }
        }.padding(16)
    }
}
