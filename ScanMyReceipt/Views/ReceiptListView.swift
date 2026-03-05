import SwiftUI

/// Shows all receipt collections. The user can create a new collection or tap an existing one.
struct CollectionListView: View {
    @EnvironmentObject var viewModel: CollectionListViewModel
    @State private var showingNewCollection = false
    @State private var newCollectionName = ""
    @State private var renamingCollection: ReceiptCollection?
    @State private var renameText = ""
    @State private var showingSplash = false

    var body: some View {
        VStack(spacing: 0) {
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
                    .swipeActions(edge: .leading) {
                        Button {
                            renameText = collection.name
                            renamingCollection = collection
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                }
                .onDelete(perform: viewModel.deleteCollection)

                if viewModel.collections.isEmpty {
                    VStack(spacing: 16) {
                        Text("No collections yet")
                            .font(.title3.weight(.semibold))
                        Text("A collection groups your receipts — for example by trip, event, or period.\n\nTap + to create a new collection.\nSelect a collection to start scanning your receipts.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 16)
                    .padding(.horizontal)
                    .listRowBackground(Color.clear)
                }
            }

            // Static footer — always pinned at bottom
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 100)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color(.systemGroupedBackground))
                .onTapGesture { showingSplash = true }
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
        .alert("Rename Collection", isPresented: Binding(
            get: { renamingCollection != nil },
            set: { if !$0 { renamingCollection = nil } }
        )) {
            TextField("Collection name", text: $renameText)
            Button("Save") {
                let name = renameText.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty, let collection = renamingCollection {
                    viewModel.renameCollection(collection.id, to: name)
                }
                renamingCollection = nil
            }
            Button("Cancel", role: .cancel) {
                renamingCollection = nil
            }
        }
        .fullScreenCover(isPresented: $showingSplash) {
            SplashScreenView(onDismiss: {
                showingSplash = false
            })
        }
    }
}