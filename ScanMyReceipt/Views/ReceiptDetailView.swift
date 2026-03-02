import SwiftUI

/// Shows all receipts inside a single collection.
/// Allows scanning new receipts, editing existing ones, and exporting.
struct CollectionDetailView: View {
    let collectionID: UUID
    @EnvironmentObject var viewModel: CollectionListViewModel

    @State private var showingScanner = false
    @State private var showingReceiptEdit = false
    @State private var showingExportOptions = false
    @State private var showingShareSheet = false
    @State private var isProcessingOCR = false
    @State private var exportFiles: [URL] = []
    @State private var editingReceipt: Receipt?

    private var collection: ReceiptCollection? {
        viewModel.collection(for: collectionID)
    }

    var body: some View {
        Group {
            if let collection = collection {
                List {
                    ForEach(collection.receipts) { receipt in
                        ReceiptRow(receipt: receipt)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editingReceipt = receipt
                                showingReceiptEdit = true
                            }
                    }
                    .onDelete { offsets in
                        viewModel.deleteReceipt(at: offsets, in: collectionID)
                    }

                    if collection.receipts.isEmpty {
                        Text("No receipts yet.\nTap the camera to scan one.")
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    }
                }
                .navigationTitle(collection.name)
                .toolbar {
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        Button(action: { showingScanner = true }) {
                            Image(systemName: "camera")
                        }
                        if !collection.receipts.isEmpty {
                            Button(action: { showingExportOptions = true }) {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                    }
                }
                // Scanner sheet
                .fullScreenCover(isPresented: $showingScanner) {
                    DocumentCameraView(
                        onScanComplete: { images in
                            showingScanner = false
                            let fileNames = viewModel.saveImages(images)
                            let number = viewModel.nextReceiptNumber()
                            isProcessingOCR = true

                            TextRecognitionService.shared.recognizeReceipt(from: images) { recognizedData in
                                var receipt = Receipt(
                                    receiptNumber: number,
                                    imageFileNames: fileNames
                                )
                                if let shop = recognizedData.shopName { receipt.shopName = shop }
                                if let date = recognizedData.purchaseDate { receipt.purchaseDate = date }
                                if let total = recognizedData.totalAmount { receipt.totalAmount = total }
                                if let taxPct = recognizedData.taxPercentage { receipt.taxPercentage = taxPct }
                                if let exclTax = recognizedData.amountWithoutTax { receipt.amountWithoutTax = exclTax }

                                editingReceipt = receipt
                                isProcessingOCR = false
                                showingReceiptEdit = true
                            }
                        },
                        onCancel: {
                            showingScanner = false
                        }
                    )
                    .ignoresSafeArea()
                }
                // Receipt edit sheet
                .sheet(isPresented: $showingReceiptEdit) {
                    if let receipt = editingReceipt {
                        let isNew = !collection.receipts.contains { $0.id == receipt.id }
                        ReceiptEditView(
                            receipt: receipt,
                            isNew: isNew,
                            onSave: { updated in
                                if isNew {
                                    viewModel.addReceipt(updated, to: collectionID)
                                } else {
                                    viewModel.updateReceipt(updated, in: collectionID)
                                }
                                showingReceiptEdit = false
                                editingReceipt = nil
                            },
                            onCancel: {
                                // Clean up images for unsaved new receipts
                                if isNew {
                                    for fileName in receipt.imageFileNames {
                                        PersistenceService.shared.deleteImage(fileName: fileName)
                                    }
                                }
                                showingReceiptEdit = false
                                editingReceipt = nil
                            }
                        )
                    }
                }
                // Export options
                .confirmationDialog("Export Collection", isPresented: $showingExportOptions) {
                    Button("PDF (Receipt Images)") { exportPDF(collection) }
                    Button("CSV (Spreadsheet)") { exportCSV(collection) }
                    Button("UBL (Bookkeeping)") { exportUBL(collection) }
                    Button("All Formats") { exportAll(collection) }
                    Button("Cancel", role: .cancel) {}
                }
                // Share sheet
                .sheet(isPresented: $showingShareSheet) {
                    ShareSheet(activityItems: exportFiles)
                }
                // OCR processing overlay
                .overlay {
                    if isProcessingOCR {
                        ZStack {
                            Color.black.opacity(0.3)
                                .ignoresSafeArea()
                            VStack(spacing: 12) {
                                ProgressView()
                                    .scaleEffect(1.5)
                                    .tint(.primary)
                                Text("Reading receipt…")
                                    .font(.headline)
                            }
                            .padding(24)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.regularMaterial)
                            )
                        }
                    }
                }
            } else {
                Text("Collection not found")
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Export helpers

    private func exportPDF(_ c: ReceiptCollection) {
        exportFiles = []
        if let url = ExportService.shared.generatePDF(for: c) { exportFiles.append(url) }
        showShareSheetIfNeeded()
    }

    private func exportCSV(_ c: ReceiptCollection) {
        exportFiles = []
        if let url = ExportService.shared.generateCSV(for: c) { exportFiles.append(url) }
        showShareSheetIfNeeded()
    }

    private func exportUBL(_ c: ReceiptCollection) {
        exportFiles = ExportService.shared.generateUBLFiles(for: c)
        showShareSheetIfNeeded()
    }

    private func exportAll(_ c: ReceiptCollection) {
        exportFiles = []
        if let url = ExportService.shared.generatePDF(for: c) { exportFiles.append(url) }
        if let url = ExportService.shared.generateCSV(for: c) { exportFiles.append(url) }
        exportFiles.append(contentsOf: ExportService.shared.generateUBLFiles(for: c))
        showShareSheetIfNeeded()
    }

    private func showShareSheetIfNeeded() {
        if !exportFiles.isEmpty { showingShareSheet = true }
    }
}

// MARK: - Receipt Row

struct ReceiptRow: View {
    let receipt: Receipt

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail — uses cached, downscaled image (~100px) instead of full res
            ThumbnailView(fileName: receipt.imageFileNames.first, size: 50)
                .frame(width: 50, height: 50)
                .cornerRadius(6)

            VStack(alignment: .leading, spacing: 2) {
                Text(receipt.receiptNumber)
                    .font(.headline)
                Text(receipt.shopName.isEmpty ? "No shop name" : receipt.shopName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                HStack {
                    Text(receipt.purchaseDate, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(receipt.totalAmount.euroFormatted)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }
        }
        .padding(.vertical, 4)
    }
}