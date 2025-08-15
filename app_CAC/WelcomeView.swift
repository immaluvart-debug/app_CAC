//
//  WelcomeView.swift
//  app_CAC
//
//  Created by Rosa Lee on 8/15/25.
//
import SwiftUI

struct WelcomeView: View {
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Text("Leaf&Fork Login")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.top, 100)
                
                NavigationLink(destination: CreateAccountView()) {
                    Text("Create New Account")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                
                NavigationLink(destination: LoginView()) {
                    Text("Returning User")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("")
            .navigationBarHidden(true)
        }
    }
}

struct CreateAccountView: View {
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var navigateToPreferences = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Create Account")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.top, 60)
            
            // Username
            VStack(alignment: .leading) {
                Text("Create Username")
                    .font(.headline)
                TextField("Enter username", text: $username)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocapitalization(.none)
            }
            
            // Password
            VStack(alignment: .leading) {
                Text("Create Password")
                    .font(.headline)
                SecureField("Enter password", text: $password)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            
            // Submit Button
            Button(action: {
                saveCredentials()
                navigateToPreferences = true
            }) {
                Text("Create Account")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
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

struct LoginView: View {
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var loginFailed = false
    @State private var navigateToPreferences = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Login")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.top, 60)
            
            TextField("Username", text: $username)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .autocapitalization(.none)
            
            SecureField("Password", text: $password)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            if loginFailed {
                Text("Invalid username or password")
                    .foregroundColor(.red)
                    .font(.caption)
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
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
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
    
    let mediumBlue = Color(red: 0.0, green: 122/255, blue: 1.0)
    
    var body: some View {
        VStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text("Choose Preferences")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(mediumBlue)
                        .padding(.top, 40)
                    
                    ForEach(preferenceOptions, id: \.self) { option in
                        PreferenceRow(
                            title: option,
                            isSelected: selectedPreferences.contains(option),
                            highlightColor: mediumBlue
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
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(mediumBlue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
                
                NavigationLink(destination: GoalsView(), isActive: $navigateToGoals) {
                    EmptyView()
                }
            }
        }
        .background(Color.white.ignoresSafeArea())
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
                    .font(.headline)
                    .foregroundColor(isSelected ? highlightColor : .primary)
                Spacer()
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundColor(isSelected ? highlightColor : .gray)
                    .font(.title2)
            }
            .padding()
            .background(Color.white)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? highlightColor : Color.gray.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 1)
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
    
    let mediumBlue = Color(red: 0.0, green: 122/255, blue: 1.0)
    
    var body: some View {
        VStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text("Select Your Goals")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(mediumBlue)
                        .padding(.top, 40)
                    
                    ForEach(goalOptions, id: \.self) { goal in
                        GoalRow(
                            title: goal,
                            isSelected: selectedGoals.contains(goal),
                            highlightColor: mediumBlue
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
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(mediumBlue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
                
                // Navigation to ContentView
                NavigationLink(destination: ContentView(), isActive: $navigateToContent) {
                    EmptyView()
                }
            }
        }
        .background(Color.white.ignoresSafeArea())
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
                    .font(.headline)
                    .foregroundColor(isSelected ? highlightColor : .primary)
                Spacer()
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundColor(isSelected ? highlightColor : .gray)
                    .font(.title2)
            }
            .padding()
            .background(Color.white)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? highlightColor : Color.gray.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 1)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

