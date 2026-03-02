import SwiftUI

@main
struct ScanMyReceiptApp: App {
    @StateObject private var viewModel = CollectionListViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
        }
    }
}