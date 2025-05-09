//
//  ProfileView.swift
//  WasteNotMobile
//
//  Created by Ethan Yan on 19/1/25.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import PhotosUI
import CoreLocation
import Cloudinary

struct ProfileView: View {
    @State private var username: String = ""
    @State private var email: String = ""
    @State private var location: String = ""
    @State private var avatarURL: URL?
    
    // For picking avatar
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImageData: Data?
    
    // For status messages or errors
    @State private var statusMessage: String?
    
    // For showing alerts
    @State private var showingLocationAlert = false
    
    // Notification Lead Time (in hours) as a global default
    @State private var defaultNotificationLeadTime: Double = 24
    
    // Observe custom LocationManager
    @StateObject private var locationManager = LocationManager()
    
    // Firestore reference
    private let db = Firestore.firestore()
    
    // Image Upload Service
    private let imageUploadService = ImageUploadService()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 14) {
                
                // Avatar with pick button
                if let avatarURL = avatarURL {
                    AsyncImage(url: avatarURL) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                        case .success(let image):
                            image.resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 100, height: 100)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                        case .failure(_):
                            Image(systemName: "person.crop.circle.badge.xmark")
                                .resizable()
                                .frame(width: 100, height: 100)
                        @unknown default:
                            EmptyView()
                        }
                    }
                } else {
                    // Placeholder avatar
                    Image(systemName: "person.crop.circle")
                        .resizable()
                        .frame(width: 100, height: 100)
                }
                
                PhotosPicker(
                    selection: $selectedItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Text("Change Avatar")
                        .foregroundColor(.blue)
                }
                .onChange(of: selectedItem) { newValue in
                    Task {
                        if let data = try? await newValue?.loadTransferable(type: Data.self) {
                            selectedImageData = data
                            // Upload to Cloudinary using ImageUploadService
                            uploadAvatar(data: data)
                        }
                    }
                }
                
                // User info fields
                VStack(alignment: .leading, spacing: 6) {
                    Text("Email (read-only)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("Email", text: $email)
                        .disabled(true)
                        .opacity(0.7)
                    
                    Text("Display Name")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("Display Name", text: $username)
                    
                    Text("Location")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("Location", text: $location)
                    
                    Button("Use Current Location") {
                        locationManager.requestPermission()
                    }
                    
                    // Global Notification Lead Time Setting
                    Text("Default Notification Lead Time (hours)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Stepper(value: $defaultNotificationLeadTime, in: 0...168, step: 1) {
                        Text("\(Int(defaultNotificationLeadTime)) hours before")
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal)
                
                Button("Save Profile") {
                    saveProfile()
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
                
                // Show status or error
                if let statusMessage = statusMessage {
                    Text(statusMessage)
                        .foregroundColor(.blue)
                }
                
                Spacer()
                
                // Sign out button
                Button("Sign Out") {
                    do {
                        try Auth.auth().signOut()
                    } catch {
                        print("Sign out error: \(error.localizedDescription)")
                    }
                }
                .padding()
                .background(Color.red)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .padding(.top, 20)
            .navigationTitle("Profile")
            .alert(isPresented: $showingLocationAlert) {
                Alert(
                    title: Text("Location Access Denied"),
                    message: Text("Please enable location services for this app in Settings."),
                    primaryButton: .default(Text("Open Settings")) {
                        openAppSettings()
                    },
                    secondaryButton: .cancel()
                )
            }
        }
        // On appear, load profile from Firestore
        .onAppear {
            loadProfile()
        }
        // If userLocation changes, reverse geocode to get city, state, etc.
        .onChange(of: locationManager.userLocation) { newLocation in
            guard let loc = newLocation else { return }
            reverseGeocode(location: loc)
        }
        // Handle location authorization changes
        .onChange(of: locationManager.status) { newStatus in
            if newStatus == .denied || newStatus == .restricted {
                showingLocationAlert = true
            }
        }
    }
    
    // MARK: - Load Profile
    private func loadProfile() {
        guard let user = Auth.auth().currentUser else {
            statusMessage = "User not found. Please log in or sign up."
            return
        }
        
        // Set email from Auth (read-only)
        email = user.email ?? ""
        
        // Read from Firestore
        let userRef = db.collection("users").document(user.uid)
        userRef.getDocument { document, error in
            if let error = error {
                statusMessage = "Error loading profile: \(error.localizedDescription)"
                return
            }
            if let document = document, document.exists {
                let data = document.data() ?? [:]
                self.username = data["username"] as? String ?? ""
                self.location = data["location"] as? String ?? ""
                self.defaultNotificationLeadTime = data["notificationLeadTime"] as? Double ?? 24.0
                
                if let avatarString = data["avatarURL"] as? String,
                   let url = URL(string: avatarString) {
                    self.avatarURL = url
                }
            }
        }
    }
    
    // MARK: - Upload Avatar Using ImageUploadService
    private func uploadAvatar(data: Data) {
        guard let user = Auth.auth().currentUser else { return }

        let publicId = "avatars-\(user.uid)"
        imageUploadService.uploadImage(data: data, publicId: publicId) { result in
            switch result {
            case .success(let secureUrl):
                self.avatarURL = URL(string: secureUrl)
                self.saveAvatarURLToFirestore(url: secureUrl)
            case .failure(let error):
                self.statusMessage = "Upload failed: \(error.localizedDescription)"
            }
        }
    }

    private func saveAvatarURLToFirestore(url: String) {
        guard let user = Auth.auth().currentUser else { return }
        db.collection("users").document(user.uid).setData(["avatarURL": url], merge: true) { error in
            if let error = error {
                self.statusMessage = "Error saving avatar URL: \(error.localizedDescription)"
            } else {
                self.statusMessage = "Avatar updated!"
            }
        }
    }
    
    // MARK: - Save Profile
    private func saveProfile() {
        guard let user = Auth.auth().currentUser else { return }
        
        let userData: [String: Any] = [
            "username": username,
            "location": location,
            "email": email,
            "notificationLeadTime": defaultNotificationLeadTime
            // "avatarURL" is set in uploadAvatar
        ]
        
        db.collection("users").document(user.uid).setData(userData, merge: true) { error in
            if let error = error {
                statusMessage = "Error saving profile: \(error.localizedDescription)"
            } else {
                statusMessage = "Profile updated"
            }
        }
    }
    
    // MARK: - Reverse Geocode
    private func reverseGeocode(location: CLLocation) {
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            if let error = error {
                print("Reverse geocode error: \(error.localizedDescription)")
                statusMessage = "Unable to retrieve location details."
                return
            }
            if let placemark = placemarks?.first {
                let city = placemark.locality ?? ""
                let state = placemark.administrativeArea ?? ""
                let country = placemark.country ?? ""
                
                self.location = [city, state, country]
                    .filter { !$0.isEmpty }
                    .joined(separator: ", ")
            }
        }
    }
    
    // MARK: - Helper to Convert CLAuthorizationStatus to String
    private func statusString(for status: CLAuthorizationStatus) -> String {
        switch status {
        case .notDetermined:
            return "Not Determined"
        case .restricted:
            return "Restricted"
        case .denied:
            return "Denied"
        case .authorizedWhenInUse:
            return "Authorized When In Use"
        case .authorizedAlways:
            return "Authorized Always"
        @unknown default:
            return "Unknown"
        }
    }
    
    // MARK: - Open App Settings
    private func openAppSettings() {
        if let appSettings = URL(string: UIApplication.openSettingsURLString) {
            if UIApplication.shared.canOpenURL(appSettings) {
                UIApplication.shared.open(appSettings)
            }
        }
    }
}
