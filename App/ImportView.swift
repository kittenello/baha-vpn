import SwiftUI
import UniformTypeIdentifiers
import BahaCore

struct ImportView: View {
    @EnvironmentObject var store: ClientStore
    @Environment(\.dismiss) var dismiss
    let mode: ImportDestination
    var initialText = ""
    @State private var text = ""
    @State private var name = ""
    @State private var importing = false
    @State private var scan = false
    @State private var files = false
    @State private var localError: String?
    @State private var subscriptionMode = false
    @State private var initialized = false
    @FocusState private var editing: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(spacing: 0) {
                        action("вставить ссылку", symbol: "link") {
                            guard let value = UIPasteboard.general.string else { localError = "в буфере обмена нет текста"; return }
                            use(value)
                        }
                        Divider().padding(.leading, 48)
                        action("сканировать qr", symbol: "qrcode.viewfinder") { scan = true }
                        Divider().padding(.leading, 48)
                        action("добавить подписку", symbol: "rectangle.stack.badge.plus") { subscriptionMode = true }
                        Divider().padding(.leading, 48)
                        action("импортировать файл", symbol: "doc") { files = true }
                    }.background(Design.card, in: RoundedRectangle(cornerRadius: 18))
                    if subscriptionMode {
                        TextField("название подписки", text: $name).textInputAutocapitalization(.never).cardStyle()
                        Text("провайдеру подписки передаётся постоянный идентификатор устройства для проверки лимита устройств").font(.caption).foregroundStyle(.secondary)
                    }
                    Text(subscriptionMode ? "https-ссылка подписки" : "ссылка или список серверов").font(.subheadline).foregroundStyle(.secondary)
                    TextEditor(text: $text).font(.system(.body, design: .monospaced)).frame(minHeight: 150)
                        .accessibilityIdentifier("profile-input").focused($editing)
                        .scrollContentBackground(.hidden).autocorrectionDisabled().textInputAutocapitalization(.never)
                        .padding(12).background(Design.card, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty { Text(subscriptionMode ? "https://example.com/sub/…" : "vless://… или vmess://…").font(.caption.monospaced()).foregroundStyle(.tertiary).padding(20).allowsHitTesting(false) }
                        }
                    if let localError { Text(localError).font(.subheadline).foregroundStyle(.red) }
                    Button {
                        Task {
                            importing = true; localError = nil
                            defer { importing = false }
                            do {
                                if subscriptionMode { try await store.addSubscription(name: name, text: text) }
                                else { try store.importText(text) }
                                dismiss()
                            } catch { localError = error.localizedDescription }
                        }
                    } label: {
                        HStack { if importing { ProgressView().tint(.white) }; Text(subscriptionMode ? "добавить подписку" : "импортировать").fontWeight(.semibold) }
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                    }.buttonStyle(.borderedProminent).disabled(importing || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Text("профили шифруются и сохраняются на устройстве").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    Text("vless, vmess, trojan, shadowsocks, hysteria2, wireguard; tcp, ws, grpc, xhttp. подписки: ссылки, base64 и xray json. wireguard: ссылки и файлы conf.")
                        .font(.caption).foregroundStyle(.tertiary)
                }.padding(20)
            }
            .navigationTitle(subscriptionMode ? "добавить подписку" : "добавить сервер")
            .navigationBarTitleDisplayMode(.inline).pageBackground()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("закрыть") { dismiss() }.disabled(importing) } }
            .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("готово") { editing = false } } }
            .interactiveDismissDisabled(importing)
            .onAppear {
                guard !initialized else { return }
                initialized = true; text = initialText
                subscriptionMode = mode == .subscription || initialText.lowercased().hasPrefix("https://")
            }
            .sheet(isPresented: $scan) { ScanView { value in use(value); scan = false } }
            .fileImporter(isPresented: $files, allowedContentTypes: [.plainText, .text, .data], allowsMultipleSelection: false) { result in
                do {
                    guard let url = try result.get().first else { return }
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    let values = try url.resourceValues(forKeys: [.fileSizeKey])
                    guard (values.fileSize ?? 0) <= ImportParser.maximumBytes else { throw ClientError.invalid("файл превышает 8 мб") }
                    let data = try Data(contentsOf: url)
                    guard data.count <= ImportParser.maximumBytes, let value = String(data: data, encoding: .utf8) else { throw ClientError.invalid("нужен текстовый файл utf-8 до 8 мб") }
                    use(value)
                } catch { localError = error.localizedDescription }
            }
        }
    }

    private func use(_ value: String) {
        text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        subscriptionMode = text.lowercased().hasPrefix("https://")
        localError = nil
    }
    private func action(_ title: String, symbol: String, operation: @escaping () -> Void) -> some View {
        Button(action: operation) {
            HStack(spacing: 14) {
                Image(systemName: symbol).frame(width: 22).foregroundStyle(Design.accent)
                Text(title).foregroundStyle(.primary); Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }.padding(16)
        }.disabled(importing)
    }
}
