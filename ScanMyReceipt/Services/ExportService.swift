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

                        // Reserve space for the receipt number label at the top
                        let labelHeight: CGFloat = 24.0
                        let labelSpacing: CGFloat = 8.0
                        let availableWidth = pageWidth - 2 * margin
                        let availableHeight = pageHeight - 2 * margin - labelHeight - labelSpacing
                        let imageAspect = image.size.width / image.size.height
                        let areaAspect = availableWidth / availableHeight

                        // Draw receipt number at top-left
                        let labelAttributes: [NSAttributedString.Key: Any] = [
                            .font: UIFont.boldSystemFont(ofSize: 14),
                            .foregroundColor: UIColor.darkGray
                        ]
                        let label = receipt.receiptNumber as NSString
                        label.draw(at: CGPoint(x: margin, y: margin), withAttributes: labelAttributes)

                        let imageTop = margin + labelHeight + labelSpacing
                        let drawRect: CGRect
                        if imageAspect > areaAspect {
                            let w = availableWidth
                            let h = w / imageAspect
                            drawRect = CGRect(x: margin, y: imageTop + (availableHeight - h) / 2, width: w, height: h)
                        } else {
                            let h = availableHeight
                            let w = h * imageAspect
                            drawRect = CGRect(x: margin + (availableWidth - w) / 2, y: imageTop, width: w, height: h)
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
            csv += [
                csvEscape(r.receiptNumber),
                csvEscape(r.shopName),
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

    // MARK: - UBL + PDF Export

    /// Generates paired UBL XML + PDF files for each receipt in the collection.
    /// Each receipt produces two files with matching base names:
    ///   - `Receipt_202603-001.xml`  (structured UBL 2.1 invoice)
    ///   - `Receipt_202603-001.pdf`  (receipt image)
    /// The UBL XML includes an `AdditionalDocumentReference` pointing to the
    /// PDF filename so bookkeeping systems can auto-link the two.
    func generateUBLFiles(for collection: ReceiptCollection) -> [URL] {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let tempDir = FileManager.default.temporaryDirectory
        var urls: [URL] = []

        for receipt in collection.receipts {
            let baseName = "Receipt_\(sanitize(receipt.receiptNumber))"
            let pdfFileName = "\(baseName).pdf"
            let xmlFileName = "\(baseName).xml"

            // Generate the receipt image PDF
            if let pdfData = singleReceiptPDFData(for: receipt) {
                let pdfURL = tempDir.appendingPathComponent(pdfFileName)
                do {
                    try pdfData.write(to: pdfURL)
                    urls.append(pdfURL)
                } catch {
                    print("Failed to write receipt PDF: \(error)")
                }
            }

            // Generate the UBL XML with a reference to the PDF
            let xml = ublInvoice(for: receipt, pdfFileName: pdfFileName, dateFormatter: df)
            let xmlURL = tempDir.appendingPathComponent(xmlFileName)
            do {
                try xml.write(to: xmlURL, atomically: true, encoding: .utf8)
                urls.append(xmlURL)
            } catch {
                print("Failed to write UBL XML: \(error)")
            }
        }
        return urls
    }

    /// Returns the UBL XML string for a single receipt (useful for testing).
    func ublXMLString(for receipt: Receipt) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let pdfFileName = "Receipt_\(sanitize(receipt.receiptNumber)).pdf"
        return ublInvoice(for: receipt, pdfFileName: pdfFileName, dateFormatter: df)
    }

    // MARK: - Single Receipt PDF

    /// Renders receipt images into a PDF Data object (one page per image).
    private func singleReceiptPDFData(for receipt: Receipt) -> Data? {
        let pageWidth: CGFloat = 595.28
        let pageHeight: CGFloat = 841.89
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let margin: CGFloat = 36.0

        let pdfMetaData: [String: Any] = [
            kCGPDFContextCreator as String: "ScanMyReceipt",
            kCGPDFContextTitle as String: receipt.receiptNumber
        ]
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMetaData

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        var hasPages = false

        let data = renderer.pdfData { context in
            for fileName in receipt.imageFileNames {
                autoreleasepool {
                    guard let image = persistence.loadImage(fileName: fileName) else { return }
                    hasPages = true
                    context.beginPage()

                    let labelHeight: CGFloat = 24.0
                    let labelSpacing: CGFloat = 8.0
                    let availableWidth = pageWidth - 2 * margin
                    let availableHeight = pageHeight - 2 * margin - labelHeight - labelSpacing
                    let imageAspect = image.size.width / image.size.height
                    let areaAspect = availableWidth / availableHeight

                    let labelAttributes: [NSAttributedString.Key: Any] = [
                        .font: UIFont.boldSystemFont(ofSize: 14),
                        .foregroundColor: UIColor.darkGray
                    ]
                    let label = receipt.receiptNumber as NSString
                    label.draw(at: CGPoint(x: margin, y: margin), withAttributes: labelAttributes)

                    let imageTop = margin + labelHeight + labelSpacing
                    let drawRect: CGRect
                    if imageAspect > areaAspect {
                        let w = availableWidth
                        let h = w / imageAspect
                        drawRect = CGRect(x: margin, y: imageTop + (availableHeight - h) / 2, width: w, height: h)
                    } else {
                        let h = availableHeight
                        let w = h * imageAspect
                        drawRect = CGRect(x: margin + (availableWidth - w) / 2, y: imageTop, width: w, height: h)
                    }
                    image.draw(in: drawRect)
                }
            }
        }

        return hasPages ? data : nil
    }

    // MARK: - UBL Invoice XML

    /// Generates a UBL 2.1 Invoice XML string compliant with Dutch/EU e-invoicing.
    /// Includes an `AdditionalDocumentReference` that links to the paired PDF file.
    private func ublInvoice(for r: Receipt, pdfFileName: String, dateFormatter df: DateFormatter) -> String {
        let tax = r.totalAmount - r.amountWithoutTax
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <Invoice xmlns="urn:oasis:names:specification:ubl:schema:xsd:Invoice-2"
                 xmlns:cac="urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2"
                 xmlns:cbc="urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2">
            <cbc:CustomizationID>urn:cen.eu:en16931:2017#compliant#urn:fdc:nen.nl:nlcius:v1.0</cbc:CustomizationID>
            <cbc:ProfileID>urn:fdc:peppol.eu:2017:poacc:billing:01:1.0</cbc:ProfileID>
            <cbc:ID>\(esc(r.receiptNumber))</cbc:ID>
            <cbc:IssueDate>\(df.string(from: r.purchaseDate))</cbc:IssueDate>
            <cbc:InvoiceTypeCode>380</cbc:InvoiceTypeCode>
            <cbc:DocumentCurrencyCode>EUR</cbc:DocumentCurrencyCode>
            <cac:AdditionalDocumentReference>
                <cbc:ID>\(esc(r.receiptNumber))-img</cbc:ID>
                <cbc:DocumentDescription>Receipt image</cbc:DocumentDescription>
                <cac:Attachment>
                    <cbc:EmbeddedDocumentBinaryObject mimeCode="application/pdf" filename="\(esc(pdfFileName))"/>
                    <cac:ExternalReference>
                        <cbc:URI>\(esc(pdfFileName))</cbc:URI>
                    </cac:ExternalReference>
                </cac:Attachment>
            </cac:AdditionalDocumentReference>
            <cac:AccountingSupplierParty>
                <cac:Party>
                    <cac:PartyName>
                        <cbc:Name>\(esc(r.shopName))</cbc:Name>
                    </cac:PartyName>
                    <cac:PostalAddress>
                        <cac:Country>
                            <cbc:IdentificationCode>NL</cbc:IdentificationCode>
                        </cac:Country>
                    </cac:PostalAddress>
                </cac:Party>
            </cac:AccountingSupplierParty>
            <cac:AccountingCustomerParty>
                <cac:Party>
                    <cac:PartyName>
                        <cbc:Name>—</cbc:Name>
                    </cac:PartyName>
                    <cac:PostalAddress>
                        <cac:Country>
                            <cbc:IdentificationCode>NL</cbc:IdentificationCode>
                        </cac:Country>
                    </cac:PostalAddress>
                </cac:Party>
            </cac:AccountingCustomerParty>
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
                <cbc:LineExtensionAmount currencyID="EUR">\(fmt(r.amountWithoutTax))</cbc:LineExtensionAmount>
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
                    <cac:ClassifiedTaxCategory>
                        <cbc:ID>S</cbc:ID>
                        <cbc:Percent>\(String(format: "%.1f", r.taxPercentage))</cbc:Percent>
                        <cac:TaxScheme>
                            <cbc:ID>VAT</cbc:ID>
                        </cac:TaxScheme>
                    </cac:ClassifiedTaxCategory>
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

    /// RFC 4180–compliant CSV field escaping.
    private func csvEscape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
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
