import SwiftUI

/// Identifiable wrapper for share-sheet URLs.
/// Using `.sheet(item:)` instead of `.sheet(isPresented:)` ensures the
/// activity items are available when UIActivityViewController is created,
/// preventing the blank-sheet bug.
struct ShareableItems: Identifiable {
    let id = UUID()
    let urls: [URL]
}

/// Wraps UIActivityViewController for sharing files via the system share sheet.
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
