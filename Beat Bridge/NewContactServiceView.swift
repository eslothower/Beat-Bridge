import SwiftUI
import MessageUI

// View for selecting a service for a new contact
struct NewContactServiceView: View {
    var contactName: String
    var contactID: String
    var contactPhone: String?
    var sharedURL: String?
    var onComplete: (MusicService) -> Void
    
    @State private var selectedService: MusicService?
    @State private var showingMessageComposer = false
    @State private var convertedLink: String?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Text("Set Up Music Service")
                        .font(.headline)
                    
                    Text("What music service does \(contactName) use?")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                }
                .padding(.top)
                
                if isLoading {
                    // Loading indicator
                    VStack(spacing: 15) {
                        ProgressView()
                        Text("Converting link...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Service selection list
                    List {
                        ForEach(MusicService.allCases) { service in
                            Button(action: {
                                selectedService = service
                                if let url = sharedURL {
                                    convertLinkAndContinue(url: url, targetService: service)
                                } else {
                                    handleServiceSelection(service)
                                }
                            }) {
                                HStack {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8)
                                            .frame(width: 40, height: 40)
                                            .foregroundColor(Color.gray.opacity(0.2))
                                        
                                        Text(String(service.rawValue.prefix(1)))
                                            .font(.title3)
                                            .fontWeight(.semibold)
                                    }
                                    
                                    Text(service.rawValue)
                                        .padding(.leading, 8)
                                    
                                    Spacer()
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
            }
            .navigationBarTitle("Select Service", displayMode: .inline)
            .navigationBarItems(trailing: Button("Cancel") {
                dismiss()
            })
            .alert(isPresented: $showingError) {
                Alert(
                    title: Text("Error"),
                    message: Text(errorMessage ?? "An unknown error occurred"),
                    dismissButton: .default(Text("OK"))
                )
            }
            .sheet(isPresented: $showingMessageComposer) {
                if let link = convertedLink, let phone = contactPhone {
                    MessageComposerView(
                        recipients: [phone],
                        messageBody: "Check out this song: \(link)",
                        onComplete: { _ in
                            // Complete the flow
                            if let service = selectedService {
                                handleServiceSelection(service)
                            }
                        }
                    )
                }
            }
        }
    }
    
    private func convertLinkAndContinue(url: String, targetService: MusicService) {
        isLoading = true
        
        // Create a link converter
        let linkConverter = LinkConverterService()
        
        // Convert the link
        linkConverter.convertLink(url) { result in
            isLoading = false
            
            switch result {
            case .success(let links):
                // Check if we have a link for the selected service
                if let link = links[targetService] {
                    convertedLink = link
                    
                    // If we have a phone number, show message composer
                    if let _ = contactPhone, MFMessageComposeViewController.canSendText() {
                        showingMessageComposer = true
                    } else {
                        // Otherwise just save the preference
                        handleServiceSelection(targetService)
                    }
                } else {
                    errorMessage = "This song isn't available on \(targetService.rawValue)."
                    showingError = true
                }
                
            case .failure:
                errorMessage = "Could not convert this music link."
                showingError = true
            }
        }
    }
    
    private func handleServiceSelection(_ service: MusicService) {
        onComplete(service)
        dismiss()
    }
}

// Helper to show message composer
struct MessageComposerView: UIViewControllerRepresentable {
    var recipients: [String]
    var messageBody: String
    var onComplete: (MessageComposeResult) -> Void
    
    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        guard MFMessageComposeViewController.canSendText() else {
            fatalError("Cannot send text messages")
        }
        
        let messageComposeVC = MFMessageComposeViewController()
        messageComposeVC.messageComposeDelegate = context.coordinator
        messageComposeVC.recipients = recipients
        messageComposeVC.body = messageBody
        return messageComposeVC
    }
    
    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        var parent: MessageComposerView
        
        init(_ messageComposerView: MessageComposerView) {
            self.parent = messageComposerView
        }
        
        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            controller.dismiss(animated: true) {
                self.parent.onComplete(result)
            }
        }
    }
}
