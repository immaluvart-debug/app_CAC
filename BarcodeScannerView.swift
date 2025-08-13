//
//  BarcodeScannerView.swift
//  
//
//  Created by desai on 8/11/25.
//
import SwiftUI
import MLKitBarcodeScanning
import MLKitVision

struct BarcodeScannerView: UIViewControllerRepresentable {
    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        var parent: BarcodeScannerView

        init(parent: BarcodeScannerView) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            picker.dismiss(animated: true)

            if let image = info[.originalImage] as? UIImage {
                parent.scanBarcodes(in: image)
            }
        }
    }

    @Binding var scannedCode: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func scanBarcodes(in image: UIImage) {
        guard let cgImage = image.cgImage else { return }
        let visionImage = VisionImage(image: image)
        visionImage.orientation = image.imageOrientation

        let options = BarcodeScannerOptions(formats: .all)
        let scanner = BarcodeScanner.barcodeScanner(options: options)

        scanner.process(visionImage) { barcodes, error in
            guard error == nil, let barcodes = barcodes else { return }
            if let first = barcodes.first {
                self.scannedCode = first.rawValue
            }
        }
    }
}

struct ContentView: View {
    @State private var scannedCode: String? = nil
    @State private var showScanner = false

    var body: some View {
        VStack(spacing: 20) {
            Text(scannedCode ?? "No code scanned yet")
                .padding()
                .background(Color.gray.opacity(0.2))
                .cornerRadius(10)

            Button("Scan Barcode") {
                showScanner = true
            }
            .font(.headline)
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
        }
        .sheet(isPresented: $showScanner) {
            BarcodeScannerView(scannedCode: $scannedCode)
        }
    }
}
