import SwiftUI

/// Per-collection settings: numbering format, custom prefix, default tax, categories.
struct CollectionSettingsView: View {
    let collectionID: UUID
    @EnvironmentObject var viewModel: CollectionListViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var numberFormat: ReceiptNumberFormat = .yearMonth
    @State private var customPrefix: String = ""
    @State private var defaultTax: Int = 21
    @State private var showingRenumberConfirm = false
    @State private var categories: [String] = ReceiptCollection.defaultCategories
    @State private var newCategory: String = ""

    private var collection: ReceiptCollection? {
        viewModel.collection(for: collectionID)
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Receipt Numbering
                Section {
                    ForEach(ReceiptNumberFormat.allCases) { format in
                        Button {
                            numberFormat = format
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(format.displayName)
                                        .foregroundColor(.primary)
                                    Text("e.g. \(format.example(collectionName: collection?.name ?? "Collection", customPrefix: customPrefix))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if numberFormat == format {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                        .fontWeight(.semibold)
                                }
                            }
                        }
                    }

                    if numberFormat == .custom {
                        HStack {
                            Text("Prefix")
                            Spacer()
                            TextField("e.g. INV2026", text: $customPrefix)
                                .multilineTextAlignment(.trailing)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.characters)
                        }
                    }
                } header: {
                    Text("Receipt Numbering")
                } footer: {
                    switch numberFormat {
                    case .yearMonth:
                        Text("Prefix is auto-generated from the current year and month.")
                    case .collectionName:
                        Text("Uses the collection name as prefix, e.g. \"\(ReceiptNumberFormat.sanitizePrefix(collection?.name ?? "Collection"))-001\".")
                    case .custom:
                        Text("Receipts will be numbered as \(customPrefix.isEmpty ? "MY" : customPrefix)-001, -002, etc.")
                    }
                }

                // MARK: Renumber
                Section {
                    Button(role: .destructive) {
                        showingRenumberConfirm = true
                    } label: {
                        Label("Renumber All Receipts", systemImage: "arrow.trianglehead.2.clockwise")
                    }
                    .disabled(collection?.receipts.isEmpty ?? true)
                } footer: {
                    Text("Reassigns sequential numbers (001, 002, …) to all receipts in their current order.")
                }

                // MARK: Default Tax
                Section {
                    HStack(spacing: 0) {
                        taxButton(0)
                        taxButton(9)
                        taxButton(21)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } header: {
                    Text("Default Tax Percentage")
                } footer: {
                    Text("Pre-selected tax rate for newly scanned receipts. OCR may override this if it detects a tax rate on the receipt.")
                }

                // MARK: Categories
                Section {
                    ForEach(categories, id: \.self) { cat in
                        Text(cat)
                    }
                    .onDelete { offsets in
                        categories.remove(atOffsets: offsets)
                    }
                    .onMove { from, to in
                        categories.move(fromOffsets: from, toOffset: to)
                    }

                    HStack {
                        TextField("New category", text: $newCategory)
                            .autocorrectionDisabled()
                        Button {
                            let trimmed = newCategory.trimmingCharacters(in: .whitespaces)
                            guard !trimmed.isEmpty, !categories.contains(trimmed) else { return }
                            categories.append(trimmed)
                            newCategory = ""
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.accentColor)
                        }
                        .disabled(newCategory.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("Categories")
                } footer: {
                    Text("Swipe to delete, drag to reorder. Add custom categories for your receipts.")
                }
            }
            .navigationTitle("Collection Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        viewModel.updateCollectionSettings(
                            collectionID,
                            numberFormat: numberFormat,
                            customPrefix: customPrefix,
                            defaultTax: Double(defaultTax),
                            categories: categories
                        )
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .overlay {
                if showingRenumberConfirm {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture { showingRenumberConfirm = false }
                        .overlay {
                            VStack(spacing: 16) {
                                Text("Renumber Receipts")
                                    .font(.headline)

                                Text("This will reassign all receipt numbers using **\(numberFormat.displayName)** sequentially. This cannot be undone.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)

                                // Warning box with orange border
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                    Text("Previously exported files will not be updated.")
                                        .font(.callout)
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.orange.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.orange, lineWidth: 1.5)
                                )

                                Divider()

                                Button {
                                    // Save current settings first so renumber uses latest format
                                    viewModel.updateCollectionSettings(
                                        collectionID,
                                        numberFormat: numberFormat,
                                        customPrefix: customPrefix,
                                        defaultTax: Double(defaultTax),
                                        categories: categories
                                    )
                                    viewModel.renumberReceipts(in: collectionID)
                                    showingRenumberConfirm = false
                                } label: {
                                    Text("Renumber \(collection?.receipts.count ?? 0) receipt(s)")
                                        .fontWeight(.semibold)
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)

                                Button("Cancel") {
                                    showingRenumberConfirm = false
                                }
                                .foregroundColor(.accentColor)
                            }
                            .padding(24)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                            .padding(.horizontal, 32)
                        }
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: showingRenumberConfirm)
            .onAppear {
                guard let c = collection else { return }
                numberFormat = c.numberFormat
                customPrefix = c.customPrefix
                defaultTax = Int(c.defaultTaxPercentage)
                categories = c.categories
            }
        }
    }

    // MARK: - Tax Button

    @ViewBuilder
    private func taxButton(_ pct: Int) -> some View {
        let isSelected = defaultTax == pct
        Text("\(pct)%")
            .font(.subheadline.weight(.medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isSelected ? Color.accentColor : Color(.systemGray5))
            .foregroundColor(isSelected ? .white : .primary)
            .contentShape(Rectangle())
            .onTapGesture { defaultTax = pct }
    }
}
