import Foundation

public struct ServerProfile: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var name: String
    public var link: String
    public var host: String
    public var port: Int
    public var protocolName: String
    public var transport: String
    public var security: String
    public var subscriptionID: UUID?
    public var isFavorite = false

    public init(name: String, link: String, host: String, port: Int,
                protocolName: String, transport: String, security: String) {
        self.name = name; self.link = link; self.host = host; self.port = port
        self.protocolName = protocolName; self.transport = transport; self.security = security
    }

    public var detail: String { "\(protocolName) · \(security == "none" ? transport : security)" }
    public var identity: String {
        if protocolName == "vmess", let data = ImportParser.decodeBase64(String(link.dropFirst(8))),
           var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            object.removeValue(forKey: "ps")
            if let canonical = try? JSONSerialization.data(withJSONObject: object, options: .sortedKeys) {
                return canonical.base64EncodedString()
            }
        }
        var parts = URLComponents(string: link)
        parts?.fragment = nil
        parts?.queryItems = parts?.queryItems?.sorted { ($0.name, $0.value ?? "") < ($1.name, $1.value ?? "") }
        return parts?.string ?? link
    }
}

public struct ServerSubscription: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var name: String
    public var url: URL
    public var updatedAt: Date?
    public var usage: SubscriptionUsage?
    public init(name: String, url: URL) { self.name = name; self.url = url }
}

public struct SubscriptionUsage: Codable, Equatable {
    public var upload: Int64 = 0
    public var download: Int64 = 0
    public var total: Int64?
    public var expires: Date?
    public var traffic: Int64 {
        let sum = upload.addingReportingOverflow(download)
        return sum.overflow ? Int64.max : sum.partialValue
    }
    public init(header: String) {
        for part in header.split(separator: ";") {
            let fields = part.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard fields.count == 2, let value = Int64(fields[1]), value >= 0 else { continue }
            switch fields[0] {
            case "upload": upload = value
            case "download": download = value
            case "total": total = value > 0 ? value : nil
            case "expire": expires = value > 0 ? Date(timeIntervalSince1970: Double(value)) : nil
            default: break
            }
        }
    }
}

public struct ClientSettings: Codable, Equatable {
    public var autoRefresh = true
    public var refreshHours = 6
    public var connectOnDemand = false
    public var dns = "1.1.1.1"
    public init() {}
}

public struct ClientState: Codable, Equatable {
    public var profiles: [ServerProfile] = []
    public var subscriptions: [ServerSubscription] = []
    public var selectedID: UUID?
    public var settings = ClientSettings()
    public init() {}

    public mutating func add(_ incoming: [ServerProfile]) -> Int {
        var identities = Set(profiles.filter { $0.subscriptionID == nil }.map(\.identity))
        var added = 0
        for profile in incoming where identities.insert(profile.identity).inserted {
            profiles.append(profile); added += 1
        }
        repairSelection()
        return added
    }

    /// A validated refresh is replaced atomically; stable profiles keep identity and favorites.
    public mutating func replace(subscriptionID: UUID, profiles incoming: [ServerProfile],
                                 usage: SubscriptionUsage?, at date: Date = Date()) {
        let previous = profiles.filter { $0.subscriptionID == subscriptionID }
        var seen = Set<String>()
        let replacements = incoming.compactMap { profile -> ServerProfile? in
            guard seen.insert(profile.identity).inserted else { return nil }
            var result = profile
            result.subscriptionID = subscriptionID
            if let old = previous.first(where: { $0.identity == profile.identity }) {
                result.id = old.id; result.isFavorite = old.isFavorite
            }
            return result
        }
        profiles.removeAll { $0.subscriptionID == subscriptionID }
        profiles.append(contentsOf: replacements)
        if let index = subscriptions.firstIndex(where: { $0.id == subscriptionID }) {
            subscriptions[index].updatedAt = date; subscriptions[index].usage = usage
        }
        repairSelection()
    }

    public mutating func removeSubscription(_ id: UUID) {
        subscriptions.removeAll { $0.id == id }
        profiles.removeAll { $0.subscriptionID == id }
        repairSelection()
    }

    public mutating func repairSelection() {
        if !profiles.contains(where: { $0.id == selectedID }) { selectedID = profiles.first?.id }
    }
}

public enum ClientError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}
