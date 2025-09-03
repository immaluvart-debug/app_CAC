import SwiftUI
import AVFoundation
import Vision
import CoreML
import PhotosUI
import Foundation
import FirebaseAuth

import FirebaseFirestore
import FirebaseStorage

struct ScanItem: Identifiable, Codable {
    @DocumentID var id: String?
    var title: String
    var energy: Double
    var fat: Double
    var carbohydrates: Double
    var sugars: Double
    var fiber: Double
    var proteins: Double
    var salt: Double
    var greenScore: String
    var imageURL: String
    var scannedAt: Date
}

final class FirestoreManager {
    static let shared = FirestoreManager()
    private let db = Firestore.firestore()
    private let storage = Storage.storage()

    private init() {}

    // Save scan item to Firestore
    func saveScan(for userID: String, item: ScanItem, completion: @escaping (Error?) -> Void) {
        do {
            try db.collection("users")
                .document(userID)
                .collection("scans")
                .document()
                .setData(from: item)
            completion(nil)
        } catch {
            completion(error)
        }
    }

    // Fetch recent scans for a user
    func fetchScans(for userID: String, completion: @escaping ([ScanItem]) -> Void) {
        db.collection("users")
            .document(userID)
            .collection("scans")
            .order(by: "scannedAt", descending: true)
            .limit(to: 10)
            .getDocuments { snapshot, error in
                guard let docs = snapshot?.documents, error == nil else {
                    completion([])
                    return
                }

                let scans = docs.compactMap { try? $0.data(as: ScanItem.self) }
                completion(scans)
            }
    }

    // Upload custom image to Firebase Storage
    func uploadImage(_ image: UIImage, userID: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            completion(.failure(NSError(domain: "ImageError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to compress image"])))
            return
        }

        let ref = storage.reference().child("users/\(userID)/scans/\(UUID().uuidString).jpg")
        ref.putData(imageData, metadata: nil) { _, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            ref.downloadURL { url, error in
                if let url = url {
                    completion(.success(url.absoluteString))
                } else {
                    completion(.failure(error ?? NSError(domain: "ImageURL", code: -1, userInfo: nil)))
                }
            }
        }
    }
}


// Mark: - ContentView
struct ContentView: View {
    
    @State private var selectedImage: UIImage?
    @State private var classificationResult: String = "No image classified yet"
    @State private var greenScoreResult: String = ""
    @State private var isShowingScanner = false
    @State private var photoItem: PhotosPickerItem? = nil
    @State private var nutritionInfo: String = ""
    @State private var productImageURL: URL? = nil

