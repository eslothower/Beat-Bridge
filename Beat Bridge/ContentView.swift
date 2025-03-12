import SwiftUI
import Contacts
import ContactsUI
import MessageUI
import SwiftData

struct ContentView: View {
    @State private var selectedTab = 0
    @State private var showingContactPicker = false
    @State private var showingServiceSelection = false
    @State private var pendingContactID: String?
    @State private var pendingContactName: String?
    @State private var pendingContactPhone: String?
    @State private var sharedURL: String?
    
    @Query var contactPreferences: [ContactServicePreference]
    @Query var conversionHistory: [ConversionHistory]
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Home tab
            NavigationView {
                HomeView()
            }
            .tabItem {
                Label("Home", systemImage: "house.fill")
            }
            .tag(0)
            
            // Contact Preferences tab
            NavigationView {
                ContactPreferencesView(contactPreferences: contactPreferences)
            }
            .tabItem {
                Label("My Contacts", systemImage: "person.crop.circle.fill")
            }
            .tag(1)
            
            // History tab
            NavigationView {
                HistoryView(conversionHistory: conversionHistory)
            }
            .tabItem {
                Label("History", systemImage: "clock.arrow.circlepath")
            }
            .tag(2)
            
            // Settings tab
            NavigationView {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
            .tag(3)
        }
        .sheet(isPresented: $showingContactPicker) {
            ContactPickerView { contact in
                handleContactSelection(contact)
            }
        }
        .sheet(isPresented: $showingServiceSelection) {
            if let contactName = pendingContactName {
                NewContactServiceView(
                    contactName: contactName,
                    contactID: pendingContactID ?? "",
                    contactPhone: pendingContactPhone,
                    sharedURL: sharedURL,
                    onComplete: handleServiceSelection
                )
            }
        }
        .onAppear(perform: checkForPendingActions)
        .onReceive(NotificationCenter.default.publisher(for: .didReceiveShareExtensionRequest)) { _ in
            print("DEBUG: ContentView received share request notification")
            // Retrieve the shared URL from UserDefaults
            let userDefaults = UserDefaults(suiteName: "group.com.elislothower.Beat-Bridge")
            if let url = userDefaults?.string(forKey: "lastSharedURL") {
                sharedURL = url
                print("DEBUG: Retrieved shared URL: \(url)")
                
                // Present the contact picker
                DispatchQueue.main.async {
                    self.showingContactPicker = true
                }
            } else {
                print("DEBUG: No shared URL found in UserDefaults")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .didReceiveServiceSelectionRequest)) { _ in
            print("DEBUG: ContentView received service selection notification")
            checkForPendingActions()
        }
    }
    
    private func checkForPendingActions() {
        let userDefaults = UserDefaults(suiteName: "group.com.elislothower.Beat-Bridge")
        print("DEBUG: ContentView: Checking for pending actions")

        // Debug print all relevant keys in UserDefaults
        if let contactID = userDefaults?.string(forKey: "pendingContactIdentifier") {
            print("DEBUG: pendingContactIdentifier: \(contactID)")
        } else {
            print("DEBUG: pendingContactIdentifier: nil")
        }
        
        if let contactName = userDefaults?.string(forKey: "pendingContactName") {
            print("DEBUG: pendingContactName: \(contactName)")
        } else {
            print("DEBUG: pendingContactName: nil")
        }
        
        if let url = userDefaults?.string(forKey: "lastSharedURL") {
            print("DEBUG: lastSharedURL: \(url)")
            sharedURL = url
        } else {
            print("DEBUG: lastSharedURL: nil")
        }

        // Safely unwrap and ensure they're not empty strings
        if
          let contactID = userDefaults?.string(forKey: "pendingContactIdentifier"),
          !contactID.isEmpty,
          let contactName = userDefaults?.string(forKey: "pendingContactName"),
          !contactName.isEmpty
        {
            print("DEBUG: Found pending contact: \(contactName)")
            pendingContactID = contactID
            pendingContactName = contactName
            pendingContactPhone = userDefaults?.string(forKey: "pendingContactPhone")
            
            // Present the sheet
            DispatchQueue.main.async {
                print("DEBUG: Showing service selection sheet")
                self.showingServiceSelection = true
                self.selectedTab = 1
            }
        }
    }
    
    private func handleContactSelection(_ contact: CNContact) {
        let contactID = contact.identifier
        let contactName = ContactServicePreference.formatName(from: contact)
        let contactPhone = contact.phoneNumbers.first?.value.stringValue
        
        print("DEBUG: Selected contact: \(contactName)")
        
        // Check if we have a service preference for this contact
        if let serviceName = ContactPreferencesHelper.shared.getPreferredService(for: contactID) {
            print("DEBUG: Found service preference: \(serviceName)")
            
            // Contact has a service preference, process the link
            convertAndSendLink(for: contact, serviceName: serviceName)
        } else {
            print("DEBUG: No service preference found, showing service selection UI")
            
            // Contact doesn't have a service preference, show service selection UI
            pendingContactID = contactID
            pendingContactName = contactName
            pendingContactPhone = contactPhone
            
            DispatchQueue.main.async {
                self.showingContactPicker = false
                self.showingServiceSelection = true
            }
        }
    }
    
    private func convertAndSendLink(for contact: CNContact, serviceName: String) {
        guard let url = sharedURL, let targetService = MusicService(rawValue: serviceName) else {
            print("DEBUG: Missing URL or invalid service")
            return
        }
        
        // Show an alert to indicate the conversion is in progress
        let loadingAlert = UIAlertController(title: nil, message: "Converting link...", preferredStyle: .alert)
        let loadingIndicator = UIActivityIndicatorView(frame: CGRect(x: 10, y: 5, width: 50, height: 50))
        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.style = .medium
        loadingIndicator.startAnimating()
        loadingAlert.view.addSubview(loadingIndicator)
        
        UIApplication.shared.windows.first?.rootViewController?.present(loadingAlert, animated: true)
        
        // Convert the link
        let linkConverter = LinkConverterService()
        linkConverter.convertLink(url) { result in
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    switch result {
                    case .success(let links):
                        if let convertedLink = links[targetService] {
                            print("DEBUG: Successfully converted link: \(convertedLink)")
                            self.sendMessage(to: contact, withLink: convertedLink)
                        } else {
                            print("DEBUG: Song not available on \(serviceName)")
                            self.showError("This song isn't available on \(serviceName).")
                        }
                    case .failure:
                        print("DEBUG: Failed to convert link")
                        self.showError("Failed to convert link. Please try again.")
                    }
                }
            }
        }
    }
    
    private func sendMessage(to contact: CNContact, withLink link: String) {
        if let phoneNumber = contact.phoneNumbers.first?.value.stringValue {
            let messageVC = MFMessageComposeViewController()
            messageVC.recipients = [phoneNumber]
            messageVC.body = "Check out this song: \(link)"
            
            if MFMessageComposeViewController.canSendText() {
                // Present the message composer
                UIApplication.shared.windows.first?.rootViewController?.present(messageVC, animated: true)
                
                // Add a delegate to handle the completion
                if let delegate = UIApplication.shared.windows.first?.rootViewController as? MFMessageComposeViewControllerDelegate {
                    messageVC.messageComposeDelegate = delegate
                }
            } else {
                // Fallback: copy to clipboard
                UIPasteboard.general.string = link
                showError("Cannot send messages. Link copied to clipboard.")
            }
        } else {
            showError("No phone number found for this contact.")
        }
    }
    
    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        UIApplication.shared.windows.first?.rootViewController?.present(alert, animated: true)
    }
    
    private func handleServiceSelection(service: MusicService) {
        guard let contactID = pendingContactID, let contactName = pendingContactName else {
            return
        }
        
        // Save the contact preference to SwiftData
        let preference = ContactServicePreference(
            contactIdentifier: contactID,
            contactName: contactName,
            musicService: service.rawValue
        )
        modelContext.insert(preference)
        
        // Also save to UserDefaults for the share extension to access
        ContactPreferencesHelper.shared.savePreference(
            contactIdentifier: contactID,
            contactName: contactName,
            musicService: service.rawValue
        )
        
        // If we have a URL and phone number, send the message
        if let url = sharedURL, let phone = pendingContactPhone {
            // Convert and send the link
            let linkConverter = LinkConverterService()
            
            // Show loading indicator
            let loadingAlert = UIAlertController(title: nil, message: "Converting link...", preferredStyle: .alert)
            let loadingIndicator = UIActivityIndicatorView(frame: CGRect(x: 10, y: 5, width: 50, height: 50))
            loadingIndicator.hidesWhenStopped = true
            loadingIndicator.style = .medium
            loadingIndicator.startAnimating()
            loadingAlert.view.addSubview(loadingIndicator)
            
            UIApplication.shared.windows.first?.rootViewController?.present(loadingAlert, animated: true)
            
            linkConverter.convertLink(url) { result in
                DispatchQueue.main.async {
                    loadingAlert.dismiss(animated: true) {
                        switch result {
                        case .success(let links):
                            if let convertedLink = links[service] {
                                if MFMessageComposeViewController.canSendText() {
                                    let messageVC = MFMessageComposeViewController()
                                    messageVC.recipients = [phone]
                                    messageVC.body = "Check out this song: \(convertedLink)"
                                    
                                    UIApplication.shared.windows.first?.rootViewController?.present(messageVC, animated: true)
                                } else {
                                    UIPasteboard.general.string = convertedLink
                                    self.showError("Cannot send messages. Link copied to clipboard.")
                                }
                            } else {
                                self.showError("This song isn't available on \(service.rawValue).")
                            }
                        case .failure:
                            self.showError("Failed to convert link. Please try again.")
                        }
                    }
                }
            }
        }
        
        // Clear pending data
        let userDefaults = UserDefaults(suiteName: "group.com.elislothower.Beat-Bridge")
        userDefaults?.removeObject(forKey: "pendingContactIdentifier")
        userDefaults?.removeObject(forKey: "pendingContactName")
        userDefaults?.removeObject(forKey: "pendingContactPhone")
        userDefaults?.synchronize()
        
        pendingContactID = nil
        pendingContactName = nil
        pendingContactPhone = nil
        showingServiceSelection = false
    }
}

