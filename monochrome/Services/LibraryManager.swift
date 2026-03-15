import Foundation
import Observation

@Observable
class LibraryManager {
    static let shared = LibraryManager()

    var favoriteTracks: [Track] = []
    var favoriteAlbums: [Album] = []
    var favoriteArtists: [Artist] = []
    var favoritePlaylists: [Playlist] = []
    var favoriteMixes: [Mix] = []

    private let tracksKey = "monochrome_favorite_tracks"
    private let albumsKey = "monochrome_favorite_albums"
    private let artistsKey = "monochrome_favorite_artists"
    private let playlistsKey = "monochrome_favorite_playlists"
    private let mixesKey = "monochrome_favorite_mixes"

    @ObservationIgnored
    private var isRefreshingTrackQualities = false

    init() {
        loadFavorites()
    }

    func loadFavorites() {
        if let data = UserDefaults.standard.data(forKey: tracksKey),
           let items = try? JSONDecoder().decode([Track].self, from: data) {
            favoriteTracks = items
        }
        if let data = UserDefaults.standard.data(forKey: albumsKey),
           let items = try? JSONDecoder().decode([Album].self, from: data) {
            favoriteAlbums = items
        }
        if let data = UserDefaults.standard.data(forKey: artistsKey),
           let items = try? JSONDecoder().decode([Artist].self, from: data) {
            favoriteArtists = items
        }
        if let data = UserDefaults.standard.data(forKey: playlistsKey),
           let items = try? JSONDecoder().decode([Playlist].self, from: data) {
            favoritePlaylists = items
        }
        if let data = UserDefaults.standard.data(forKey: mixesKey),
           let items = try? JSONDecoder().decode([Mix].self, from: data) {
            favoriteMixes = items
        }

        refreshMissingTrackQualities()
    }

