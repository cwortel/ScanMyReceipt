import Foundation

// MARK: - Receipt

struct Receipt: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    /// e.g. "202603-001" — YYYYMM-NNN
    var receiptNumber: String = ""
    var shopName: String = ""
    var purchaseDate: Date = Date()
    /// Total amount including tax
    var totalAmount: Double = 0.0
    /// Amount excluding tax
    var amountWithoutTax: Double = 0.0
    /// VAT percentage (e.g. 21.0 for 21%)
    var taxPercentage: Double = 21.0
    /// Category label (e.g. "Travel", "Office"). Empty = uncategorised.
    var category: String = ""
    /// File names of scanned images stored on disk
    var imageFileNames: [String] = []

    var taxAmount: Double {
        totalAmount - amountWithoutTax
    }
}

// MARK: - ReceiptCollection

struct ReceiptCollection: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var createdDate: Date = Date()
    var receipts: [Receipt] = []

    // MARK: Per-collection settings

    /// Numbering format for receipts in this collection.
    var numberFormat: ReceiptNumberFormat = .yearMonth
    /// Custom prefix used when `numberFormat == .custom`.
    var customPrefix: String = ""
    /// Default tax percentage for new receipts in this collection.
    var defaultTaxPercentage: Double = 21.0
}