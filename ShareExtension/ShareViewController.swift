import UIKit
import Social
import SwiftUI

class ShareViewController: UIViewController {
    private var sharedURL: String?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        print("DEBUG: ShareViewController viewDidLoad")
        
        // Extract the shared URL from the extension context and immediately open main app
        extractSharedURL()
    }
    
    private func extractSharedURL() {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            print("DEBUG: No extension items found")
            presentErrorAlert(message: "No items to share.")
            return
        }
        
        print("DEBUG: Found \(extensionItems.count) extension items")
        var foundURL = false
        
        for (index, extensionItem) in extensionItems.enumerated() {
            print("DEBUG: Processing extension item \(index + 1)")
            
            if let itemProviders = extensionItem.attachments {
                print("DEBUG: Item has \(itemProviders.count) attachments")
                
                for (providerIndex, itemProvider) in itemProviders.enumerated() {
                    print("DEBUG: Checking provider \(providerIndex + 1)")
                    print("DEBUG: Available types: \(itemProvider.registeredTypeIdentifiers)")
                    
                    if itemProvider.hasItemConformingToTypeIdentifier("public.url") {
                        print("DEBUG: Found provider with URL type")
                        foundURL = true
                        
                        itemProvider.loadItem(forTypeIdentifier: "public.url", options: nil) { [weak self] (url, error) in
                            guard let self = self else { return }
                            
                            DispatchQueue.main.async {
                                if let shareURL = url as? URL {
                                    self.sharedURL = shareURL.absoluteString
                                    print("DEBUG: Extracted URL: \(shareURL.absoluteString)")
                                    
                                    // Save the URL to UserDefaults
                                    let userDefaults = UserDefaults(suiteName: "group.com.elislothower.Beat-Bridge")
                                    userDefaults?.set(shareURL.absoluteString, forKey: "lastSharedURL")
                                    userDefaults?.synchronize()
                                    
                                    // Immediately open the main app
                                    self.openMainApp()
                                } else {
                                    print("DEBUG: URL cast failed, received: \(String(describing: url))")
                                    self.presentErrorAlert(message: "Could not process the shared link.")
                                }
                            }
                        }
                        return
                    } else if itemProvider.hasItemConformingToTypeIdentifier("public.text") {
                        // Try text type as fallback (some music apps share as text)
                        print("DEBUG: Found public.text type, trying to extract URL")
                        foundURL = true
                        
                        itemProvider.loadItem(forTypeIdentifier: "public.text", options: nil) { [weak self] (text, error) in
                            guard let self = self else { return }
                            
                            DispatchQueue.main.async {
                                if let urlString = text as? String,
                                   urlString.contains("http") {
                                    self.sharedURL = urlString
                                    print("DEBUG: Extracted URL from text: \(urlString)")
                                    
                                    // Save the URL to UserDefaults
                                    let userDefaults = UserDefaults(suiteName: "group.com.elislothower.Beat-Bridge")
                                    userDefaults?.set(urlString, forKey: "lastSharedURL")
                                    userDefaults?.synchronize()
                                    
                                    // Immediately open the main app
                                    self.openMainApp()
                                } else {
                                    print("DEBUG: Text doesn't contain URL")
                                    self.presentErrorAlert(message: "No music link found in shared content.")
                                }
                            }
                        }
                        return
                    }
                }
            }
        }
        
        if !foundURL {
            print("DEBUG: No URL found")
            presentErrorAlert(message: "No music link found in shared content.")
        }
    }
    
    private func openMainApp() {
        print("DEBUG: Showing instructions to user")
        
        // Show a clear message to guide the user
        let alert = UIAlertController(
            title: "Music Link Ready",
            message: "Your link has been saved!\n\nPlease tap 'Done' below, then open the Beat Bridge app from your home screen to continue sharing.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Done", style: .default) { _ in
            // Complete the extension request which returns to the user's previous app
            self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        })
        
        present(alert, animated: true)
    }
    
    private func presentErrorAlert(message: String) {
        print("DEBUG: Error alert: \(message)")
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        })
        present(alert, animated: true)
    }
}
