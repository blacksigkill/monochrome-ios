import Foundation
import Combine

class PlaylistManager: ObservableObject {
    static let shared = PlaylistManager()

    @Published var userPlaylists: [UserPlaylist] = []
    @Published var userFolders: [UserFolder] = []

    private let playlistsKey = "monochrome_user_playlists"
    private let foldersKey = "monochrome_user_folders"

    init() {
        loadLocal()
    }

    // MARK: - Local Persistence

    func loadLocal() {
        if let data = UserDefaults.standard.data(forKey: playlistsKey),
           let items = try? JSONDecoder().decode([UserPlaylist].self, from: data) {
            userPlaylists = items
        }
        if let data = UserDefaults.standard.data(forKey: foldersKey),
           let items = try? JSONDecoder().decode([UserFolder].self, from: data) {
            userFolders = items
        }
    }

    private func savePlaylists() {
        if let data = try? JSONEncoder().encode(userPlaylists) {
            UserDefaults.standard.set(data, forKey: playlistsKey)
        }
    }

    private func saveFolders() {
        if let data = try? JSONEncoder().encode(userFolders) {
            UserDefaults.standard.set(data, forKey: foldersKey)
        }
    }

    // MARK: - Playlist CRUD

    @discardableResult
    func createPlaylist(name: String, isPublic: Bool = false) -> UserPlaylist {
        let playlist = UserPlaylist(name: name, isPublic: isPublic)
        userPlaylists.insert(playlist, at: 0)
        savePlaylists()
        syncPlaylistToCloud(playlist)
        return playlist
    }

    func deletePlaylist(id: String) {
        userPlaylists.removeAll { $0.id == id }
        // Remove from any folders
        for i in userFolders.indices {
            userFolders[i].playlists.removeAll { $0 == id }
        }
        savePlaylists()
        saveFolders()
        syncDeletePlaylistFromCloud(id)
    }

    func renamePlaylist(id: String, name: String) {
        guard let idx = userPlaylists.firstIndex(where: { $0.id == id }) else { return }
        userPlaylists[idx].name = name
        userPlaylists[idx].updatedAt = Date().timeIntervalSince1970 * 1000
        savePlaylists()
        syncPlaylistToCloud(userPlaylists[idx])
    }

    func updatePlaylistDescription(id: String, description: String) {
        guard let idx = userPlaylists.firstIndex(where: { $0.id == id }) else { return }
        userPlaylists[idx].description = description
        userPlaylists[idx].updatedAt = Date().timeIntervalSince1970 * 1000
        savePlaylists()
        syncPlaylistToCloud(userPlaylists[idx])
    }

    func updatePlaylistCover(id: String, cover: String) {
        guard let idx = userPlaylists.firstIndex(where: { $0.id == id }) else { return }
        userPlaylists[idx].cover = cover
        userPlaylists[idx].updatedAt = Date().timeIntervalSince1970 * 1000
        savePlaylists()
        syncPlaylistToCloud(userPlaylists[idx])
    }

    func togglePlaylistVisibility(id: String) {
        guard let idx = userPlaylists.firstIndex(where: { $0.id == id }) else { return }
        userPlaylists[idx].isPublic.toggle()
        userPlaylists[idx].updatedAt = Date().timeIntervalSince1970 * 1000
        savePlaylists()
        syncPlaylistToCloud(userPlaylists[idx])
    }

    // MARK: - Track Management

    func addTrack(_ track: Track, to playlistId: String) {
        guard let idx = userPlaylists.firstIndex(where: { $0.id == playlistId }) else { return }
        // Don't add duplicates
        guard !userPlaylists[idx].tracks.contains(where: { $0.id == track.id }) else { return }
        userPlaylists[idx].tracks.append(track)
        userPlaylists[idx].numberOfTracks = userPlaylists[idx].tracks.count
        userPlaylists[idx].updatedAt = Date().timeIntervalSince1970 * 1000
        updatePlaylistImages(at: idx)
        savePlaylists()
        syncPlaylistToCloud(userPlaylists[idx])
    }

    func removeTrack(_ trackId: Int, from playlistId: String) {
        guard let idx = userPlaylists.firstIndex(where: { $0.id == playlistId }) else { return }
        userPlaylists[idx].tracks.removeAll { $0.id == trackId }
        userPlaylists[idx].numberOfTracks = userPlaylists[idx].tracks.count
        userPlaylists[idx].updatedAt = Date().timeIntervalSince1970 * 1000
        updatePlaylistImages(at: idx)
        savePlaylists()
        syncPlaylistToCloud(userPlaylists[idx])
    }

