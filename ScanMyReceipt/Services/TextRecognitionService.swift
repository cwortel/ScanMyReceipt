import Foundation
import Vision
import UIKit

// MARK: - Recognized Data

struct RecognizedReceiptData {
    var shopName: String?
    var purchaseDate: Date?
    var totalAmount: Double?
    var taxPercentage: Double?
    var amountWithoutTax: Double?
}

// MARK: - TextRecognitionService

/// Uses Apple Vision to OCR scanned receipt images and extract structured data.
class TextRecognitionService {
    static let shared = TextRecognitionService()
    private init() {}

    // MARK: - Cached Regex & DateFormatters

    // Product-line detection
    private static let priceRegex = try! NSRegularExpression(pattern: "\\d+[,.]\\d{2}")
    private static let qtyRegex = try! NSRegularExpression(pattern: "^\\d{1,3}\\s*[xX]?\\s+[a-zA-Z]")

    // Classification helpers
    private static let amountRegex = try! NSRegularExpression(pattern: "^[€$]?\\s*\\d+[,.]\\d{2}$")
    private static let dateLineRegex = try! NSRegularExpression(pattern: "^\\d{2}[\\-/\\.]\\d{2}[\\-/\\.]\\d{2,4}(\\s*[,.]?\\s*\\d{2}[:\\.\\-]\\d{2}(:\\d{2})?)?$")
    private static let postalRegex = try! NSRegularExpression(pattern: "\\b\\d{4}\\s*[a-z]{2}\\b")
    private static let streetRegex = try! NSRegularExpression(pattern: "^[a-zA-Z]+\\s+\\d{1,5}$")
    private static let timeOnlyRegex = try! NSRegularExpression(pattern: "^\\d{1,2}[:\\.]\\d{2}([:\\.]\\d{2})?$")
    private static let genericPctRegex = try! NSRegularExpression(pattern: "(\\d{1,2})[,.]?\\d*\\s*%")
    private static let tariefRegex = try! NSRegularExpression(pattern: "(?:tarief|rate).*?(\\d{1,2})[,.]\\d+\\s*%")

    // Order/table patterns
    private static let orderTablePatterns: [NSRegularExpression] = [
        try! NSRegularExpression(pattern: "^(tafel|table|order|bestelling|bon|nr\\.?|#)\\s*\\d+", options: .caseInsensitive),
        try! NSRegularExpression(pattern: "^\\d{1,3}$"),
        try! NSRegularExpression(pattern: "^\\d{1,3}\\s+\\w{1,3}$"),
    ]

    // Date extraction patterns (regex + DateFormatters)
    private static let datePatterns: [(regex: NSRegularExpression, formatters: [DateFormatter])] = {
        func makeDateFormatters(_ formats: [String]) -> [DateFormatter] {
            formats.map { fmt in
                let df = DateFormatter()
                df.dateFormat = fmt
                df.locale = Locale(identifier: "nl_NL")
                return df
            }
        }
        return [
            (try! NSRegularExpression(pattern: "(\\d{2})[\\-/\\.](\\d{2})[\\-/\\.](\\d{4})"),
             makeDateFormatters(["dd-MM-yyyy", "dd/MM/yyyy", "dd.MM.yyyy"])),
            (try! NSRegularExpression(pattern: "(\\d{4})[\\-/\\.](\\d{2})[\\-/\\.](\\d{2})"),
             makeDateFormatters(["yyyy-MM-dd", "yyyy/MM/dd", "yyyy.MM.dd"])),
            (try! NSRegularExpression(pattern: "\\b(\\d{2})[\\-/\\.](\\d{2})[\\-/\\.](\\d{2})\\b"),
             makeDateFormatters(["dd-MM-yy", "dd/MM/yy", "dd.MM.yy"])),
        ]
    }()