    var body: some View {
        NavigationView {
            ZStack {
                Color.ourgreen.ignoresSafeArea()

                VStack(spacing: 25) {
                    // Display selected image
                    if let selectedImage {
                        Image(uiImage: selectedImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 250)
                            .cornerRadius(12)
                            .background(Color.ourgreen)
                    }

                    // Classification result
                    Text(classificationResult)
                        .font(.custom("Quicksand-Regular", size: 30))
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.ourgreen.opacity(0.15))
                        .cornerRadius(8)

                    // Green Score result
                    if !greenScoreResult.isEmpty {
                        Text("Green Score: \(greenScoreResult)")
                            .font(.custom("Quicksand-Regular", size: 30))
                            .foregroundColor(.black)
                            .padding()
                    }

                    // Product image
                    if let imageURL = productImageURL {
                        AsyncImage(url: imageURL) { phase in
                            switch phase {
                            case .empty:
                                ProgressView()
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxHeight: 200)
                                    .cornerRadius(10)
                            case .failure:
                                Text("Failed to load image")
                            @unknown default:
                                EmptyView()
                            }
                        }
                    }

                    // Nutrition result
                    if !nutritionInfo.isEmpty {
                        Text(nutritionInfo)
                            .font(.custom("Quicksand-Regular", size: 20))
                            .foregroundColor(.black)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.gray)
                            .cornerRadius(8)
                    }

                    // PhotosPicker Button
                    PhotosPicker("Classify Image", selection: $photoItem, matching: .images)
                        .font(.custom("Quicksand-Regular", size: 20))
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 0)
                                .fill(Color.grey)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 0)
                                .stroke(Color(white: 0.2), lineWidth: 2) // darkestGrey
                        )
                        .foregroundColor(.white)
                        .onChange(of: photoItem) { newItem in
                            Task {
                                if let data = try? await newItem?.loadTransferable(type: Data.self),
                                   let uiImage = UIImage(data: data) {
                                    selectedImage = uiImage
                                    classifyImage(uiImage)
                                }
                            }
                        }

                    // Barcode Scanner Button
                    Button("Scan Barcode for Green Score") {
                        isShowingScanner = true
                    }
                    .font(.custom("Quicksand-Regular", size: 20))
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 0)
                            .fill(Color.darkestGrey)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 0)
                            .stroke(Color(white: 0.2), lineWidth: 2) // darkestGrey
                    )
                    .foregroundColor(.white)
                }
                .padding()
                
                Image("leaf")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .padding(.top, 8)
            }
            .navigationTitle("Food Scanner")
            .accentColor(.white)
            .font(.custom("Quicksand-Regular", size: 35))
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
            let model = try VNCoreMLModel(for: MobileNet().model)
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

    func fetchGreenScore(for barcode: String) {
        guard let url = URL(string: "https://world.openfoodfacts.org/api/v0/product/\(barcode).json") else {
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

            struct Nutriments: Codable {
                let energy_kcal: Double?
                let fat: Double?
                let carbohydrates: Double?
                let sugars: Double?
                let fiber: Double?
                let proteins: Double?
                let salt: Double?
            }

            struct Product: Codable {
                let product_name: String?
                let ecoscore_grade: String?
                let image_url: String?
                let nutriments: Nutriments?
            }

            struct Response: Codable {
                let product: Product?
            }

            if let decoded = try? JSONDecoder().decode(Response.self, from: data),
               let product = decoded.product {

                DispatchQueue.main.async {
                    greenScoreResult = product.ecoscore_grade?.uppercased() ?? "Unknown"

                    if let imageURLString = product.image_url,
                       let url = URL(string: imageURLString) {
                        productImageURL = url
                    } else {
                        productImageURL = nil
                    }

                    if let n = product.nutriments {
                        nutritionInfo = """
                        Energy: \(n.energy_kcal ?? 0) kcal
                        Fat: \(n.fat ?? 0) g
                        Carbs: \(n.carbohydrates ?? 0) g
                        Sugars: \(n.sugars ?? 0) g
                        Fiber: \(n.fiber ?? 0) g
                        Proteins: \(n.proteins ?? 0) g
                        Salt: \(n.salt ?? 0) g
                        """
                    } else {
                        nutritionInfo = "No nutrition data available"
                    }

                    // ✅ Save scanned item to Firestore
                    if let user = Auth.auth().currentUser {
                        let scanItem = ScanItem(
                            title: product.product_name ?? "Unknown Product",
                            energy: product.nutriments?.energy_kcal ?? 0,
                            fat: product.nutriments?.fat ?? 0,
                            carbohydrates: product.nutriments?.carbohydrates ?? 0,
                            sugars: product.nutriments?.sugars ?? 0,
                            fiber: product.nutriments?.fiber ?? 0,
                            proteins: product.nutriments?.proteins ?? 0,
                            salt: product.nutriments?.salt ?? 0,
                            greenScore: product.ecoscore_grade?.uppercased() ?? "Unknown",
                            imageURL: product.image_url ?? "",
                            scannedAt: Date()
                        )

                        FirestoreManager.shared.saveScan(for: user.uid, item: scanItem) { error in
                            if let error = error {
                                print("🔥 Failed to save scan: \(error.localizedDescription)")
                            } else {
                                print("✅ Scan saved successfully!")
                            }
                        }
                    }
                }
            } else {
                DispatchQueue.main.async {
                    greenScoreResult = "Error decoding data"
                }
            }
        }.resume()
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
            view.backgroundColor = .green

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
}

//MARK: - WelcomeView
struct WelcomeView: View {
    @State private var isLogin = true
    @State private var email = ""
    @State private var password = ""
    // navigation states
    @State private var navigateToHome = false
    @State private var navigateToPreferences = false
    // ui states
    @State private var errorMessage = ""
    @State private var isLoading = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.ourgreen.ignoresSafeArea()
                
