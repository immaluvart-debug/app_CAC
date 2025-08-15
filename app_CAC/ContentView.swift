import SwiftUI
import AVFoundation
import Vision
import CoreML
import PhotosUI


/* This is the pseudo code:
 
 App {
     @State var userName
     @State var userGoals
     @State var favoritesList
     @State var recentScans

     // First Screen
     LoginView()  // enter name, basic info
         -> AddInfoView()  // extra user info, such as allegerns and stuff
         -> GoalsView()  // choose goals (maybe a list of goals can pop up), they can choose multiple or just one.

     // Main Navigation
     TabView {
         HomeView() // dashboard with quick links, under the dashboard could be recent scans.
            
         BarcodeScannerView()
             // scan barcode, show nutritional value and green score in two different tabs??
             // add to recentScans

         RecommendationsView()
             // search food items, get nutritional + green suggestions to replace or add
            // this takes your goals into consideration
             //can favorite these items

         FavoritesView()
             // list of liked/favorited items, link to recommendations page possibly

         SettingsView()
             // edit/add name, goals, preferences, allergens
     }
 }

 // Example HomeView Layout
 HomeView {
     ShowWelcomeMessage(userName)
     ShowRecentScans()
     ShowRecommendedItems(favoritesList)
 }
 
        //future ideas:
            Could integrate an ai model where the user can type in stuff they dont like (such as coconut) and the recommendation page will not suggest anything with coconut in it.
            If the data is there, could say "you can save X carbon emissions if you buy this" which would show more impact
            Could have a "Like this? here are some similar items" When a user favorites an item this can pop up possibly.
 */

import SwiftUI
import AVFoundation
import PhotosUI

// MARK: - Welcome Screen
struct WelcomeView: View {
    @State private var isStarted = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 40) {
                Text("Welcome to Leaf & Fork")
                    .font(.largeTitle)
                    .multilineTextAlignment(.center)
                    .padding()
                
                Text("Scan foods to see their nutritional value and environmental impact!")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                NavigationLink(destination: HomeView(), isActive: $isStarted) {
                    Button("Start") {
                        isStarted = true
                    }
                    .font(.headline)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
        }
    }
}


struct HomeView: View {
    @State private var isShowingScanner = false
    @State private var scannedBarcode: String?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Button("Scan now") {
                    isShowingScanner = true
                }
                .font(.headline)
                .padding()
                .background(Color.purple)
                .foregroundColor(.white)
                .clipShape(Capsule())
                
                NavigationLink(
                    destination: ResultsView(barcode: scannedBarcode),
                    isActive: Binding(
                        get: { scannedBarcode != nil },
                        set: { _ in }
                    )
                ) { EmptyView() }
            }
            .sheet(isPresented: $isShowingScanner) {
                BarcodeScannerView { barcode in
                    isShowingScanner = false
                    scannedBarcode = barcode
                }
            }
        }
    }
}

// MARK: - Results Screen
struct ResultsView: View {
    var barcode: String? = nil
    
    // Product info
    @State private var productName: String = ""
    @State private var productImageURL: String = ""
    @State private var greenScoreResult: String = ""
    @State private var nutritionInfo: String = ""
    
    @State private var isShowingScanner = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 25) {
                    
                    // Product image
                    if let url = URL(string: productImageURL), !productImageURL.isEmpty {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 200)
                                .cornerRadius(12)
                        } placeholder: {
                            ProgressView()
                        }
                    }
                    
                    // Product name
                    if !productName.isEmpty {
                        Text(productName)
                            .font(.title2)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    
                    // Nutritional info
                    if !nutritionInfo.isEmpty {
                        Text("Nutritional Info:")
                            .font(.headline)
                        Text(nutritionInfo)
                            .padding()
                            .multilineTextAlignment(.center)
                            .background(Color.gray.opacity(0.15))
                            .cornerRadius(8)
                    }
                    
                    // Green Score result
                    if !greenScoreResult.isEmpty {
                        Text("Green Score: \(greenScoreResult)")
                            .font(.title2)
                            .foregroundColor(.green)
                            .padding()
                    }
                    
                    // Button to scan another barcode
                    Button("Scan Another Barcode") {
                        isShowingScanner = true
                    }
                    .font(.headline)
                    .padding()
                    .background(Color.purple)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                }
                .padding()
            }
            .navigationTitle("Food Scanner")
            .onAppear {
                if let code = barcode {
                    fetchProductInfo(for: code)
                }
            }
            .sheet(isPresented: $isShowingScanner) {
                BarcodeScannerView { barcode in
                    isShowingScanner = false
                    fetchProductInfo(for: barcode)
                }
            }
        }
    }
    
    // MARK: - Fetch Product Info (Name + Image + Nutrition + Green Score)
    func fetchProductInfo(for barcode: String) {
        guard let url = URL(string:
            "https://world.openfoodfacts.org/api/v0/product/\(barcode).json?fields=product_name,image_url,ecoscore_grade,nutriments"
        ) else {
            greenScoreResult = "Invalid barcode"
            nutritionInfo = ""
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data else {
                DispatchQueue.main.async {
                    greenScoreResult = "No data from server"
                    nutritionInfo = ""
                }
                return
            }
            
            struct Nutriments: Codable {
                let energy_kcal_100g: Double?
                let fat_100g: Double?
                let saturated_fat_100g: Double?
                let sugars_100g: Double?
                let proteins_100g: Double?
            }
            struct Product: Codable {
                let product_name: String?
                let image_url: String?
                let ecoscore_grade: String?
                let nutriments: Nutriments?
            }
            struct Response: Codable { let product: Product? }
            
            if let decoded = try? JSONDecoder().decode(Response.self, from: data) {
                DispatchQueue.main.async {
                    productName = decoded.product?.product_name ?? "Unknown Product"
                    productImageURL = decoded.product?.image_url ?? ""
                    greenScoreResult = decoded.product?.ecoscore_grade?.uppercased() ?? "Unknown"
                    
                    if let n = decoded.product?.nutriments {
                        nutritionInfo = """
                        Energy: \(n.energy_kcal_100g ?? 0) kcal / 100g
                        Fat: \(n.fat_100g ?? 0) g
                        Saturated Fat: \(n.saturated_fat_100g ?? 0) g
                        Sugars: \(n.sugars_100g ?? 0) g
                        Protein: \(n.proteins_100g ?? 0) g
                        """
                    } else {
                        nutritionInfo = "No nutritional info available"
                    }
                }
            } else {
                DispatchQueue.main.async {
                    greenScoreResult = "Error decoding data"
                    nutritionInfo = ""
                    productName = ""
                    productImageURL = ""
                }
            }
        }.resume()
    }
}

// MARK: - Barcode Scanner
struct BarcodeScannerView: UIViewControllerRepresentable {
    var onBarcodeScanned: (String) -> Void
    
    func makeUIViewController(context: Context) -> UIViewController {
        #if DEBUG
        // Show placeholder in Xcode Canvas preview
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            let placeholder = UIHostingController(rootView:
                ZStack {
                    Color.gray.opacity(0.3)
                    Text("Camera preview here")
                        .foregroundColor(.black)
                        .font(.headline)
                }
            )
            return placeholder
        }
        #endif
        
        // Real scanner at runtime
        let vc = ScannerViewController()
        vc.onBarcodeScanned = onBarcodeScanned
        return vc
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
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

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView_PreviewMode()
    }
}

// This is a PREVIEW-ONLY version of ContentView
struct ContentView_PreviewMode: View {

    var body: some View {
       //add the ui/ux all in here to test out how it looks.
    }
}
