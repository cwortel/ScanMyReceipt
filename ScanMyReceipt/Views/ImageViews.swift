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

// MARK: - FullScreenImageView

/// Full-screen image viewer with pinch-to-zoom and drag-to-pan.
struct FullScreenImageView: View {
    let fileName: String
    @Environment(\.dismiss) private var dismiss

    @State private var image: UIImage?
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = lastScale * value
                            }
                            .onEnded { value in
                                lastScale = scale
                                if scale < 1.0 {
                                    withAnimation { scale = 1.0 }
                                    lastScale = 1.0
                                }
                            }
                    )
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { value in
                                offset = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                            }
                            .onEnded { _ in
                                lastOffset = offset
                                if scale <= 1.0 {
                                    withAnimation {
                                        offset = .zero
                                        lastOffset = .zero
                                    }
                                }
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation {
                            if scale > 1.0 {
                                scale = 1.0
                                lastScale = 1.0
                                offset = .zero
                                lastOffset = .zero
                            } else {
                                scale = 3.0
                                lastScale = 3.0
                            }
                        }
                    }
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.6))
            }
            .padding()
        }
        .onAppear { loadFullImage() }
    }

    private func loadFullImage() {
        DispatchQueue.global(qos: .userInitiated).async {
            let full = PersistenceService.shared.loadImage(fileName: fileName)
            DispatchQueue.main.async {
                self.image = full
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