                VStack(spacing: 20) {
                    Image("app_CAC icon")
                        .resizable()
                        .frame(width: 175, height: 175)
                    Text("welcome")
                        .font(.custom("Allura-Regular", size: 70))
                        .foregroundStyle(Color(.white))
                    
                    ZStack {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.lightestgreen)
                            .frame(width: 345, height: 420)
                        
                        VStack(spacing: 14) {
                            HStack(spacing: 16) {
                                Button {
                                    isLogin = true
                                    email = ""
                                    password = ""
                                    errorMessage = ""
                                } label: {
                                    Text("LOG IN")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                        .padding(.vertical, 15)
                                        .padding(.horizontal, 20)
                                        .background(Color("darkestGrey"))
                                }
                                
                                Button {
                                    isLogin = false
                                    email = ""
                                    password = ""
                                    errorMessage = ""
                                } label: {
                                    Text("SIGN UP")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                        .padding(.vertical, 15)
                                        .padding(.horizontal, 20)
                                        .background(Color("darkestGrey"))
                                }
                            }
                            
                            ZStack {
                                Rectangle()
                                    .fill(Color("darkestGrey"))
                                    .frame(width: 280, height: 260)
                                
                                VStack(alignment: .leading, spacing: 12) {
                                    if isLogin {
                                        Text("enter email:")
                                            .foregroundColor(.white)
                                        TextField("you@example.com", text: $email)
                                            .textFieldStyle(RoundedBorderTextFieldStyle())
                                            .frame(width: 250)
                                            .autocapitalization(.none)
                                            .keyboardType(.emailAddress)
                                        
                                        Text("enter password:")
                                            .foregroundColor(.white)
                                        SecureField("Password", text: $password)
                                            .textFieldStyle(RoundedBorderTextFieldStyle())
                                            .frame(width: 250)
                                        
                                        if !errorMessage.isEmpty {
                                            Text(errorMessage)
                                                .foregroundColor(.red)
                                                .font(.system(size: 14))
                                        }
                                        
                                        Button(action: loginTapped) {
                                            HStack {
                                                if isLoading {
                                                    ProgressView().scaleEffect(0.8)
                                                }
                                                Text("OK")
                                                    .font(.headline)
                                                    .foregroundColor(.white)
                                                    .padding()
                                                    .frame(width: 100)
                                                    .background(Color("grey"))
                                                    .cornerRadius(8)
                                            }
                                        }
                                        .disabled(email.isEmpty || password.isEmpty || isLoading)
                                        
                                    } else {
                                        Text("create email:")
                                            .foregroundColor(.white)
                                        TextField("you@example.com", text: $email)
                                            .textFieldStyle(RoundedBorderTextFieldStyle())
                                            .frame(width: 250)
                                            .autocapitalization(.none)
                                            .keyboardType(.emailAddress)
                                        
                                        Text("create password:")
                                            .foregroundColor(.white)
                                        SecureField("Password", text: $password)
                                            .textFieldStyle(RoundedBorderTextFieldStyle())
                                            .frame(width: 250)
                                        
                                        if !errorMessage.isEmpty {
                                            Text(errorMessage)
                                                .foregroundColor(.red)
                                                .font(.system(size: 14))
                                        }
                                        
                                        Button(action: signUpTapped) {
                                            HStack {
                                                if isLoading {
                                                    ProgressView().scaleEffect(0.8)
                                                }
                                                Text("OK")
                                                    .font(.headline)
                                                    .foregroundColor(.white)
                                                    .padding()
                                                    .frame(width: 100)
                                                    .background(Color("grey"))
                                                    .cornerRadius(8)
                                            }
                                        }
                                        .disabled(email.isEmpty || password.isEmpty || isLoading)
                                    }
                                    
                                    // Hidden NavigationLinks — triggered only on success
                                    NavigationLink(destination: HomeView(), isActive: $navigateToHome) { EmptyView() }
                                    NavigationLink(destination: PreferencesView(), isActive: $navigateToPreferences) { EmptyView() }
                                }
                                .padding()
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
    }

   // MARK: - Actions
   private func loginTapped() {
       errorMessage = ""
       isLoading = true
       FirebaseAuthManager.shared.login(email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                                        password: password) { result in
           isLoading = false
           switch result {
           case .success:
               errorMessage = ""
               navigateToHome = true
           case .failure(let error):
               errorMessage = error.localizedDescription
               navigateToHome = false
           }
       }
   }

   private func signUpTapped() {
       errorMessage = ""
       isLoading = true
       FirebaseAuthManager.shared.signUp(email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                                         password: password) { result in
           isLoading = false
           switch result {
           case .success:
               errorMessage = ""
               navigateToPreferences = true
           case .failure(let error):
               errorMessage = error.localizedDescription
               navigateToPreferences = false
           }
       }
   }
}
    
       
    
    /*
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Text("Leaf&Fork Login")
                    .font(.custom("Quicksand-Regular", size: 35))
                    .fontWeight(.bold)
                    .padding(.top, 100)
                
                NavigationLink(destination: CreateAccountView()) {
                    Text("Create New Account")
                        .font(.custom("Quicksand-Regular", size: 20))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.grey)
                        .foregroundColor(.white)
                        .cornerRadius(0)
                        .overlay(
                            RoundedRectangle(cornerRadius: 0)
                                .stroke(Color.white, lineWidth: 2)
                        )
                }

                NavigationLink(destination: LoginView()) {
                    Text("Returning User")
                        .font(.custom("Quicksand-Regular", size: 20))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.darkestGrey)
                        .foregroundColor(.white)
                        .cornerRadius(0)
                        .overlay(
                            RoundedRectangle(cornerRadius: 0)
                                .stroke(Color.white, lineWidth: 2)
                        )
                }

                
                Spacer()
                
                Image("leafIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 40)

            }
            .padding()
            .background(Color.ourgreen)
            .foregroundColor(.white)
            .edgesIgnoringSafeArea(.all)
            .navigationTitle("")
            .navigationBarHidden(true)
        }
    }
     */
    


//MARK: - Create Account
struct CreateAccountView: View {
   
    
    /*
     @State private var username: String = ""
    @State private var password: String = ""
    @State private var navigateToPreferences = false
    
    var body: some View {
        ZStack {
            Color.ourgreen.ignoresSafeArea()
        }
        
        VStack(spacing: 20) {
            Text("Create Account")
                .font(.custom("Quicksand-Regular", size: 30))
                .fontWeight(.bold)
                .padding(.top, 60)
            
            // Username
            VStack(alignment: .leading) {
                Text("Create Username")
                    .font(.custom("Quicksand-Regular", size: 20))
                TextField("Enter username", text: $username)
                    .font(.custom("Quicksand-Regular", size: 20))
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocapitalization(.none)
            }
            
            // Password
            VStack(alignment: .leading) {
                Text("Create Password")
                    .font(.custom("Quicksand-Regular", size: 20))
                SecureField("Enter password", text: $password)
                    .font(.custom("Quicksand-Regular", size: 20))
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            
            // Submit Button
            Button(action: {
                saveCredentials()
                navigateToPreferences = true
            }) {
                Text("Register")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.grey)
                    .foregroundColor(.white)
                    .cornerRadius(0)
                    .font(.custom("Quicksand-Regular", size: 25))
            }
            .disabled(username.isEmpty || password.isEmpty)
            
            NavigationLink(destination: PreferencesView(), isActive: $navigateToPreferences) {
                EmptyView()
            }
            
            Spacer()
        }
        .padding()
        .navigationTitle("Create Account")
    }
    
    // Save credentials using UserDefaults
    func saveCredentials() {
        UserDefaults.standard.set(username, forKey: "savedUsername")
        UserDefaults.standard.set(password, forKey: "savedPassword")
    }
     */

        @State private var email = ""
        @State private var password = ""
        @State private var errorMessage = ""
        @State private var navigateToPreferences = false
    @State private var navigateToHome = false

        var body: some View {
            VStack(spacing: 20) {
                Text("Create Account")
                    .font(.custom("Quicksand-Regular", size: 30))
                    .fontWeight(.bold)
                    .padding(.top, 60)

                TextField("Enter Email", text: $email)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                SecureField("Enter Password", text: $password)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.custom("Quicksand-Regular", size: 18))
                }

                Button(action: {
                    FirebaseAuthManager.shared.signUp(email: email, password: password) { result in
                        switch result {
                        case .success:
                            errorMessage = ""
                            navigateToHome = true
                        case .failure(let error):
                            errorMessage = error.localizedDescription
                            navigateToHome = false
                        }
                    }
                }) {
                    Text("Sign Up")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.darkestGrey)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .disabled(email.isEmpty || password.isEmpty)

                NavigationLink(destination: PreferencesView(), isActive: $navigateToPreferences) {
                    EmptyView()
                }
            }
            .padding()
            .navigationTitle("Create Account")
        }
}

