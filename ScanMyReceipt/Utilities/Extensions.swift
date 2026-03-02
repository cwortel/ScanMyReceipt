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
    /// Formats as "€ 1.234,56" using Dutch locale (comma decimal, dot thousands).
    var euroFormatted: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "EUR"
        formatter.currencySymbol = "€"
        formatter.locale = Locale(identifier: "nl_NL")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: self)) ?? "€ 0,00"
    }

    /// Formats as "12,34" (no currency symbol) for text field display.
    var dutchFormatted: String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "nl_NL")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = ""
        return formatter.string(from: NSNumber(value: self)) ?? "0,00"
    }
}