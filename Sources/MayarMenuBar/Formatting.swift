import Foundation

enum Format {
    static let idr: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "id_ID")
        f.numberStyle = .currency
        f.currencyCode = "IDR"
        f.maximumFractionDigits = 0
        return f
    }()

    static func rupiah(_ amount: Int) -> String {
        idr.string(from: NSNumber(value: amount)) ?? "Rp \(amount)"
    }

    static func shortRupiah(_ amount: Int) -> String {
        let n = abs(amount)
        let sign = amount < 0 ? "-" : ""
        switch n {
        case 1_000_000_000...:
            return "\(sign)Rp \(String(format: "%.1f", Double(n) / 1_000_000_000))M"
        case 1_000_000...:
            return "\(sign)Rp \(String(format: "%.1f", Double(n) / 1_000_000))jt"
        case 1_000...:
            return "\(sign)Rp \(String(format: "%.0f", Double(n) / 1_000))k"
        default:
            return rupiah(amount)
        }
    }

    static func relativeTime(epochMs: Double) -> String {
        let date = Date(timeIntervalSince1970: epochMs / 1000)
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .short
        return fmt.localizedString(for: date, relativeTo: Date())
    }
}
