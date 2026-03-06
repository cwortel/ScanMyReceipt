import Foundation
import UIKit

extension Bundle {
    /// "1.0.42" — short version + build number.
    var versionString: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(version).\(build)"
    }
}

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

extension UIImage {
    /// Redraws the image so its pixel data matches `.up` orientation,
    /// removing any EXIF rotation flag. This prevents photos imported
    /// from the photo library from appearing rotated.
    func normalizedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}