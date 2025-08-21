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

    // MARK: - Fetch Green Score
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
                let saturated_fat: Double?
                let carbohydrates: Double?
                let sugars: Double?
                let fiber: Double?
                let proteins: Double?
                let salt: Double?
            }

            struct Product: Codable {
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
                        let info = """
                        Energy: \(n.energy_kcal ?? 0) kcal
                        Fat: \(n.fat ?? 0) g
                        Saturated Fat: \(n.saturated_fat ?? 0) g
                        Carbohydrates: \(n.carbohydrates ?? 0) g
                        Sugars: \(n.sugars ?? 0) g
                        Fiber: \(n.fiber ?? 0) g
                        Proteins: \(n.proteins ?? 0) g
                        Salt: \(n.salt ?? 0) g
                        """
                        nutritionInfo = info
                    } else {
                        nutritionInfo = "No nutrition data available"
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
}

//MARK: - Create Account
struct CreateAccountView: View {
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
}

//MARK: - Login View
struct LoginView: View {
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var loginFailed = false
    @State private var navigateToPreferences = false
    
    var body: some View {
        ZStack {
            Color.ourgreen.ignoresSafeArea()
        }
       
        VStack(spacing: 20) {
            Text("Login")
                .font(.custom("Quicksand-Regular", size: 30))
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.top, 60)
            
            TextField("Username", text: $username)
                .font(.custom("Quicksand-Regular", size: 20))
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .autocapitalization(.none)
            
            SecureField("Password", text: $password)
                .font(.custom("Quicksand-Regular", size: 20))
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            if loginFailed {
                Text("Invalid username or password")
                    .foregroundColor(.red)
                    .font(.custom("Quicksand-Regular", size: 25))
            }
            
            Button(action: {
                if checkCredentials() {
                    loginFailed = false
                    navigateToPreferences = true
                } else {
                    loginFailed = true
                }
            }) {
                Text("Log In")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.darkestGrey)
                    .foregroundColor(.white)
                    .cornerRadius(0)
                    .font(.custom("Quicksand-Regular", size: 25))
            }
            .padding(.top)
            
            // Navigate to PreferencesView
            NavigationLink(destination: PreferencesView(), isActive: $navigateToPreferences) {
                EmptyView()
            }
            
            Spacer()
        }
        .padding()
        .navigationTitle("Login")
    }
    
    // Check stored credentials
    func checkCredentials() -> Bool {
        let savedUsername = UserDefaults.standard.string(forKey: "savedUsername") ?? ""
        let savedPassword = UserDefaults.standard.string(forKey: "savedPassword") ?? ""
        return username == savedUsername && password == savedPassword
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
                NavigationLink(destination: ContentView(), isActive: $navigateToContent) {
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



