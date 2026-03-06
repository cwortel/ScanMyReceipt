import Foundation
import Combine
import UIKit

/// Single source of truth for all receipt collections.
/// Passed via @EnvironmentObject from the app root.
class CollectionListViewModel: ObservableObject {
    @Published var collections: [ReceiptCollection] = []

    private let persistence = PersistenceService.shared

    init() {
        loadCollections()
    }

    func loadCollections() {
        collections = persistence.loadCollections()
            .sorted { $0.createdDate > $1.createdDate }
    }

    func save() {
        persistence.saveCollections(collections)
    }

    // MARK: - Collection CRUD

    func addCollection(name: String) {
        let collection = ReceiptCollection(name: name)
        collections.insert(collection, at: 0)
        save()
    }

    func deleteCollection(at offsets: IndexSet) {
        for index in offsets {
            let collection = collections[index]
            for receipt in collection.receipts {
                for fileName in receipt.imageFileNames {
                    persistence.deleteImage(fileName: fileName)
                }
            }
        }
        collections.remove(atOffsets: offsets)
        save()
    }

    func renameCollection(_ id: UUID, to newName: String) {
        guard let idx = collections.firstIndex(where: { $0.id == id }) else { return }
        collections[idx].name = newName
        save()
    }

    func collection(for id: UUID) -> ReceiptCollection? {
        collections.first { $0.id == id }
    }

    // MARK: - Receipt CRUD

    func addReceipt(_ receipt: Receipt, to collectionID: UUID, autoSave: Bool = true) {
        guard let idx = collections.firstIndex(where: { $0.id == collectionID }) else { return }
        collections[idx].receipts.append(receipt)
        if autoSave { save() }
    }

    func updateReceipt(_ receipt: Receipt, in collectionID: UUID) {
        guard let ci = collections.firstIndex(where: { $0.id == collectionID }),
              let ri = collections[ci].receipts.firstIndex(where: { $0.id == receipt.id }) else { return }
        collections[ci].receipts[ri] = receipt
        save()
    }

    func deleteReceipt(at offsets: IndexSet, in collectionID: UUID) {
        guard let ci = collections.firstIndex(where: { $0.id == collectionID }) else { return }
        for index in offsets {
            let receipt = collections[ci].receipts[index]
            for fileName in receipt.imageFileNames {
                persistence.deleteImage(fileName: fileName)
            }
        }
        collections[ci].receipts.remove(atOffsets: offsets)
        save()
    }

    // MARK: - Images

    func saveImages(_ images: [UIImage]) -> [String] {
        images.compactMap { image in
            let fileName = UUID().uuidString + ".jpg"
            return persistence.saveImage(image, fileName: fileName) ? fileName : nil
        }
    }

    // MARK: - Receipt Numbering

    func nextReceiptNumber(forCollectionID collectionID: UUID) -> String {
        guard let collection = collections.first(where: { $0.id == collectionID }) else { return "000-001" }
        return persistence.nextReceiptNumber(for: collection)
    }

    /// Renumbers all receipts in the collection sequentially (001, 002, …)
    /// using the collection’s current numbering format.
    func renumberReceipts(in collectionID: UUID) {
        guard let ci = collections.firstIndex(where: { $0.id == collectionID }) else { return }
        let collection = collections[ci]
        let prefix = collection.numberFormat.prefix(
            collectionName: collection.name,
            customPrefix: collection.customPrefix
        )
        for i in collections[ci].receipts.indices {
            collections[ci].receipts[i].receiptNumber = String(format: "%@-%03d", prefix, i + 1)
        }
        save()
    }

    /// Updates collection-level settings (format, prefix, tax).
    func updateCollectionSettings(_ collectionID: UUID, numberFormat: ReceiptNumberFormat, customPrefix: String, defaultTax: Double) {
        guard let ci = collections.firstIndex(where: { $0.id == collectionID }) else { return }
        collections[ci].numberFormat = numberFormat
        collections[ci].customPrefix = customPrefix
        collections[ci].defaultTaxPercentage = defaultTax
        save()
    }
}