//
//  Views/Home/Inventory/InventoryEditView.swift
//  WasteNotMobile
//
//  Created by Ethan Yan on 23/2/25.
//

import SwiftUI
import FirebaseAuth

struct InventoryEditView: View {
    var item: InventoryItem
    var onSave: () -> Void
    
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var toastManager: ToastManager
    
    @State private var itemName: String
    @State private var quantity: Int
    @State private var productDescription: String
    @State private var reminderDate: Date
    @State private var errorMessage: String?
    @State private var isSaving: Bool = false
    
    // State variables to hold fetched usernames.
    @State private var createdByName: String = "Loading..."
    @State private var updatedByName: String = "Loading..."
    
    init(item: InventoryItem, onSave: @escaping () -> Void) {
        self.item = item
        self.onSave = onSave
        _itemName = State(initialValue: item.itemName)
        _quantity = State(initialValue: item.quantity)
        _productDescription = State(initialValue: item.productDescription)
        _reminderDate = State(initialValue: item.reminderDate ?? Date())
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Item Details")) {
                    TextField("Item Name", text: $itemName)
                    HStack {
                        Text("Quantity:")
                        Spacer()
                        Button(action: { if quantity > 1 { quantity -= 1 } }) {
                            Image(systemName: "minus.circle")
                        }
                        Text("\(quantity)")
                        Button(action: { quantity += 1 }) {
                            Image(systemName: "plus.circle")
                        }
                    }
                    TextField("Product Description", text: $productDescription)
                }
                
                Section(header: Text("Reminder")) {
                    DatePicker("Reminder Date", selection: $reminderDate, displayedComponents: [.date, .hourAndMinute])
                }
                                
                Section(header: Text("Item History")) {
                    HStack {
                        Text("Created by:")
                        Spacer()
                        Text("\(createdByName)")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Last updated by:")
                        Spacer()
                        Text("\(updatedByName)")
                            .foregroundColor(.secondary)
                    }
                }
                
                if let errorMessage = errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Edit Item")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") {
                            saveChanges()
                        }
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            .onAppear {
                fetchUserNames()
            }
        }
    }
    
    private func fetchUserNames() {
        // Fetch the creator's username using their UID.
        UserService().fetchUserProfile(uid: item.createdBy) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let profile):
                    self.createdByName = profile.username
                case .failure(_):
                    self.createdByName = "Unknown"
                }
            }
        }
        // Fetch the last updater's username using their UID.
        UserService().fetchUserProfile(uid: item.lastUpdatedBy) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let profile):
                    self.updatedByName = profile.username
                case .failure(_):
                    self.updatedByName = "Unknown"
                }
            }
        }
    }
    
    private func saveChanges() {
        isSaving = true
        
        // Use the global notification lead time to calculate the effective reminder time.
        let globalLeadTime = UserSettingsManager.shared.defaultNotificationLeadTime
        let leadTimeInSeconds = Int(globalLeadTime * 3600)
        let effectiveReminderDate = Calendar.current.date(byAdding: .second, value: -leadTimeInSeconds, to: reminderDate) ?? reminderDate
        
        let updatedItem = InventoryItem(
            id: item.id,
            barcode: item.barcode,
            itemName: itemName,
            quantity: quantity,
            lastUpdated: Date(),
            productDescription: productDescription,
            imageURL: item.imageURL,
            ingredients: item.ingredients,
            nutritionFacts: item.nutritionFacts,
            brand: item.brand,
            title: item.title,
            // Use the effective reminder date
            reminderDate: effectiveReminderDate,
            category: item.category,
            createdBy: item.createdBy,
            lastUpdatedBy: Auth.auth().currentUser?.uid ?? item.lastUpdatedBy
        )
        
        InventoryService.shared.updateInventoryItem(updatedItem: updatedItem) { result in
            DispatchQueue.main.async {
                isSaving = false
                switch result {
                case .success:
                    toastManager.show(message: "Item updated successfully!", isSuccess: true)
                    onSave()
                    presentationMode.wrappedValue.dismiss()
                case .failure(let error):
                    errorMessage = error.localizedDescription
                    toastManager.show(message: error.localizedDescription, isSuccess: false)
                }
            }
        }
    }
}
