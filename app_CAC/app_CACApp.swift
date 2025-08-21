//
//  app_CACApp.swift
//  app_CAC
//
//  Created by desai on 8/11/25.
//

import SwiftUI

@main
struct app_CACApp: App {
    init() {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor.ourgreen
            appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
            appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]

            
            UINavigationBar.appearance().standardAppearance = appearance
            UINavigationBar.appearance().scrollEdgeAppearance = appearance
        }

    var body: some Scene {
        WindowGroup {
            WelcomeView()
        }
    }
}
