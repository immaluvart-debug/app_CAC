import SwiftUI
import Vision
import CoreML
import PhotosUI

struct ContentView: View {
    @State private var selectedImage: UIImage?
    @State private var classificationResult: String = "No image classified yet"
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var photoItem: PhotosPickerItem? // @state combines the internal stuff with the view
    
    var body: some View {
        VStack(spacing: 20) { //20 pixels spacing around the stack, Everyhing in the vstack stacks horizontallly
            
            //display the img
            if let selectedImage { //if let is a safe way to bind optional values. if somehow there is no pic taken then it will not cause an error basically (IF the image is there LET it show)
                Image(uiImage: selectedImage)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 200)
            }
            
            // Display classification result
            Text(classificationResult)
                .font(.title)
                .multilineTextAlignment(.center)
                .padding()
            
            // Pick from photo library
            PhotosPicker("Pick an Image", selection: $photoItem, matching: .images)
                .font(.headline)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .clipShape(Capsule())
                .onChange(of: photoItem) { _ in
                    loadImageFromPicker()
                }
            
            // Capture from camera
            Button("Use Live Camera") {
                showCamera = true
            }
            .font(.headline)
            .padding()
            .background(Color.green)
            .foregroundColor(.white)
            .clipShape(Capsule())
            .sheet(isPresented: $showCamera) {
                ImagePicker(sourceType: .camera) { image in
                    selectedImage = image
                    classifyImage(image)
                }
            }
        }
        .padding()
    }
    
    
    func loadImageFromPicker() {
        Task {
            if let data = try? await photoItem?.loadTransferable(type: Data.self),
               let uiImage = UIImage(data: data) {
                selectedImage = uiImage
                classifyImage(uiImage)
            }
        }
    }
    
    // MARK: - Classify image
    func classifyImage(_ image: UIImage) {
        guard let model = try? VNCoreMLModel(for: MobileNet().model) else {
            classificationResult = "Failed to load model"
            return
        }
        
        let request = VNCoreMLRequest(model: model) { request, error in
            if let results = request.results as? [VNClassificationObservation],
               let topResult = results.first {
                DispatchQueue.main.async {
                    classificationResult = "\(topResult.identifier) - \(Int(topResult.confidence * 100))% confident"
                }
            }
        }
        
        guard let ciImage = CIImage(image: image) else { return }
        let handler = VNImageRequestHandler(ciImage: ciImage)
        try? handler.perform([request])
    }
}

// MARK: - UIKit Camera Picker for SwiftUI
struct ImagePicker: UIViewControllerRepresentable {
    var sourceType: UIImagePickerController.SourceType
    var onImagePicked: (UIImage) -> Void
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onImagePicked: onImagePicked)
    }
    
    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        var onImagePicked: (UIImage) -> Void
        
        init(onImagePicked: @escaping (UIImage) -> Void) {
            self.onImagePicked = onImagePicked
        }
        
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                onImagePicked(image)
            }
            picker.dismiss(animated: true)
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
