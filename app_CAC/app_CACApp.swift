//
//  app_CACApp.swift
//  app_CAC
//
//  Created by desai on 8/11/25.
//

import SwiftUI
import FirebaseCore
import FirebaseAI
import FirebaseAuth
import FirebaseStorage
import FirebaseAnalytics
import UIKit
import Firebase

@main
struct app_CACApp: App {
    @StateObject var favoritesManager = FavoritesManager()
    @StateObject var scansManager = ScansManager()
    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            WelcomeView()
                .environmentObject(favoritesManager)
                .environmentObject(scansManager)
        }
    }
}
