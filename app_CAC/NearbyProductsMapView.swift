import SwiftUI
import MapKit
import CoreLocation

// MARK: - Product Model
struct Product: Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let coordinate: CLLocationCoordinate2D
    let imageUrl: String?
    let nutrition: String?
    
    // MARK: - Equatable
    static func == (lhs: Product, rhs: Product) -> Bool {
        lhs.id == rhs.id
    }
    
    // MARK: - Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}



// MARK: - Location Manager
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var lastLocation: CLLocation?
    private let manager = CLLocationManager()
    
    override init() {
        super.init()
        manager.delegate = self
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        lastLocation = locations.first
    }
}

// MARK: - Demo API
struct DemoOFFProduct: Codable {
    let product_name: String?
    let image_url: String?
}

struct DemoOFFSearchResponse: Codable {
    let products: [DemoOFFProduct]
}

final class DemoAPIManager {
    static let shared = DemoAPIManager()
    private init() {}
    
    func fetchDemoProducts(completion: @escaping ([DemoOFFProduct]) -> Void) {
        let urlString = "https://world.openfoodfacts.org/cgi/search.pl?search_simple=1&json=1&page_size=50"
        guard let url = URL(string: urlString) else { return }
        
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let decoded = try? JSONDecoder().decode(DemoOFFSearchResponse.self, from: data)
            else {
                completion([])
                return
            }
            completion(decoded.products)
        }.resume()
    }
}

struct NearbyProductsMapView: View {
    @StateObject private var locationManager = LocationManager()
    @State private var products: [Product] = []
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.2, longitude: -121.8),
        span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
    )
    @State private var showIntroPopup = true
    @State private var showPopup = true
    @State private var selectedProduct: Product? = nil   // ✅ moved here
    
    var body: some View {
        ZStack {
            Map(coordinateRegion: $region, annotationItems: products) { product in
                MapAnnotation(coordinate: product.coordinate) {
                    VStack(spacing: 4) {
                        Text(product.name)
                            .font(.caption)
                            .padding(4)
                            .background(Color.white.opacity(0.8))
                            .cornerRadius(6)
                        
                        Image(systemName: "mappin.circle.fill")
                            .font(.title)
                            .foregroundColor(.green)
                            .onTapGesture {
                                selectedProduct = product
                            }
                    }
                    .onTapGesture {
                        selectedProduct = product
                    }
                }
            }
            
            if let product = selectedProduct {
                VStack {
                    Spacer()
                    
                    VStack(spacing: 10) {
                        Text(product.name)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                        
                        if let imageUrl = product.imageUrl, let url = URL(string: imageUrl) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .empty:
                                    ProgressView()
                                case .success(let image):
                                    image.resizable()
                                         .scaledToFit()
                                         .frame(height: 100)
                                case .failure:
                                    Image(systemName: "photo")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(height: 100)
                                @unknown default:
                                    EmptyView()
                                }
                            }
                        }
                        
                        if let nutrition = product.nutrition {
                            Text(nutrition)
                                .font(.subheadline)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        
                        Button("Close") {
                            selectedProduct = nil
                        }
                        .padding(.top, 10)
                        .frame(maxWidth: 100)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .frame(maxHeight: UIScreen.main.bounds.height / 3)
                    .padding()
                    .background(Color.white)
                    .cornerRadius(12)
                    .shadow(radius: 10)
                    .padding(.bottom, 40)
                }
                .transition(.move(edge: .bottom))
                .animation(.spring(), value: selectedProduct)  // ✅ works now
            }
            if showIntroPopup {
                VStack(spacing: 20) {
                    Image("app_CAC icon") // 👈 from Assets
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                    
                    
                    Text("Reduce your carbon footprint\nby buying items near you!")
                        .font(.custom("Quicksand-Regular", size: 24))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Button(action: {
                        showIntroPopup = false
                    }) {
                        Text("OK")
                            .font(.custom("Quicksand-Regular", size: 22))
                            .padding(.vertical, 8)
                            .padding(.horizontal, 24)
                            .background(Color("darkgreen"))
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }
                .padding()
                .frame(maxWidth: 300)
                .background(Color("ourgreen").opacity(0.9))
                .cornerRadius(20) // 👈 rounded green rectangle
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color("lightestgreen").opacity(0.7), lineWidth: 2) // 👈 rounded border
                )
                .shadow(radius: 10)
            }
        }
        .onAppear {
            fetchProducts()
        }
    }
    
    private func fetchProducts() {
        DemoAPIManager.shared.fetchDemoProducts { offProducts in
            DispatchQueue.main.async {
                if offProducts.isEmpty {
                    // Fallback: ~20 demo pins around South San Jose
                    let sanJosePins = (1...20).map { _ in
                        let lat = 37.2 + Double.random(in: -0.05...0.05)
                        let lon = -121.8 + Double.random(in: -0.05...0.05)
                        return Product(
                            id: UUID().uuidString,
                            name: "San Jose Demo Product",
                            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                            imageUrl: nil,
                            nutrition: "Calories: \(Int.random(in: 50...500)) • Fat: \(Int.random(in: 1...20))g • Sugar: \(Int.random(in: 1...30))g"
                        )
                    }
                    
                    // ~500 demo pins across the US
                    let usPins = (1...500).map { _ in
                        let lat = Double.random(in: 25.0...49.0)
                        let lon = Double.random(in: -124.0 ... -67.0)
                        return Product(
                            id: UUID().uuidString,
                            name: "US Demo Product",
                            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                            imageUrl: nil,
                            nutrition: "Calories: \(Int.random(in: 50...500)) • Fat: \(Int.random(in: 1...20))g • Sugar: \(Int.random(in: 1...30))g"
                        )
                    }
                    
                    products = sanJosePins + usPins
                } else {
                    // Real API results: pins near San Jose
                    products = offProducts.map { offProduct in
                        let lat = 37.2 + Double.random(in: -0.05...0.05)
                        let lon = -121.8 + Double.random(in: -0.05...0.05)
                        return Product(
                            id: UUID().uuidString,
                            name: offProduct.product_name ?? "Unknown",
                            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                            imageUrl: offProduct.image_url,
                            nutrition: "Calories: \(Int.random(in: 50...500)) • Fat: \(Int.random(in: 1...20))g • Sugar: \(Int.random(in: 1...30))g"
                        )
                    }
                }
            }
        }
    }
}
