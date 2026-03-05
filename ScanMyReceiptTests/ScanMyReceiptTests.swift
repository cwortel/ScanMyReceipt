import XCTest
@testable import ScanMyReceipt

final class ScanMyReceiptTests: XCTestCase {

    // MARK: - Receipt Model

    func testReceiptTaxAmount() {
        var receipt = Receipt()
        receipt.totalAmount = 12.10
        receipt.amountWithoutTax = 10.00
        receipt.taxPercentage = 21.0
        XCTAssertEqual(receipt.taxAmount, 2.10, accuracy: 0.001)
    }

    func testReceiptDefaultTax() {
        let receipt = Receipt()
        XCTAssertEqual(receipt.taxPercentage, 21.0)
    }

    // MARK: - Receipt Numbering

    func testNextReceiptNumberEmpty() {
        let service = PersistenceService.shared
        let collection = ReceiptCollection(name: "Test", receipts: [])
        let number = service.nextReceiptNumber(for: collection)
        let prefix = collection.numberFormat.prefix(collectionName: "Test", customPrefix: collection.customPrefix)
        XCTAssertEqual(number, "\(prefix)-001")
    }

    func testNextReceiptNumberIncrement() {
        let format = ReceiptNumberFormat.yearMonth
        let prefix = format.prefix(collectionName: "Test")
        let collection = ReceiptCollection(
            name: "Test",
            receipts: [
                Receipt(receiptNumber: "\(prefix)-001"),
                Receipt(receiptNumber: "\(prefix)-003")
            ]
        )
        let number = PersistenceService.shared.nextReceiptNumber(for: collection)
        XCTAssertEqual(number, "\(prefix)-004")
    }

    // MARK: - CSV Export

    func testCSVGeneration() {
        var receipt = Receipt()
        receipt.receiptNumber = "202603-001"
        receipt.shopName = "Albert Heijn"
        receipt.totalAmount = 12.10
        receipt.amountWithoutTax = 10.00
        receipt.taxPercentage = 21.0

        let collection = ReceiptCollection(name: "Test", receipts: [receipt])
        let url = ExportService.shared.generateCSV(for: collection)
        XCTAssertNotNil(url)

        if let url = url, let csv = try? String(contentsOf: url, encoding: .utf8) {
            XCTAssertTrue(csv.contains("Receipt Number,Shop Name"))
            XCTAssertTrue(csv.contains("202603-001"))
            XCTAssertTrue(csv.contains("Albert Heijn"))
            XCTAssertTrue(csv.contains("12.10"))
        }
    }

    // MARK: - UBL Export

    func testUBLXMLContent() {
        var receipt = Receipt()
        receipt.receiptNumber = "202603-001"
        receipt.shopName = "Jumbo"
        receipt.totalAmount = 24.20
        receipt.amountWithoutTax = 20.00
        receipt.taxPercentage = 21.0

        let xml = ExportService.shared.ublXMLString(for: receipt)
        XCTAssertTrue(xml.contains("<cbc:ID>202603-001</cbc:ID>"))
        XCTAssertTrue(xml.contains("<cbc:Name>Jumbo</cbc:Name>"))
        XCTAssertTrue(xml.contains("PayableAmount"))
        XCTAssertTrue(xml.contains("24.20"))
        // NLCIUS customization ID
        XCTAssertTrue(xml.contains("nlcius"))
        // PDF reference
        XCTAssertTrue(xml.contains("Receipt_202603-001.pdf"))
    }

    // MARK: - Collection ViewModel

    func testAddAndDeleteCollection() {
        let vm = CollectionListViewModel()
        let initial = vm.collections.count
        vm.addCollection(name: "Unit Test Collection")
        XCTAssertEqual(vm.collections.count, initial + 1)
        XCTAssertEqual(vm.collections.last?.name, "Unit Test Collection")

        // Clean up
        if let last = vm.collections.indices.last {
            vm.deleteCollection(at: IndexSet(integer: last))
        }
        XCTAssertEqual(vm.collections.count, initial)
    }

    // MARK: - Tax Percentage Detection

    private func detectTax(_ text: String) -> Double? {
        TextRecognitionService.shared.parseReceiptData(from: text).taxPercentage
    }

    func testTaxDetection_btw21Percent() {
        XCTAssertEqual(detectTax("BTW 21%"), 21.0)
        XCTAssertEqual(detectTax("btw 21,00%"), 21.0)
        XCTAssertEqual(detectTax("21% BTW"), 21.0)
        XCTAssertEqual(detectTax("BTW hoog 21%"), 21.0)
    }

    func testTaxDetection_btw9Percent() {
        XCTAssertEqual(detectTax("BTW 9%"), 9.0)
        XCTAssertEqual(detectTax("9% BTW"), 9.0)
        XCTAssertEqual(detectTax("BTW laag 9%"), 9.0)
        XCTAssertEqual(detectTax("BTW 9,00%"), 9.0)
    }

    func testTaxDetection_btw0Percent() {
        XCTAssertEqual(detectTax("BTW 0%"), 0.0)
        XCTAssertEqual(detectTax("0% BTW"), 0.0)
    }

    func testTaxDetection_colonSeparator() {
        // Colons between keyword and number should be handled
        XCTAssertEqual(detectTax("BTW: 21%"), 21.0)
        XCTAssertEqual(detectTax("BTW: 9%"), 9.0)
        XCTAssertEqual(detectTax("BTW:21"), 21.0)
    }

    func testTaxDetection_hyphenSeparator() {
        XCTAssertEqual(detectTax("BTW-21"), 21.0)
        XCTAssertEqual(detectTax("BTW-9"), 9.0)
    }

    func testTaxDetection_btwDotted() {
        // B.T.W. format
        XCTAssertEqual(detectTax("B.T.W. 21%"), 21.0)
        XCTAssertEqual(detectTax("B.T.W. 9%"), 9.0)
    }

    func testTaxDetection_amountNotRate() {
        // "BTW 9,45" is a tax AMOUNT, not a 9% rate — should return nil
        XCTAssertNil(detectTax("BTW 9,45"))
        // "BTW 0,83" is a tax amount of €0.83, not 0%
        XCTAssertNil(detectTax("BTW 0,83"))
    }

    func testTaxDetection_genericFallback() {
        // Generic: text contains "btw" + a valid percentage somewhere
        XCTAssertEqual(detectTax("totaal incl. 21% btw"), 21.0)
        XCTAssertEqual(detectTax("inclusief btw\ntarief 9,00%"), 9.0)
    }

    func testTaxDetection_noMatch() {
        XCTAssertNil(detectTax("Total: 12,50"))
        XCTAssertNil(detectTax("Thank you for shopping"))
    }

    func testTaxDetection_multiLine() {
        // Number on the line below the keyword
        XCTAssertEqual(detectTax("BTW%\n21"), 21.0)
        XCTAssertEqual(detectTax("BTW%\n9"), 9.0)
        XCTAssertEqual(detectTax("BTW\n21%"), 21.0)
        // Number on the line above the keyword
        XCTAssertEqual(detectTax("9%\nBTW"), 9.0)
    }
}