    private func updatePlaylistImages(at idx: Int) {
        // Collect unique album covers (up to 4) for collage
        var seen = Set<String>()
        var covers: [String] = []
        for track in userPlaylists[idx].tracks {
            if let cover = track.album?.cover, !cover.isEmpty, !seen.contains(cover) {
                seen.insert(cover)
                covers.append(cover)
                if covers.count >= 4 { break }
            }
        }
        userPlaylists[idx].images = covers
    }

    // MARK: - Folder CRUD

    @discardableResult
    func createFolder(name: String) -> UserFolder {
        let folder = UserFolder(name: name)
        userFolders.insert(folder, at: 0)
        saveFolders()
        syncFoldersToCloud()
        return folder
    }

    func deleteFolder(id: String) {
        userFolders.removeAll { $0.id == id }
        saveFolders()
        syncFoldersToCloud()
    }

    func renameFolder(id: String, name: String) {
        guard let idx = userFolders.firstIndex(where: { $0.id == id }) else { return }
        userFolders[idx].name = name
        userFolders[idx].updatedAt = Date().timeIntervalSince1970 * 1000
        saveFolders()
        syncFoldersToCloud()
    }

    func addPlaylistToFolder(playlistId: String, folderId: String) {
        guard let idx = userFolders.firstIndex(where: { $0.id == folderId }) else { return }
        guard !userFolders[idx].playlists.contains(playlistId) else { return }
        userFolders[idx].playlists.append(playlistId)
        userFolders[idx].updatedAt = Date().timeIntervalSince1970 * 1000
        saveFolders()
        syncFoldersToCloud()
    }

    func removePlaylistFromFolder(playlistId: String, folderId: String) {
        guard let idx = userFolders.firstIndex(where: { $0.id == folderId }) else { return }
        userFolders[idx].playlists.removeAll { $0 == playlistId }
        userFolders[idx].updatedAt = Date().timeIntervalSince1970 * 1000
        saveFolders()
        syncFoldersToCloud()
    }

    func playlistsInFolder(_ folderId: String) -> [UserPlaylist] {
        guard let folder = userFolders.first(where: { $0.id == folderId }) else { return [] }
        return folder.playlists.compactMap { pid in userPlaylists.first { $0.id == pid } }
    }

    func unfolderedPlaylists() -> [UserPlaylist] {
        let foldered = Set(userFolders.flatMap { $0.playlists })
        return userPlaylists.filter { !foldered.contains($0.id) }
    }

    // MARK: - Cloud Sync

    func syncFromCloud(uid: String) async {
        do {
            let record = try await PocketBaseService.shared.getUserRecord(uid: uid, forceRefresh: true)
            let cloudPlaylists = Self.decodePlaylists(from: record.user_playlists)
            let cloudFolders = Self.decodeFolders(from: record.user_folders)

            userPlaylists = cloudPlaylists.sorted { $0.updatedAt > $1.updatedAt }
            userFolders = cloudFolders.sorted { $0.updatedAt > $1.updatedAt }
            savePlaylists()
            saveFolders()
            print("[Sync] User playlists synced: \(userPlaylists.count) playlists, \(userFolders.count) folders")
        } catch {
            print("[Sync] User playlists sync error: \(error.localizedDescription)")
        }
    }

    private func syncPlaylistToCloud(_ playlist: UserPlaylist) {
        guard let uid = AuthService.shared.currentUser?.uid else { return }
        Task.detached(priority: .utility) {
            do {
                let record = try await PocketBaseService.shared.getUserRecord(uid: uid, forceRefresh: true)
                var dict = Self.parseJSON(record.user_playlists) ?? [:]
                dict[playlist.id] = Self.playlistToDict(playlist)
                try await PocketBaseService.shared.updateUserField(recordId: record.id, uid: uid, field: "user_playlists", value: dict)
                print("[Sync] Synced playlist '\(playlist.name)' to cloud")
            } catch {
                print("[Sync] Playlist sync error: \(error.localizedDescription)")
            }
        }
    }

