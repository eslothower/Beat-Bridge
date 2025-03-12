import SwiftUI
import SwiftData
import UIKit
import MessageUI

@main
struct BeatBridgeApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            ConversionHistory.self,
            ContactServicePreference.self
        ])
        
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
        
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .onOpenURL { url in
                    handleDeepLink(url: url)
                }
                .onAppear {
                    // Debug App Group access
                    let fileManager = FileManager.default
                    if let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: "group.com.elislothower.Beat-Bridge") {
                        print("✅ App: App group container exists at: \(containerURL.path)")
                    } else {
                        print("❌ App: App group container NOT available")
                    }
                }
        }
        .modelContainer(sharedModelContainer)
    }
    
    private func handleDeepLink(url: URL) {
        print("DEBUG: App received URL: \(url.absoluteString)")
        if url.scheme == "beatbridge" {
            if url.host == "share" {
                print("DEBUG: Received share request")
                NotificationCenter.default.post(name: .didReceiveShareExtensionRequest, object: nil)
                
                // If onboarding isn't complete, mark it as completed
                if !hasCompletedOnboarding {
                    hasCompletedOnboarding = true
                }
            } else if url.host == "selectservice" {
                print("DEBUG: Received service selection request")
                // If onboarding isn't complete, mark it as completed
                if !hasCompletedOnboarding {
                    hasCompletedOnboarding = true
                }
                
                NotificationCenter.default.post(name: .didReceiveServiceSelectionRequest, object: nil)
            } else {
                print("DEBUG: Received unknown URL host: \(url.host ?? "nil")")
            }
        } else {
            print("DEBUG: Received unknown URL scheme: \(url.scheme ?? "nil")")
        }
    }
}

struct RootView: View {
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false
    
    var body: some View {
        if hasCompletedOnboarding {
            ContentView()
        } else {
            OnboardingView()
        }
    }
}



class AppDelegate: NSObject, UIApplicationDelegate {
    
    func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        print("DEBUG: AppDelegate: didFinishLaunchingWithOptions")
        
        // Check if app was launched with a URL
        if let url = launchOptions?[.url] as? URL {
            print("DEBUG: App launched with URL: \(url.absoluteString)")
            
            // Save the URL to UserDefaults
            let userDefaults = UserDefaults(suiteName: "group.com.elislothower.Beat-Bridge")
            userDefaults?.set(url.absoluteString, forKey: "lastSharedURL")
            userDefaults?.synchronize()
            
            // Post notification to trigger contact picker
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NotificationCenter.default.post(name: .didReceiveShareExtensionRequest, object: nil)
            }
        }
        
        // Keep any other code you have in this method
        return true
    }

    // In your existing application(_:open:options:) method,
    // add this code to handle opened URLs:

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        print("DEBUG: AppDelegate: open URL: \(url.absoluteString)")
        
        // Handle beatbridge:// scheme URLs
        if url.scheme == "beatbridge" {
            if url.host == "share" {
                print("DEBUG: Manually handling share URL")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NotificationCenter.default.post(name: .didReceiveShareExtensionRequest, object: nil)
                }
                return true
            } else if url.host == "selectservice" {
                print("DEBUG: Manually handling selectservice URL")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NotificationCenter.default.post(name: .didReceiveServiceSelectionRequest, object: nil)
                }
                return true
            }
        } else {
            // This could be a direct document open from the share sheet
            print("DEBUG: Handling direct URL: \(url.absoluteString)")
            
            // Save the URL to UserDefaults
            let userDefaults = UserDefaults(suiteName: "group.com.elislothower.Beat-Bridge")
            userDefaults?.set(url.absoluteString, forKey: "lastSharedURL")
            userDefaults?.synchronize()
            
            // Notify the app to show the contact picker
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NotificationCenter.default.post(name: .didReceiveShareExtensionRequest, object: nil)
            }
            return true
        }
        
        return false
    }
    
    
    // Add ability to handle activity continuation
    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        print("DEBUG: AppDelegate: continue userActivity: \(userActivity.activityType)")
        
        // Check if this is a shared URL
        if userActivity.activityType == NSUserActivityTypeBrowsingWeb,
           let url = userActivity.webpageURL {
            print("DEBUG: Received webpage URL: \(url.absoluteString)")
            
            // Save URL to UserDefaults
            let userDefaults = UserDefaults(suiteName: "group.com.elislothower.Beat-Bridge")
            userDefaults?.set(url.absoluteString, forKey: "lastSharedURL")
            userDefaults?.synchronize()
            
            // Notify the app
            NotificationCenter.default.post(name: .didReceiveShareExtensionRequest, object: nil)
            return true
        }
        
        return false
    }
}

// MARK: - MFMessageComposeViewControllerDelegate
extension AppDelegate: MFMessageComposeViewControllerDelegate {
    func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
        // Dismiss the message composer
        controller.dismiss(animated: true) {
            print("DEBUG: Message composer dismissed with result: \(result.rawValue)")
            
            // Clean up any state as needed
            let userDefaults = UserDefaults(suiteName: "group.com.elislothower.Beat-Bridge")
            userDefaults?.removeObject(forKey: "lastSharedURL")
            userDefaults?.synchronize()
        }
    }
}

// Notifications for deep link events
extension Notification.Name {
    static let didReceiveShareExtensionRequest = Notification.Name("didReceiveShareExtensionRequest")
    static let didReceiveServiceSelectionRequest = Notification.Name("didReceiveServiceSelectionRequest")
}
