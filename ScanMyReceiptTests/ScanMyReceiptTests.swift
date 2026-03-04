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
        let number = service.nextReceiptNumber(receiptsInCollection: [], collectionName: "Test")
        let prefix = AppSettings.shared.receiptNumberFormat.prefix(collectionName: "Test")
        XCTAssertEqual(number, "\(prefix)-001")
    }

    func testNextReceiptNumberIncrement() {
        let prefix = AppSettings.shared.receiptNumberFormat.prefix(collectionName: "Test")
        let receipts = [
            Receipt(receiptNumber: "\(prefix)-001"),
            Receipt(receiptNumber: "\(prefix)-003")
        ]
        let number = PersistenceService.shared.nextReceiptNumber(receiptsInCollection: receipts, collectionName: "Test")
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

    // MARK: - UBL / Factur-X Export

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
}