//MARK: - Login View
struct LoginView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage = ""
    @State private var navigateToHome = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TextField("Email", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .keyboardType(.emailAddress)
                
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }
                
                Button(action: {
                    FirebaseAuthManager.shared.login(email: email, password: password) { result in
                        switch result {
                        case .success:
                            errorMessage = ""
                            navigateToHome = true  // ✅ Navigate only on success
                        case .failure(let error):
                            errorMessage = error.localizedDescription
                            navigateToHome = false
                        }
                    }
                }) {
                    Text("Log In")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .disabled(email.isEmpty || password.isEmpty)
                
                NavigationLink("Sign Up", destination: LoginView())
            }
            .padding()
            .navigationDestination(isPresented: $navigateToHome) {
                HomeView()  // ✅ Navigate to HomeView only if login succeeds
            }
        }
    }
    }




//MARK: - Preferences

struct PreferencesView: View {
    let preferenceOptions = [
        "Gluten-Free",
        "Vegan",
        "Vegetarian",
        "Halal",
        "Kosher",
        "Lactose-Free",
        "Peanut-Free",
        "Keto"
    ]
    
    @State private var selectedPreferences: Set<String> = []
    @State private var navigateToGoals = false
    
    
    var body: some View {
        VStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text("Choose Preferences")
                        .font(.custom("Quicksand-Regular", size: 30))
                        .fontWeight(.bold)
                        .foregroundColor(Color.white)
                        .padding(.top, 40)
                    
                    ForEach(preferenceOptions, id: \.self) { option in
                        PreferenceRow(
                            title: option,
                            isSelected: selectedPreferences.contains(option),
                            highlightColor: Color.lightgreen
                        ) {
                            toggleSelection(for: option)
                        }
                    }
                }
                .padding()
            }
            
            VStack {
                Button(action: {
                    savePreferences()
                    navigateToGoals = true
                }) {
                    Text("Continue")
                        .font(.custom("Quicksand-Regular", size: 25))
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.darkgreen)
                        .foregroundColor(.white)
                        .cornerRadius(0)
                        .overlay(
                            RoundedRectangle(cornerRadius: 0)
                                .stroke(Color.white, lineWidth: 2.5)
                 )
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
                
                NavigationLink(destination: GoalsView(), isActive: $navigateToGoals) {
                    EmptyView()
                }
            }
        }
        .background(Color.lightGrey.ignoresSafeArea())
        .navigationTitle("Preferences")
    }
    
    private func toggleSelection(for option: String) {
        if selectedPreferences.contains(option) {
            selectedPreferences.remove(option)
        } else {
            selectedPreferences.insert(option)
        }
    }
    
    private func savePreferences() {
        let prefsArray = Array(selectedPreferences)
        UserDefaults.standard.set(prefsArray, forKey: "userPreferences")
    }
}

