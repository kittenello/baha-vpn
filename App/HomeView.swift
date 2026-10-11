import SwiftUI
import NetworkExtension

struct HomeView: View {
    @EnvironmentObject var store: ClientStore
    @EnvironmentObject var tunnel: TunnelController
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    let add: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Text(tunnel.title).font(.subheadline.weight(.medium)).foregroundStyle(tunnel.status == .connected ? Design.accent : .secondary)
                        .padding(.horizontal, 18).padding(.vertical, 9)
                        .background(Design.accent.opacity(tunnel.running ? 0.2 : 0.07), in: Capsule())
                    Button {
                        Task { await tunnel.toggle(profile: store.selected, settings: store.state.settings) }
                    } label: {
                        ZStack {
                            Circle().fill(Design.card)
                            Circle().stroke(Design.accent.opacity(tunnel.running ? 1 : 0.3), lineWidth: 3).padding(3)
                            Circle().stroke(Design.accent.opacity(0.12), lineWidth: 1).padding(10)
                            if tunnel.busy || [.connecting, .disconnecting, .reasserting].contains(tunnel.status) {
                                ProgressView().controlSize(.large).tint(Design.accent)
                            } else { Image(systemName: "power").font(.system(size: 48, weight: .light)).foregroundStyle(Design.accent) }
                        }.frame(width: 174, height: 174)
                    }
                    .buttonStyle(.plain).disabled(tunnel.busy || (store.selected == nil && !tunnel.running))
                    .accessibilityLabel(tunnel.running ? "отключить впн" : "подключить впн")
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: tunnel.status)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(duration(at: context.date)).font(.system(.subheadline, design: .monospaced)).foregroundStyle(.secondary)
                    }
                    if let selected = store.selected {
                        HStack(spacing: 14) {
                            Image(systemName: "mappin.and.ellipse").font(.title2).foregroundStyle(Design.accent)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(tunnel.running ? tunnel.activeName : selected.name).font(.headline).lineLimit(2)
                                Text(selected.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(latencyText(selected.id)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }.cardStyle()
                    } else {
                        VStack(spacing: 16) {
                            Text("добавь свой первый сервер").font(.headline)
                            Text("ссылка, qr-код или подписка от твоего провайдера").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            Button("добавить сервер", action: add).buttonStyle(.borderedProminent)
                        }.frame(maxWidth: .infinity).cardStyle()
                    }
                    HStack(spacing: 12) {
                        statistic("загрузка", bytes: tunnel.received, symbol: "arrow.down")
                        statistic("отдача", bytes: tunnel.sent, symbol: "arrow.up")
                    }
                    Text("трафик за текущее подключение").font(.caption).foregroundStyle(.tertiary)
                }.padding(20).padding(.top, 12)
            }
            .navigationTitle("главная").pageBackground()
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(action: add) { Image(systemName: "plus") }.accessibilityLabel("добавить сервер") } }
        }
    }

    private func statistic(_ title: String, bytes: Int64, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text(title).foregroundStyle(.secondary); Spacer(); Image(systemName: symbol).foregroundStyle(Design.accent) }.font(.caption)
            Text(formattedBytes(bytes)).font(.title3.weight(.semibold)).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading).cardStyle()
    }
    private func latencyText(_ id: UUID) -> String {
        guard let latency = store.latency[id] else { return "— мс" }
        return latency < 0 ? "недоступен" : "\(latency) мс"
    }
    private func duration(at date: Date) -> String {
        guard tunnel.status == .connected, let start = tunnel.connectedAt else { return "00:00:00" }
        let seconds = max(0, Int(date.timeIntervalSince(start)))
        return String(format: "%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }
}
