import Foundation
import SwiftData
import Contacts
import Combine

// MARK: - Music Service Enum
enum MusicService: String, CaseIterable, Identifiable {
    case spotify = "Spotify"
    case appleMusic = "Apple Music"
    case youtubeMusic = "YouTube Music"
    case pandora = "Pandora"
    case tidal = "Tidal"
    case deezer = "Deezer"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .spotify: return "spotify-icon"
        case .appleMusic: return "apple-music-icon"
        case .youtubeMusic: return "youtube-music-icon"
        case .pandora: return "pandora-icon"
        case .tidal: return "tidal-icon"
        case .deezer: return "deezer-icon"
        }
    }
}

// MARK: - Contact to Service Preferences
@Model
final class ContactServicePreference {
    var contactIdentifier: String  // CNContact.identifier
    var contactName: String        // For display purposes
    var musicService: String       // MusicService.rawValue
    var lastUsed: Date
    
    init(contactIdentifier: String, contactName: String, musicService: String) {
        self.contactIdentifier = contactIdentifier
        self.contactName = contactName
        self.musicService = musicService
        self.lastUsed = Date()
    }
    
    // Helper to create a readable name from a contact
    static func formatName(from contact: CNContact) -> String {
        let givenName = contact.givenName
        let familyName = contact.familyName
        
        if !givenName.isEmpty && !familyName.isEmpty {
            return "\(givenName) \(familyName)"
        } else if !givenName.isEmpty {
            return givenName
        } else if !familyName.isEmpty {
            return familyName
        } else {
            return contact.phoneNumbers.first?.value.stringValue ?? "Unknown Contact"
        }
    }
}

// MARK: - Conversion History
@Model
final class ConversionHistory {
    var originalLink: String
    var convertedLink: String
    var originalService: String
    var convertedService: String
    var songTitle: String?
    var artistName: String?
    var timestamp: Date
    
    init(
        originalLink: String,
        convertedLink: String,
        originalService: String,
        convertedService: String,
        songTitle: String? = nil,
        artistName: String? = nil
    ) {
        self.originalLink = originalLink
        self.convertedLink = convertedLink
        self.originalService = originalService
        self.convertedService = convertedService
        self.songTitle = songTitle
        self.artistName = artistName
        self.timestamp = Date()
    }
}

// MARK: - Helper for UserDefaults Preferences
// This allows the share extension to access the same data
class ContactPreferencesHelper {
    static let shared = ContactPreferencesHelper()
    
    private let userDefaults = UserDefaults(suiteName: "group.com.elislothower.Beat-Bridge")!
    private let contactPreferencesKey = "contactMusicServicePreferences"
    
    // Simple model for contact preferences
    struct ContactPreference: Codable {
        let contactIdentifier: String
        let contactName: String
        let musicService: String
        let lastUsed: Date
    }
    
    private init() {}
    
    // Save a contact's music service preference
    func savePreference(contactIdentifier: String, contactName: String, musicService: String) {
        var preferences = getPreferences()
        
        // Update or add new preference
        if let index = preferences.firstIndex(where: { $0.contactIdentifier == contactIdentifier }) {
            preferences[index] = ContactPreference(
                contactIdentifier: contactIdentifier,
                contactName: contactName,
                musicService: musicService,
                lastUsed: Date()
            )
        } else {
            preferences.append(ContactPreference(
                contactIdentifier: contactIdentifier,
                contactName: contactName,
                musicService: musicService,
                lastUsed: Date()
            ))
        }
        
        // Save to UserDefaults
        if let encodedData = try? JSONEncoder().encode(preferences) {
            userDefaults.set(encodedData, forKey: contactPreferencesKey)
        }
    }
    
    // Get music service for a contact
    func getPreferredService(for contactIdentifier: String) -> String? {
        let preferences = getPreferences()
        return preferences.first(where: { $0.contactIdentifier == contactIdentifier })?.musicService
    }
    
    // Get all stored preferences
    func getPreferences() -> [ContactPreference] {
        guard let data = userDefaults.data(forKey: contactPreferencesKey),
              let preferences = try? JSONDecoder().decode([ContactPreference].self, from: data) else {
            return []
        }
        return preferences
    }
    
    // Check if we have a preference for this contact
    func hasPreference(for contactIdentifier: String) -> Bool {
        return getPreferredService(for: contactIdentifier) != nil
    }
    
    
}