    // Tax percentage detection
    private static let taxPatterns: [(regex: NSRegularExpression, pct: Double)] = [
        (try! NSRegularExpression(pattern: "btw\\s*(?:hoog)?\\s*21"), 21.0),
        (try! NSRegularExpression(pattern: "21[,.]?\\d*\\s*%\\s*btw"), 21.0),
        (try! NSRegularExpression(pattern: "btw\\s*21[,.]?\\d*\\s*%"), 21.0),
        (try! NSRegularExpression(pattern: "btw\\s*(?:laag)?\\s*9"), 9.0),
        (try! NSRegularExpression(pattern: "9[,.]00\\s*%"), 9.0),
        (try! NSRegularExpression(pattern: "9\\s*%\\s*btw"), 9.0),
        (try! NSRegularExpression(pattern: "btw\\s*9[,.]?\\d*\\s*%"), 9.0),
        (try! NSRegularExpression(pattern: "btw\\s*0"), 0.0),
        (try! NSRegularExpression(pattern: "0[,.]?\\d*\\s*%\\s*btw"), 0.0),
        (try! NSRegularExpression(pattern: "vat\\s*21"), 21.0),
        (try! NSRegularExpression(pattern: "21[,.]?\\d*\\s*%\\s*vat"), 21.0),
        (try! NSRegularExpression(pattern: "vat\\s*9"), 9.0),
        (try! NSRegularExpression(pattern: "9[,.]?\\d*\\s*%\\s*vat"), 9.0),
    ]

    // Amount extraction
    private static let amountPatterns: [NSRegularExpression] = [
        try! NSRegularExpression(pattern: "€\\s*([\\d.]+,\\d{2})"),
        try! NSRegularExpression(pattern: "€\\s*([\\d,]+\\.\\d{2})"),
        try! NSRegularExpression(pattern: "EUR\\s*([\\d.]+,\\d{2})"),
        try! NSRegularExpression(pattern: "EUR\\s*([\\d,]+\\.\\d{2})"),
        try! NSRegularExpression(pattern: "([\\d.]+,\\d{2})\\s*€"),
        try! NSRegularExpression(pattern: "([\\d,]+\\.\\d{2})\\s*€"),
        try! NSRegularExpression(pattern: "\\b(\\d+,\\d{2})\\b"),
        try! NSRegularExpression(pattern: "\\b(\\d+\\.\\d{2})\\b"),
    ]

    // MARK: - Public API

    /// Runs OCR on all images, combines text, and parses receipt fields.
    func recognizeReceipt(from images: [UIImage], completion: @escaping (RecognizedReceiptData) -> Void) {
        let group = DispatchGroup()
        // Preserve page order: pre-allocate array slots
        var texts = [String](repeating: "", count: images.count)
        let lock = NSLock()

        for (index, image) in images.enumerated() {
            group.enter()
            recognizeText(from: image) { text in
                lock.lock()
                texts[index] = text
                lock.unlock()
                group.leave()
            }
        }

        group.notify(queue: .global(qos: .userInitiated)) {
            let combined = texts.joined(separator: "\n")
            let data = self.parseReceiptData(from: combined)
            DispatchQueue.main.async {
                completion(data)
            }
        }
    }

    // MARK: - OCR