struct PreferenceRow: View {
    let title: String
    let isSelected: Bool
    let highlightColor: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.custom("Quicksand-Regular", size: 20))
                    .foregroundColor(isSelected ? highlightColor : .white)
                Spacer()
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundColor(isSelected ? highlightColor : .white)
                    .font(.title2)
            }
            .padding()
            .background(Color.darkestGrey)
            .cornerRadius(0)
            .overlay(
                RoundedRectangle(cornerRadius: 0)
                    .stroke(isSelected ? highlightColor : Color.gray.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: Color.grey.opacity(0.05), radius: 3, x: 0, y: 1)
        }
        .buttonStyle(PlainButtonStyle())
    }
}



//MARK: - Goals

struct GoalsView: View {
    let goalOptions = [
        "Eat Greener",
        "Lose Weight",
        "Gain Weight",
        "Maintain Weight",
        "Lose Fat",
        "Gain Muscle"
    ]
    
    @State private var selectedGoals: Set<String> = []
    @State private var navigateToContent = false
    
    
    var body: some View {
        VStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text("Select Your Goals")
                        .font(.custom("Quicksand-Regular", size: 30))
                        .fontWeight(.bold)
                        .foregroundColor(Color.white)
                        .padding(.top, 40)
                    
                    ForEach(goalOptions, id: \.self) { goal in
                        GoalRow(
                            title: goal,
                            isSelected: selectedGoals.contains(goal),
                            highlightColor: Color.lightgreen
                        ) {
                            toggleGoal(goal)
                        }
                    }
                }
                .padding()
            }
            
            VStack {
                Button(action: {
                    saveGoals()
                    navigateToContent = true
                }) {
                    Text("Continue")
                        .font(.custom("Quicksand-Regular", size: 25))
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.darkgreen)
                        .foregroundColor(.white)
                        .cornerRadius(0)
                        .overlay(
                            RoundedRectangle(cornerRadius: 0)
                                .stroke(Color.white, lineWidth: 2.5)
                )
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
                
                // Navigation to ContentView
                NavigationLink(destination: HomeView(), isActive: $navigateToContent) {
                    EmptyView()
                }
            }
        }
        .background(Color.lightGrey.ignoresSafeArea())
        .navigationTitle("Goals")
    }
    
    private func toggleGoal(_ goal: String) {
        if selectedGoals.contains(goal) {
            selectedGoals.remove(goal)
        } else {
            selectedGoals.insert(goal)
        }
    }
    
    private func saveGoals() {
        let goalsArray = Array(selectedGoals)
        UserDefaults.standard.set(goalsArray, forKey: "userGoals")
    }
}

