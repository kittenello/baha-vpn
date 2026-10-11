import Foundation

public struct SubscriptionDevice: Equatable {
    public let hwid: String
    public let os: String
    public let version: String
    public let model: String
    public init(hwid: String, os: String, version: String, model: String) {
        self.hwid = hwid; self.os = os; self.version = version; self.model = model
    }

    public func headers() throws -> [String: String] {
        guard hwid.range(of: "^[a-zA-Z0-9=-]{10,64}$", options: .regularExpression) != nil else {
            throw ClientError.invalid("не удалось подготовить идентификатор устройства")
        }
        return ["x-hwid": hwid, "x-device-os": os, "x-ver-os": version, "x-device-model": model]
    }
}

public enum SubscriptionResponsePolicy {
    public static func check(_ response: HTTPURLResponse) throws {
        func enabled(_ header: String) -> Bool { response.value(forHTTPHeaderField: header)?.lowercased() == "true" }
        // Some panels use HTTP 200 with an empty body for these denials.
        if enabled("x-hwid-max-devices-reached") || enabled("x-hwid-limit") {
            throw ClientError.invalid("достигнут лимит устройств подписки; удали старое устройство в кабинете провайдера или обратись в его поддержку")
        }
        if enabled("x-hwid-not-supported") {
            throw ClientError.invalid("провайдер не принял идентификатор устройства; проверь совместимость клиента с подпиской")
        }
        guard (200...299).contains(response.statusCode), response.url?.scheme == "https" else {
            throw ClientError.invalid("подписка вернула ошибку http \(response.statusCode)")
        }
    }
}
