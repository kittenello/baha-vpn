import Foundation

extension XrayConfiguration {
    static func extendedOutbound(_ profile: ServerProfile) throws -> [String: Any] {
        if profile.protocolName == "shadowsocks" {
            let (_, method, password) = try ImportParser.shadowsocksParts(profile.link)
            return ["tag": "proxy", "protocol": "shadowsocks", "settings": ["servers": [["address": profile.host, "port": profile.port, "method": method, "password": password]]]]
        }
        guard let parts = URLComponents(string: profile.link) else { throw ClientError.invalid("некорректная ссылка") }
        let q = try ImportParser.parameters(parts)
        if profile.protocolName == "wireguard" {
            let endpoint = (profile.host.contains(":") ? "[\(profile.host)]" : profile.host) + ":\(profile.port)"
            var peer: [String: Any] = ["publicKey": q["publickey"] ?? q["publicKey"]!, "endpoint": endpoint,
                                       "allowedIPs": ImportParser.csv(q["allowedIPs"] ?? "0.0.0.0/0,::/0")]
            if let key = q["presharedkey"] ?? q["preSharedKey"] {
                guard ImportParser.validWGKey(key) else { throw ClientError.invalid("неверный presharedkey wireguard") }
                peer["preSharedKey"] = key
            }
            var settings: [String: Any] = ["secretKey": parts.user!, "peers": [peer], "noKernelTun": true]
            if let address = q["address"] { settings["address"] = ImportParser.csv(address) }
            if let text = q["mtu"] {
                guard let mtu = Int(text), (1280...9000).contains(mtu) else { throw ClientError.invalid("неверный mtu wireguard") }
                settings["mtu"] = mtu
            }
            if let reserved = q["reserved"] {
                let values = ImportParser.csv(reserved).compactMap(UInt8.init)
                guard values.count == 3 else { throw ClientError.invalid("reserved должен содержать 3 байта") }
                settings["reserved"] = Data(values).base64EncodedString()
            }
            return ["tag": "proxy", "protocol": "wireguard", "settings": settings]
        }
        if profile.protocolName == "hysteria2" {
            let auth = (parts.user ?? "") + (parts.password.map { ":" + $0 } ?? "")
            var stream: [String: Any] = ["network": "hysteria", "security": "tls",
                "tlsSettings": ["serverName": q["sni"] ?? profile.host, "alpn": ["h3"]],
                "hysteriaSettings": ["version": 2, "auth": auth]]
            var mask: [String: Any] = [:], udp: [[String: Any]] = []
            if q["obfs"] == "salamander" { udp.append(["type": "salamander", "settings": ["password": q["obfs-password"]!]]) }
            if let ports = q["mport"] ?? q["ports"] {
                let interval = Int(q["hop-interval"] ?? "30") ?? 0
                guard interval >= 5, interval <= 3600 else { throw ClientError.invalid("интервал смены портов должен быть 5–3600 секунд") }
                for range in ImportParser.csv(ports) {
                    let values = range.split(separator: "-", omittingEmptySubsequences: false).compactMap { Int($0) }
                    guard !values.isEmpty, values.count <= 2, values.allSatisfy({ (1...65535).contains($0) }), values.first! <= values.last! else { throw ClientError.invalid("неверный диапазон портов hysteria2") }
                }
                udp.append(["type": "udphop", "settings": ["mode": "intervalLocal,intervalRemote", "remotePorts": ports, "interval": interval]])
            }
            if !udp.isEmpty { mask["udp"] = udp }
            if q["up"] != nil || q["down"] != nil {
                func bandwidth(_ text: String?) -> String {
                    guard let text else { return "" }
                    return Double(text) != nil ? text + "mbps" : text
                }
                mask["quicParams"] = ["congestion": "brutal", "brutalUp": bandwidth(q["up"]), "brutalDown": bandwidth(q["down"])]
            }
            if !mask.isEmpty { stream["finalmask"] = mask }
            return ["tag": "proxy", "protocol": "hysteria", "settings": ["version": 2, "address": profile.host, "port": profile.port], "streamSettings": stream]
        }
        var stream: [String: Any] = ["network": profile.transport, "security": profile.security]
        if profile.security == "tls" {
            var tls: [String: Any] = ["serverName": q["sni"] ?? profile.host, "fingerprint": q["fp"] ?? "chrome"]
            if let alpn = q["alpn"] { tls["alpn"] = ImportParser.csv(alpn) }
            stream["tlsSettings"] = tls
        } else if profile.security == "reality" {
            stream["realitySettings"] = ["serverName": q["sni"] ?? profile.host, "fingerprint": q["fp"] ?? "chrome", "publicKey": q["pbk"]!, "shortId": q["sid"] ?? ""]
        }
        if profile.transport == "ws" { stream["wsSettings"] = ["path": q["path"] ?? "/", "headers": ["Host": q["host"] ?? profile.host]] }
        if profile.transport == "grpc" { stream["grpcSettings"] = ["serviceName": q["serviceName"] ?? "", "multiMode": q["mode"] == "multi", "authority": q["authority"] ?? ""] }
        if profile.transport == "httpupgrade" { stream["httpupgradeSettings"] = ["host": q["host"] ?? profile.host, "path": q["path"] ?? "/"] }
        if profile.transport == "xhttp" { stream["xhttpSettings"] = ["host": q["host"] ?? profile.host, "path": q["path"] ?? "/", "mode": q["mode"] ?? "auto"] }
        let password = (parts.user ?? "") + (parts.password.map { ":" + $0 } ?? "")
        return ["tag": "proxy", "protocol": "trojan", "settings": ["servers": [["address": profile.host, "port": profile.port, "password": password]]], "streamSettings": stream]
    }

