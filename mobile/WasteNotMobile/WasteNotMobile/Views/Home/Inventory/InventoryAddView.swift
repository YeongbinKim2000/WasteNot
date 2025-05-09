//
//  Views/Home/Inventory/InventoryAddView.swift
//  WasteNotMobile
//
//  Created by Ethan Yan on 26/2/25.
//

import SwiftUI
import FirebaseAuth

struct InventoryAddView: View {
    var onSave: () -> Void
    
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var toastManager: ToastManager
    
    @State private var itemName: String = ""
    @State private var quantity: Int = 1
    @State private var productDescription: String = ""
    @State private var errorMessage: String?
    @State private var isSaving: Bool = false
    
    // New fields for manual entry.
    @State private var category: String = "Dairy"
    let categories = ["Dairy", "Vegetables", "Frozen", "Bakery", "Meat", "Other"]
    @State private var reminderDate: Date = Date()
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("New Item Details")) {
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
                    Picker("Category", selection: $category) {
                        ForEach(categories, id: \.self) { cat in
                            Text(cat)
                        }
                    }
                    DatePicker("Reminder Date", selection: $reminderDate, displayedComponents: [.date, .hourAndMinute])
                }
                
                // Removed notification settings section; effective time is calculated from the global setting.
                
                if let errorMessage = errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Add Item")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") {
                            saveNewItem()
                        }
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
    
    private func saveNewItem() {
        isSaving = true
        
        // Retrieve global notification lead time
        let globalLeadTime = UserSettingsManager.shared.defaultNotificationLeadTime
        let leadTimeInSeconds = Int(globalLeadTime * 3600)
        let effectiveReminderDate = Calendar.current.date(byAdding: .second, value: -leadTimeInSeconds, to: reminderDate) ?? reminderDate
        
        // Retrieve current user uid (or "Unknown" if nil)
        let currentUid = Auth.auth().currentUser?.uid ?? "Unknown"
        
        let newItem = InventoryItem(
            id: "", // Will be set by the service.
            barcode: "", // Manual add has an empty barcode.
            itemName: itemName,
            quantity: quantity,
            lastUpdated: Date(),
            productDescription: productDescription,
            imageURL: "",
            ingredients: "",
            nutritionFacts: "",
            brand: "",
            title: "",
            // Use the effective reminder date
            reminderDate: effectiveReminderDate,
            category: category,
            createdBy: currentUid,
            lastUpdatedBy: currentUid
        )
        
        InventoryService.shared.addInventoryItem(newItem: newItem) { result in
            DispatchQueue.main.async {
                isSaving = false
                switch result {
                case .success:
                    toastManager.show(message: "Item added successfully!", isSuccess: true)
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
