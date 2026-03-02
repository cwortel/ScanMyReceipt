import Foundation
import UIKit

class ExportService {
    static let shared = ExportService()
    private let persistence = PersistenceService.shared

    // MARK: - PDF Generation

    /// Generates a single PDF containing all receipt images in the collection (A4 pages).
    func generatePDF(for collection: ReceiptCollection) -> URL? {
        let pageWidth: CGFloat = 595.28   // A4 in points
        let pageHeight: CGFloat = 841.89
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let margin: CGFloat = 36.0

        let pdfMetaData: [String: Any] = [
            kCGPDFContextCreator as String: "ScanMyReceipt",
            kCGPDFContextTitle as String: collection.name
        ]
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMetaData

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

        var hasPages = false
        let data = renderer.pdfData { context in
            for receipt in collection.receipts {
                for fileName in receipt.imageFileNames {
                    // Use autoreleasepool to free each image after drawing
                    autoreleasepool {
                        guard let image = persistence.loadImage(fileName: fileName) else { return }
                        hasPages = true
                        context.beginPage()

                        let availableWidth = pageWidth - 2 * margin
                        let availableHeight = pageHeight - 2 * margin
                        let imageAspect = image.size.width / image.size.height
                        let areaAspect = availableWidth / availableHeight

                        let drawRect: CGRect
                        if imageAspect > areaAspect {
                            let w = availableWidth
                            let h = w / imageAspect
                            drawRect = CGRect(x: margin, y: margin + (availableHeight - h) / 2, width: w, height: h)
                        } else {
                            let h = availableHeight
                            let w = h * imageAspect
                            drawRect = CGRect(x: margin + (availableWidth - w) / 2, y: margin, width: w, height: h)
                        }
                        image.draw(in: drawRect)
                    }
                }
            }
        }

        guard hasPages else { return nil }

        let fileName = "\(sanitize(collection.name))_receipts.pdf"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: fileURL)
            return fileURL
        } catch {
            print("Failed to write PDF: \(error)")
            return nil
        }
    }

    // MARK: - CSV Generation

    /// Generates a CSV file with receipt data (comma-separated, dot decimals).
    func generateCSV(for collection: ReceiptCollection) -> URL? {
        var csv = "Receipt Number,Shop Name,Date,Total Amount,Amount Without Tax,Tax Percentage\n"

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"

        for r in collection.receipts {
            let shop = r.shopName.contains(",") ? "\"\(r.shopName)\"" : r.shopName
            csv += [
                r.receiptNumber,
                shop,
                df.string(from: r.purchaseDate),
                String(format: "%.2f", r.totalAmount),
                String(format: "%.2f", r.amountWithoutTax),
                String(format: "%.1f", r.taxPercentage)
            ].joined(separator: ",") + "\n"
        }

        let fileName = "\(sanitize(collection.name)).csv"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try csv.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            print("Failed to write CSV: \(error)")
            return nil
        }
    }

    // MARK: - UBL Generation

    /// Generates one UBL 2.1 Invoice XML file per receipt. Returns the file URLs.
    func generateUBLFiles(for collection: ReceiptCollection) -> [URL] {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let tempDir = FileManager.default.temporaryDirectory
        var urls: [URL] = []

        for receipt in collection.receipts {
            let xml = ublInvoice(for: receipt, dateFormatter: df)
            let fileName = "UBL_\(sanitize(receipt.receiptNumber)).xml"
            let fileURL = tempDir.appendingPathComponent(fileName)
            do {
                try xml.write(to: fileURL, atomically: true, encoding: .utf8)
                urls.append(fileURL)
            } catch {
                print("Failed to write UBL for \(receipt.receiptNumber): \(error)")
            }
        }
        return urls
    }

    // MARK: - UBL Invoice XML

    private func ublInvoice(for r: Receipt, dateFormatter df: DateFormatter) -> String {
        let tax = r.totalAmount - r.amountWithoutTax
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <Invoice xmlns="urn:oasis:names:specification:ubl:schema:xsd:Invoice-2"
                 xmlns:cac="urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2"
                 xmlns:cbc="urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2">
            <cbc:UBLVersionID>2.1</cbc:UBLVersionID>
            <cbc:ID>\(esc(r.receiptNumber))</cbc:ID>
            <cbc:IssueDate>\(df.string(from: r.purchaseDate))</cbc:IssueDate>
            <cbc:InvoiceTypeCode>380</cbc:InvoiceTypeCode>
            <cbc:DocumentCurrencyCode>EUR</cbc:DocumentCurrencyCode>
            <cac:AccountingSupplierParty>
                <cac:Party>
                    <cac:PartyName>
                        <cbc:Name>\(esc(r.shopName))</cbc:Name>
                    </cac:PartyName>
                </cac:Party>
            </cac:AccountingSupplierParty>
            <cac:TaxTotal>
                <cbc:TaxAmount currencyID="EUR">\(fmt(tax))</cbc:TaxAmount>
                <cac:TaxSubtotal>
                    <cbc:TaxableAmount currencyID="EUR">\(fmt(r.amountWithoutTax))</cbc:TaxableAmount>
                    <cbc:TaxAmount currencyID="EUR">\(fmt(tax))</cbc:TaxAmount>
                    <cac:TaxCategory>
                        <cbc:ID>S</cbc:ID>
                        <cbc:Percent>\(String(format: "%.1f", r.taxPercentage))</cbc:Percent>
                        <cac:TaxScheme>
                            <cbc:ID>VAT</cbc:ID>
                        </cac:TaxScheme>
                    </cac:TaxCategory>
                </cac:TaxSubtotal>
            </cac:TaxTotal>
            <cac:LegalMonetaryTotal>
                <cbc:TaxExclusiveAmount currencyID="EUR">\(fmt(r.amountWithoutTax))</cbc:TaxExclusiveAmount>
                <cbc:TaxInclusiveAmount currencyID="EUR">\(fmt(r.totalAmount))</cbc:TaxInclusiveAmount>
                <cbc:PayableAmount currencyID="EUR">\(fmt(r.totalAmount))</cbc:PayableAmount>
            </cac:LegalMonetaryTotal>
            <cac:InvoiceLine>
                <cbc:ID>1</cbc:ID>
                <cbc:InvoicedQuantity unitCode="EA">1</cbc:InvoicedQuantity>
                <cbc:LineExtensionAmount currencyID="EUR">\(fmt(r.amountWithoutTax))</cbc:LineExtensionAmount>
                <cac:Item>
                    <cbc:Name>Purchase at \(esc(r.shopName))</cbc:Name>
                </cac:Item>
                <cac:Price>
                    <cbc:PriceAmount currencyID="EUR">\(fmt(r.amountWithoutTax))</cbc:PriceAmount>
                </cac:Price>
            </cac:InvoiceLine>
        </Invoice>
        """
    }

    // MARK: - Helpers

    private func fmt(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func sanitize(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return String(name.unicodeScalars.filter { allowed.contains($0) }.map { Character($0) })
    }

    private func esc(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "'", with: "&apos;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
