import Foundation

extension ImportParser {
    public static func jsonProfiles(_ text: String) throws -> [ServerProfile] {
        guard let data = text.data(using: .utf8) else { throw ClientError.invalid("некорректный json") }
        let object: Any
        do { object = try JSONSerialization.jsonObject(with: data) }
        catch { throw ClientError.invalid("некорректный json; нужен объект xray или массив конфигураций") }
        let list: [Any]
        if let array = object as? [Any] { list = array }
        else if let dictionary = object as? [String: Any], let configs = dictionary["configs"] as? [Any] { list = configs }
        else { list = [object] }
        guard !list.isEmpty, list.count <= 2000 else { throw ClientError.invalid("пустой json или больше 2000 профилей") }
        return try list.enumerated().map { index, value in
            guard let dictionary = value as? [String: Any] else { throw ClientError.invalid("элемент json \(index + 1) должен быть объектом") }
            var config = dictionary
            if dictionary["protocol"] is String { config = ["outbounds": [dictionary]] }
            guard let outbounds = config["outbounds"] as? [[String: Any]], !outbounds.isEmpty else {
                throw ClientError.invalid("в json отсутствует список outbounds xray")
            }
            guard outbounds.allSatisfy({ $0["protocol"] is String }) else {
                throw ClientError.invalid("это не xray json; формат sing-box/clash требует конвертации")
            }
            let first = outbounds.first { !["freedom", "blackhole", "dns"].contains($0["protocol"] as? String ?? "") } ?? outbounds[0]
            let endpoint = jsonEndpoint(first)
            let name = ["remarks", "remark", "name", "ps"].compactMap { config[$0] as? String }.first
                ?? first["tag"] as? String ?? (endpoint.0.isEmpty ? "json профиль \(index + 1)" : endpoint.0)
            let json = try JSONSerialization.data(withJSONObject: config, options: .sortedKeys)
            return ServerProfile(name: name, link: String(decoding: json, as: UTF8.self), host: endpoint.0,
                                 port: endpoint.1, protocolName: "json", transport: "raw json", security: "config")
        }
    }

    static func jsonEndpoint(_ outbound: [String: Any]) -> (String, Int) {
        let settings = outbound["settings"] as? [String: Any] ?? [:]
        if let server = ((settings["vnext"] ?? settings["servers"]) as? [[String: Any]])?.first {
            return (server["address"] as? String ?? "", Int(String(describing: server["port"] ?? "0")) ?? 0)
        }
        if let address = settings["address"] as? String { return (address, Int(String(describing: settings["port"] ?? "0")) ?? 0) }
        if let endpoint = (settings["peers"] as? [[String: Any]])?.first?["endpoint"] as? String,
           let parts = URLComponents(string: "udp://" + endpoint) { return (host(parts), parts.port ?? 0) }
        return ("", 0)
    }