// Contact Picker View using UIViewControllerRepresentable
struct ContactPickerView: UIViewControllerRepresentable {
    var onContactSelected: (CNContact) -> Void
    
    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, CNContactPickerDelegate {
        var parent: ContactPickerView
        
        init(_ contactPickerView: ContactPickerView) {
            self.parent = contactPickerView
        }
        
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            parent.onContactSelected(contact)
        }
        
        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            // Handle cancellation
        }
    }
}

struct HomeView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // App logo/icon
                Image(systemName: "music.note.list")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                    .foregroundColor(.blue)
                    .padding(.top, 20)
                
                // App title
                Text("Beat Bridge")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                // Description
                Text("Share music with friends on any streaming service")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                // How to use section
                VStack(alignment: .leading, spacing: 24) {
                    Text("How to use Beat Bridge")
                        .font(.headline)
                        .padding(.vertical, 8)
                    
                    // Step 1
                    HowToUseRow(
                        number: "1",
                        title: "Find a song to share",
                        description: "Open your favorite music app and find a song you want to share.",
                        iconName: "music.note"
                    )
                    
                    // Step 2
                    HowToUseRow(
                        number: "2",
                        title: "Tap the share button",
                        description: "Use the share button in your music app.",
                        iconName: "square.and.arrow.up"
                    )
                    
                    // Step 3
                    HowToUseRow(
                        number: "3",
                        title: "Select Beat Bridge",
                        description: "Find and tap on Beat Bridge in the share sheet.",
                        iconName: "app.badge"
                    )
                    
                    // Step 4
                    HowToUseRow(
                        number: "4",
                        title: "Choose a contact",
                        description: "Select who you want to share with. We'll remember their preferred music service.",
                        iconName: "person.crop.circle"
                    )
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
                .padding(.horizontal)
                
                // Note about the app
                VStack(spacing: 8) {
                    Text("Note")
                        .font(.headline)
                    
                    Text("You don't need to open this app directly. Just use the share button in your music app and select Beat Bridge.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)
                .padding(.horizontal)
                
                Spacer()
            }
            .padding()
        }
        .navigationTitle("Beat Bridge")
    }
}

