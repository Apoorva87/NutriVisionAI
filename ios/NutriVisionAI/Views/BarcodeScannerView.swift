// BarcodeScannerView — VisionKit DataScannerViewController wrapper for live barcode scanning.

import SwiftUI
import VisionKit

struct BarcodeScannerView: UIViewControllerRepresentable {
    @Binding var scannedBarcode: String?
    @Environment(\.dismiss) private var dismiss

    static var isAvailable: Bool {
        DataScannerViewController.isSupported
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        if !scanner.isScanning {
            try? scanner.startScanning()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let parent: BarcodeScannerView
        private var hasScanned = false

        init(_ parent: BarcodeScannerView) {
            self.parent = parent
        }

        func dataScanner(_ scanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !hasScanned else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item, let value = barcode.payloadStringValue {
                    hasScanned = true
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    parent.scannedBarcode = value
                    parent.dismiss()
                    return
                }
            }
        }

        func dataScanner(_ scanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            guard !hasScanned else { return }
            if case .barcode(let barcode) = item, let value = barcode.payloadStringValue {
                hasScanned = true
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                parent.scannedBarcode = value
                parent.dismiss()
            }
        }
    }
}
