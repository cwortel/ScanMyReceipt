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
                        TextField("0.00", text: $totalAmountText)
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

                    Picker("Tax %", selection: $receipt.taxPercentage) {
                        Text("0%").tag(0.0)
                        Text("9%").tag(9.0)
                        Text("21%").tag(21.0)
                    }
                    .onChange(of: receipt.taxPercentage) { _ in
                        recalculateIfNeeded()
                    }

                    HStack {
                        Text("Amount (excl. tax)")
                        Spacer()
                        Text("€")
                        TextField("0.00", text: $amountWithoutTaxText)
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
                totalAmountText = receipt.totalAmount > 0 ? String(format: "%.2f", receipt.totalAmount) : ""
                amountWithoutTaxText = receipt.amountWithoutTax > 0 ? String(format: "%.2f", receipt.amountWithoutTax) : ""
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
        amountWithoutTaxText = String(format: "%.2f", receipt.amountWithoutTax)
    }

    private func parseAmount(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
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
