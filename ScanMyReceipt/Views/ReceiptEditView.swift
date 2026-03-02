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
                                if let total = parseAmount(totalAmountText) {
                                    receipt.totalAmount = total
                                    recalculateIfNeeded()
                                }
                            }
                    }

                    // Tax percentage — custom buttons for reliable tap handling
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tax %")
                        HStack(spacing: 0) {
                            ForEach([0.0, 9.0, 21.0], id: \.self) { pct in
                                Button {
                                    receipt.taxPercentage = pct
                                    recalculateIfNeeded()
                                } label: {
                                    Text("\(Int(pct))%")
                                        .font(.subheadline.weight(.medium))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(
                                            receipt.taxPercentage == pct
                                                ? Color.accentColor
                                                : Color(.systemGray5)
                                        )
                                        .foregroundColor(
                                            receipt.taxPercentage == pct ? .white : .primary
                                        )
                                }
                                .buttonStyle(.plain)
                            }
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
                            .onChange(of: amountWithoutTaxText) { _ in
                                if let amt = parseAmount(amountWithoutTaxText) {
                                    receipt.amountWithoutTax = amt
                                }
                            }
                    }

                    Toggle("Auto-calculate excl. tax", isOn: $autoCalculate)
                        .onChange(of: autoCalculate) { _ in
                            recalculateIfNeeded()
                        }
                }

                // MARK: Summary
                Section("Summary") {
                    HStack {
                        Text("Tax amount")
                        Spacer()
                        Text(receipt.taxAmount.euroFormatted)
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
                    Button("Save") { onSave(receipt) }
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                totalAmountText = receipt.totalAmount > 0 ? receipt.totalAmount.dutchFormatted : ""
                amountWithoutTaxText = receipt.amountWithoutTax > 0 ? receipt.amountWithoutTax.dutchFormatted : ""
                // Auto-calculate excl-tax when total is known but excl-tax wasn't set (e.g. OCR only found total)
                if receipt.totalAmount > 0 && receipt.amountWithoutTax == 0 {
                    recalculateIfNeeded()
                }
            }
        }
    }

    // MARK: - Helpers

    private func recalculateIfNeeded() {
        guard autoCalculate,
              let total = parseAmount(totalAmountText) else { return }
        if receipt.taxPercentage > 0 {
            receipt.amountWithoutTax = total / (1.0 + receipt.taxPercentage / 100.0)
        } else {
            receipt.amountWithoutTax = total
        }
        amountWithoutTaxText = receipt.amountWithoutTax.dutchFormatted
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