    static func finish(_ original: [String: Any], dns: String, rules: [TrafficRule], bypassLAN: Bool, domainStrategy: String?) throws -> String {
        var config = original
        guard var outbounds = config["outbounds"] as? [[String: Any]], !outbounds.isEmpty else { throw ClientError.invalid("нет outbounds") }
        // iOS cannot open a kernel WireGuard interface inside the packet tunnel sandbox.
        for index in outbounds.indices where outbounds[index]["protocol"] as? String == "wireguard" {
            var settings = outbounds[index]["settings"] as? [String: Any] ?? [:]
            settings["noKernelTun"] = true; outbounds[index]["settings"] = settings
        }
        var routing = config["routing"] as? [String: Any] ?? ["domainStrategy": "AsIs"]
        if let strategy = domainStrategy {
            guard ["AsIs", "IPIfNonMatch", "IPOnDemand"].contains(strategy) else { throw ClientError.invalid("неверная стратегия маршрутизации") }
            routing["domainStrategy"] = strategy
        }
        if !rules.isEmpty || bypassLAN {
            let proxyIndex = outbounds.firstIndex { !["freedom", "blackhole", "dns"].contains($0["protocol"] as? String ?? "") } ?? 0
            let proxyTag = outbounds[proxyIndex]["tag"] as? String ?? "baha-proxy"
            outbounds[proxyIndex]["tag"] = proxyTag
            guard !outbounds.contains(where: { ["baha-direct", "baha-block"].contains($0["tag"] as? String ?? "") }) else { throw ClientError.invalid("в json заняты служебные теги baha-direct/baha-block") }
            outbounds.append(["tag": "baha-direct", "protocol": "freedom", "settings": [:]])
            outbounds.append(["tag": "baha-block", "protocol": "blackhole", "settings": [:]])
            var generated = try rules.map { try $0.xray(proxyTag: proxyTag) }
            if bypassLAN {
                generated.insert(["type": "field", "ip": ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "127.0.0.0/8", "169.254.0.0/16", "::1/128", "fc00::/7", "fe80::/10"], "outboundTag": "baha-direct"], at: 0)
            }
            routing["rules"] = generated + (routing["rules"] as? [[String: Any]] ?? [])
        }
        config["outbounds"] = outbounds
        config["routing"] = routing
        if config["dns"] == nil { config["dns"] = ["servers": [dns]] }
        config["log"] = ["loglevel": "none"]
        let data = try JSONSerialization.data(withJSONObject: config, options: .sortedKeys)
        return String(decoding: data, as: UTF8.self)
    }
}
