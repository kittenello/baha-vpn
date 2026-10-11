import Foundation
import NetworkExtension
import Combine
import BahaCore

@MainActor final class TunnelController: ObservableObject {
    @Published private(set) var status: NEVPNStatus = .invalid
    @Published private(set) var busy = false
    @Published private(set) var sent: Int64 = 0
    @Published private(set) var received: Int64 = 0
    @Published private(set) var activeName = ""
    @Published var error: String?
    private var manager: NETunnelProviderManager?
    private var observer: AnyCancellable?
    private var polling: Task<Void, Never>?
    private let providerID = (Bundle.main.bundleIdentifier ?? "com.kittenello.bahavpn") + ".tunnel"

    var running: Bool { [.connected, .connecting, .reasserting, .disconnecting].contains(status) }
    var connectedAt: Date? { manager?.connection.connectedDate }
    var title: String {
        switch status {
        case .connected: return "подключено"
        case .connecting: return "подключение"
        case .reasserting: return "переподключение"
        case .disconnecting: return "отключение"
        default: return "не подключено"
        }
    }

    init() {
        guard !ProcessInfo.processInfo.arguments.contains("--preview-data"),
              !ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return }
        busy = true
        observer = NotificationCenter.default.publisher(for: .NEVPNStatusDidChange)
            .receive(on: DispatchQueue.main).sink { [weak self] _ in self?.updateStatus() }
        Task { await load() }
        polling = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.pollStats()
            }
        }
    }

    private func load() async {
        defer { busy = false }
        do {
            manager = try await NETunnelProviderManager.loadAllFromPreferences().first {
                ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == providerID
            }
            updateStatus()
        } catch { self.error = "не удалось загрузить впн: \(error.localizedDescription)" }
    }

    private func updateStatus() {
        let next = manager?.connection.status ?? .invalid
        if next == .connected && status != .connected { sent = 0; received = 0 }
        status = next
        activeName = manager?.protocolConfiguration?.serverAddress ?? ""
    }

    func toggle(profile: ServerProfile?, settings: ClientSettings) async {
        guard !busy else { return }
        if running {
            busy = true
            defer { busy = false }
            do {
                // A manual disconnect must not be immediately undone by an active on-demand rule.
                manager?.isOnDemandEnabled = false
                try await manager?.saveToPreferences()
                manager?.connection.stopVPNTunnel()
                updateStatus()
            } catch { self.error = "не удалось отключить впн: \(error.localizedDescription)" }
            return
        }
        guard !busy, let profile else { error = "сначала добавь и выбери сервер"; return }
        busy = true
        defer { busy = false }
        do {
            let json = try XrayConfiguration.make(profile: profile, dns: settings.dns)
            let selectedManager = manager ?? NETunnelProviderManager()
            let tunnel = NETunnelProviderProtocol()
            tunnel.providerBundleIdentifier = providerID
            tunnel.serverAddress = profile.name
            tunnel.providerConfiguration = ["config": json, "dns": settings.dns]
            tunnel.disconnectOnSleep = false
            tunnel.includeAllNetworks = true
            tunnel.excludeLocalNetworks = false
            selectedManager.protocolConfiguration = tunnel
            selectedManager.localizedDescription = "baha vpn"
            selectedManager.isEnabled = true
            applyOnDemand(selectedManager, enabled: settings.connectOnDemand)
            try await selectedManager.saveToPreferences()
            try await selectedManager.loadFromPreferences()
            manager = selectedManager
            try selectedManager.connection.startVPNTunnel()
            updateStatus()
        } catch { self.error = "не удалось запустить туннель: \(error.localizedDescription)"; updateStatus() }
    }

    func setOnDemand(_ enabled: Bool) async {
        guard let manager else { return } // Applied on first connection after the system VPN consent.
        do {
            applyOnDemand(manager, enabled: enabled)
            try await manager.saveToPreferences()
        } catch { self.error = "не удалось изменить автоподключение: \(error.localizedDescription)" }
    }
    private func applyOnDemand(_ manager: NETunnelProviderManager, enabled: Bool) {
        let rule = NEOnDemandRuleConnect()
        rule.interfaceTypeMatch = .any
        manager.onDemandRules = enabled ? [rule] : []
        manager.isOnDemandEnabled = enabled
    }

    private func pollStats() {
        guard status == .connected, let session = manager?.connection as? NETunnelProviderSession else { return }
        try? session.sendProviderMessage(Data("stats".utf8)) { [weak self] data in
            guard let data, let object = try? JSONDecoder().decode(TunnelStats.self, from: data) else { return }
            Task { @MainActor in self?.sent = object.sent; self?.received = object.received }
        }
    }
}

struct TunnelStats: Codable { let sent: Int64; let received: Int64 }
