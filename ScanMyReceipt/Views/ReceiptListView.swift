import SwiftUI

/// Shows all receipt collections. The user can create a new collection or tap an existing one.
struct CollectionListView: View {
    @EnvironmentObject var viewModel: CollectionListViewModel
    @State private var showingNewCollection = false
    @State private var newCollectionName = ""

    var body: some View {
        List {
            ForEach(viewModel.collections) { collection in
                NavigationLink(destination: CollectionDetailView(collectionID: collection.id)) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(collection.name)
                            .font(.headline)
                        HStack {
                            Text("\(collection.receipts.count) receipt(s)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(collection.createdDate, style: .date)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .onDelete(perform: viewModel.deleteCollection)

            if viewModel.collections.isEmpty {
                Text("No collections yet.\nTap + to create one.")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
            }
        }
        .navigationTitle("Collections")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingNewCollection = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .alert("New Collection", isPresented: $showingNewCollection) {
            TextField("Collection name", text: $newCollectionName)
            Button("Create") {
                let name = newCollectionName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    viewModel.addCollection(name: name)
                    newCollectionName = ""
                }
            }
            Button("Cancel", role: .cancel) {
                newCollectionName = ""
            }
        }
    }
}