    private func syncDeletePlaylistFromCloud(_ playlistId: String) {
        guard let uid = AuthService.shared.currentUser?.uid else { return }
        Task.detached(priority: .utility) {
            do {
                let record = try await PocketBaseService.shared.getUserRecord(uid: uid, forceRefresh: true)
                var dict = Self.parseJSON(record.user_playlists) ?? [:]
                dict.removeValue(forKey: playlistId)
                try await PocketBaseService.shared.updateUserField(recordId: record.id, uid: uid, field: "user_playlists", value: dict)
                // Also sync folders since playlist was removed from them
                var foldersDict = Self.parseJSON(record.user_folders) ?? [:]
                for (key, value) in foldersDict {
                    if var folder = value as? [String: Any],
                       var pids = folder["playlists"] as? [String] {
                        pids.removeAll { $0 == playlistId }
                        folder["playlists"] = pids
                        foldersDict[key] = folder
                    }
                }
                try await PocketBaseService.shared.updateUserField(recordId: record.id, uid: uid, field: "user_folders", value: foldersDict)
            } catch {
                print("[Sync] Playlist delete sync error: \(error.localizedDescription)")
            }
        }
    }

    private func syncFoldersToCloud() {
        guard let uid = AuthService.shared.currentUser?.uid else { return }
        let folders = userFolders
        Task.detached(priority: .utility) {
            do {
                let record = try await PocketBaseService.shared.getUserRecord(uid: uid, forceRefresh: true)
                var dict: [String: Any] = [:]
                for folder in folders {
                    dict[folder.id] = Self.folderToDict(folder)
                }
                try await PocketBaseService.shared.updateUserField(recordId: record.id, uid: uid, field: "user_folders", value: dict)
            } catch {
                print("[Sync] Folders sync error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Serialization Helpers

    nonisolated private static func playlistToDict(_ p: UserPlaylist) -> [String: Any] {
        var dict: [String: Any] = [
            "id": p.id,
            "name": p.name,
            "cover": p.cover,
            "description": p.description,
            "createdAt": p.createdAt,
            "updatedAt": p.updatedAt,
            "numberOfTracks": p.numberOfTracks,
            "images": p.images,
            "isPublic": p.isPublic
        ]
        dict["tracks"] = p.tracks.map { PocketBaseService.minifyTrackForPlaylist($0) }
        return dict
    }

    nonisolated private static func folderToDict(_ f: UserFolder) -> [String: Any] {
        return [
            "id": f.id,
            "name": f.name,
            "cover": f.cover,
            "playlists": f.playlists,
            "createdAt": f.createdAt,
            "updatedAt": f.updatedAt
        ]
    }

    nonisolated private static func parseJSON(_ value: String?) -> [String: Any]? {
        guard let str = value, let data = str.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    static func decodePlaylists(from jsonString: String?) -> [UserPlaylist] {
        guard let dict = parseJSON(jsonString) else { return [] }
        return dict.values.compactMap { value -> UserPlaylist? in
            guard let obj = value as? [String: Any],
                  let id = obj["id"] as? String,
                  let name = obj["name"] as? String else { return nil }

            let trackDicts = (obj["tracks"] as? [[String: Any]]) ?? []
            let tracks = trackDicts.decodeTracks()

            return UserPlaylist(
                id: id,
                name: name,
                tracks: tracks,
                cover: obj["cover"] as? String ?? "",
                description: obj["description"] as? String ?? "",
                createdAt: (obj["createdAt"] as? Double) ?? 0,
                updatedAt: (obj["updatedAt"] as? Double) ?? 0,
                numberOfTracks: (obj["numberOfTracks"] as? Int) ?? tracks.count,
                images: (obj["images"] as? [String]) ?? [],
                isPublic: (obj["isPublic"] as? Bool) ?? false
            )
        }
    }

    static func decodeFolders(from jsonString: String?) -> [UserFolder] {
        guard let dict = parseJSON(jsonString) else { return [] }
        return dict.values.compactMap { value -> UserFolder? in
            guard let obj = value as? [String: Any],
                  let id = obj["id"] as? String,
                  let name = obj["name"] as? String else { return nil }

            return UserFolder(
                id: id,
                name: name,
                cover: obj["cover"] as? String ?? "",
                playlists: (obj["playlists"] as? [String]) ?? [],
                createdAt: (obj["createdAt"] as? Double) ?? 0,
                updatedAt: (obj["updatedAt"] as? Double) ?? 0
            )
        }
    }
}