    private func refreshMissingTrackQualities() {
        guard !isRefreshingTrackQualities else { return }
        let missingTracks = favoriteTracks.filter {
            $0.audioQuality == nil && !QualityCache.isCached($0.id)
        }
        guard !missingTracks.isEmpty else { return }

        isRefreshingTrackQualities = true

        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let api = MonochromeAPI()
            var updates: [Int: Track] = [:]
            var failedIds: [Int] = []

            await withTaskGroup(of: (Int, Track?).self) { group in
                var pending = 0
                for track in missingTracks {
                    if pending >= 3, let (id, result) = await group.next() {
                        if let result { updates[id] = result } else { failedIds.append(id) }
                        pending -= 1
                    }
                    group.addTask {
                        // Use the proxy to check actual available quality (Tidal v1 metadata is unreliable)
                        if let quality = await api.fetchBestAvailableQuality(trackId: track.id) {
                            let updated = track.withQuality(quality)
                            return (track.id, updated)
                        }
                        return (track.id, nil)
                    }
                    pending += 1
                }
                for await (id, result) in group {
                    if let result { updates[id] = result } else { failedIds.append(id) }
                }
            }

            var cacheEntries: [(id: Int, audioQuality: String?, mediaTags: [String]?)] = []
            for (id, track) in updates {
                cacheEntries.append((id, track.audioQuality, track.mediaMetadata?.tags))
            }
            for id in failedIds {
                cacheEntries.append((id, nil, nil))
            }
            QualityCache.store(cacheEntries)

            await MainActor.run {
                defer { self.isRefreshingTrackQualities = false }
                guard !updates.isEmpty else { return }

                self.favoriteTracks = self.favoriteTracks.map { track in
                    guard track.audioQuality == nil,
                          let update = updates[track.id] else { return track }
                    return track.withUpdatedQuality(from: update)
                }
                self.saveTracks()

                for track in self.favoriteTracks where updates[track.id] != nil {
                    self.syncItemInBackground(type: "track", track: track, added: true)
                }
            }
        }
    }

    // MARK: - Save

    func saveTracks() {
        if let data = try? JSONEncoder().encode(favoriteTracks) {
            UserDefaults.standard.set(data, forKey: tracksKey)
        }
    }

    func saveAlbums() {
        if let data = try? JSONEncoder().encode(favoriteAlbums) {
            UserDefaults.standard.set(data, forKey: albumsKey)
        }
    }

    func saveArtists() {
        if let data = try? JSONEncoder().encode(favoriteArtists) {
            UserDefaults.standard.set(data, forKey: artistsKey)
        }
    }

    func savePlaylists() {
        if let data = try? JSONEncoder().encode(favoritePlaylists) {
            UserDefaults.standard.set(data, forKey: playlistsKey)
        }
    }

    func saveMixes() {
        if let data = try? JSONEncoder().encode(favoriteMixes) {
            UserDefaults.standard.set(data, forKey: mixesKey)
        }
    }

    // MARK: - Toggle Favorites

    func toggleFavorite(track: Track) {
        let wasAdded: Bool
        if let index = favoriteTracks.firstIndex(where: { $0.id == track.id }) {
            favoriteTracks.remove(at: index)
            wasAdded = false
        } else {
            favoriteTracks.insert(track, at: 0)
            wasAdded = true
        }
        saveTracks()
        syncItemInBackground(type: "track", track: track, added: wasAdded)
    }

    func toggleFavorite(album: Album) {
        let wasAdded: Bool
        if let index = favoriteAlbums.firstIndex(where: { $0.id == album.id }) {
            favoriteAlbums.remove(at: index)
            wasAdded = false
        } else {
            favoriteAlbums.insert(album, at: 0)
            wasAdded = true
        }
        saveAlbums()
        syncItemInBackground(type: "album", album: album, added: wasAdded)
    }

    func toggleFavorite(artist: Artist) {
        let wasAdded: Bool
        if let index = favoriteArtists.firstIndex(where: { $0.id == artist.id }) {
            favoriteArtists.remove(at: index)
            wasAdded = false
        } else {
            favoriteArtists.insert(artist, at: 0)
            wasAdded = true
        }
        saveArtists()
        syncItemInBackground(type: "artist", artist: artist, added: wasAdded)
    }

    func toggleFavorite(playlist: Playlist) {
        let wasAdded: Bool
        if let index = favoritePlaylists.firstIndex(where: { $0.uuid == playlist.uuid }) {
            favoritePlaylists.remove(at: index)
            wasAdded = false
        } else {
            favoritePlaylists.insert(playlist, at: 0)
            wasAdded = true
        }
        savePlaylists()
        syncItemInBackground(type: "playlist", playlist: playlist, added: wasAdded)
    }

    func toggleFavorite(mix: Mix) {
        let wasAdded: Bool
        if let index = favoriteMixes.firstIndex(where: { $0.id == mix.id }) {
            favoriteMixes.remove(at: index)
            wasAdded = false
        } else {
            favoriteMixes.insert(mix, at: 0)
            wasAdded = true
        }
        saveMixes()
        syncItemInBackground(type: "mix", mix: mix, added: wasAdded)
    }

    // MARK: - Is Favorite

    func isFavorite(trackId: Int) -> Bool {
        favoriteTracks.contains { $0.id == trackId }
    }

    func isFavorite(albumId: Int) -> Bool {
        favoriteAlbums.contains { $0.id == albumId }
    }

    func isFavorite(artistId: Int) -> Bool {
        favoriteArtists.contains { $0.id == artistId }
    }

    func isFavorite(playlistId: String) -> Bool {
        favoritePlaylists.contains { $0.uuid == playlistId }
    }

    func isFavorite(mixId: String) -> Bool {
        favoriteMixes.contains { $0.id == mixId }
    }

    // MARK: - Cloud Sync

    func syncFromCloud(uid: String) async {
        do {
            let cloud = try await PocketBaseService.shared.fullSync(uid: uid)

            let localTracksById = Dictionary(uniqueKeysWithValues: favoriteTracks.map { ($0.id, $0) })
            let mergedTracks = cloud.tracks.map { track in
                guard track.audioQuality == nil || track.mediaMetadata == nil else { return track }
                guard let local = localTracksById[track.id] else { return track }
                let quality = track.audioQuality ?? local.audioQuality
                let metadata = track.mediaMetadata ?? local.mediaMetadata
                guard let quality else { return track }
                return track.withQuality(quality, mediaMetadata: metadata)
            }

            favoriteTracks = mergedTracks
            saveTracks()
            refreshMissingTrackQualities()

            favoriteAlbums = cloud.albums
            saveAlbums()

            favoriteArtists = cloud.artists
            saveArtists()

            favoritePlaylists = cloud.playlists
            savePlaylists()

            favoriteMixes = cloud.mixes
            saveMixes()

            print("[Sync] Cloud sync completed: \(favoriteTracks.count) tracks, \(favoriteAlbums.count) albums, \(favoriteArtists.count) artists, \(favoritePlaylists.count) playlists, \(favoriteMixes.count) mixes")
        } catch {
            print("[Sync] Cloud sync error: \(error.localizedDescription)")
        }
    }

    private func syncItemInBackground(type: String, track: Track? = nil, album: Album? = nil, artist: Artist? = nil, playlist: Playlist? = nil, mix: Mix? = nil, added: Bool) {
        guard let uid = AuthService.shared.currentUser?.uid else { return }

        Task.detached(priority: .utility) {
            do {
                try await PocketBaseService.shared.syncLibraryItem(
                    uid: uid, type: type,
                    track: track, album: album, artist: artist,
                    playlist: playlist, mix: mix, added: added
                )
            } catch {
                print("[Sync] Item sync error: \(error.localizedDescription)")
            }
        }
    }
}
