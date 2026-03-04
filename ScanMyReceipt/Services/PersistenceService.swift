import Foundation
import UIKit

class PersistenceService {
    static let shared = PersistenceService()

    private let fileManager = FileManager.default

    /// In-memory thumbnail cache using NSCache (auto-evicts under memory pressure).
    private let thumbnailCache = NSCache<NSString, UIImage>()

    private init() {
        // Limit cache: max 100 thumbnails, ~50 MB
        thumbnailCache.countLimit = 100
        thumbnailCache.totalCostLimit = 50 * 1024 * 1024
    }

    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var collectionsFileURL: URL {
        documentsDirectory.appendingPathComponent("collections.json")
    }

    /// Cached images directory URL. Created once on first access.
    lazy var imagesDirectory: URL = {
        let dir = documentsDirectory.appendingPathComponent("ReceiptImages")
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    // MARK: - Collections

    func saveCollections(_ collections: [ReceiptCollection]) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(collections)
            try data.write(to: collectionsFileURL)
        } catch {
            print("Failed to save collections: \(error)")
        }
    }

    func loadCollections() -> [ReceiptCollection] {
        guard fileManager.fileExists(atPath: collectionsFileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: collectionsFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([ReceiptCollection].self, from: data)
        } catch {
            print("Failed to load collections: \(error)")
            return []
        }
    }

    // MARK: - Images

    /// Downscale to a reasonable resolution before saving to avoid
    /// storing 12+ MP images from the document scanner.
    @discardableResult
    func saveImage(_ image: UIImage, fileName: String, maxDimension: CGFloat = 2000) -> Bool {
        let scaled = downsample(image, maxDimension: maxDimension)
        guard let data = scaled.jpegData(compressionQuality: 0.7) else { return false }
        let fileURL = imagesDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: fileURL)
            return true
        } catch {
            print("Failed to save image: \(error)")
            return false
        }
    }

    private func downsample(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let longer = max(size.width, size.height)
        guard longer > maxDimension else { return image }
        let scale = maxDimension / longer
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    func loadImage(fileName: String) -> UIImage? {
        let fileURL = imagesDirectory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return UIImage(data: data)
    }

    /// Returns a downscaled thumbnail, cached in NSCache.
    func loadThumbnail(fileName: String, maxDimension: CGFloat = 100) -> UIImage? {
        let cacheKey = "\(fileName)_\(Int(maxDimension))" as NSString
        if let cached = thumbnailCache.object(forKey: cacheKey) {
            return cached
        }
        let fileURL = imagesDirectory.appendingPathComponent(fileName)
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let thumb = UIImage(cgImage: cgImage)
        thumbnailCache.setObject(thumb, forKey: cacheKey, cost: Int(maxDimension * maxDimension * 4))
        return thumb
    }

    /// Loads a preview-sized image (e.g. for the edit form). Not full res.
    func loadPreviewImage(fileName: String, maxDimension: CGFloat = 800) -> UIImage? {
        let fileURL = imagesDirectory.appendingPathComponent(fileName)
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    func deleteImage(fileName: String) {
        let fileURL = imagesDirectory.appendingPathComponent(fileName)
        try? fileManager.removeItem(at: fileURL)
    }

    // MARK: - Receipt Numbering

    /// Generates the next receipt number using the configured format.
    func nextReceiptNumber(existingCollections: [ReceiptCollection]) -> String {
        let format = AppSettings.shared.receiptNumberFormat
        let prefix = format.prefix()

        var maxNumber = 0
        for collection in existingCollections {
            for receipt in collection.receipts {
                if receipt.receiptNumber.hasPrefix(prefix + "-") {
                    let suffix = receipt.receiptNumber.replacingOccurrences(of: prefix + "-", with: "")
                    if let num = Int(suffix) {
                        maxNumber = max(maxNumber, num)
                    }
                }
            }
        }

        return String(format: "%@-%03d", prefix, maxNumber + 1)
    }
}