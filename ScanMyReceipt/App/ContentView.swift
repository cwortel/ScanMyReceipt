import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationView {
            CollectionListView()
        }
        .navigationViewStyle(.stack)
    }
}