import Foundation
import Network

/// Measures TCP handshake latency only; this does not authenticate a proxy or assert VPN availability.
final class LatencyProbe: @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "baha.latency")
    private var finished = false
    private init(host: String, port: Int) {
        connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: UInt16(port))!, using: .tcp)
    }
    static func measure(host: String, port: Int) async -> Int? {
        let probe = LatencyProbe(host: host, port: port)
        return await probe.run()
    }
    private func run() async -> Int? {
        await withCheckedContinuation { continuation in
            let start = DispatchTime.now().uptimeNanoseconds
            let finish: (Int?) -> Void = { value in
                guard !self.finished else { return }
                self.finished = true
                self.connection.stateUpdateHandler = nil
                self.connection.cancel()
                continuation.resume(returning: value)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: finish(Int((DispatchTime.now().uptimeNanoseconds - start) / 1_000_000))
                case .failed, .cancelled: finish(nil)
                default: break
                }
            }
            queue.asyncAfter(deadline: .now() + 4) { finish(nil) }
            connection.start(queue: queue)
        }
    }
}
