import Foundation

// MARK: - Receipt Number Format

/// Determines how the receipt number prefix is generated.
enum ReceiptNumberFormat: String, Codable, CaseIterable, Identifiable {
    /// YYYYMM-NNN  (e.g. 202603-001)
    case yearMonth = "yearMonth"
    /// CollectionName-NNN  (e.g. TripParis-001)
    case collectionName = "collectionName"
    /// User-defined prefix (e.g. "INV2026-001", "TRIP-001")
    case custom = "custom"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .yearMonth:      return "Year + Month"
        case .collectionName: return "Collection Name"
        case .custom:         return "Custom Prefix"
        }
    }

    /// Generates the prefix. For `.collectionName` supply the name; for `.custom` reads AppSettings.
    func prefix(for date: Date = Date(), collectionName: String? = nil) -> String {
        switch self {
        case .yearMonth:
            let cal = Calendar.current
            let year = cal.component(.year, from: date)
            let month = cal.component(.month, from: date)
            return String(format: "%04d%02d", year, month)
        case .collectionName:
            let name = collectionName ?? "Collection"
            return Self.sanitizePrefix(name)
        case .custom:
            return AppSettings.shared.customPrefix
        }
    }

    /// Example string shown in settings.
    func example(customPrefix: String = "") -> String {
        switch self {
        case .yearMonth:      return "\(prefix())-001"
        case .collectionName: return "TripParis-001"
        case .custom:
            let p = customPrefix.isEmpty ? "MY" : customPrefix
            return "\(p)-001"
        }
    }

    /// Strips whitespace and special characters, keeping only alphanumerics, hyphens, underscores.
    static func sanitizePrefix(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = String(name.unicodeScalars.filter { allowed.contains($0) }.map { Character($0) })
        return cleaned.isEmpty ? "Collection" : cleaned
    }
}

// MARK: - AppSettings

/// Persists user preferences in UserDefaults.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    // MARK: Keys

    private enum Key: String {
        case receiptNumberFormat
        case customPrefix
        case defaultTaxPercentage
    }

    // MARK: Published Properties

    @Published var receiptNumberFormat: ReceiptNumberFormat {
        didSet { defaults.set(receiptNumberFormat.rawValue, forKey: Key.receiptNumberFormat.rawValue) }
    }

    @Published var customPrefix: String {
        didSet { defaults.set(customPrefix, forKey: Key.customPrefix.rawValue) }
    }

    @Published var defaultTaxPercentage: Double {
        didSet { defaults.set(defaultTaxPercentage, forKey: Key.defaultTaxPercentage.rawValue) }
    }

    // MARK: Init

    private init() {
        // Receipt number format
        if let raw = defaults.string(forKey: Key.receiptNumberFormat.rawValue),
           let fmt = ReceiptNumberFormat(rawValue: raw) {
            self.receiptNumberFormat = fmt
        } else {
            self.receiptNumberFormat = .yearMonth
        }

        // Custom prefix
        self.customPrefix = defaults.string(forKey: Key.customPrefix.rawValue) ?? ""

        // Default tax percentage (0 means not yet set -> use 21)
        let storedTax = defaults.double(forKey: Key.defaultTaxPercentage.rawValue)
        self.defaultTaxPercentage = storedTax > 0 ? storedTax : 21.0
    }
}
