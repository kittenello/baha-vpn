import Foundation
import NetworkExtension
import SwiftyXrayKit

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private var bridge: XrayBridge?
    private let coreQueue = DispatchQueue(label: "baha.xray.lifecycle")
    private var totalSent: Int64 = 0
    private var totalReceived: Int64 = 0

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        guard let proto = protocolConfiguration as? NETunnelProviderProtocol,
              let config = proto.providerConfiguration?["config"] as? String,
              let dns = proto.providerConfiguration?["dns"] as? String else {
            completionHandler(NSError(domain: "baha.tunnel", code: 1, userInfo: [NSLocalizedDescriptionKey: "отсутствует конфигурация сервера"]))
            return
        }
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        settings.mtu = 1360
        let ipv4 = NEIPv4Settings(addresses: ["198.18.0.1"], subnetMasks: ["255.255.255.0"])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4
        let ipv6 = NEIPv6Settings(addresses: ["fd12:3456:789a::1"], networkPrefixLengths: [64])
        ipv6.includedRoutes = [NEIPv6Route.default()]
        settings.ipv6Settings = ipv6
        let resolver = NEDNSSettings(servers: [dns])
        resolver.matchDomains = [""]
        settings.dnsSettings = resolver

        setTunnelNetworkSettings(settings) { [weak self] error in
            guard let self else { completionHandler(NSError(domain: "baha.tunnel", code: 2)); return }
            if let error { completionHandler(error); return }
            self.coreQueue.async {
                let bridge = XrayBridge(packetFlow: self.packetFlow)
                do {
                    let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    let configPath = directory.appendingPathComponent("active-xray.json")
                    try bridge.start(config: .json(config), dataDir: directory, finalConfigPath: configPath, preset: .mobile)
                    // The core has consumed the configuration. Do not keep credentials in a plaintext file.
                    try? FileManager.default.removeItem(at: configPath)
                    self.bridge = bridge
                    self.totalSent = 0; self.totalReceived = 0
                    completionHandler(nil)
                } catch {
                    bridge.stop()
                    // The upstream error may embed the config; only surface a neutral message.
                    completionHandler(NSError(domain: "baha.tunnel", code: 3, userInfo: [NSLocalizedDescriptionKey: "xray не запустился; проверь параметры профиля"]))
                }
            }
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        coreQueue.async {
            self.bridge?.stop(); self.bridge = nil
            completionHandler()
        }
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        guard String(data: messageData, encoding: .utf8) == "stats" else { completionHandler?(nil); return }
        coreQueue.async {
            if let stats = self.bridge?.getAndClearStats() {
                self.totalSent += stats.sent; self.totalReceived += stats.received
            }
            completionHandler?(try? JSONSerialization.data(withJSONObject: ["sent": self.totalSent, "received": self.totalReceived]))
        }
    }
}
