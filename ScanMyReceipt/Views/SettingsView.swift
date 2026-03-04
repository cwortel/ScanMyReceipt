import SwiftUI

/// App settings screen — accessible from the collection list toolbar.
struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Receipt Numbering
                Section {
                    ForEach(ReceiptNumberFormat.allCases) { format in
                        Button {
                            settings.receiptNumberFormat = format
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(format.displayName)
                                        .foregroundColor(.primary)
                                    Text("e.g. \(format.example(customPrefix: settings.customPrefix))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if settings.receiptNumberFormat == format {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                        .fontWeight(.semibold)
                                }
                            }
                        }
                    }

                    // Custom prefix text field — only shown when custom is selected
                    if settings.receiptNumberFormat == .custom {
                        HStack {
                            Text("Prefix")
                            Spacer()
                            TextField("e.g. INV2026", text: $settings.customPrefix)
                                .multilineTextAlignment(.trailing)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.characters)
                        }
                    }
                } header: {
                    Text("Receipt Numbering")
                } footer: {
                    if settings.receiptNumberFormat == .custom {
                        Text("New receipts will be numbered as \(settings.customPrefix.isEmpty ? "MY" : settings.customPrefix)-001, -002, etc. Existing receipts are not affected.")
                    } else {
                        Text("Controls the prefix used for new receipt numbers. Existing receipts are not affected.")
                    }
                }

                // MARK: Default Tax
                Section {
                    HStack(spacing: 0) {
                        taxOptionButton(0)
                        taxOptionButton(9)
                        taxOptionButton(21)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } header: {
                    Text("Default Tax Percentage")
                } footer: {
                    Text("Pre-selected tax rate for newly scanned receipts. OCR may override this if it detects a tax rate on the receipt.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Tax Button

    @ViewBuilder
    private func taxOptionButton(_ pct: Int) -> some View {
        let isSelected = Int(settings.defaultTaxPercentage) == pct
        Text("\(pct)%")
            .font(.subheadline.weight(.medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isSelected ? Color.accentColor : Color(.systemGray5))
            .foregroundColor(isSelected ? .white : .primary)
            .contentShape(Rectangle())
            .onTapGesture {
                settings.defaultTaxPercentage = Double(pct)
            }
    }
}
