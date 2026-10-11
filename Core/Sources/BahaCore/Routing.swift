import Foundation

public struct TrafficRule: Codable, Identifiable, Equatable {
    public enum Kind: String, Codable, CaseIterable, Hashable { case domain, ip, port, protocolName }
    public enum Action: String, Codable, CaseIterable, Hashable { case proxy, direct, block }
    public var id = UUID()
    public var kind: Kind
    public var action: Action
    public var patterns: [String]
    public init(kind: Kind, action: Action, patterns: [String]) { self.kind = kind; self.action = action; self.patterns = patterns }

    public func xray(proxyTag: String) throws -> [String: Any] {
        guard !patterns.isEmpty, patterns.count <= 2000, patterns.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw ClientError.invalid("правило должно содержать от 1 до 2000 значений")
        }
        let tag = action == .proxy ? proxyTag : (action == .direct ? "baha-direct" : "baha-block")
        var rule: [String: Any] = ["type": "field", "outboundTag": tag]
        switch kind {
        case .domain:
            for pattern in patterns where pattern.hasPrefix("regexp:") { _ = try NSRegularExpression(pattern: String(pattern.dropFirst(7))) }
            rule["domain"] = patterns.map { value in
                ["domain:", "full:", "regexp:", "geosite:", "keyword:"].contains(where: value.hasPrefix) ? value : "domain:" + value
            }
        case .ip: rule["ip"] = patterns
        case .port:
            guard patterns.allSatisfy({ pattern in
                let parts = pattern.split(separator: "-", omittingEmptySubsequences: false)
                guard (1...2).contains(parts.count), let start = Int(parts[0]), (1...65535).contains(start) else { return false }
                if parts.count == 2 { guard let end = Int(parts[1]), end >= start && end <= 65535 else { return false } }
                return true
            }) else { throw ClientError.invalid("нужны порты 1–65535 или диапазоны, например 8000-9000") }
            rule["port"] = patterns.joined(separator: ",")
        case .protocolName:
            guard patterns.allSatisfy({ ["http", "tls", "bittorrent"].contains($0) }) else { throw ClientError.invalid("поддерживаются http, tls и bittorrent") }
            rule["protocol"] = patterns
        }
        return rule
    }
}
