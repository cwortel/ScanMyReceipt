import SwiftUI

/// Shows all receipts inside a single collection.
/// Allows scanning new receipts, editing existing ones, and exporting.
struct CollectionDetailView: View {
    let collectionID: UUID
    @EnvironmentObject var viewModel: CollectionListViewModel

    @State private var showingScanner = false
    @State private var showingExportOptions = false
    @State private var showingShareSheet = false
    @State private var isProcessingOCR = false
    @State private var ocrProgress = ""
    @State private var exportFiles: [URL] = []
    @State private var editingReceipt: Receipt?
    @State private var showingSplash = false

    private var collection: ReceiptCollection? {
        viewModel.collection(for: collectionID)
    }

    var body: some View {
        Group {
            if let collection = collection {
                VStack(spacing: 0) {
                List {
                    ForEach(collection.receipts) { receipt in
                        ReceiptRow(receipt: receipt)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editingReceipt = receipt
                            }
                    }
                    .onDelete { offsets in
                        viewModel.deleteReceipt(at: offsets, in: collectionID)
                    }

                    if collection.receipts.isEmpty {
                        Text("No Receipts yet.\nTap the camera to start scanning.")
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
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
                            processScannedImages(images)
                        },
                        onCancel: {
                            showingScanner = false
                        }
                    )
                    .ignoresSafeArea()
                }
                // Receipt edit sheet — driven by editingReceipt (non-nil = show)
                .sheet(item: $editingReceipt) { receipt in
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
                            editingReceipt = nil
                        },
                        onCancel: {
                            if isNew {
                                for fileName in receipt.imageFileNames {
                                    PersistenceService.shared.deleteImage(fileName: fileName)
                                }
                            }
                            editingReceipt = nil
                        }
                    )
                }
                // Export options
                .confirmationDialog("Export Collection", isPresented: $showingExportOptions) {
                    Button("PDF (Receipt Images)") { exportPDF(collection) }
                    Button("CSV (Spreadsheet)") { exportCSV(collection) }
                    Button("PDF + UBL (Factur-X)") { exportFacturX(collection) }
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
                                Text(ocrProgress)
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
                .fullScreenCover(isPresented: $showingSplash) {
                    SplashScreenView(onDismiss: {
                        showingSplash = false
                    })
                }
            } else {
                Text("Collection not found")
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Scan Processing

    /// Each scanned image becomes a separate receipt. OCR runs on each
    /// individually and receipts are auto-saved to the collection.
    private func processScannedImages(_ images: [UIImage]) {
        guard !images.isEmpty else { return }
        isProcessingOCR = true
        let total = images.count

        // Process each image sequentially to get correct receipt numbers
        func processNext(index: Int) {
            guard index < images.count else {
                isProcessingOCR = false
                ocrProgress = ""
                return
            }

            ocrProgress = "Reading receipt \(index + 1) of \(total)\u{2026}"

            let image = images[index]
            let fileName = UUID().uuidString + ".jpg"
            PersistenceService.shared.saveImage(image, fileName: fileName)

            TextRecognitionService.shared.recognizeReceipt(from: [image]) { recognizedData in
                let number = viewModel.nextReceiptNumber(forCollectionID: collectionID, collectionName: collection?.name)
                var receipt = Receipt(
                    receiptNumber: number,
                    imageFileNames: [fileName]
                )
                if let shop = recognizedData.shopName { receipt.shopName = shop }
                if let date = recognizedData.purchaseDate { receipt.purchaseDate = date }
                if let total = recognizedData.totalAmount { receipt.totalAmount = total }
                if let taxPct = recognizedData.taxPercentage {
                    receipt.taxPercentage = taxPct
                } else {
                    receipt.taxPercentage = AppSettings.shared.defaultTaxPercentage
                }
                if let exclTax = recognizedData.amountWithoutTax {
                    receipt.amountWithoutTax = exclTax
                } else if receipt.totalAmount > 0 {
                    if receipt.taxPercentage > 0 {
                        receipt.amountWithoutTax = receipt.totalAmount / (1.0 + receipt.taxPercentage / 100.0)
                    } else {
                        receipt.amountWithoutTax = receipt.totalAmount
                    }
                }

                viewModel.addReceipt(receipt, to: collectionID)
                processNext(index: index + 1)
            }
        }

        processNext(index: 0)
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

    private func exportFacturX(_ c: ReceiptCollection) {
        exportFiles = ExportService.shared.generateFacturXFiles(for: c)
        showShareSheetIfNeeded()
    }

    private func exportAll(_ c: ReceiptCollection) {
        exportFiles = []
        if let url = ExportService.shared.generatePDF(for: c) { exportFiles.append(url) }
        if let url = ExportService.shared.generateCSV(for: c) { exportFiles.append(url) }
        exportFiles.append(contentsOf: ExportService.shared.generateFacturXFiles(for: c))
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