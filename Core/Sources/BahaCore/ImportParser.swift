import Foundation

public enum ImportParser {
    public static let maximumBytes = 2 * 1024 * 1024

    public static func decodeBase64(_ text: String) -> Data? {
        var cleaned = text.filter { !$0.isWhitespace }.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        cleaned += String(repeating: "=", count: (4 - cleaned.count % 4) % 4)
        return Data(base64Encoded: cleaned)
    }

    public static func subscriptionURL(_ text: String) throws -> URL {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value), url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else {
            throw ClientError.invalid("нужна корректная https-ссылка подписки")
        }
        return url
    }

    public static func parse(_ text: String) throws -> [ServerProfile] {
        guard text.utf8.count <= maximumBytes else { throw ClientError.invalid("файл превышает 2 мб") }
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !body.contains("://"), let decoded = decodeBase64(body), let string = String(data: decoded, encoding: .utf8) {
            body = string
        }
        let lines = body.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        guard !lines.isEmpty, lines.count <= 2000 else { throw ClientError.invalid("пустой список или больше 2000 серверов") }
        // Fail the entire transaction instead of silently losing unsupported profiles on refresh.
        return try lines.enumerated().map { index, line in
            do { return try profile(line) }
            catch { throw ClientError.invalid("строка \(index + 1): \(error.localizedDescription)") }
        }
    }

    public static func profile(_ raw: String) throws -> ServerProfile {
        let link = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if link.lowercased().hasPrefix("vmess://") { return try vmess(link) }
        guard let parts = URLComponents(string: link), parts.scheme?.lowercased() == "vless",
              let host = parts.host, !host.isEmpty, !host.contains(where: \.isWhitespace),
              let port = parts.port, (1...65535).contains(port),
              let user = parts.user, UUID(uuidString: user) != nil, parts.password == nil else {
            throw ClientError.invalid("поддерживаются vless:// и vmess:// с корректным адресом и uuid")
        }
        let query = try parameters(parts)
        let transport = query["type"] ?? "tcp"
        let security = query["security"] ?? "none"
        guard ["tcp", "ws", "xhttp"].contains(transport) else { throw ClientError.invalid("транспорт \(transport) пока не поддерживается") }
        guard ["none", "tls", "reality"].contains(security) else { throw ClientError.invalid("неизвестная защита соединения") }
        guard query["encryption", default: "none"] == "none" else { throw ClientError.invalid("поддерживается encryption=none") }
        guard !["1", "true"].contains(query["allowInsecure", default: "0"]) else { throw ClientError.invalid("небезопасный tls не поддерживается") }
        let flow = query["flow"] ?? ""
        guard flow.isEmpty || (flow == "xtls-rprx-vision" && transport == "tcp" && security != "none") else {
            throw ClientError.invalid("vision требует tcp с tls или reality")
        }
        if security == "reality" {
            guard let key = query["pbk"], decodeBase64(key)?.count == 32 else { throw ClientError.invalid("некорректный публичный ключ reality") }
            let shortID = query["sid"] ?? ""
            guard shortID.count <= 16, shortID.count % 2 == 0, shortID.allSatisfy(\.isHexDigit) else {
                throw ClientError.invalid("некорректный short id reality")
            }
        }
        if transport == "xhttp", let mode = query["mode"], !["auto", "packet-up", "stream-up", "stream-one"].contains(mode) {
            throw ClientError.invalid("неизвестный режим xhttp")
        }
        let name = parts.fragment.flatMap { $0.isEmpty ? nil : $0 } ?? host
        return ServerProfile(name: name, link: link, host: host, port: port,
                             protocolName: "vless", transport: transport, security: security)
    }

    public static func parameters(_ parts: URLComponents) throws -> [String: String] {
        var result: [String: String] = [:]
        for item in parts.queryItems ?? [] {
            guard result[item.name] == nil else { throw ClientError.invalid("повторяющийся параметр \(item.name)") }
            result[item.name] = item.value ?? ""
        }
        return result
    }

    public static func vmessObject(_ link: String) throws -> [String: Any] {
        guard let data = decodeBase64(String(link.dropFirst(8))),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClientError.invalid("некорректная vmess-ссылка")
        }
        return object
    }

    private static func vmess(_ link: String) throws -> ServerProfile {
        let object = try vmessObject(link)
        guard let host = object["add"] as? String, !host.isEmpty, !host.contains(where: \.isWhitespace),
              let uuid = object["id"] as? String, UUID(uuidString: uuid) != nil,
              let port = Int(String(describing: object["port"] ?? "")), (1...65535).contains(port) else {
            throw ClientError.invalid("некорректный адрес, порт или uuid vmess")
        }
        let transport = object["net"] as? String ?? "tcp"
        let tls = object["tls"] as? String ?? ""
        guard ["tcp", "ws"].contains(transport), ["", "none", "tls"].contains(tls) else {
            throw ClientError.invalid("для vmess поддерживаются tcp/ws и tls")
        }
        guard Int(String(describing: object["aid"] ?? "0")) == 0 else { throw ClientError.invalid("устаревший vmess alterid не поддерживается") }
        guard (object["type"] as? String ?? "none") == "none" else { throw ClientError.invalid("маскировка vmess tcp пока не поддерживается") }
        return ServerProfile(name: (object["ps"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? host,
                             link: link, host: host, port: port, protocolName: "vmess", transport: transport,
                             security: tls == "tls" ? "tls" : "none")
    }
}