    /// Runs Vision text recognition on a single image.
    func recognizeText(from image: UIImage, completion: @escaping (String) -> Void) {
        guard let cgImage = image.cgImage else {
            completion("")
            return
        }

        let request = VNRecognizeTextRequest { request, error in
            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                completion("")
                return
            }
            let text = observations
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
            completion(text)
        }

        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["nl-NL", "en-US"]
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                print("OCR failed: \(error)")
                completion("")
            }
        }
    }

    // MARK: - Parsing

    func parseReceiptData(from text: String) -> RecognizedReceiptData {
        var data = RecognizedReceiptData()
        let lines = text
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        data.shopName = extractShopName(from: lines)
        data.purchaseDate = extractDate(from: text)
        data.totalAmount = extractTotalAmount(from: lines)
        data.taxPercentage = extractTaxPercentage(from: text)

        // Derive excl-tax amount if we have total and tax %
        if let total = data.totalAmount, let taxPct = data.taxPercentage {
            if taxPct > 0 {
                data.amountWithoutTax = total / (1.0 + taxPct / 100.0)
            } else {
                data.amountWithoutTax = total
            }
        }

        return data
    }

    // MARK: - Extraction Helpers

    /// Shop name is typically in the first few lines of the receipt.
    /// Strategy: scan top lines, skip anything that looks like a product/amount/date/code line.
    /// A product line typically contains a price (€ or digit,digit pattern) on the same line,
    /// or starts with a quantity like "1x", "2 x", "1 Cirilo".
    private func extractShopName(from lines: [String]) -> String? {
        // Pass 1: look for a clean shop-name candidate in the first 10 lines
        for line in lines.prefix(10) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isValidShopNameCandidate(trimmed) else { continue }
            return trimmed
        }
        return nil
    }

    /// Returns true if a line looks like a genuine shop/business name rather than
    /// a product line, code, date, address, etc.
    private func isValidShopNameCandidate(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Basic length check
        guard trimmed.count >= 2 else { return false }

        // Filter out known non-name patterns
        guard !looksLikeAmount(trimmed),
              !looksLikeDate(trimmed),
              !looksLikeAddress(trimmed),
              !looksLikePhoneNumber(trimmed),
              !looksLikeNumericCode(trimmed),
              !looksLikeReceiptKeyword(trimmed),
              !looksLikeOrderOrTableLine(trimmed),
              !looksLikeTimeOnly(trimmed),
              !looksLikeProductLine(trimmed) else { return false }

        // Line must contain at least 2 letters (not just numbers/symbols)
        let letterCount = trimmed.filter { $0.isLetter }.count
        guard letterCount >= 2 else { return false }

        return true
    }

    /// Detects product/item lines: lines with a price embedded, or starting with a quantity.
    /// Examples: "1 Cirilo 3,50", "2x Cappuccino", "Broodje kaas  €4,50", "1 Cirilo"
    private func looksLikeProductLine(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let lower = trimmed.lowercased()

        // Line contains an amount (€ or bare price pattern like "3,50" or "12.34")
        if Self.priceRegex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil {
            return true
        }

        // Starts with a quantity: "1 ", "2x ", "1x", "3 x "
        if Self.qtyRegex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil {
            return true
        }

        // Contains € or EUR symbol somewhere in the middle/end
        if lower.contains("€") || lower.contains("eur ") {
            return true
        }

        return false
    }

    /// Tries several date formats common on Dutch & EU receipts.
    private func extractDate(from text: String) -> Date? {
        for (regex, formatters) in Self.datePatterns {
            let range = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, range: range)
            for match in matches {
                guard let matchRange = Range(match.range, in: text) else { continue }
                let matchStr = String(text[matchRange])
                for df in formatters {
                    if let date = df.date(from: matchStr) {
                        let year = Calendar.current.component(.year, from: date)
                        if year >= 2020 && year <= 2030 { return date }
                    }
                }
            }
        }
        return nil
    }

    /// Looks for total-related keywords (Dutch & English) and extracts the amount.
    private func extractTotalAmount(from lines: [String]) -> Double? {
        let totalKeywords = [
            "totaal", "total", "te betalen", "betalen",
            "bedrag", "amount", "som", "to pay", "subtotaal", "subtotal"
        ]

        // Pass 1: lines containing a total keyword
        for (index, line) in lines.enumerated() {
            let lower = line.lowercased()
            for keyword in totalKeywords {
                guard lower.contains(keyword) else { continue }
                // Prefer "totaal" / "te betalen" over sub-totals
                if let amount = extractAmount(from: line) { return amount }
                // Amount might be on the next line
                if index + 1 < lines.count,
                   let amount = extractAmount(from: lines[index + 1]) {
                    return amount
                }
            }
        }

        // Pass 2: largest amount in the bottom third of the receipt
        let bottomStart = max(0, lines.count * 2 / 3)
        var bottomAmounts: [Double] = []
        for i in bottomStart..<lines.count {
            if let amount = extractAmount(from: lines[i]) {
                bottomAmounts.append(amount)
            }
        }
        if let largest = bottomAmounts.max() { return largest }

        // Pass 3: largest amount anywhere
        let allAmounts = lines.compactMap { extractAmount(from: $0) }
        return allAmounts.max()
    }

    /// Detects BTW / VAT percentage from the recognized text.
    private func extractTaxPercentage(from text: String) -> Double? {
        let lower = text.lowercased()
        let range = NSRange(lower.startIndex..., in: lower)

        // Explicit keyword + percentage combos
        for (regex, pct) in Self.taxPatterns {
            if regex.firstMatch(in: lower, range: range) != nil {
                return pct
            }
        }

        // Generic: look for percentage near BTW/VAT keywords.
        if lower.contains("btw") || lower.contains("vat") {
            if let match = Self.genericPctRegex.firstMatch(in: lower, range: range),
               let pctRange = Range(match.range(at: 1), in: lower) {
                if let pct = Double(String(lower[pctRange])), [0, 9, 21].contains(Int(pct)) {
                    return pct
                }
            }
        }

        // Also look for "tarief" (Dutch for rate/tariff) lines
        if let match = Self.tariefRegex.firstMatch(in: lower, range: range),
           let pctRange = Range(match.range(at: 1), in: lower) {
            if let pct = Double(String(lower[pctRange])), [0, 9, 21].contains(Int(pct)) {
                return pct
            }
        }

        return nil
    }

    // MARK: - Amount Parsing

    /// Extracts a monetary amount from a line of text, handling both
    /// Dutch (comma-decimal) and English (dot-decimal) formats.
    private func extractAmount(from text: String) -> Double? {
        for regex in Self.amountPatterns {
            if let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                let raw = String(text[range])
                if let amount = normalizeAmount(raw), amount > 0 {
                    return amount
                }
            }
        }
        return nil
    }

    /// Converts "1.234,56" (Dutch) or "1,234.56" (English) to a Double.
    private func normalizeAmount(_ str: String) -> Double? {
        var s = str.trimmingCharacters(in: .whitespaces)

        if let lastComma = s.lastIndex(of: ","),
           let lastDot = s.lastIndex(of: ".") {
            if lastComma > lastDot {
                // Dutch: 1.234,56 → remove dots, comma → dot
                s = s.replacingOccurrences(of: ".", with: "")
                s = s.replacingOccurrences(of: ",", with: ".")
            } else {
                // English: 1,234.56 → remove commas
                s = s.replacingOccurrences(of: ",", with: "")
            }
        } else if s.contains(",") {
            // Only comma → Dutch: 12,34
            s = s.replacingOccurrences(of: ",", with: ".")
        }
        // If only dot → already standard: 12.34

        return Double(s)
    }

    // MARK: - Classification Helpers

    private func looksLikeAmount(_ text: String) -> Bool {
        Self.amountRegex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private func looksLikeDate(_ text: String) -> Bool {
        Self.dateLineRegex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private func looksLikeAddress(_ text: String) -> Bool {
        let lower = text.lowercased()
        if Self.postalRegex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)) != nil {
            return true
        }
        if Self.streetRegex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
            return true
        }
        return false
    }

    private func looksLikePhoneNumber(_ text: String) -> Bool {
        // Matches phone patterns: 06-12345678, +31 6 1234, 06 42126771, etc.
        let cleaned = text.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "+", with: "")
        // Mostly digits (8+), possibly starting with 0 or country code
        let digits = cleaned.filter { $0.isNumber }
        return digits.count >= 8 && digits.count <= 15 && Double(cleaned) != nil
    }

    private func looksLikeNumericCode(_ text: String) -> Bool {
        // Lines that are mostly numbers, hashes, stars — receipt codes, ticket IDs
        let stripped = text.replacingOccurrences(of: " ", with: "")
        let nonAlpha = stripped.filter { !$0.isLetter }
        // If over 60% non-letter and contains digits, it's likely a code
        let digits = stripped.filter { $0.isNumber }
        return digits.count >= 3 && Double(nonAlpha.count) / Double(max(stripped.count, 1)) > 0.6
    }

    private func looksLikeReceiptKeyword(_ text: String) -> Bool {
        let lower = text.lowercased()
            .trimmingCharacters(in: .punctuationCharacters.union(.symbols).union(.whitespaces))
        let keywords = [
            "vat receipt", "btw bon", "copy", "kopie",
            "kassabon", "receipt", "bon", "factuur", "invoice",
            "welkom", "welcome", "klant", "klantnr", "tafel",
            "bestelling", "order", "ober", "kassa", "terminal"
        ]
        return keywords.contains(where: { lower.contains($0) })
            || lower.allSatisfy({ $0 == "*" || $0 == " " })  // decorative lines like "** COPY 1 **"
    }

    /// Lines like "Table 1", "Tafel 3", "Order 42", "#123", "Nr. 5"
    private func looksLikeOrderOrTableLine(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespaces)
        let range = NSRange(lower.startIndex..., in: lower)
        for regex in Self.orderTablePatterns {
            if regex.firstMatch(in: lower, range: range) != nil {
                return true
            }
        }
        return false
    }

    /// Lines that are only a time, e.g. "13:45", "13:45:20"
    private func looksLikeTimeOnly(_ text: String) -> Bool {
        Self.timeOnlyRegex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}
