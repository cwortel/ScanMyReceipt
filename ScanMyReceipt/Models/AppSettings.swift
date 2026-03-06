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

    /// Generates the prefix for a receipt number.
    /// - Parameters:
    ///   - date: Date used for `.yearMonth` (defaults to now).
    ///   - collectionName: The collection name, used for `.collectionName`.
    ///   - customPrefix: The user-defined prefix, used for `.custom`.
    func prefix(for date: Date = Date(), collectionName: String? = nil, customPrefix: String = "") -> String {
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
            return customPrefix.isEmpty ? "CUSTOM" : customPrefix
        }
    }

    /// Example string shown in settings.
    func example(collectionName: String = "TripParis", customPrefix: String = "") -> String {
        switch self {
        case .yearMonth:      return "\(prefix())-001"
        case .collectionName: return "\(Self.sanitizePrefix(collectionName))-001"
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

/// Persists global user preferences in UserDefaults.
/// Numbering settings are now per-collection — only default tax remains global.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    private enum Key: String {
        case defaultTaxPercentage
        case categories
    }

    /// Global categories shared across all collections.
    static let defaultCategories: [String] = [
        "Travel",
        "Representation",
        "Office",
        "Car Expenses",
        "Food & Drinks",
        "Subscriptions",
        "Equipment",
        "Telecom",
        "Insurance",
        "Other",
    ]

    @Published var defaultTaxPercentage: Double {
        didSet { defaults.set(defaultTaxPercentage, forKey: Key.defaultTaxPercentage.rawValue) }
    }

    @Published var categories: [String] {
        didSet {
            if let data = try? JSONEncoder().encode(categories) {
                defaults.set(data, forKey: Key.categories.rawValue)
            }
        }
    }

    private init() {
        let storedTax = defaults.double(forKey: Key.defaultTaxPercentage.rawValue)
        self.defaultTaxPercentage = storedTax > 0 ? storedTax : 21.0

        if let data = defaults.data(forKey: Key.categories.rawValue),
           let stored = try? JSONDecoder().decode([String].self, from: data) {
            self.categories = stored
        } else {
            self.categories = Self.defaultCategories
        }
    }
}