    static func host(_ parts: URLComponents) -> String { (parts.host ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "[]")) }
    static func endpoint(_ parts: URLComponents, defaultPort: Int? = nil) throws -> (String, Int) {
        let hostname = host(parts)
        guard !hostname.isEmpty, !hostname.contains(where: \.isWhitespace),
              let port = parts.port ?? defaultPort, (1...65535).contains(port) else { throw ClientError.invalid("некорректный адрес или порт сервера") }
        return (hostname, port)
    }

    static func trojan(_ link: String) throws -> ServerProfile {
        guard let parts = URLComponents(string: link), let password = parts.user, !password.isEmpty else { throw ClientError.invalid("в trojan отсутствует пароль") }
        let (hostname, port) = try endpoint(parts, defaultPort: 443)
        let q = try parameters(parts)
        let transport = q["type"] ?? "tcp", security = q["security"] ?? "tls"
        guard ["tcp", "raw", "ws", "grpc", "xhttp", "httpupgrade"].contains(transport), ["tls", "reality", "none"].contains(security) else { throw ClientError.invalid("неизвестный транспорт trojan") }
        guard !["1", "true"].contains(q["allowInsecure"] ?? "") else { throw ClientError.invalid("небезопасный tls не поддерживается") }
        if security == "reality", decodeBase64(q["pbk"] ?? "")?.count != 32 { throw ClientError.invalid("некорректный ключ reality") }
        return ServerProfile(name: parts.fragment ?? hostname, link: link, host: hostname, port: port,
                             protocolName: "trojan", transport: transport, security: security)
    }

    public static func shadowsocksParts(_ link: String) throws -> (URLComponents, String, String) {
        var normalized = link
        let remainder = String(link.dropFirst(5))
        if !remainder.contains("@") {
            let pieces = remainder.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
            guard let data = decodeBase64(String(pieces[0])), let clear = String(data: data, encoding: .utf8) else { throw ClientError.invalid("некорректная ss-ссылка") }
            normalized = "ss://" + clear + (pieces.count == 2 ? "#" + pieces[1] : "")
        }
        guard let parts = URLComponents(string: normalized), let username = parts.user else { throw ClientError.invalid("некорректная ss-ссылка") }
        let credentials: String
        if let password = parts.password { credentials = username + ":" + password }
        else if let data = decodeBase64(username), let string = String(data: data, encoding: .utf8) { credentials = string }
        else { throw ClientError.invalid("некорректный пароль shadowsocks") }
        let pieces = credentials.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let methods = ["aes-128-gcm", "aes-256-gcm", "chacha20-ietf-poly1305", "chacha20-poly1305", "xchacha20-ietf-poly1305",
                       "2022-blake3-aes-128-gcm", "2022-blake3-aes-256-gcm", "2022-blake3-chacha20-poly1305"]
        guard pieces.count == 2, methods.contains(String(pieces[0])), !pieces[1].isEmpty else { throw ClientError.invalid("неподдерживаемый шифр или пустой пароль shadowsocks") }
        if let plugin = try parameters(parts)["plugin"], !plugin.isEmpty { throw ClientError.invalid("плагины sip003 не поддерживаются xray; нужен профиль без plugin") }
        return (parts, String(pieces[0]), String(pieces[1]))
    }

    static func shadowsocks(_ link: String) throws -> ServerProfile {
        let (parts, _, _) = try shadowsocksParts(link)
        let (hostname, port) = try endpoint(parts)
        return ServerProfile(name: parts.fragment ?? hostname, link: link, host: hostname, port: port,
                             protocolName: "shadowsocks", transport: "tcp/udp", security: "aead")
    }

    static func hysteria2(_ link: String) throws -> ServerProfile {
        guard let parts = URLComponents(string: link) else { throw ClientError.invalid("некорректная hysteria2-ссылка") }
        let (hostname, port) = try endpoint(parts, defaultPort: 443)
        let q = try parameters(parts)
        guard !["1", "true"].contains(q["insecure"] ?? q["allowInsecure"] ?? ""), q["pinSHA256"] == nil else {
            throw ClientError.invalid("ядро требует проверяемый tls; insecure и pinsha256 этой ссылки не поддерживаются")
        }
        guard ["none", "salamander"].contains(q["obfs"] ?? "none") else { throw ClientError.invalid("неизвестная маскировка hysteria2") }
        if q["obfs"] == "salamander", (q["obfs-password"] ?? "").count < 4 { throw ClientError.invalid("нужен пароль salamander минимум 4 символа") }
        return ServerProfile(name: parts.fragment ?? hostname, link: link, host: hostname, port: port,
                             protocolName: "hysteria2", transport: "quic", security: "tls")
    }

    static func validWGKey(_ key: String) -> Bool { decodeBase64(key)?.count == 32 || (key.count == 64 && key.allSatisfy(\.isHexDigit)) }
    static func wireGuardLink(_ link: String) throws -> ServerProfile {
        guard let parts = URLComponents(string: link), let key = parts.user, validWGKey(key) else { throw ClientError.invalid("некорректный приватный ключ wireguard") }
        let (hostname, port) = try endpoint(parts)
        let q = try parameters(parts)
        guard validWGKey(q["publickey"] ?? q["publicKey"] ?? "") else { throw ClientError.invalid("некорректный публичный ключ wireguard") }
        return ServerProfile(name: parts.fragment ?? hostname, link: link, host: hostname, port: port,
                             protocolName: "wireguard", transport: "udp", security: "wireguard")
    }

    static func wireGuardFile(_ text: String) throws -> ServerProfile {
        var interface: [String: String] = [:], peers: [[String: String]] = [], section = ""
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") { continue }
            if line == "[Interface]" { section = "interface"; continue }
            if line == "[Peer]" { section = "peer"; peers.append([:]); continue }
            let pair = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard pair.count == 2 else { throw ClientError.invalid("некорректная строка wireguard conf") }
            if section == "interface" { interface[pair[0]] = pair[1] }
            else if section == "peer", !peers.isEmpty { peers[peers.count - 1][pair[0]] = pair[1] }
            else { throw ClientError.invalid("неизвестная секция wireguard") }
        }
        guard let secret = interface["PrivateKey"], validWGKey(secret), !peers.isEmpty else { throw ClientError.invalid("в conf нужны privatekey и peer") }
        if ["PreUp", "PostUp", "PreDown", "PostDown"].contains(where: { interface[$0] != nil }) { throw ClientError.invalid("команды shell из wireguard conf не выполняются клиентом") }
        let mapped: [[String: Any]] = try peers.map { peer in
            guard let key = peer["PublicKey"], validWGKey(key), let endpoint = peer["Endpoint"],
                  let parts = URLComponents(string: "udp://" + endpoint) else { throw ClientError.invalid("в peer нужны корректные publickey и endpoint") }
            _ = try self.endpoint(parts)
            var result: [String: Any] = ["publicKey": key, "endpoint": endpoint]
            if let key = peer["PresharedKey"] { guard validWGKey(key) else { throw ClientError.invalid("неверный presharedkey") }; result["preSharedKey"] = key }
            if let allowed = peer["AllowedIPs"] { result["allowedIPs"] = csv(allowed) }
            if let keepAlive = peer["PersistentKeepalive"], let value = Int(keepAlive), value >= 0 { result["keepAlive"] = value }
            return result
        }
        var settings: [String: Any] = ["secretKey": secret, "peers": mapped, "noKernelTun": true]
        if let addresses = interface["Address"] { settings["address"] = csv(addresses) }
        if let mtu = interface["MTU"], let value = Int(mtu), (1280...9000).contains(value) { settings["mtu"] = value }
        var config: [String: Any] = ["remarks": "wireguard", "outbounds": [["protocol": "wireguard", "tag": "proxy", "settings": settings]]]
        if let dns = interface["DNS"] { config["dns"] = ["servers": csv(dns)] }
        let json = try JSONSerialization.data(withJSONObject: config, options: .sortedKeys)
        return try jsonProfiles(String(decoding: json, as: UTF8.self))[0]
    }

    static func csv(_ text: String) -> [String] { text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
}