// In Models.swift, at the end of the file, after all other code:

// MARK: - Debug Extensions
extension ContactPreferencesHelper {
    // Debug: Print all stored preferences
    func debugPrintAllPreferences() {
        let preferences = getPreferences()
        print("DEBUG: ContactPreferencesHelper - All preferences:")
        if preferences.isEmpty {
            print("  - No preferences found")
        } else {
            for pref in preferences {
                print("  - Contact: \(pref.contactName), ID: \(pref.contactIdentifier), Service: \(pref.musicService)")
            }
        }
    }
    
    // Debug: Test if a preference can be successfully saved and retrieved
    func testPreferenceSaveRetrieve() {
        print("DEBUG: Testing preference save/retrieve")
        
        // Save a test preference
        let testID = "TEST_CONTACT_ID"
        let testName = "Test Contact"
        let testService = "Spotify"
        
        savePreference(contactIdentifier: testID, contactName: testName, musicService: testService)
        print("DEBUG: Saved test preference")
        
        // Try to retrieve it
        if let service = getPreferredService(for: testID) {
            print("DEBUG: Successfully retrieved test preference: \(service)")
        } else {
            print("DEBUG: Failed to retrieve test preference")
        }
        
        // Check if hasPreference works
        let hasPreference = hasPreference(for: testID)
        print("DEBUG: hasPreference result: \(hasPreference)")
    }
}

// MARK: - Link Converter Service

// Response model for Odesli API
struct OdesliResponse: Decodable {
    struct PlatformLink: Decodable {
        let url: String
    }
    
    struct PlatformLinks: Decodable {
        let spotify: PlatformLink?
        let appleMusic: PlatformLink?
        let youtubeMusic: PlatformLink?
        let pandora: PlatformLink?
        let tidal: PlatformLink?
        let deezer: PlatformLink?
        
        enum CodingKeys: String, CodingKey {
            case spotify
            case appleMusic = "appleMusic"
            case youtubeMusic = "youtubeMusic"
            case pandora
            case tidal
            case deezer
        }
    }
    
    let linksByPlatform: PlatformLinks
}

// Link converter service
class LinkConverterService: ObservableObject {
    enum ConversionError: Error {
        case invalidURL
        case requestFailed
        case decodingFailed
        case noMatchFound
    }
    
    private let baseURL = "https://api.song.link/v1-alpha.1/links"
    
    @Published var isLoading: Bool = false
    
    func convertLink(_ originalURL: String, forService targetService: MusicService? = nil, completion: @escaping (Result<[MusicService: String], ConversionError>) -> Void) {
        guard let encodedURL = originalURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let requestURL = URL(string: "\(baseURL)?url=\(encodedURL)") else {
            completion(.failure(.invalidURL))
            return
        }
        
        isLoading = true
        
        URLSession.shared.dataTask(with: requestURL) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                guard let data = data, error == nil else {
                    completion(.failure(.requestFailed))
                    return
                }
                
                do {
                    let response = try JSONDecoder().decode(OdesliResponse.self, from: data)
                    var serviceLinks: [MusicService: String] = [:]
                    
                    // Extract links for each supported service
                    if let spotifyLink = response.linksByPlatform.spotify?.url {
                        serviceLinks[.spotify] = spotifyLink
                    }
                    
                    if let appleMusicLink = response.linksByPlatform.appleMusic?.url {
                        serviceLinks[.appleMusic] = appleMusicLink
                    }
                    
                    if let youtubeMusicLink = response.linksByPlatform.youtubeMusic?.url {
                        serviceLinks[.youtubeMusic] = youtubeMusicLink
                    }
                    
                    if let pandoraLink = response.linksByPlatform.pandora?.url {
                        serviceLinks[.pandora] = pandoraLink
                    }
                    
                    if let tidalLink = response.linksByPlatform.tidal?.url {
                        serviceLinks[.tidal] = tidalLink
                    }
                    
                    if let deezerLink = response.linksByPlatform.deezer?.url {
                        serviceLinks[.deezer] = deezerLink
                    }
                    
                    if serviceLinks.isEmpty {
                        completion(.failure(.noMatchFound))
                    } else {
                        completion(.success(serviceLinks))
                    }
                } catch {
                    print("Decoding error: \(error)")
                    completion(.failure(.decodingFailed))
                }
            }
        }.resume()
    }
}
