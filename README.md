# ScanMyReceipt

ScanMyReceipt is an iOS app that turns paper receipts into organized digital records. Point your camera at a receipt, and the app automatically reads the shop name, date, total amount, and VAT percentage. Everything stays on your device — no account needed, no internet required.

## Features

- **Scan Receipts Instantly** — Hold your phone over a receipt and the camera detects the edges automatically. Scan one receipt or a whole stack in a single session.
- **Automatic Text Recognition** — The app reads your receipt and fills in the shop name, date, total, and tax rate for you. Especially good at reading Dutch receipts, but works with English too.
- **Organize in Collections** — Group your receipts however you like — by month, by project, by trip. Each collection gets its own numbering and settings.
- **Flexible Receipt Numbering** — Number your receipts by year and month (e.g. 202603-001), by collection name, or with a custom prefix. Renumber an entire collection with one tap.
- **Quick Tax Calculation** — Select 0%, 9%, or 21% VAT and the amounts excluding tax are calculated instantly.
- **Export Anywhere** — Share your receipts as a PDF with images, a CSV spreadsheet, or UBL e-invoices with paired PDFs. Send them by email, save to Files, or AirDrop — whatever works for you.
- **View Receipt Images** — Swipe through your scanned pages, pinch to zoom in on details, or double-tap to magnify.
- **Private by Design** — All data lives on your device. Nothing is uploaded anywhere unless you choose to share it.

## How to Use

### Create a Collection

From the home screen, tap **+** and give your collection a name (e.g. "March 2026 Receipts"). Collections appear newest first.

### Scan Receipts

Open a collection and tap the **camera icon**:

1. Position the receipt in the camera frame — edges are detected automatically.
2. Tap the shutter or let auto-capture grab it.
3. Scan as many pages as you need.
4. Tap **Save** when done.

The app reads each page one by one and shows your progress ("Reading receipt 1 of 3…").

### Review & Edit

After scanning, each receipt opens in an edit form so you can check and correct what was read:

- **Images** — Swipe through pages. Tap to view full-screen. Remove pages with the × button.
- **Receipt Number** — Auto-generated, but you can change it.
- **Shop Name** — Picked up from the top of the receipt.
- **Date** — Parsed from the receipt text. Adjust with the date picker if needed.
- **Total Amount** — Enter amounts with a comma (Dutch format, e.g. 12,50).
- **Tax Percentage** — Tap 0%, 9%, or 21%. The amount without tax and the tax amount update automatically.

Tap **Save** to keep, or **Cancel** to discard.

### Organize

- **Rename** a collection — swipe left, tap the pencil icon.
- **Delete** a collection — swipe left, tap the trash icon.
- **Edit a receipt** — tap it in the list to reopen the edit form.

### Collection Settings

Tap the **gear icon** in a collection to configure:

| Setting | Options | What It Does |
|---|---|---|
| **Number Format** | Year+Month / Collection Name / Custom | Sets the prefix for receipt numbers |
| **Custom Prefix** | Free text | Your own prefix (only when "Custom" is selected) |
| **Default Tax %** | 0% / 9% / 21% | Pre-selected tax rate for new receipts |
| **Renumber All** | — | Reassigns sequential numbers to every receipt |

### Export

Tap the **share icon** and pick a format:

| Format | What You Get |
|---|---|
| **PDF** | A4 pages with receipt images and receipt numbers |
| **CSV** | Spreadsheet with number, shop, date, total, excl. tax, and tax % |
| **UBL + PDF** | Per-receipt UBL 2.1 XML e-invoice + matching PDF with receipt image. Import the XML into your bookkeeping system; the PDF is linked by filename. |
| **All Formats** | Everything above, bundled together |

Files are shared via the standard iOS share sheet.

## Requirements