// Row for the How To Use section
struct HowToUseRow: View {
    var number: String
    var title: String
    var description: String
    var iconName: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 30, height: 30)
                
                Text(number)
                    .font(.headline)
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: iconName)
                        .foregroundColor(.blue)
                    
                    Text(title)
                        .font(.headline)
                }
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct ContactPreferencesView: View {
    var contactPreferences: [ContactServicePreference]
    @Environment(\.modelContext) private var modelContext
    @State private var editingContact: ContactServicePreference?
    @State private var showingServicePicker = false
    
    var body: some View {
        Group {
            if contactPreferences.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "person.crop.circle.badge.exclamationmark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 70, height: 70)
                        .foregroundColor(.gray)
                        .padding(.top, 50)
                    
                    Text("No contact preferences yet")
                        .font(.headline)
                    
                    Text("When you share music with contacts, their preferred music services will appear here.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 40)
                }
            } else {
                List {
                    ForEach(contactPreferences.sorted(by: { $0.lastUsed > $1.lastUsed })) { preference in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(preference.contactName)
                                    .font(.headline)
                                
                                HStack {
                                    Text("Uses:")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    
                                    Text(preference.musicService)
                                        .font(.subheadline)
                                        .foregroundColor(.blue)
                                }
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                editingContact = preference
                                showingServicePicker = true
                            }) {
                                Image(systemName: "pencil.circle")
                                    .foregroundColor(.blue)
                                    .font(.title3)
                            }
                        }
                    }
                    .onDelete(perform: deletePreferences)
                }
            }
        }
        .navigationTitle("Contact Preferences")
        .sheet(isPresented: $showingServicePicker) {
            if let contact = editingContact {
                ServicePickerView(contactPreference: contact)
            }
        }
    }
    
    private func deletePreferences(at offsets: IndexSet) {
        for index in offsets {
            let sortedPreferences = contactPreferences.sorted(by: { $0.lastUsed > $1.lastUsed })
            let preference = sortedPreferences[index]
            modelContext.delete(preference)
        }
    }
}

