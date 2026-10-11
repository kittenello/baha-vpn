import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: ClientStore
    @EnvironmentObject var tunnel: TunnelController
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("подключать автоматически", isOn: Binding(get: { store.state.settings.connectOnDemand }, set: { value in
                        store.settings { $0.connectOnDemand = value }
                        Task { await tunnel.setOnDemand(store.state.settings.connectOnDemand) }
                    }))
                    NavigationLink("маршрутизация") { RoutingView() }
                    Picker("dns", selection: Binding(get: { store.state.settings.dns }, set: { value in store.settings { $0.dns = value } })) {
                        Text("cloudflare · 1.1.1.1").tag("1.1.1.1")
                        Text("quad9 · 9.9.9.9").tag("9.9.9.9")
                        Text("google · 8.8.8.8").tag("8.8.8.8")
                    }
                } header: { Text("соединение") } footer: { Text("dns применяется при следующем подключении. автоподключение использует системный впн on demand после первого подключения.") }
                Section("приложение") {
                    LabeledContent("тема", value: "тёмная")
                    NavigationLink("о приложении") { about }
                }
                Section {
                    LabeledContent("серверов", value: "\(store.state.profiles.count)")
                    LabeledContent("подписок", value: "\(store.state.subscriptions.count)")
                } header: { Text("данные") } footer: { Text("профили зашифрованы aes-gcm, ключ — в keychain. при загрузке подписки провайдер получает идентификатор устройства, версию ios и тип устройства для проверки лимита. разработчику клиента профили не отправляются.") }
            }.scrollContentBackground(.hidden).pageBackground().navigationTitle("настройки")
        }
    }
    private var about: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("baha vpn").font(.largeTitle.bold())
                Text("ios-клиент для твоих серверов на базе xray-core").font(.title3)
                Text("прототип 0.2.0").foregroundStyle(.secondary)
                Text("vless, vmess, trojan, shadowsocks, hysteria2, wireguard; reality, vision, grpc, xhttp; json, подписки и qr. подключение выполняется системным расширением network extension.")
                Text("полный официальный xray-core 26.9.30, собранный из закреплённых исходников. cgo-мост передаёт пакеты между network extension и встроенным tun xray.").font(.subheadline).foregroundStyle(.secondary)
                Link("исходники клиента", destination: URL(string: "https://github.com/kittenello/baha-vpn")!)
                Link("xray-core · mpl 2.0", destination: URL(string: "https://github.com/XTLS/Xray-core")!)
            }.padding(24)
        }.navigationTitle("о приложении").pageBackground()
    }
}
