import Foundation

public enum XrayConfiguration {
    public static func make(profile: ServerProfile, dns: String, rules: [TrafficRule] = [], bypassLAN: Bool = false, domainStrategy: String? = nil) throws -> String {
        let checked = try ImportParser.profile(profile.link)
        guard ["1.1.1.1", "9.9.9.9", "8.8.8.8"].contains(dns) else { throw ClientError.invalid("неподдерживаемый dns") }
        if checked.protocolName == "json" {
            let dictionary = try JSONSerialization.jsonObject(with: Data(checked.link.utf8)) as! [String: Any]
            return try finish(dictionary, dns: dns, rules: rules, bypassLAN: bypassLAN, domainStrategy: domainStrategy)
        }
        if !["vless", "vmess"].contains(checked.protocolName) {
            let outbound = try extendedOutbound(checked)
            return try finish(["outbounds": [outbound]], dns: dns, rules: rules, bypassLAN: bypassLAN, domainStrategy: domainStrategy)
        }
        var stream: [String: Any] = ["network": checked.transport, "security": checked.security]
        var user: [String: Any]
        if checked.protocolName == "vless" {
            let parts = URLComponents(string: profile.link)!
            let query = try ImportParser.parameters(parts)
            user = ["id": parts.user!, "encryption": "none"]
            if let flow = query["flow"], !flow.isEmpty { user["flow"] = flow }
            if checked.security == "reality" {
                stream["realitySettings"] = [
                    "serverName": query["sni"] ?? checked.host, "fingerprint": query["fp"] ?? "chrome",
                    "publicKey": query["pbk"]!, "shortId": query["sid"] ?? "", "spiderX": query["spx"] ?? "/"
                ]
            } else if checked.security == "tls" {
                var tls: [String: Any] = ["serverName": query["sni"] ?? checked.host, "fingerprint": query["fp"] ?? "chrome"]
                if let alpn = query["alpn"] { tls["alpn"] = alpn.split(separator: ",").map(String.init) }
                stream["tlsSettings"] = tls
            }
            if checked.transport == "ws" {
                stream["wsSettings"] = ["path": query["path"] ?? "/", "headers": ["Host": query["host"] ?? checked.host]]
            } else if checked.transport == "xhttp" {
                var settings: [String: Any] = ["path": query["path"] ?? "/", "host": query["host"] ?? checked.host, "mode": query["mode"] ?? "auto"]
                if let extra = query["extra"] {
                    guard let data = extra.data(using: .utf8), let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        throw ClientError.invalid("неверные дополнительные настройки xhttp")
                    }
                    settings["extra"] = json
                }
                stream["xhttpSettings"] = settings
            } else if checked.transport == "grpc" {
                stream["grpcSettings"] = ["serviceName": query["serviceName"] ?? "", "multiMode": query["mode"] == "multi", "authority": query["authority"] ?? ""]
            } else if checked.transport == "httpupgrade" {
                stream["httpupgradeSettings"] = ["host": query["host"] ?? checked.host, "path": query["path"] ?? "/"]
            }
        } else {
            let object = try ImportParser.vmessObject(profile.link)
            user = ["id": object["id"]!, "alterId": 0, "security": object["scy"] as? String ?? "auto"]
            if checked.transport == "ws" { stream["wsSettings"] = ["path": object["path"] as? String ?? "/", "headers": ["Host": object["host"] as? String ?? checked.host]] }
            if checked.transport == "grpc" { stream["grpcSettings"] = ["serviceName": object["path"] as? String ?? "", "multiMode": false] }
            if checked.transport == "httpupgrade" { stream["httpupgradeSettings"] = ["path": object["path"] as? String ?? "/", "host": object["host"] as? String ?? checked.host] }
            if checked.transport == "xhttp" { stream["xhttpSettings"] = ["path": object["path"] as? String ?? "/", "host": object["host"] as? String ?? checked.host, "mode": "auto"] }
            if checked.security == "tls" {
                stream["tlsSettings"] = ["serverName": object["sni"] as? String ?? checked.host, "fingerprint": object["fp"] as? String ?? "chrome"]
            }
        }
        let outbound: [String: Any] = ["tag": "proxy", "protocol": checked.protocolName,
            "settings": ["vnext": [["address": checked.host, "port": checked.port, "users": [user]]]], "streamSettings": stream]
        let config: [String: Any] = ["log": ["loglevel": "none"], "dns": ["servers": [dns]],
                                   "outbounds": [outbound], "routing": ["domainStrategy": "AsIs"]]
        return try finish(config, dns: dns, rules: rules, bypassLAN: bypassLAN, domainStrategy: domainStrategy)
    }
}