struct FillerView: View {
    var body: some View {
        ZStack{
            Color("grey")
                .ignoresSafeArea()
        }
    }
}

struct GoalRow: View {
    let title: String
    let isSelected: Bool
    let highlightColor: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.custom("Quicksand-Regular", size: 20))
                    .foregroundColor(isSelected ? highlightColor : .white)
                Spacer()
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundColor(isSelected ? highlightColor : .gray)
                    .font(.title2)
            }
            .padding()
            .background(Color.darkestGrey)
            .cornerRadius(0)
            .overlay(
                RoundedRectangle(cornerRadius: 0)
                    .stroke(isSelected ? highlightColor : Color.gray.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: Color.grey.opacity(0.05), radius: 3, x: 0, y: 1)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
/*
struct HomeView: View {
    var body: some View {
        NavigationView {
            ZStack {
                // Background color
                Color("ourgreen")
                    .ignoresSafeArea()
                
                VStack(spacing: 20) {
                    
                    // MARK: - Top Section (Centered Logo + Right Icons)
                    ZStack {
                        // Centered Logo
                        Image("app_CAC icon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 150, height: 150)
                            .padding(.top, 0)
                        
                        HStack {
                            Spacer()
                            VStack {
                                // Settings Gear (navigation link)
                                NavigationLink(destination: SettingsView()) {
                                    Image(systemName: "gearshape")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 40, height: 40)
                                        .padding(.top, 10)
                                }
                                .buttonStyle(PlainButtonStyle())
                                
                                Spacer()
                                
                                // Heart Icon
                                Image("heart_icon")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 50, height: 50)
                                    .padding(.bottom, 0)
                            }
                            .padding(.trailing, 15)
                        }
                    }
                    .padding(.top, 20)
                    .navigationBarHidden(true)
                    
                    // MARK: - RECOMMENDED / NEAR ME Buttons
                    HStack(spacing: 0) {
                        NavigationLink(destination: FillerView()) {
                            Text("RECOMMENDED")
                                .font(.custom("BebasNeue-Regular", size: 30))
                                .frame(width: 172)
                                .padding(.vertical, 5)
                                .foregroundColor(.white)
                                .background(Color("grey"))
                        }
                        
                        NavigationLink(destination: FillerView()) {
                            Text("NEAR ME")
                                .font(.custom("BebasNeue-Regular", size: 30))
                                .frame(width: 172)
                                .padding(.vertical, 5)
                                .foregroundColor(.white)
                                .background(Color("grey"))
                        }
                    }
                    .cornerRadius(5)
                    
                    // MARK: - Recent Scans Section
                    VStack(alignment: .leading, spacing: 10) {
                        
                        
                        VStack(alignment: .leading) {
                           
                            HStack {
                                Text("Recent Scans")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .padding(.top, 15)
                                Spacer()
                            }
                            .padding(.leading, 15)
                            
                            ScrollView {
                                VStack(spacing: 20) {
                                    // First scan item (green)
                                    scanItem(
                                        imageName: "imgPlaceholder",
                                        title: "Doritos bits bbq",
                                        energy: "x Cal",
                                        fat: "29.0g",
                                        yada: "6g",
                                        sodium: "999mg",
                                        other: "67j",
                                        greenScore: 5,
                                        borderColor: .green
                                    )
                                    
                                    // Second scan item (red)
                                    scanItem(
                                        imageName: "imgPlaceholder",
                                        title: "Flaming Hot Cheetos",
                                        energy: "x Cal",
                                        fat: "29.0g",
                                        yada: "6g",
                                        sodium: "999mg",
                                        other: "67j",
                                        greenScore: 4,
                                        borderColor: .red
                                    )
                                }
                                .padding(.horizontal, 15)
                                .padding(.top, 5)
                                .padding(.bottom, 15)
                            }
                        }
                        .background(Color("lightestgreen"))
                        .cornerRadius(10)
                        .padding(.horizontal, 10)
                        .frame(height: 350)
                    }
                    
                    // MARK: - Scan Button
                    NavigationLink(destination: ContentView()) {
                        Text("SCAN")
                            .font(.custom("BebasNeue-Regular", size: 30))
                            .frame(width: 150, height: 60)
                            .foregroundColor(.white)
                            .background(Color("grey"))
                            .cornerRadius(10)
                    }
                    .padding(.top, 10)
                    
                    Spacer()
                }
            }
        }
    }
}


        // MARK: - Scan Item View
        
        func scanItem(
            imageName: String,
            title: String,
            energy: String,
            fat: String,
            yada: String,
            sodium: String,
            other: String,
            greenScore: Int,
            borderColor: Color
        ) -> some View {
            
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Image(imageName)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(borderColor, lineWidth: 2))
                    
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    HStack {
                        Text("Energy: \(energy)")
                        Spacer()
                        Text("Fat: \(fat)")
                    }
                    .foregroundColor(.white)
                    
                    HStack {
                        Text("Yada: \(yada)")
                        Spacer()
                        Text("Sodium: \(sodium)")
                    }
                    .foregroundColor(.white)
                    
                    Text("Other: \(other)")
                        .foregroundColor(.white)
                }
                .padding()
                .background(Color("grey"))
                .overlay(
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(borderColor, lineWidth: 4)
                )
                .cornerRadius(15)
                .frame(width: 320)
                
                // GREEN/RED Score Rectangle (attached to the box)
                Text("GREEN SCORE: \(greenScore)")
                    .font(.headline)
                    .frame(width: 320, height: 35)
                    .background(borderColor)
                    .cornerRadius(8)
                    .foregroundColor(.white)
            }
        }
        */
struct HomeView: View {
    @State private var recentScans: [ScanItem] = []

     var body: some View {
         NavigationView {
             ZStack {
                 Color("ourgreen").ignoresSafeArea()

                 VStack(spacing: 15) {
                     // MARK: - Top Logo & Recommended Bar
                     VStack(spacing: 5) {
                         Image("app_CAC icon")
                             .resizable()
                             .scaledToFit()
                             .frame(width: 140, height: 140)

                         HStack(spacing: 0) {
                             Text("RECOMMENDED")
                                 .font(.custom("BebasNeue-Regular", size: 22))
                                 .foregroundColor(.white)
                                 .frame(maxWidth: .infinity)
                                 .padding(.vertical, 8)
                                 .background(Color("grey"))

                             Text("NEAR ME")
                                 .font(.custom("BebasNeue-Regular", size: 22))
                                 .foregroundColor(.white)
                                 .frame(maxWidth: .infinity)
                                 .padding(.vertical, 8)
                                 .background(Color("grey"))
                         }
                         .cornerRadius(5)
                         .padding(.horizontal, 15)
                     }

                     // MARK: - Recent Scans Section
                     VStack(alignment: .leading, spacing: 10) {
                         Text("Recent Scans")
                             .font(.title2)
                             .fontWeight(.bold)
                             .padding(.leading, 15)
                             .padding(.top, 5)

                         ScrollView {
                             VStack(spacing: 15) {
                                 ForEach(recentScans) { scan in
                                     scanItem(scan: scan)
                                 }
                             }
                             .padding(.horizontal, 15)
                             .padding(.vertical, 10)
                         }
                     }
                     .background(Color("lightestgreen"))
                     .cornerRadius(15)
                     .padding(.horizontal, 10)
                     .frame(height: 400)

                     // MARK: - Scan Button
                     NavigationLink(destination: ContentView()) {
                         Text("SCAN")
                             .font(.custom("BebasNeue-Regular", size: 30))
                             .frame(width: 180, height: 60)
                             .foregroundColor(.white)
                             .background(Color("grey"))
                             .cornerRadius(10)
                     }
                     .padding(.top, 10)

                     Spacer()
                 }
             }
         }
         .onAppear(perform: fetchRecentScans)
     }

     // MARK: - Fetch Scans
     private func fetchRecentScans() {
         if let user = Auth.auth().currentUser {
             FirestoreManager.shared.fetchScans(for: user.uid) { scans in
                 DispatchQueue.main.async {
                     self.recentScans = scans
                 }
             }
         }
     }

     // MARK: - Scan Item Card
     private func scanItem(scan: ScanItem) -> some View {
         VStack(spacing: 0) {
             HStack(alignment: .top, spacing: 15) {
                 // Product Image
                 AsyncImage(url: URL(string: scan.imageURL)) { phase in
                     switch phase {
                     case .empty:
                         ProgressView()
                             .frame(width: 80, height: 80)
                     case .success(let image):
                         image.resizable()
                             .scaledToFill()
                             .frame(width: 80, height: 80)
                             .clipShape(RoundedRectangle(cornerRadius: 8))
                     case .failure:
                         Image(systemName: "photo")
                             .resizable()
                             .scaledToFit()
                             .frame(width: 80, height: 80)
                             .background(Color.gray.opacity(0.3))
                             .clipShape(RoundedRectangle(cornerRadius: 8))
                     @unknown default:
                         EmptyView()
                     }
                 }

                 // Nutrition Info
                 VStack(alignment: .leading, spacing: 4) {
                     Text(scan.title)
                         .font(.headline)
                         .foregroundColor(.white)
                         .lineLimit(2)

                     Text("Energy: \(String(format: "%.2f", scan.energy)) kcal")
                         .foregroundColor(.white)
                     Text("Fat: \(String(format: "%.2f", scan.fat)) g")
                         .foregroundColor(.white)
                     Text("Carbs: \(String(format: "%.2f", scan.carbohydrates)) g")
                         .foregroundColor(.white)
                     Text("Sugars: \(String(format: "%.2f", scan.sugars)) g")
                         .foregroundColor(.white)
                     Text("Fiber: \(String(format: "%.2f", scan.fiber)) g")
                         .foregroundColor(.white)
                 }
             }
             .padding()
             .background(Color("grey"))
             .cornerRadius(15)

             // Green Score Bar
             Text("GREEN SCORE: \(scan.greenScore)")
                 .font(.custom("BebasNeue-Regular", size: 18))
                 .frame(width: 300, height: 35)
                 .background(
                     scan.greenScore.uppercased() == "A" || scan.greenScore.uppercased() == "B"
                     ? Color.green
                     : Color.red
                 )
                 .cornerRadius(8)
                 .foregroundColor(.white)
                 .padding(.top, 5)
         }
     }
}

        //MARK: - Settings
struct SettingsView: View {
    var body: some View {
        ZStack {
            Color("ourgreen")
                .ignoresSafeArea()  // fills whole screen
            
            VStack(spacing: 20) {
                NavigationLink(destination: PreferencesView()) {
                    CustomButton(title: "Adjust Preferences and Goals")
                }
                CustomButton(title: "App Settings")
                CustomButton(title: "Help")
            }
            .padding()
            .navigationTitle("Settings")
        }
    }
}

        
        struct CustomButton: View {
            var title: String
            
            var body: some View {
                Text(title)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color("darkestGrey"))
                    .foregroundColor(.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 0)
                            .stroke(Color.white, lineWidth: 2)
                    )
                    .cornerRadius(0)
            }
            
        }
    
