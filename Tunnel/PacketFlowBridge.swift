import Foundation
import NetworkExtension
import Darwin
import XrayNative

/// Datagrams retain packet boundaries and match the official Darwin TUN's 4-byte AF header.
/// Each extension loads exactly one Go runtime; no private packetFlow.fileDescriptor API is used.
final class PacketFlowBridge {
    private let flow: NEPacketTunnelFlow
    private let queue = DispatchQueue(label: "baha.packet.flow")
    private var source: DispatchSourceRead?
    private var descriptors: [Int32] = [-1, -1]
    private var running = false
    private let lock = NSLock()
    private var sent: Int64 = 0
    private var received: Int64 = 0
    var failure: ((Error) -> Void)?

    init(flow: NEPacketTunnelFlow) { self.flow = flow }

    func start(json: String, assets: String) throws {
        guard socketpair(AF_UNIX, SOCK_DGRAM, 0, &descriptors) == 0 else { throw bridgeError() }
        let coreFD = descriptors[0], swiftFD = descriptors[1]
        var buffer: Int32 = 256 * 1024
        _ = setsockopt(swiftFD, SOL_SOCKET, SO_RCVBUF, &buffer, socklen_t(MemoryLayout<Int32>.size))
        _ = setsockopt(swiftFD, SOL_SOCKET, SO_SNDBUF, &buffer, socklen_t(MemoryLayout<Int32>.size))
        guard fcntl(swiftFD, F_SETFL, fcntl(swiftFD, F_GETFL) | O_NONBLOCK) == 0 else { closeDescriptors(); throw bridgeError() }
        // Replace listener inbounds with one system packet-flow TUN. Preserve its original tag/sniffing.
        var config = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        let originals = config["inbounds"] as? [[String: Any]] ?? []
        let originalTag = originals.first?["tag"] as? String ?? "baha-tun"
        let originalTags = Set(originals.compactMap { $0["tag"] as? String })
        var routing = config["routing"] as? [String: Any] ?? [:]
        if var rules = routing["rules"] as? [[String: Any]] {
            for index in rules.indices {
                if let tags = rules[index]["inboundTag"] as? [String], !originalTags.isDisjoint(with: tags) {
                    rules[index]["inboundTag"] = [originalTag]
                }
            }
            routing["rules"] = rules; config["routing"] = routing
        }
        config["inbounds"] = [["protocol": "tun", "tag": originalTag,
            "settings": ["name": "utun", "MTU": 1360],
            "sniffing": originals.first?["sniffing"] ?? ["enabled": true, "destOverride": ["http", "tls", "quic"], "routeOnly": true]]]
        let serialized = try JSONSerialization.data(withJSONObject: config, options: .sortedKeys)
        let configText = String(decoding: serialized, as: UTF8.self)
        let result = configText.withCString { text in assets.withCString { directory in BahaStart(UnsafeMutablePointer(mutating: text), coreFD, UnsafeMutablePointer(mutating: directory)) } }
        guard result == 0 else { BahaStop(); closeDescriptors(); throw bridgeError() }
        queue.sync {
            running = true
            let reader = DispatchSource.makeReadSource(fileDescriptor: swiftFD, queue: queue)
            reader.setEventHandler { [weak self] in self?.drain(fd: swiftFD) }
            reader.setCancelHandler { Darwin.close(swiftFD); Darwin.close(coreFD) }
            source = reader; reader.resume()
            readPackets(fd: swiftFD)
        }
    }

    func stop() {
        queue.sync { running = false }
        BahaStop()
        queue.sync {
            if let source { source.cancel(); self.source = nil; descriptors = [-1, -1] }
            else { closeDescriptors() }
        }
    }

    func getAndClearStats() -> (sent: Int64, received: Int64) {
        lock.lock(); defer { lock.unlock() }
        let stats = (sent, received); sent = 0; received = 0
        return stats
    }

    private func readPackets(fd: Int32) {
        guard running else { return }
        flow.readPackets { [weak self] packets, protocols in
            guard let self else { return }
            self.queue.async {
                guard self.running else { return }
                for (packet, proto) in zip(packets, protocols) {
                    var family = proto.uint32Value.bigEndian
                    var framed = withUnsafeBytes(of: &family) { Data($0) }; framed.append(packet)
                    let result = framed.withUnsafeBytes { Darwin.send(fd, $0.baseAddress, $0.count, 0) }
                    if result == framed.count {
                        self.lock.lock(); self.sent += Int64(packet.count); self.lock.unlock()
                    } else if result < 0 && errno != EAGAIN && errno != ENOBUFS && errno != EINTR {
                        self.reportFailure(); return
                    }
                }
                self.readPackets(fd: fd)
            }
        }
    }

    private func drain(fd: Int32) {
        guard running else { return }
        var buffer = [UInt8](repeating: 0, count: 65540)
        while running {
            let count = buffer.withUnsafeMutableBytes { Darwin.recv(fd, $0.baseAddress, $0.count, 0) }
            if count < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK { return }
                if errno == EINTR { continue }
                reportFailure(); return
            }
            guard count > 4 else { continue }
            let version = buffer[4] >> 4
            guard version == 4 || version == 6 else { continue }
            let packet = Data(buffer[4..<count])
            let proto = NSNumber(value: version == 4 ? AF_INET : AF_INET6)
            if flow.writePackets([packet], withProtocols: [proto]) {
                lock.lock(); received += Int64(packet.count); lock.unlock()
            }
        }
    }
    private func reportFailure() { running = false; failure?(bridgeError()) }
    private func bridgeError() -> NSError { NSError(domain: "baha.xray", code: 1, userInfo: [NSLocalizedDescriptionKey: "xray не запустился или завершил соединение; проверь профиль"]) }
    private func closeDescriptors() {
        for descriptor in descriptors where descriptor >= 0 { Darwin.close(descriptor) }
        descriptors = [-1, -1]
    }
}
