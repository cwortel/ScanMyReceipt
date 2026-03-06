import SwiftUI

/// Form for editing receipt details after scanning.
struct ReceiptEditView: View {
    @State var receipt: Receipt
    let isNew: Bool
    var onSave: (Receipt) -> Void
    var onCancel: () -> Void

    @State private var totalAmountText: String
    @State private var enlargedImageFileName: String?
    @State private var selectedTax: Int
    @State private var selectedCategory: String

    /// Global categories from AppSettings.
    private var categories: [String] { AppSettings.shared.categories }

    // Initialise @State from the receipt directly instead of relying on
    // .onAppear, which can fire too late or be skipped in SwiftUI sheets.
    init(receipt: Receipt, isNew: Bool,
         onSave: @escaping (Receipt) -> Void, onCancel: @escaping () -> Void) {
        _receipt = State(initialValue: receipt)
        _totalAmountText = State(initialValue: receipt.totalAmount > 0 ? receipt.totalAmount.dutchFormatted : "")
        _selectedTax = State(initialValue: Int(receipt.taxPercentage))
        _selectedCategory = State(initialValue: receipt.category)
        self.isNew = isNew
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Scanned images
                if !receipt.imageFileNames.isEmpty {
                    Section("Scanned Images") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(receipt.imageFileNames, id: \.self) { fileName in
                                    ZStack(alignment: .topTrailing) {
                                        PreviewImageView(fileName: fileName, height: 200)
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                enlargedImageFileName = fileName
                                            }
                                        Button {
                                            removeImage(fileName: fileName)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.title2)
                                                .symbolRenderingMode(.palette)
                                                .foregroundStyle(.white, .black.opacity(0.6))
                                        }
                                        .padding(6)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                // MARK: Details
                Section("Receipt Details") {
                    LabeledTextField(label: "Receipt #", text: $receipt.receiptNumber)
                    LabeledTextField(label: "Shop", text: $receipt.shopName, placeholder: "Shop name")
                    DatePicker("Date", selection: $receipt.purchaseDate, displayedComponents: .date)
                }

                // MARK: Category
                Section("Category") {
                    Menu {
                        Button {
                            selectedCategory = ""
                        } label: {
                            if selectedCategory.isEmpty {
                                Label("None", systemImage: "checkmark")
                            } else {
                                Text("None")
                            }
                        }
                        ForEach(categories, id: \.self) { cat in
                            Button {
                                selectedCategory = cat
                            } label: {
                                if selectedCategory == cat {
                                    Label(cat, systemImage: "checkmark")
                                } else {
                                    Text(cat)
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Text(selectedCategory.isEmpty ? "None" : selectedCategory)
                                .foregroundColor(selectedCategory.isEmpty ? .secondary : .primary)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // MARK: Amounts
                Section("Amounts") {
                    HStack {
                        Text("Total (incl. tax)")
                        Spacer()
                        Text("€")
                        TextField("0,00", text: $totalAmountText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }

                    // Tax percentage selector
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tax %")
                        HStack(spacing: 0) {
                            taxButton(0)
                            taxButton(9)
                            taxButton(21)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    HStack {
                        Text("Amount (excl. tax)")
                        Spacer()
                        Text(computedExclTax.euroFormatted)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Tax amount")
                        Spacer()
                        Text(computedTaxAmount.euroFormatted)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle(isNew ? "New Receipt" : "Edit Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        // Sync all @State values to receipt before saving
                        receipt.totalAmount = parseAmount(totalAmountText) ?? receipt.totalAmount
                        receipt.taxPercentage = Double(selectedTax)
                        receipt.amountWithoutTax = computedExclTax
                        receipt.category = selectedCategory
                        onSave(receipt)
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                // @State is initialised in init; onAppear kept only as
                // a safety net in case SwiftUI reuses the view identity.
                if selectedTax == 0 && receipt.taxPercentage > 0 {
                    selectedTax = Int(receipt.taxPercentage)
                }
                if totalAmountText.isEmpty && receipt.totalAmount > 0 {
                    totalAmountText = receipt.totalAmount.dutchFormatted
                }
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { enlargedImageFileName != nil },
            set: { if !$0 { enlargedImageFileName = nil } }
        )) {
            if let fileName = enlargedImageFileName {
                FullScreenImageView(fileName: fileName)
            }
        }
    }

    // MARK: - Tax button

    @ViewBuilder
    private func taxButton(_ pct: Int) -> some View {
        Text("\(pct)%")
            .font(.subheadline.weight(.medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(selectedTax == pct ? Color.accentColor : Color(.systemGray5))
            .foregroundColor(selectedTax == pct ? .white : .primary)
            .contentShape(Rectangle())
            .onTapGesture {
                selectedTax = pct
            }
    }

    // MARK: - Computed values (always derived, always correct)

    private var computedExclTax: Double {
        let total = parseAmount(totalAmountText) ?? 0
        guard total > 0 else { return 0 }
        if selectedTax > 0 {
            return total / (1.0 + Double(selectedTax) / 100.0)
        }
        return total
    }

    private var computedTaxAmount: Double {
        let total = parseAmount(totalAmountText) ?? 0
        return max(total - computedExclTax, 0)
    }

    // MARK: - Helpers

    private func parseAmount(_ text: String) -> Double? {
        // Accept both comma (Dutch) and dot (English) input
        let cleaned = text
            .replacingOccurrences(of: ".", with: "")  // remove thousand separators
            .replacingOccurrences(of: ",", with: ".") // comma → dot for Double parsing
        return Double(cleaned)
    }

    private func removeImage(fileName: String) {
        receipt.imageFileNames.removeAll { $0 == fileName }
        PersistenceService.shared.deleteImage(fileName: fileName)
    }
}

// MARK: - Small helper view

private struct LabeledTextField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField(placeholder.isEmpty ? label : placeholder, text: $text)
                .multilineTextAlignment(.trailing)
        }
    }
}
