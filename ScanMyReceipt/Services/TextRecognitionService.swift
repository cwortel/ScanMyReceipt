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
    private func extractShopName(from lines: [String]) -> String? {
        for line in lines.prefix(8) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 2,
                  !looksLikeAmount(trimmed),
                  !looksLikeDate(trimmed),
                  !looksLikeAddress(trimmed),
                  !looksLikePhoneNumber(trimmed),
                  !looksLikeNumericCode(trimmed),
                  !looksLikeReceiptKeyword(trimmed),
                  !looksLikeOrderOrTableLine(trimmed),
                  !looksLikeTimeOnly(trimmed) else { continue }

            // Strip leading digits/punctuation that OCR may prepend (e.g. "1 Cirilo" → "Cirilo")
            let cleaned = trimmed.replacingOccurrences(
                of: "^[\\d#*\\-\\.\\s]+",
                with: "",
                options: .regularExpression
            )
            // After stripping, must still have at least 2 meaningful characters
            guard cleaned.count >= 2 else { continue }
            return cleaned
        }
        return nil
    }

    /// Tries several date formats common on Dutch & EU receipts.
    private func extractDate(from text: String) -> Date? {
        let patterns: [(regex: String, formats: [String])] = [
            // DD-MM-YYYY, DD/MM/YYYY, DD.MM.YYYY
            ("(\\d{2})[\\-/\\.](\\d{2})[\\-/\\.](\\d{4})",
             ["dd-MM-yyyy", "dd/MM/yyyy", "dd.MM.yyyy"]),
            // YYYY-MM-DD
            ("(\\d{4})[\\-/\\.](\\d{2})[\\-/\\.](\\d{2})",
             ["yyyy-MM-dd", "yyyy/MM/dd", "yyyy.MM.dd"]),
            // DD-MM-YY
            ("\\b(\\d{2})[\\-/\\.](\\d{2})[\\-/\\.](\\d{2})\\b",
             ["dd-MM-yy", "dd/MM/yy", "dd.MM.yy"]),
        ]

        for (pattern, formats) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            // Check all matches — the first match might be a phone number or code
            let matches = regex.matches(in: text, range: range)
            for match in matches {
                guard let matchRange = Range(match.range, in: text) else { continue }
                let matchStr = String(text[matchRange])
                for fmt in formats {
                    let df = DateFormatter()
                    df.dateFormat = fmt
                    df.locale = Locale(identifier: "nl_NL")
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

        // Explicit keyword + percentage combos (handles both "21%" and "21,00%")
        let patterns: [(String, Double)] = [
            ("btw\\s*(?:hoog)?\\s*21", 21.0),
            ("21[,.]?\\d*\\s*%\\s*btw", 21.0),
            ("btw\\s*21[,.]?\\d*\\s*%", 21.0),
            ("btw\\s*(?:laag)?\\s*9", 9.0),
            ("9[,.]00\\s*%", 9.0),
            ("9\\s*%\\s*btw", 9.0),
            ("btw\\s*9[,.]?\\d*\\s*%", 9.0),
            ("btw\\s*0", 0.0),
            ("0[,.]?\\d*\\s*%\\s*btw", 0.0),
            ("vat\\s*21", 21.0),
            ("21[,.]?\\d*\\s*%\\s*vat", 21.0),
            ("vat\\s*9", 9.0),
            ("9[,.]?\\d*\\s*%\\s*vat", 9.0),
        ]

        for (pattern, pct) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)) != nil {
                return pct
            }
        }

        // Generic: look for percentage near BTW/VAT keywords.
        // Handles both "9%" and "9,00%" comma-decimal formats.
        if lower.contains("btw") || lower.contains("vat") {
            let pctPattern = "(\\d{1,2})[,.]?\\d*\\s*%"
            if let regex = try? NSRegularExpression(pattern: pctPattern),
               let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
               let range = Range(match.range(at: 1), in: lower) {
                if let pct = Double(String(lower[range])), [0, 9, 21].contains(Int(pct)) {
                    return pct
                }
            }
        }

        // Also look for "tarief" (Dutch for rate/tariff) lines like "9,00% A"
        let tariefPattern = "(?:tarief|rate).*?(\\d{1,2})[,.]\\d+\\s*%"
        if let regex = try? NSRegularExpression(pattern: tariefPattern),
           let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
           let range = Range(match.range(at: 1), in: lower) {
            if let pct = Double(String(lower[range])), [0, 9, 21].contains(Int(pct)) {
                return pct
            }
        }

        return nil
    }

    // MARK: - Amount Parsing

    /// Extracts a monetary amount from a line of text, handling both
    /// Dutch (comma-decimal) and English (dot-decimal) formats.
    private func extractAmount(from text: String) -> Double? {
        let patterns = [
            "€\\s*([\\d.]+,\\d{2})",         // €1.234,56  or €12,34
            "€\\s*([\\d,]+\\.\\d{2})",        // €1,234.56  or €12.34
            "EUR\\s*([\\d.]+,\\d{2})",
            "EUR\\s*([\\d,]+\\.\\d{2})",
            "([\\d.]+,\\d{2})\\s*€",
            "([\\d,]+\\.\\d{2})\\s*€",
            "\\b(\\d+,\\d{2})\\b",            // bare 12,34
            "\\b(\\d+\\.\\d{2})\\b",          // bare 12.34
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: 1), in: text) else { continue }
            let raw = String(text[range])
            if let amount = normalizeAmount(raw), amount > 0 {
                return amount
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
        let pattern = "^[€$]?\\s*\\d+[,.]\\d{2}$"
        return (try? NSRegularExpression(pattern: pattern))?
            .firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private func looksLikeDate(_ text: String) -> Bool {
        // Matches "DD-MM-YYYY", "DD-MM-YYYY, HH:MM:SS", etc.
        let pattern = "^\\d{2}[\\-/\\.]\\d{2}[\\-/\\.]\\d{2,4}(\\s*[,.]?\\s*\\d{2}[:\\.\\-]\\d{2}(:\\d{2})?)?$"
        return (try? NSRegularExpression(pattern: pattern))?
            .firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private func looksLikeAddress(_ text: String) -> Bool {
        let lower = text.lowercased()
        // Dutch postal code: 1234 AB
        let postalPattern = "\\b\\d{4}\\s*[a-z]{2}\\b"
        if let regex = try? NSRegularExpression(pattern: postalPattern),
           regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)) != nil {
            return true
        }
        // Street address: word + number (e.g. "Vleutenseweg 169")
        let streetPattern = "^[a-zA-Z]+\\s+\\d{1,5}$"
        if let regex = try? NSRegularExpression(pattern: streetPattern),
           regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
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
        let patterns = [
            "^(tafel|table|order|bestelling|bon|nr\\.?|#)\\s*\\d+",  // "Tafel 1", "Order 42", "#123"
            "^\\d{1,3}$",                                             // just a bare number like "1", "42"
            "^\\d{1,3}\\s+\\w{1,3}$",                                // "1 st", "2 x"
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)) != nil {
                return true
            }
        }
        return false
    }

    /// Lines that are only a time, e.g. "13:45", "13:45:20"
    private func looksLikeTimeOnly(_ text: String) -> Bool {
        let pattern = "^\\d{1,2}[:\\.]\\d{2}([:\\.]\\d{2})?$"
        return (try? NSRegularExpression(pattern: pattern))?
            .firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}
