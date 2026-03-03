import SwiftUI

/// Form for editing receipt details after scanning.
struct ReceiptEditView: View {
    @State var receipt: Receipt
    let isNew: Bool
    var onSave: (Receipt) -> Void
    var onCancel: () -> Void

    @State private var totalAmountText = ""
    @State private var amountWithoutTaxText = ""
    @State private var autoCalculate = true
    @State private var enlargedImageFileName: String?
    @State private var selectedTax: Int = 0
    @State private var isUpdating = false   // prevents onChange loops

    var body: some View {
        NavigationView {
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
                    .fullScreenCover(item: $enlargedImageFileName) { fileName in
                        FullScreenImageView(fileName: fileName)
                    }
                }

                // MARK: Details
                Section("Receipt Details") {
                    LabeledTextField(label: "Receipt #", text: $receipt.receiptNumber)
                    LabeledTextField(label: "Shop", text: $receipt.shopName, placeholder: "Shop name")
                    DatePicker("Date", selection: $receipt.purchaseDate, displayedComponents: .date)
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
                            .onChange(of: totalAmountText) { _ in
                                guard !isUpdating else { return }
                                syncTotalToReceipt()
                                recalculateExclTax()
                            }
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
                        Text("€")
                        TextField("0,00", text: $amountWithoutTaxText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                            .disabled(autoCalculate)
                            .foregroundColor(autoCalculate ? .secondary : .primary)
                            .onChange(of: amountWithoutTaxText) { _ in
                                guard !isUpdating, !autoCalculate else { return }
                                if let amt = parseAmount(amountWithoutTaxText) {
                                    receipt.amountWithoutTax = amt
                                }
                            }
                    }

                    Toggle("Auto-calculate excl. tax", isOn: $autoCalculate)
                        .onChange(of: autoCalculate) { newValue in
                            if newValue {
                                recalculateExclTax()
                            }
                        }
                }

                // MARK: Summary
                Section("Summary") {
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
                        receipt.amountWithoutTax = parseAmount(amountWithoutTaxText) ?? receipt.amountWithoutTax
                        receipt.taxPercentage = Double(selectedTax)
                        onSave(receipt)
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                totalAmountText = receipt.totalAmount > 0 ? receipt.totalAmount.dutchFormatted : ""
                amountWithoutTaxText = receipt.amountWithoutTax > 0 ? receipt.amountWithoutTax.dutchFormatted : ""
                selectedTax = Int(receipt.taxPercentage)
                // Auto-calculate excl-tax when total is known but excl-tax wasn't set
                if receipt.totalAmount > 0 && receipt.amountWithoutTax == 0 {
                    recalculateExclTax()
                }
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
                guard selectedTax != pct else { return }
                selectedTax = pct
                receipt.taxPercentage = Double(pct)
                recalculateExclTax()
            }
    }

    // MARK: - Computed tax amount (always live from current text fields)

    private var computedTaxAmount: Double {
        let total = parseAmount(totalAmountText) ?? 0
        let excl = parseAmount(amountWithoutTaxText) ?? 0
        return max(total - excl, 0)
    }

    // MARK: - Helpers

    private func syncTotalToReceipt() {
        if let total = parseAmount(totalAmountText) {
            receipt.totalAmount = total
        }
    }

    private func recalculateExclTax() {
        guard autoCalculate else { return }
        guard let total = parseAmount(totalAmountText), total > 0 else { return }

        let excl: Double
        if selectedTax > 0 {
            excl = total / (1.0 + Double(selectedTax) / 100.0)
        } else {
            excl = total
        }

        receipt.amountWithoutTax = excl
        isUpdating = true
        amountWithoutTaxText = excl.dutchFormatted
        isUpdating = false
    }

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
