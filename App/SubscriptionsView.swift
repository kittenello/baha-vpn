import SwiftUI
import BahaCore

struct SubscriptionsView: View {
    @EnvironmentObject var store: ClientStore
    @EnvironmentObject var tunnel: TunnelController
    @State private var destination: ImportDestination?
    @State private var deleting: ServerSubscription?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if store.state.subscriptions.isEmpty {
                    EmptyState(title: "подписок пока нет", text: "добавь https-ссылку со списком своих серверов", symbol: "rectangle.stack")
                    Button("добавить подписку") { destination = .subscription }.buttonStyle(.borderedProminent)
                }
                ForEach(store.state.subscriptions) { subscription in
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top) {
                            Image(systemName: "doc.text").font(.title2).foregroundStyle(Design.accent)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(subscription.name).font(.headline)
                                Text("\(store.state.profiles.filter { $0.subscriptionID == subscription.id }.count) серверов").font(.subheadline).foregroundStyle(.secondary)
                                if let updated = subscription.updatedAt {
                                    Text("обновлено \(updated.formatted(.relative(presentation: .named)))").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if store.refreshing.contains(subscription.id) { ProgressView() }
                            else {
                                Menu {
                                    Button("обновить", systemImage: "arrow.clockwise") { Task { await store.refresh(subscription) } }
                                    Button("скопировать ссылку", systemImage: "doc.on.doc") { UIPasteboard.general.string = subscription.url.absoluteString }
                                    Button("удалить", systemImage: "trash", role: .destructive) { deleting = subscription }.disabled(tunnel.running)
                                } label: { Image(systemName: "ellipsis").padding(8) }
                            }
                        }
                        if let usage = subscription.usage {
                            if let total = usage.total, total > 0 {
                                ProgressView(value: min(1, (Double(usage.upload) + Double(usage.download)) / Double(total))).tint(Design.accent)
                                Text("\(formattedBytes(usage.traffic)) из \(formattedBytes(total))").font(.caption).foregroundStyle(.secondary)
                            }
                            if let expires = usage.expires { Text("до \(expires.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary) }
                        }
                    }.cardStyle()
                }
                Button { Task { await store.refreshAll() } } label: { Label("обновить все", systemImage: "arrow.clockwise").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered).disabled(store.state.subscriptions.isEmpty || !store.refreshing.isEmpty)
                VStack(spacing: 16) {
                    Toggle("автообновление", isOn: Binding(get: { store.state.settings.autoRefresh }, set: { value in store.settings { $0.autoRefresh = value } }))
                    Picker("интервал", selection: Binding(get: { store.state.settings.refreshHours }, set: { value in store.settings { $0.refreshHours = value } })) {
                        Text("каждый час").tag(1); Text("каждые 6 часов").tag(6); Text("каждые 24 часа").tag(24)
                    }
                }.cardStyle()
                Text("автообновление выполняется при открытии приложения. iос ограничивает выполнение приложений в фоне.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }.padding(20)
        }.pageBackground().navigationTitle("подписки")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { destination = .subscription } label: { Image(systemName: "plus") } } }
        .sheet(item: $destination) { ImportView(mode: $0) }
        .alert("удалить подписку?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("удалить", role: .destructive) { if let deleting { store.removeSubscription(deleting.id) }; deleting = nil }
            Button("отмена", role: .cancel) { deleting = nil }
        } message: { Text("все серверы этой подписки будут удалены") }
    }
}
