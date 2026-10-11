import Foundation

public struct SubscriptionResult {
    public let profiles: [ServerProfile]
    public let usage: SubscriptionUsage?
}

private final class HTTPSRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url?.scheme == "https" ? request : nil)
    }
}

public enum SubscriptionLoader {
    public static func fetch(_ url: URL) async throws -> SubscriptionResult {
        _ = try ImportParser.subscriptionURL(url.absoluteString)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.setValue("baha-vpn/0.1", forHTTPHeaderField: "User-Agent")
        request.setValue("text/plain, application/octet-stream", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request, delegate: HTTPSRedirectPolicy())
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              response.url?.scheme == "https" else { throw ClientError.invalid("подписка вернула ошибку http") }
        guard response.expectedContentLength <= Int64(ImportParser.maximumBytes) else { throw ClientError.invalid("подписка превышает 2 мб") }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < ImportParser.maximumBytes else { throw ClientError.invalid("подписка превышает 2 мб") }
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
