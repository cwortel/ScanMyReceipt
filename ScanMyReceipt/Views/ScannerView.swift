import SwiftUI

/// Full-screen gallery for viewing receipt images (swipe between pages).
/// Loads preview-sized images lazily to avoid holding all full-res images in memory.
struct ReceiptImageGallery: View {
    let imageFileNames: [String]

    var body: some View {
        TabView {
            ForEach(imageFileNames, id: \.self) { fileName in
                PreviewImageView(fileName: fileName, height: nil)
                    .padding()
            }
        }
        .tabViewStyle(.page)
        .indexViewStyle(.page(backgroundDisplayMode: .always))
    }
}