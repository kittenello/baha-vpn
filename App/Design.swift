import SwiftUI

enum Design {
    static let accent = Color(red: 0.64, green: 0.52, blue: 0.98)
    static let background = Color(red: 0.055, green: 0.06, blue: 0.075)
    static let card = Color(red: 0.115, green: 0.12, blue: 0.14)
    static let line = Color.white.opacity(0.075)
}

extension View {
    func cardStyle() -> some View {
        padding(16).background(Design.card, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Design.line))
    }
    func pageBackground() -> some View { background(Design.background.ignoresSafeArea()) }
}

struct EmptyState: View {
    let title: String
    let text: String
    let symbol: String
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 36, weight: .light)).foregroundStyle(Design.accent)
            Text(title).font(.title3.bold())
            Text(text).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 48).padding(.horizontal, 24)
    }
}

func formattedBytes(_ value: Int64) -> String {
    let units = ["б", "кб", "мб", "гб", "тб"]
    var count = Double(max(0, value))
    var index = 0
    while count >= 1024 && index < units.count - 1 { count /= 1024; index += 1 }
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "ru_RU")
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = index == 0 ? 0 : 1
    return "\(formatter.string(from: NSNumber(value: count)) ?? "0") \(units[index])"
}
