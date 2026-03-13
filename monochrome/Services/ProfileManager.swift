import Foundation
import Observation

@Observable
class ProfileManager {
    static let shared = ProfileManager()

    var profile = UserProfile()
    var isLoaded = false

    private let profileKey = "monochrome_user_profile"

    init() {
        loadLocal()
    }

    // MARK: - Local

    private func loadLocal() {
        if let data = UserDefaults.standard.data(forKey: profileKey),
           let saved = try? JSONDecoder().decode(UserProfile.self, from: data) {
            profile = saved
            isLoaded = true
        }
    }

    private func saveLocal() {
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: profileKey)
        }
    }

    // MARK: - Cloud Sync

    func syncFromCloud(uid: String) async {
        do {
            let record = try await PocketBaseService.shared.getUserRecord(uid: uid, forceRefresh: true)

            profile.username = record.username ?? ""
            profile.displayName = record.display_name ?? ""
            profile.avatarUrl = record.avatar_url ?? ""
            profile.banner = record.banner ?? ""
            profile.status = record.status ?? ""
            profile.about = record.about ?? ""
            profile.website = record.website ?? ""
            profile.lastfmUsername = record.lastfm_username ?? ""

            // Parse privacy
            if let privacyStr = record.privacy,
               let privacyData = privacyStr.data(using: .utf8),
               let privacyDict = try? JSONSerialization.jsonObject(with: privacyData) as? [String: Any] {
                profile.privacy.playlists = (privacyDict["playlists"] as? String) ?? "public"
                profile.privacy.lastfm = (privacyDict["lastfm"] as? String) ?? "public"
            }

            // Count history items
            if let historyStr = record.history,
               let historyData = historyStr.data(using: .utf8),
               let historyArray = try? JSONSerialization.jsonObject(with: historyData) as? [Any] {
                profile.historyCount = historyArray.count
            }

            isLoaded = true
            saveLocal()
            print("[Profile] Synced from cloud: @\(profile.username), \(profile.displayName)")
        } catch {
            print("[Profile] Sync error: \(error.localizedDescription)")
        }
    }

    func saveToCloud(uid: String) async {
        do {
            let record = try await PocketBaseService.shared.getUserRecord(uid: uid)
            let pb = PocketBaseService.shared

            // Build profile data
            var data: [String: Any] = [
                "username": profile.username,
                "display_name": profile.displayName,
                "avatar_url": profile.avatarUrl,
                "banner": profile.banner,
                "about": profile.about,
                "website": profile.website,
                "lastfm_username": profile.lastfmUsername
            ]

            // Privacy as JSON
            let privacyDict: [String: String] = [
                "playlists": profile.privacy.playlists,
                "lastfm": profile.privacy.lastfm
            ]
            if let privacyData = try? JSONSerialization.data(withJSONObject: privacyDict),
               let privacyString = String(data: privacyData, encoding: .utf8) {
                data["privacy"] = privacyString
            }

            // Send all fields at once
            try await pb.updateUserFields(recordId: record.id, uid: uid, fields: data)

            saveLocal()
            print("[Profile] Saved to cloud")
        } catch {
            print("[Profile] Save error: \(error.localizedDescription)")
        }
    }

    func updateField(_ field: String, value: String) {
        switch field {
        case "username": profile.username = value
        case "display_name": profile.displayName = value
        case "avatar_url": profile.avatarUrl = value
        case "banner": profile.banner = value
        case "about": profile.about = value
        case "website": profile.website = value
        case "lastfm_username": profile.lastfmUsername = value
        default: break
        }
        saveLocal()
        syncFieldInBackground(field: field, value: value)
    }

    func togglePrivacy(field: String) {
        switch field {
        case "playlists":
            profile.privacy.playlists = profile.privacy.playlists == "public" ? "private" : "public"
        case "lastfm":
            profile.privacy.lastfm = profile.privacy.lastfm == "public" ? "private" : "public"
        default: break
        }
        saveLocal()

        let privacyDict: [String: String] = [
            "playlists": profile.privacy.playlists,
            "lastfm": profile.privacy.lastfm
        ]
        guard let uid = AuthService.shared.currentUser?.uid else { return }
        Task.detached(priority: .utility) {
            do {
                let record = try await PocketBaseService.shared.getUserRecord(uid: uid)
                try await PocketBaseService.shared.updateUserField(recordId: record.id, uid: uid, field: "privacy", value: privacyDict)
            } catch {
                print("[Profile] Privacy sync error: \(error.localizedDescription)")
            }
        }
    }

    func clear() {
        profile = UserProfile()
        isLoaded = false
        UserDefaults.standard.removeObject(forKey: profileKey)
    }

    private func syncFieldInBackground(field: String, value: String) {
        guard let uid = AuthService.shared.currentUser?.uid else { return }
        Task.detached(priority: .utility) {
            do {
                let record = try await PocketBaseService.shared.getUserRecord(uid: uid)
                try await PocketBaseService.shared.updateUserField(recordId: record.id, uid: uid, field: field, value: value)
            } catch {
                print("[Profile] Field sync error: \(error.localizedDescription)")
            }
        }
    }
}