- iPhone or iPad running iOS 16 or later
- A physical device for camera scanning (the simulator doesn't support the document camera)

---

## Technical Details

The sections below cover the architecture and implementation for developers who want to understand or contribute to the codebase.

### Architecture

ScanMyReceipt uses an **MVVM** (Model–View–ViewModel) architecture built entirely with **SwiftUI** and Apple's first-party frameworks. There are zero external dependencies.

| Framework | Role |
|---|---|
| **SwiftUI** | Declarative UI with `NavigationStack`, sheets, and full-screen covers |
| **VisionKit** | `VNDocumentCameraViewController` for document scanning with auto edge detection |
| **Vision** | `VNRecognizeTextRequest` for on-device OCR at `.accurate` recognition level |
| **UIKit** | `UIGraphicsPDFRenderer` for PDF generation, `UIActivityViewController` for sharing |
| **Combine** | `@Published` properties on `ObservableObject` view models for reactive state |

### How Scanning & OCR Work

1. **Document capture** — `ScannerService` wraps Apple's `VNDocumentCameraViewController` via `UIViewControllerRepresentable`. The camera handles edge detection, perspective correction, and image enhancement automatically.

2. **Text recognition** — `TextRecognitionService` runs `VNRecognizeTextRequest` with `.accurate` recognition level on each scanned image. Language hints are set to Dutch (`nl-NL`) and English (`en-US`).

3. **Data extraction** — The recognized text is parsed with heuristics tuned for Dutch receipts:
   - **Shop name**: First non-trivial line from the top 10 lines of text — skips addresses, dates, and common receipt headers like "Kassabon", "Tafel", and "Bestelling".
   - **Date**: Regex matching for DD-MM-YYYY, YYYY-MM-DD, and DD-MM-YY with various separators (dashes, slashes, dots).
   - **Total amount**: Searches for keywords ("totaal", "te betalen", "total", "amount due") and extracts the associated number. Falls back to the largest amount found in the bottom third of the receipt. Handles both comma-decimal (Dutch: `12,50`) and dot-decimal formats.
   - **Tax percentage**: Looks for BTW/VAT mentions and maps to standard Dutch rates (0%, 9%, 21%).
   - **Amount without tax**: Derived mathematically from the total and detected tax rate.

4. **Sequential processing** — When multiple pages are scanned in one session, each page is OCR'd one at a time to guarantee sequential receipt number assignment.

### Data Storage

All data stays on-device:

- **Collections & receipts** — Persisted as a single JSON file (`collections.json`) in the app's Documents directory, encoded with ISO 8601 dates and pretty-printed for debuggability.
- **Receipt images** — Saved as JPEG (70% quality) in a `ReceiptImages/` subdirectory. Images are downsampled to a maximum of 2000px on the longest edge at save time to keep storage manageable.
- **Global settings** — The default tax percentage is stored in `UserDefaults`.

### Image Loading Pipeline

To keep scrolling fast and memory usage low, images are loaded at three resolution tiers using `CGImageSource` thumbnail APIs:

| Tier | Max Size | Cache Limit | Use Case |
|---|---|---|---|
| **Thumbnail** | 100px | 100 items / 50 MB | Receipt list rows |
| **Preview** | 800px | 20 items / 25 MB | Edit form gallery |
| **Full resolution** | Original | Not cached | Full-screen zoom view |

Each tier uses a dedicated `NSCache` instance with automatic eviction under memory pressure.

### Export Formats

- **PDF** — `UIGraphicsPDFRenderer` generates A4 pages. Each receipt image is aspect-fitted onto a page with the receipt number rendered as a label in the top-left corner. Uses `autoreleasepool` per page to keep memory flat during large exports.
- **CSV** — RFC 4180–compliant comma-separated values. Fields with commas or quotes are properly escaped.
- **UBL + PDF** — Each receipt produces two files with matching base names (e.g. `Receipt_202603-001.xml` + `Receipt_202603-001.pdf`). The UBL 2.1 XML contains an `AdditionalDocumentReference` pointing to the PDF filename so bookkeeping systems like Digiboox can link the structured data to the receipt image. The XML includes NLCIUS-compliant fields: `CustomizationID`, supplier/customer party, postal address with country code, tax totals with category, legal monetary totals, and a fully classified invoice line.

### Navigation Structure

```
SplashScreen (2.5s fade-in) → NavigationStack
  └─ CollectionListView
       └─ CollectionDetailView
            ├─ ReceiptEditView (sheet)
            │    └─ FullScreenImageView (fullscreen cover, pinch-to-zoom)
            ├─ DocumentCameraView (fullscreen cover)
            ├─ CollectionSettingsView (sheet)
            └─ ShareSheet (sheet)
```

### Project Structure

```
ScanMyReceipt/
├── App/
│   ├── ScanMyReceiptApp.swift       # Entry point, injects view model
│   └── ContentView.swift            # Root view with splash screen overlay
├── Models/
│   ├── Receipt.swift                # Receipt and ReceiptCollection data models
│   └── AppSettings.swift            # ReceiptNumberFormat enum, global settings
├── Services/
│   ├── ScannerService.swift         # VisionKit document camera wrapper
│   ├── TextRecognitionService.swift # Vision OCR with Dutch-optimized parsing
│   ├── PersistenceService.swift     # JSON + JPEG file storage, image pipeline
│   └── ExportService.swift          # PDF, CSV, and UBL XML generation
├── ViewModels/
│   ├── ReceiptListViewModel.swift   # Collection & receipt CRUD, numbering logic
│   └── ScannerViewModel.swift       # Scanner state management
├── Views/
│   ├── ReceiptListView.swift        # Home screen (collection list)
│   ├── ReceiptDetailView.swift      # Receipt list within a collection
│   ├── ReceiptEditView.swift        # Create/edit receipt form
│   ├── CollectionSettingsView.swift # Per-collection settings
│   ├── ImageViews.swift             # Thumbnail, preview, and full-screen views
│   ├── ScannerView.swift            # Receipt image gallery
│   ├── ShareSheet.swift             # UIActivityViewController wrapper
│   └── SplashScreenView.swift       # Animated launch screen
├── Utilities/
│   └── Extensions.swift             # Date, Double, Bundle helpers (Dutch locale)
└── Assets.xcassets/                 # App icon and logos
```

### Building from Source

1. Clone the repository:
   ```bash
   git clone https://github.com/your-username/ScanMyReceipt.git
   ```
2. Open `ScanMyReceipt.xcodeproj` in Xcode 15+.
3. Select a physical device as the run destination.
4. Build and run (**⌘R**).

## Contributing

Contributions are welcome! Please feel free to submit a pull request or open an issue for any enhancements or bug fixes.

## License

This project is licensed under the MIT License. See the LICENSE file for more details.

---

© 2026 Cirilo Wortel