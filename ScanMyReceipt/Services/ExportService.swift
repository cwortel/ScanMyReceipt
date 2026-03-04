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

    // MARK: - Factur-X Generation (PDF + embedded UBL)

    /// Generates one Factur-X PDF per receipt.
    /// Each PDF contains the receipt image(s) with a UBL 2.1 XML file embedded as an attachment.
    func generateFacturXFiles(for collection: ReceiptCollection) -> [URL] {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let tempDir = FileManager.default.temporaryDirectory
        var urls: [URL] = []

        for receipt in collection.receipts {
            guard let basePDFData = singleReceiptPDFData(for: receipt) else { continue }
            let xml = ublInvoice(for: receipt, dateFormatter: df)
            let finalData = embedUBLInPDF(pdfData: basePDFData, ublXML: xml) ?? basePDFData

            let fileName = "FacturX_\(sanitize(receipt.receiptNumber)).pdf"
            let fileURL = tempDir.appendingPathComponent(fileName)
            do {
                try finalData.write(to: fileURL)
                urls.append(fileURL)
            } catch {
                print("Failed to write Factur-X: \(error)")
            }
        }
        return urls
    }

    /// Also exposes raw UBL XML for testing purposes.
    func ublXMLString(for receipt: Receipt) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return ublInvoice(for: receipt, dateFormatter: df)
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

    // MARK: - PDF + UBL Embedding

    /// Embeds UBL XML into an existing PDF via incremental update, creating a Factur-X compatible file.
    private func embedUBLInPDF(pdfData: Data, ublXML: String) -> Data? {
        guard let xmlBytes = ublXML.data(using: .utf8) else { return nil }

        // Parse the PDF structure using Latin-1 (preserves all bytes for binary content).
        guard let pdfString = String(data: pdfData, encoding: .isoLatin1) else { return nil }
        let nsString = pdfString as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)

        // Extract /Root object number from trailer
        let rootRegex = try! NSRegularExpression(pattern: #"/Root\s+(\d+)\s+0\s+R"#)
        guard let rootMatch = rootRegex.firstMatch(in: pdfString, range: fullRange),
              let rootRange = Range(rootMatch.range(at: 1), in: pdfString),
              let rootObjNum = Int(pdfString[rootRange]) else { return nil }

        // Extract /Size (total object count) from trailer
        let sizeRegex = try! NSRegularExpression(pattern: #"/Size\s+(\d+)"#)
        guard let sizeMatch = sizeRegex.firstMatch(in: pdfString, range: fullRange),
              let sizeRange = Range(sizeMatch.range(at: 1), in: pdfString),
              let objCount = Int(pdfString[sizeRange]) else { return nil }

        // Extract previous startxref offset
        let xrefRegex = try! NSRegularExpression(pattern: #"startxref\s+(\d+)"#)
        guard let xrefMatch = xrefRegex.firstMatch(in: pdfString, range: fullRange),
              let xrefRange = Range(xrefMatch.range(at: 1), in: pdfString),
              let prevXrefOffset = Int(pdfString[xrefRange]) else { return nil }

        // Find the catalog object and extract /Pages reference
        let catalogHeader = "\(rootObjNum) 0 obj"
        guard let catStart = pdfString.range(of: catalogHeader),
              let catEnd = pdfString.range(of: "endobj", range: catStart.upperBound..<pdfString.endIndex) else { return nil }
        let catalogContent = String(pdfString[catStart.lowerBound..<catEnd.upperBound])
        let nsCat = catalogContent as NSString

        let pagesRegex = try! NSRegularExpression(pattern: #"/Pages\s+(\d+)\s+0\s+R"#)
        guard let pagesMatch = pagesRegex.firstMatch(in: catalogContent, range: NSRange(location: 0, length: nsCat.length)),
              let pagesRange = Range(pagesMatch.range(at: 1), in: catalogContent),
              let pagesObjNum = Int(catalogContent[pagesRange]) else { return nil }

        // Preserve /Metadata reference if present
        let metaRegex = try! NSRegularExpression(pattern: #"/Metadata\s+(\d+)\s+0\s+R"#)
        var metadataClause = ""
        if let metaMatch = metaRegex.firstMatch(in: catalogContent, range: NSRange(location: 0, length: nsCat.length)),
           let metaRange = Range(metaMatch.range(at: 1), in: catalogContent),
           let metaObjNum = Int(catalogContent[metaRange]) {
            metadataClause = " /Metadata \(metaObjNum) 0 R"
        }

        // --- Build incremental update ---

        let xmlStreamObj  = objCount
        let filespecObj   = objCount + 1
        let namesObj      = objCount + 2
        let newCatalogObj = objCount + 3
        let newObjCount   = objCount + 4

        var appendData = Data()
        var xrefEntries: [(objNum: Int, offset: Int)] = []
        let baseOffset = pdfData.count

        func appendASCII(_ s: String) {
            appendData.append(Data(s.utf8))
        }

        // Object: EmbeddedFile stream (UBL XML)
        xrefEntries.append((xmlStreamObj, baseOffset + appendData.count))
        appendASCII("\(xmlStreamObj) 0 obj\n")
        appendASCII("<< /Type /EmbeddedFile /Subtype /text#2Fxml /Length \(xmlBytes.count) >>\n")
        appendASCII("stream\n")
        appendData.append(xmlBytes)
        appendASCII("\nendstream\n")
        appendASCII("endobj\n")

        // Object: Filespec
        xrefEntries.append((filespecObj, baseOffset + appendData.count))
        appendASCII("\(filespecObj) 0 obj\n")
        appendASCII("<< /Type /Filespec /F (facturx.xml) /UF (facturx.xml) /EF << /F \(xmlStreamObj) 0 R >> /AFRelationship /Data >>\n")
        appendASCII("endobj\n")

        // Object: Names dictionary with EmbeddedFiles
        xrefEntries.append((namesObj, baseOffset + appendData.count))
        appendASCII("\(namesObj) 0 obj\n")
        appendASCII("<< /EmbeddedFiles << /Names [(facturx.xml) \(filespecObj) 0 R] >> >>\n")
        appendASCII("endobj\n")

        // Object: New Catalog (replaces original, preserves /Pages and /Metadata)
        xrefEntries.append((newCatalogObj, baseOffset + appendData.count))
        appendASCII("\(newCatalogObj) 0 obj\n")
        appendASCII("<< /Type /Catalog /Pages \(pagesObjNum) 0 R\(metadataClause) /Names \(namesObj) 0 R /AF [\(filespecObj) 0 R] >>\n")
        appendASCII("endobj\n")

        // Cross-reference table
        let newXrefOffset = baseOffset + appendData.count
        appendASCII("xref\n")
        appendASCII("\(xmlStreamObj) 4\n")
        for entry in xrefEntries {
            appendASCII(String(format: "%010d 00000 n \n", entry.offset))
        }

        // Trailer
        appendASCII("trailer\n")
        appendASCII("<< /Size \(newObjCount) /Root \(newCatalogObj) 0 R /Prev \(prevXrefOffset) >>\n")
        appendASCII("startxref\n")
        appendASCII("\(newXrefOffset)\n")
        appendASCII("%%EOF\n")

        var result = pdfData
        result.append(appendData)
        return result
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
