import Foundation

public struct SubscriptionResult {
    public let profiles: [ServerProfile]
    public let usage: SubscriptionUsage?
}

private final class HTTPSRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard request.url?.scheme == "https" else { completionHandler(nil); return }
        var safe = request
        // Device headers belong to the provider entered by the user, not an unrelated redirect host.
        if response.url?.host?.lowercased() != request.url?.host?.lowercased() {
            for header in ["x-hwid", "x-device-os", "x-ver-os", "x-device-model"] { safe.setValue(nil, forHTTPHeaderField: header) }
        }
        completionHandler(safe)
    }
}

public enum SubscriptionLoader {
    public static func makeRequest(_ url: URL, device: SubscriptionDevice? = nil) throws -> URLRequest {
        _ = try ImportParser.subscriptionURL(url.absoluteString)
        var request = URLRequest(url: url)
        request.setValue("baha-vpn/0.1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("text/plain, application/octet-stream", forHTTPHeaderField: "Accept")
        if let device {
            for (header, value) in try device.headers() { request.setValue(value, forHTTPHeaderField: header) }
        }
        return request
    }

    public static func fetch(_ url: URL, device: SubscriptionDevice? = nil) async throws -> SubscriptionResult {
        _ = try ImportParser.subscriptionURL(url.absoluteString)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let request = try makeRequest(url, device: device)
        let (bytes, response) = try await session.bytes(for: request, delegate: HTTPSRedirectPolicy())
        guard let http = response as? HTTPURLResponse else { throw ClientError.invalid("некорректный ответ сервера подписки") }
        try SubscriptionResponsePolicy.check(http)
        guard response.expectedContentLength <= Int64(ImportParser.maximumBytes) else { throw ClientError.invalid("подписка превышает 8 мб") }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < ImportParser.maximumBytes else { throw ClientError.invalid("подписка превышает 8 мб") }
            data.append(byte)
        }
        guard let text = String(data: data, encoding: .utf8) else { throw ClientError.invalid("подписка должна содержать текст utf-8") }
        let profiles = try ImportParser.parse(text)
        // Validate generated configs too, before permitting an atomic replacement.
        for profile in profiles { _ = try XrayConfiguration.make(profile: profile, dns: "1.1.1.1") }
        let usage = http.value(forHTTPHeaderField: "subscription-userinfo").map(SubscriptionUsage.init(header:))
        return SubscriptionResult(profiles: profiles, usage: usage)
    }
}