struct ServicePickerView: View {
    var contactPreference: ContactServicePreference
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var selectedService = ""
    
    var body: some View {
        NavigationView {
            VStack {
                Text("Select music service for")
                    .font(.headline)
                
                Text(contactPreference.contactName)
                    .font(.title2)
                    .padding(.bottom)
                
                List {
                    ForEach(MusicService.allCases) { service in
                        Button(action: {
                            selectedService = service.rawValue
                            updatePreference()
                        }) {
                            HStack {
                                Image(service.icon)
                                    .resizable()
                                    .frame(width: 30, height: 30)
                                    .cornerRadius(6)
                                
                                Text(service.rawValue)
                                
                                Spacer()
                                
                                if service.rawValue == contactPreference.musicService {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationBarTitle("Edit Preference", displayMode: .inline)
            .navigationBarItems(trailing: Button("Done") {
                dismiss()
            })
            .onAppear {
                selectedService = contactPreference.musicService
            }
        }
    }
    
    private func updatePreference() {
        contactPreference.musicService = selectedService
        contactPreference.lastUsed = Date()
        
        // Also update in UserDefaults for the share extension
        ContactPreferencesHelper.shared.savePreference(
            contactIdentifier: contactPreference.contactIdentifier,
            contactName: contactPreference.contactName,
            musicService: selectedService
        )
        
        // SwiftData will automatically save the changes
        dismiss()
    }
}

struct HistoryView: View {
    var conversionHistory: [ConversionHistory]
    
    var body: some View {
        Group {
            if conversionHistory.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "clock.arrow.circlepath")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 70, height: 70)
                        .foregroundColor(.gray)
                        .padding(.top, 50)
                    
                    Text("No conversion history yet")
                        .font(.headline)
                    
                    Text("Your music sharing history will appear here.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 40)
                }
            } else {
                List {
                    ForEach(conversionHistory.sorted(by: { $0.timestamp > $1.timestamp })) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            if let title = item.songTitle {
                                Text(title)
                                    .font(.headline)
                            }
                            
                            if let artist = item.artistName {
                                Text(artist)
                                    .font(.subheadline)
                            }
                            
                            HStack {
                                Text("\(item.originalService) → \(item.convertedService)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                Text(item.timestamp, style: .date)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("History")
    }
}

struct SettingsView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = true
    
    var body: some View {
        Form {
            Section(header: Text("App Settings")) {
                Button("View Onboarding Again") {
                    hasCompletedOnboarding = false
                }
            }
            
            Section(header: Text("About")) {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0.0")
                        .foregroundColor(.secondary)
                }
                
                Link("Privacy Policy", destination: URL(string: "https://www.example.com/privacy")!)
                
                Link("Terms of Service", destination: URL(string: "https://www.example.com/terms")!)
            }
            
            Section(header: Text("Support")) {
                Link("Send Feedback", destination: URL(string: "mailto:support@example.com")!)
                
                Link("Rate on App Store", destination: URL(string: "https://apps.apple.com")!)
            }
        }
        .navigationTitle("Settings")
    }
}
