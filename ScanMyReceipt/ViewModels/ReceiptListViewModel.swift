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
    }

    func save() {
        persistence.saveCollections(collections)
    }

    // MARK: - Collection CRUD

    func addCollection(name: String) {
        let collection = ReceiptCollection(name: name)
        collections.append(collection)
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

    func collection(for id: UUID) -> ReceiptCollection? {
        collections.first { $0.id == id }
    }

    // MARK: - Receipt CRUD

    func addReceipt(_ receipt: Receipt, to collectionID: UUID) {
        guard let idx = collections.firstIndex(where: { $0.id == collectionID }) else { return }
        collections[idx].receipts.append(receipt)
        save()
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

    func nextReceiptNumber() -> String {
        persistence.nextReceiptNumber(existingCollections: collections)
    }
}