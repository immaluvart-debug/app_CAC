import SwiftUI
import AVFoundation
import Vision
import CoreML
import PhotosUI

struct ContentView: View {
    @State private var selectedImage: UIImage?
    @State private var classificationResult: String = "No image classified yet"
    @State private var greenScoreResult: String = ""
    @State private var isShowingScanner = false
    @State private var photoItem: PhotosPickerItem? = nil
    
    var body: some View {
        NavigationView {
            VStack(spacing: 25) {
                // Display selected image
                if let selectedImage {
                    Image(uiImage: selectedImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 250)
                        .cornerRadius(12)
                }
                
                // Classification result
                Text(classificationResult)
                    .font(.headline)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.gray.opacity(0.15))
                    .cornerRadius(8)
                
                // Green Score result
                if !greenScoreResult.isEmpty {
                    Text("Green Score: \(greenScoreResult)")
                        .font(.title2)
                        .foregroundColor(.green)
                        .padding()
                }
                
                // Buttons
                PhotosPicker("Classify Image", selection: $photoItem, matching: .images)
                    .font(.headline)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                    .onChange(of: photoItem) { newItem in
                        Task {
                            if let data = try? await newItem?.loadTransferable(type: Data.self),
                               let uiImage = UIImage(data: data) {
                                selectedImage = uiImage
                                classifyImage(uiImage)
                            }
                        }
                    }
                
                Button("Scan Barcode for Green Score") {
                    isShowingScanner = true
                }
                .font(.headline)
                .padding()
                .background(Color.green)
                .foregroundColor(.white)
                .clipShape(Capsule())
            }
            .padding()
            .navigationTitle("Food Scanner")
            .sheet(isPresented: $isShowingScanner) {
                BarcodeScannerView { barcode in
                    isShowingScanner = false
                    fetchGreenScore(for: barcode)
                }
            }
        }
    }
    
    // MARK: - Classification
    func classifyImage(_ image: UIImage) {
        guard let ciImage = CIImage(image: image) else { return }
        do {
            let model = try VNCoreMLModel(for: MobileNet().model) // <-- Your model
            let request = VNCoreMLRequest(model: model) { request, _ in
                if let result = request.results?.first as? VNClassificationObservation {
                    DispatchQueue.main.async {
                        classificationResult = "\(result.identifier) (\(String(format: "%.1f", result.confidence * 100))%)"
                    }
                }
            }
            try VNImageRequestHandler(ciImage: ciImage).perform([request])
        } catch {
            classificationResult = "Error: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Fetch Green Score
    func fetchGreenScore(for barcode: String) {
        guard let url = URL(string: "https://world.openfoodfacts.org/api/v0/product/\(barcode).json?fields=ecoscore_grade") else {
            greenScoreResult = "Invalid barcode"
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data else {
                DispatchQueue.main.async {
                    greenScoreResult = "No data from server"
                }
                return
            }
            
            struct Product: Codable { let ecoscore_grade: String? }
            struct Response: Codable { let product: Product? }
            
            if let decoded = try? JSONDecoder().decode(Response.self, from: data) {
                DispatchQueue.main.async {
                    greenScoreResult = decoded.product?.ecoscore_grade?.uppercased() ?? "Unknown"
                }
            } else {
                DispatchQueue.main.async {
                    greenScoreResult = "Error decoding data"
                }
            }
        }.resume()
    }
}

// MARK: - Barcode Scanner
struct BarcodeScannerView: UIViewControllerRepresentable {
    var onBarcodeScanned: (String) -> Void
    
    func makeUIViewController(context: Context) -> ScannerViewController {
        let vc = ScannerViewController()
        vc.onBarcodeScanned = onBarcodeScanned
        return vc
    }
    
    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}
}

class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var captureSession: AVCaptureSession!
    var previewLayer: AVCaptureVideoPreviewLayer!
    var onBarcodeScanned: ((String) -> Void)?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        
        captureSession = AVCaptureSession()
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video),
              let videoInput = try? AVCaptureDeviceInput(device: videoCaptureDevice),
              captureSession.canAddInput(videoInput) else { return }
        captureSession.addInput(videoInput)
        
        let metadataOutput = AVCaptureMetadataOutput()
        if captureSession.canAddOutput(metadataOutput) {
            captureSession.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.ean8, .ean13, .upce, .code128, .code39, .code93, .qr]
        }
        
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = view.layer.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        
        captureSession.startRunning()
    }
    
    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        if let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
           let code = metadataObject.stringValue {
            captureSession.stopRunning()
            dismiss(animated: true) {
                self.onBarcodeScanned?(code)
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
    }
}
