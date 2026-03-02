import SwiftUI

// MARK: - ThumbnailView

/// Loads a small cached thumbnail asynchronously. Ideal for List rows.
struct ThumbnailView: View {
    let fileName: String?
    let size: CGFloat

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipped()
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: size, height: size)
                    .overlay(Image(systemName: "receipt").foregroundColor(.gray))
            }
        }
        .onAppear { loadThumbnail() }
    }

    private func loadThumbnail() {
        guard let fileName = fileName else { return }
        // Load on a background queue; NSCache makes repeat loads instant
        DispatchQueue.global(qos: .userInitiated).async {
            let thumb = PersistenceService.shared.loadThumbnail(
                fileName: fileName,
                maxDimension: size * UIScreen.main.scale
            )
            DispatchQueue.main.async {
                self.image = thumb
            }
        }
    }
}

// MARK: - PreviewImageView

/// Loads a medium-resolution preview asynchronously. Used in edit forms and galleries.
struct PreviewImageView: View {
    let fileName: String
    /// If nil, the image fills available space with scaledToFit.
    let height: CGFloat?

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .if(height != nil) { view in
                        view.frame(height: height!)
                    }
                    .cornerRadius(8)
            } else {
                ProgressView()
                    .frame(height: height ?? 200)
                    .frame(maxWidth: .infinity)
            }
        }
        .onAppear { loadPreview() }
    }

    private func loadPreview() {
        DispatchQueue.global(qos: .userInitiated).async {
            let preview = PersistenceService.shared.loadPreviewImage(
                fileName: fileName,
                maxDimension: 800
            )
            DispatchQueue.main.async {
                self.image = preview
            }
        }
    }
}

// MARK: - Conditional modifier helper

private extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
