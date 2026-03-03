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
}