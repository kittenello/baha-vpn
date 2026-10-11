import Foundation
import Combine
import BahaCore

@MainActor final class ClientStore: ObservableObject {
    @Published private(set) var state = ClientState()
    @Published var error: String?
    @Published var notice: String?
    @Published private(set) var refreshing = Set<UUID>()
    @Published private(set) var latency: [UUID: Int] = [:]
    @Published private(set) var checkingLatency = false
    private let storage = SecureStore()
    private var loadFailed = false

    init() {
        do {
            if ProcessInfo.processInfo.arguments.contains("--ui-testing") && ProcessInfo.processInfo.arguments.contains("--reset-ui-state") {
                try storage.write(ClientState())
            }
            state = try storage.read(); state.repairSelection()
        }
        catch { self.error = "не удалось открыть сохранённые профили: \(error.localizedDescription)"; loadFailed = true }
    }

    var selected: ServerProfile? { state.profiles.first { $0.id == state.selectedID } }

    @discardableResult private func change(_ operation: (inout ClientState) -> Void) -> Bool {
        guard !loadFailed else { error = "перезапусти приложение после разблокировки устройства; сохранённые данные не перезаписаны"; return false }
        var next = state
        operation(&next)
        do { try storage.write(next); state = next; return true }
        catch { self.error = error.localizedDescription; return false }
    }

    func select(_ profile: ServerProfile) { change { $0.selectedID = profile.id } }
    func favorite(_ id: UUID) {
        change { state in
            if let index = state.profiles.firstIndex(where: { $0.id == id }) { state.profiles[index].isFavorite.toggle() }
        }
    }
    func removeProfile(_ id: UUID) { change { $0.profiles.removeAll { $0.id == id }; $0.repairSelection() } }
    func removeSubscription(_ id: UUID) {
        guard !refreshing.contains(id) else { return }
        change { $0.removeSubscription(id) }
    }
    func settings(_ operation: (inout ClientSettings) -> Void) { change { operation(&$0.settings) } }

    func importText(_ text: String) throws {
        let profiles = try ImportParser.parse(text)
        for profile in profiles { _ = try XrayConfiguration.make(profile: profile, dns: state.settings.dns) }
        var count = 0
        guard change({ count = $0.add(profiles) }) else { throw ClientError.invalid(error ?? "ошибка сохранения") }
        notice = count == 0 ? "эти серверы уже добавлены" : "добавлено серверов: \(count)"
    }

    func addSubscription(name: String, text: String) async throws {
        let url = try ImportParser.subscriptionURL(text)
        guard !state.subscriptions.contains(where: { $0.url == url }) else { throw ClientError.invalid("подписка уже добавлена") }
        let result = try await SubscriptionLoader.fetch(url, device: DeviceIdentity.metadata(for: url))
        // Recheck after suspension to avoid duplicate concurrent additions.
        guard !state.subscriptions.contains(where: { $0.url == url }) else { throw ClientError.invalid("подписка уже добавлена") }
        let subscription = ServerSubscription(name: name.trimmingCharacters(in: .whitespaces).isEmpty ? "подписка" : name, url: url)
        guard change({
            $0.subscriptions.append(subscription)
            $0.replace(subscriptionID: subscription.id, profiles: result.profiles, usage: result.usage)
        }) else { throw ClientError.invalid(error ?? "ошибка сохранения") }
        notice = "подписка добавлена"
    }

    func refresh(_ subscription: ServerSubscription) async {
        guard refreshing.insert(subscription.id).inserted else { return }
        defer { refreshing.remove(subscription.id) }
        do {
            let result = try await SubscriptionLoader.fetch(subscription.url, device: DeviceIdentity.metadata(for: subscription.url))
            guard state.subscriptions.contains(where: { $0.id == subscription.id }) else { return }
            change { $0.replace(subscriptionID: subscription.id, profiles: result.profiles, usage: result.usage) }
        } catch { self.error = "\(subscription.name): \(error.localizedDescription). прежние серверы сохранены" }
    }

    func refreshAll(onlyDue: Bool = false) async {
        guard !onlyDue || state.settings.autoRefresh else { return }
        let interval = Double(state.settings.refreshHours) * 3600
        for subscription in state.subscriptions {
            if onlyDue, let updated = subscription.updatedAt, Date().timeIntervalSince(updated) < interval { continue }
            await refresh(subscription)
        }
    }

    func checkLatency() async {
        guard !checkingLatency else { return }
        checkingLatency = true
        defer { checkingLatency = false }
        let snapshot = state.profiles
        // Bound simultaneous probes and avoid a burst of thousands of sockets.
        for offset in stride(from: 0, to: snapshot.count, by: 8) {
            let batch = Array(snapshot[offset..<min(offset + 8, snapshot.count)])
            let results = await withTaskGroup(of: (UUID, Int?).self) { group in
                for profile in batch { group.addTask { (profile.id, await LatencyProbe.measure(host: profile.host, port: profile.port)) } }
                var values: [(UUID, Int?)] = []
                for await value in group { values.append(value) }
                return values
            }
            for (id, value) in results { latency[id] = value ?? -1 }
        }
    }

    func seedPreview() {
        guard ProcessInfo.processInfo.arguments.contains("--preview-data") else { return }
        state = ClientState()
        let names = ["нидерланды · демо", "германия · демо", "финляндия · демо"]
        for name in names {
            if let profile = try? ImportParser.profile("vless://01234567-89ab-cdef-0123-456789abcdef@example.com:443?security=tls&type=tcp#\(name.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed)!)") {
                state.profiles.append(profile)
            }
        }
        state.repairSelection()
    }
}
