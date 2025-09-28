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
    @State private var selectedProduct: Product? = nil

    // track price popup visibility
    @State private var showPricePopup = false

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
                }
            }

            // --- DETAILS BOTTOM SHEET STYLE POPUP ---
            if let product = selectedProduct {
                VStack {
                    Spacer()

                    ZStack(alignment: .topLeading) {
                        // Main card
                        VStack(spacing: 12) {
                            // Header row
                            HStack(spacing: 10) {
                                Button(action: {
                                    withAnimation { showPricePopup.toggle() }
                                }) {
                                    Image(systemName: "dollarsign.ring")
                                        .font(.title3)
                                        .padding(6)
                                }
                                .buttonStyle(PlainButtonStyle())

                                Text(product.name)
                                    .font(.headline)
                                    .multilineTextAlignment(.center)

                                Spacer()
                            }

                            // Nutrition info
                            let nutritionLines = product.nutrition?
                                .components(separatedBy: "•")
                                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                ?? ["Nutrition data unavailable"]

                            HStack(alignment: .top, spacing: 16) {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(nutritionLines, id: \.self) { line in
                                        Text(line)
                                            .multilineTextAlignment(.leading)
                                    }
                                }
                                .font(.body) // bigger text
                                .frame(minHeight: 80, alignment: .topLeading)

                                Image("placeholder_img")
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 80, height: 80)
                                    .clipped()
                                    .cornerRadius(8)
                            }

                            // Optional product image
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

                            Button("Close") {
                                selectedProduct = nil
                                showPricePopup = false
                            }
                            .padding(.top, 10)
                            .frame(maxWidth: .infinity)
                            .background(Color("darkgreen"))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        .padding()
                        .frame(maxWidth: 240) // smaller horizontal width
                        .background(Color("ourgreen").opacity(0.7))
                        .cornerRadius(20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color("lightestgreen").opacity(0.7), lineWidth: 2)
                        )
                        .shadow(radius: 10)
                        .padding(.bottom, 40)

                        // Floating price popup overlay (above card, not inside it)
                        if showPricePopup {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Estimated Price")
                                    .font(.caption).bold()
                                Text("$\(Int.random(in: 1...20)).99")
                                    .font(.caption2)
                            }
                            .padding(8)
                            .background(Color.white)
                            .cornerRadius(8)
                            .shadow(radius: 4)
                            .offset(x: 10, y: -40) // adjust to point near the $ button
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                }
                .transition(.move(edge: .bottom))
                .animation(.spring(), value: selectedProduct)
                .onChange(of: selectedProduct) { _ in
                    showPricePopup = false
                }
            }

            // --- INTRO POPUP (unchanged) ---
            if showIntroPopup {
                VStack(spacing: 20) {
                    Image("app_CAC icon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)

                    Text("Reduce your carbon footprint\nby buying items near you!")
                        .font(.custom("Quicksand-Regular", size: 24))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Button(action: { showIntroPopup = false }) {
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
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color("lightestgreen").opacity(0.7), lineWidth: 2)
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
