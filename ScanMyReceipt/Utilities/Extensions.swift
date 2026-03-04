import Foundation

extension Date {
    /// Returns "YYYYMM" for the current date, used as receipt number prefix.
    var yearMonthPrefix: String {
        let cal = Calendar.current
        let y = cal.component(.year, from: self)
        let m = cal.component(.month, from: self)
        return String(format: "%04d%02d", y, m)
    }
}

extension Double {
    // MARK: - Cached Formatters (NumberFormatter is expensive to create)

    private static let euroFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "EUR"
        f.currencySymbol = "€"
        f.locale = Locale(identifier: "nl_NL")
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

    private static let dutchDecimalFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "nl_NL")
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.groupingSeparator = ""
        return f
    }()

    /// Formats as "€ 1.234,56" using Dutch locale (comma decimal, dot thousands).
    var euroFormatted: String {
        Self.euroFormatter.string(from: NSNumber(value: self)) ?? "€ 0,00"
    }

    /// Formats as "12,34" (no currency symbol) for text field display.
    var dutchFormatted: String {
        Self.dutchDecimalFormatter.string(from: NSNumber(value: self)) ?? "0,00"
    }
}