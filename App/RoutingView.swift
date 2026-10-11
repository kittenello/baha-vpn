import SwiftUI
import BahaCore

struct RoutingView: View {
    @EnvironmentObject var store: ClientStore
    @State private var adding = false
    var body: some View {
        List {
            Section {
                Toggle("локальная сеть напрямую", isOn: Binding(get: { store.state.settings.bypassLAN ?? false }, set: { value in store.settings { $0.bypassLAN = value } }))
                Picker("разрешение доменов", selection: Binding(get: { store.state.settings.domainStrategy ?? "profile" }, set: { value in store.settings { $0.domainStrategy = value == "profile" ? nil : value } })) {
                    Text("из профиля").tag("profile"); Text("по домену").tag("AsIs")
                    Text("ip при отсутствии совпадений").tag("IPIfNonMatch"); Text("ip для правил").tag("IPOnDemand")
                }
            }
            Section {
                ForEach(store.state.settings.routingRules ?? []) { rule in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack { Text(kind(rule.kind)).font(.headline); Spacer(); Text(action(rule.action)).foregroundStyle(Design.accent) }
                        Text(rule.patterns.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    }
                }
                .onDelete { offsets in store.settings { $0.routingRules?.remove(atOffsets: offsets) } }
                .onMove { source, destination in store.settings { $0.routingRules?.move(fromOffsets: source, toOffset: destination) } }
                Button("добавить правило") { adding = true }
            } header: { Text("правила приложения") } footer: {
                Text("порядок важен. эти правила применяются перед правилами импортированного json. исходные dns, balancers и правила xray сохраняются. изменения применяются при следующем подключении.")
            }
        }.scrollContentBackground(.hidden).pageBackground().navigationTitle("маршрутизация")
        .toolbar { EditButton() }
        .sheet(isPresented: $adding) { AddTrafficRuleView() }
    }
    private func kind(_ value: TrafficRule.Kind) -> String { [.domain: "домены", .ip: "ip и подсети", .port: "порты", .protocolName: "протоколы"][value]! }
    private func action(_ value: TrafficRule.Action) -> String { [.proxy: "через впн", .direct: "напрямую", .block: "блокировка"][value]! }
}

struct AddTrafficRuleView: View {
    @EnvironmentObject var store: ClientStore
    @Environment(\.dismiss) var dismiss
    @State private var kind = TrafficRule.Kind.domain
    @State private var action = TrafficRule.Action.proxy
    @State private var text = ""
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Picker("тип", selection: $kind) {
                    Text("домены").tag(TrafficRule.Kind.domain); Text("ip и подсети").tag(TrafficRule.Kind.ip)
                    Text("порты").tag(TrafficRule.Kind.port); Text("протоколы").tag(TrafficRule.Kind.protocolName)
                }
                Picker("действие", selection: $action) {
                    Text("через впн").tag(TrafficRule.Action.proxy); Text("напрямую").tag(TrafficRule.Action.direct); Text("блокировка").tag(TrafficRule.Action.block)
                }
                Section {
                    TextEditor(text: $text).frame(minHeight: 120).autocorrectionDisabled().textInputAutocapitalization(.never)
                } header: { Text("значения через запятую или с новой строки") } footer: {
                    Text("домены: example.com, full:example.org, geosite:category-ads-all. ip: 10.0.0.0/8, geoip:private. порты: 443, 8000-9000. протоколы: http, tls, bittorrent.")
                }
                if let error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("новое правило").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("сохранить") {
                        let patterns = text.components(separatedBy: CharacterSet(charactersIn: ",\n")).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                        let rule = TrafficRule(kind: kind, action: action, patterns: patterns)
                        do { _ = try rule.xray(proxyTag: "proxy"); store.settings { if $0.routingRules == nil { $0.routingRules = [] }; $0.routingRules?.append(rule) }; dismiss() }
                        catch { self.error = error.localizedDescription }
                    }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