//MARK: - Log in/ sign up user backend
final class FirebaseAuthManager {
    static let shared = FirebaseAuthManager()
    private init() {}

    func signUp(email: String, password: String, completion: @escaping (Result<AuthDataResult, Error>) -> Void) {
        Auth.auth().createUser(withEmail: email, password: password) { authResult, error in
            if let error = error as NSError? {
                let authError: NSError
                switch AuthErrorCode(rawValue: error.code) {
                case .emailAlreadyInUse:
                    authError = NSError(domain: "", code: error.code, userInfo: [NSLocalizedDescriptionKey: "This email is already registered. Please log in instead."])
                case .invalidEmail:
                    authError = NSError(domain: "", code: error.code, userInfo: [NSLocalizedDescriptionKey: "Invalid email format."])
                case .weakPassword:
                    authError = NSError(domain: "", code: error.code, userInfo: [NSLocalizedDescriptionKey: "Password is too weak. Use at least 6 characters."])
                default:
                    authError = error
                }
                completion(.failure(authError))
                return
            }

            if let authResult = authResult {
                completion(.success(authResult))
            }
        }
    }

    func login(email: String, password: String, completion: @escaping (Result<AuthDataResult, Error>) -> Void) {
        Auth.auth().signIn(withEmail: email, password: password) { authResult, error in
            if let err = error as NSError? {
                let mapped = Self.mapError(err)
                DispatchQueue.main.async { completion(.failure(mapped)) }
                return
            }
            if let authResult = authResult {
                DispatchQueue.main.async { completion(.success(authResult)) }
            } else {
                DispatchQueue.main.async { completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown login error"]))) }
            }
        }
    }

    func signOut() throws {
        try Auth.auth().signOut()
    }

    private static func mapError(_ error: NSError) -> NSError {
        guard let code = AuthErrorCode(rawValue: error.code) else { return error }
        let message: String
        switch code {
        case .userNotFound:
            message = "No account found for this email. Please sign up first."
        case .wrongPassword:
            message = "Incorrect password. Please try again."
        case .invalidEmail:
            message = "Invalid email format."
        case .emailAlreadyInUse:
            message = "This email is already registered. Try logging in."
        case .networkError:
            message = "Network error. Check your connection."
        default:
            message = error.localizedDescription
        }
        return NSError(domain: error.domain, code: error.code, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
    

