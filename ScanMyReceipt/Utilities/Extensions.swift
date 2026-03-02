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
    /// Formats as "€ 12.34"
    var euroFormatted: String {
        String(format: "€ %.2f", self)
    }
}