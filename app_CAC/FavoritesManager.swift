import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
class FavoritesManager: ObservableObject {
    @Published var favorites: [ScanItem] = []
    private let db = Firestore.firestore()

    init() {
        startListeningForFavorites()
    }

    func startListeningForFavorites() {
        guard let user = Auth.auth().currentUser else {
            favorites = []
            return
        }

        db.collection("users")
            .document(user.uid)
            .collection("favorites")
            .order(by: "scannedAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                guard let docs = snapshot?.documents else {
                    self.favorites = []
                    return
                }

                self.favorites = docs.compactMap { doc in
                    try? doc.data(as: ScanItem.self)
                }
            }
    }

    func toggleFavorite(scan: ScanItem) {
        guard let user = Auth.auth().currentUser else { return }
        let ref = db.collection("users").document(user.uid).collection("favorites").document(scan.id)

        if isFavorite(scan) {
            favorites.removeAll { $0.id == scan.id }
            ref.delete()
        } else {
            favorites.insert(scan, at: 0)
            do {
                try ref.setData(from: scan)
            } catch {
                print("❌ Error saving favorite: \(error)")
            }
        }
    }

    func isFavorite(_ scan: ScanItem) -> Bool {
        favorites.contains(where: { $0.id == scan.id })
    }
}

