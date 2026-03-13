import Foundation

class PocketBaseService {
    static let shared = PocketBaseService()

    private let baseURL = "https://data.samidy.xyz"
    private let collection = "DB_users"
    private var cachedRecord: PBUserRecord?
    private let urlSession = URLSession.shared

    // MARK: - Get or Create User Record

    func getUserRecord(uid: String, forceRefresh: Bool = false) async throws -> PBUserRecord {
        if !forceRefresh, let cached = cachedRecord, cached.firebase_id == uid {
            return cached
        }

        let filterQuery = "firebase_id=\"\(uid)\""
        guard let encoded = filterQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(baseURL)/api/collections/\(collection)/records?filter=\(encoded)&f_id=\(uid)&sort=-username") else {
            throw PBError.badURL
        }

        let (data, response) = try await urlSession.data(for: request(for: url))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw PBError.serverError }

        let listResponse = try JSONDecoder().decode(PBListResponse.self, from: data)

        if let existing = listResponse.items.first {
            cachedRecord = existing
            return existing
        }

        return try await createUserRecord(uid: uid)
    }

    func clearCache() {
        cachedRecord = nil
    }

    private func createUserRecord(uid: String) async throws -> PBUserRecord {
        guard let url = URL(string: "\(baseURL)/api/collections/\(collection)/records?f_id=\(uid)") else {
            throw PBError.badURL
        }

        let body: [String: Any] = [
            "firebase_id": uid,
            "library": "{}",
            "history": "[]",
            "user_playlists": "{}",
            "user_folders": "{}"
        ]

        var req = request(for: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw PBError.serverError }

        let record = try JSONDecoder().decode(PBUserRecord.self, from: data)
        cachedRecord = record
        return record
    }

    // MARK: - Full Sync (on login)

    func fullSync(uid: String) async throws -> (tracks: [Track], albums: [Album], artists: [Artist], playlists: [Playlist], mixes: [Mix], history: [Track]) {
        let record = try await getUserRecord(uid: uid, forceRefresh: true)

        // Cloud is source of truth — just fetch and decode
        let library: [String: Any] = parseJSON(record.library) ?? [:]
        let tracksDict = (library["tracks"] as? [String: Any]) ?? [:]
        let albumsDict = (library["albums"] as? [String: Any]) ?? [:]
        let artistsDict = (library["artists"] as? [String: Any]) ?? [:]
        let playlistsDict = (library["playlists"] as? [String: Any]) ?? [:]
        let mixesDict = (library["mixes"] as? [String: Any]) ?? [:]

        let trackDicts = Array(tracksDict.values.compactMap { $0 as? [String: Any] })
        print("[Sync] Cloud has \(tracksDict.count) tracks, \(albumsDict.count) albums, \(artistsDict.count) artists, \(playlistsDict.count) playlists, \(mixesDict.count) mixes")
        let cloudTracks = trackDicts.decodeTracks()
        let cloudAlbums = Array(albumsDict.values.compactMap { $0 as? [String: Any] }).decodeAlbums()
        let cloudArtists = Array(artistsDict.values.compactMap { $0 as? [String: Any] }).decodeArtists()
        let cloudPlaylists = Array(playlistsDict.values.compactMap { $0 as? [String: Any] }).decodePlaylists()
        let cloudMixes = Array(mixesDict.values.compactMap { $0 as? [String: Any] }).decodeMixes()

        let cloudHistory = parseJSONArray(record.history) ?? []
        let historyTracks = cloudHistory.compactMap { $0 as? [String: Any] }.decodeTracks()

        return (cloudTracks, cloudAlbums, cloudArtists, cloudPlaylists, cloudMixes, historyTracks)
    }

    // MARK: - Sync Single Library Item (on toggle)

    func syncLibraryItem(uid: String, type: String, track: Track? = nil, album: Album? = nil, artist: Artist? = nil, playlist: Playlist? = nil, mix: Mix? = nil, added: Bool) async throws {
        let record = try await getUserRecord(uid: uid, forceRefresh: true)
        var library: [String: Any] = parseJSON(record.library) ?? [:]

        let pluralType = type == "mix" ? "mixes" : "\(type)s"
        var items = (library[pluralType] as? [String: Any]) ?? [:]

        let key: String?
        if let track = track { key = String(track.id) }
        else if let album = album { key = String(album.id) }
        else if let artist = artist { key = String(artist.id) }
        else if let playlist = playlist { key = playlist.uuid }
        else if let mix = mix { key = mix.id }
        else { key = nil }

        print("[Sync] syncLibraryItem: \(added ? "ADD" : "REMOVE") \(type) key=\(key ?? "nil"), items before: \(items.keys.sorted())")

        if added {
            if let track = track { items[String(track.id)] = minifyTrack(track) }
            else if let album = album { items[String(album.id)] = minifyAlbum(album) }
            else if let artist = artist { items[String(artist.id)] = minifyArtist(artist) }
            else if let playlist = playlist { items[playlist.uuid] = minifyPlaylist(playlist) }
            else if let mix = mix { items[mix.id] = minifyMix(mix) }
        } else {
            if let key = key {
                let removed = items.removeValue(forKey: key)
                print("[Sync] removeValue result: \(removed != nil ? "found and removed" : "key NOT found")")
            }
        }

        print("[Sync] items after: \(items.keys.sorted())")

        library[pluralType] = items
        try await updateField(recordId: record.id, uid: uid, field: "library", value: library)

        // Update cache
        cachedRecord = try await getUserRecord(uid: uid, forceRefresh: true)
    }

    // MARK: - Sync History Item (on track play)

    func syncHistoryItem(uid: String, track: Track) async throws {
        let record = try await getUserRecord(uid: uid, forceRefresh: true)
        var history = parseJSONArray(record.history) ?? []

        let entry = minifyHistoryEntry(track)
        history.insert(entry, at: 0)

        // Keep last 100
        if history.count > 100 {
            history = Array(history.prefix(100))
        }

        try await updateField(recordId: record.id, uid: uid, field: "history", value: history)
    }

    // MARK: - Private Helpers

    private func request(for url: URL) -> URLRequest {
        var req = URLRequest(url: url)
        req.setValue("Monochrome-iOS/1.0", forHTTPHeaderField: "User-Agent")
        return req
    }

    func updateUserField(recordId: String, uid: String, field: String, value: Any) async throws {
        try await updateField(recordId: recordId, uid: uid, field: field, value: value)
    }

    func updateUserFields(recordId: String, uid: String, fields: [String: Any]) async throws {
        guard let url = URL(string: "\(baseURL)/api/collections/\(collection)/records/\(recordId)?f_id=\(uid)") else {
            throw PBError.badURL
        }

        var body: [String: Any] = [:]
        for (field, value) in fields {
            if let dict = value as? [String: Any] {
                let data = try JSONSerialization.data(withJSONObject: dict)
                body[field] = String(data: data, encoding: .utf8) ?? "{}"
            } else if let array = value as? [Any] {
                let data = try JSONSerialization.data(withJSONObject: array)
                body[field] = String(data: data, encoding: .utf8) ?? "[]"
            } else {
                body[field] = "\(value)"
            }
        }

        var req = request(for: url)
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: req)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        if statusCode != 200 {
            let responseBody = String(data: data, encoding: .utf8) ?? "no body"
            print("[Sync] PATCH fields failed with status \(statusCode): \(responseBody.prefix(500))")
            throw PBError.serverError
        }
    }

    private func updateField(recordId: String, uid: String, field: String, value: Any) async throws {
        guard let url = URL(string: "\(baseURL)/api/collections/\(collection)/records/\(recordId)?f_id=\(uid)") else {
            throw PBError.badURL
        }

        // Stringify JSON value (same as web SDK)
        let stringValue: String
        if let dict = value as? [String: Any] {
            let data = try JSONSerialization.data(withJSONObject: dict)
            stringValue = String(data: data, encoding: .utf8) ?? "{}"
        } else if let array = value as? [Any] {
            let data = try JSONSerialization.data(withJSONObject: array)
            stringValue = String(data: data, encoding: .utf8) ?? "[]"
        } else {
            stringValue = "\(value)"
        }

        var req = request(for: url)
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [field: stringValue]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        print("[Sync] PATCH \(field) to record \(recordId)")

        let (data, response) = try await urlSession.data(for: req)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        let responseBody = String(data: data, encoding: .utf8) ?? "no body"

        if statusCode != 200 {
            print("[Sync] PATCH failed with status \(statusCode): \(responseBody.prefix(500))")
            throw PBError.serverError
        }

        // Check if the response contains the updated field
        if let responseDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let updatedField = responseDict[field]
            print("[Sync] PATCH \(field) succeeded. Response \(field) type: \(type(of: updatedField)), preview: \(String(describing: updatedField).prefix(200))")
        } else {
            print("[Sync] PATCH \(field) succeeded but couldn't parse response")
        }
    }

    private func parseJSON(_ value: String?) -> [String: Any]? {
        guard let str = value, let data = str.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func parseJSONArray(_ value: String?) -> [Any]? {
        guard let str = value, let data = str.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [Any]
    }

    private func minifyTrack(_ track: Track) -> [String: Any] {
        var data: [String: Any] = [
            "id": track.id,
            "title": track.title,
            "duration": track.duration,
            "addedAt": Int(Date().timeIntervalSince1970 * 1000)
        ]
        if let artist = track.artist {
            let artistDict: [String: Any] = ["id": artist.id, "name": artist.name]
            data["artist"] = artistDict
            data["artists"] = [artistDict]
        }
        if let album = track.album {
            var albumData: [String: Any] = ["id": album.id, "title": album.title]
            if let cover = album.cover { albumData["cover"] = cover }
            if let releaseDate = album.releaseDate { albumData["releaseDate"] = releaseDate }
            data["album"] = albumData
        }
        return data
    }

    private func minifyAlbum(_ album: Album) -> [String: Any] {
        var data: [String: Any] = [
            "id": album.id,
            "title": album.title,
            "addedAt": Int(Date().timeIntervalSince1970 * 1000)
        ]
        if let cover = album.cover { data["cover"] = cover }
        if let releaseDate = album.releaseDate { data["releaseDate"] = releaseDate }
        if let artist = album.artist {
            data["artist"] = ["id": artist.id, "name": artist.name]
        }
        if let type = album.type { data["type"] = type }
        if let numberOfTracks = album.numberOfTracks { data["numberOfTracks"] = numberOfTracks }
        return data
    }

    private func minifyArtist(_ artist: Artist) -> [String: Any] {
        var data: [String: Any] = [
            "id": artist.id,
            "name": artist.name,
            "addedAt": Int(Date().timeIntervalSince1970 * 1000)
        ]
        if let picture = artist.picture { data["picture"] = picture }
        return data
    }

    private func minifyPlaylist(_ playlist: Playlist) -> [String: Any] {
        var data: [String: Any] = [
            "uuid": playlist.uuid,
            "addedAt": Int(Date().timeIntervalSince1970 * 1000)
        ]
        if let title = playlist.title { data["title"] = title }
        if let image = playlist.image { data["image"] = image }
        if let count = playlist.numberOfTracks { data["numberOfTracks"] = count }
        if let user = playlist.user, let name = user.name { data["user"] = ["name": name] }
        return data
    }

    private func minifyMix(_ mix: Mix) -> [String: Any] {
        var data: [String: Any] = [
            "id": mix.id,
            "addedAt": Int(Date().timeIntervalSince1970 * 1000)
        ]
        if let title = mix.title { data["title"] = title }
        if let subTitle = mix.subTitle { data["subTitle"] = subTitle }
        if let mixType = mix.mixType { data["mixType"] = mixType }
        if let cover = mix.cover { data["cover"] = cover }
        return data
    }

    func minifyTrackForPlaylist(_ track: Track) -> [String: Any] {
        var data = minifyTrack(track)
        data["addedAt"] = Int(Date().timeIntervalSince1970 * 1000)
        return data
    }

    private func minifyHistoryEntry(_ track: Track) -> [String: Any] {
        var data = minifyTrack(track)
        data["timestamp"] = Int(Date().timeIntervalSince1970 * 1000)
        return data
    }
}

// MARK: - Array Decode Helpers

extension Array where Element == [String: Any] {
    func decodeTracks() -> [Track] {
        compactMap { raw in
            var dict = raw
            // Ensure required non-optional fields have defaults (web can store null)
            if dict["title"] == nil || dict["title"] is NSNull { dict["title"] = "Unknown" }
            if dict["duration"] == nil || dict["duration"] is NSNull { dict["duration"] = 0 }
            if dict["id"] == nil || dict["id"] is NSNull { return nil }
            guard let data = try? JSONSerialization.data(withJSONObject: dict),
                  let track = try? JSONDecoder().decode(Track.self, from: data) else { return nil }
            return track
        }
    }

    func decodeAlbums() -> [Album] {
        compactMap { raw in
            var dict = raw
            if dict["title"] == nil || dict["title"] is NSNull { dict["title"] = "Unknown" }
            if dict["id"] == nil || dict["id"] is NSNull { return nil }
            guard let data = try? JSONSerialization.data(withJSONObject: dict),
                  let album = try? JSONDecoder().decode(Album.self, from: data) else { return nil }
            return album
        }
    }

    func decodeArtists() -> [Artist] {
        compactMap { raw in
            var dict = raw
            if dict["name"] == nil || dict["name"] is NSNull { dict["name"] = "Unknown" }
            if dict["id"] == nil || dict["id"] is NSNull { return nil }
            guard let data = try? JSONSerialization.data(withJSONObject: dict),
                  let artist = try? JSONDecoder().decode(Artist.self, from: data) else { return nil }
            return artist
        }
    }

    func decodePlaylists() -> [Playlist] {
        compactMap { raw in
            var dict = raw
            if dict["uuid"] == nil || dict["uuid"] is NSNull { return nil }
            guard let data = try? JSONSerialization.data(withJSONObject: dict),
                  let playlist = try? JSONDecoder().decode(Playlist.self, from: data) else { return nil }
            return playlist
        }
    }

    func decodeMixes() -> [Mix] {
        compactMap { raw in
            var dict = raw
            if dict["id"] == nil || dict["id"] is NSNull { return nil }
            guard let data = try? JSONSerialization.data(withJSONObject: dict),
                  let mix = try? JSONDecoder().decode(Mix.self, from: data) else { return nil }
            return mix
        }
    }
}

// MARK: - Errors

enum PBError: LocalizedError {
    case badURL
    case serverError

    var errorDescription: String? {
        switch self {
        case .badURL: return "Invalid URL"
        case .serverError: return "Server error"
        }
    }
}

// MARK: - PocketBase Response Models

struct PBListResponse: Decodable {
    let items: [PBUserRecord]
}

struct PBUserRecord: Decodable {
    let id: String
    let firebase_id: String?
    let library: String?
    let history: String?
    let user_playlists: String?
    let user_folders: String?
    let username: String?
    let display_name: String?
    let avatar_url: String?
    let banner: String?
    let status: String?
    let about: String?
    let website: String?
    let privacy: String?
    let lastfm_username: String?
    let favorite_albums: String?

    // PocketBase JSON fields can come as either strings or parsed JSON objects.
    // This custom decoder handles both cases by converting objects to strings.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        firebase_id = try container.decodeIfPresent(String.self, forKey: .firebase_id)
        username = try container.decodeIfPresent(String.self, forKey: .username)
        display_name = try container.decodeIfPresent(String.self, forKey: .display_name)
        avatar_url = try container.decodeIfPresent(String.self, forKey: .avatar_url)
        banner = try container.decodeIfPresent(String.self, forKey: .banner)
        about = try container.decodeIfPresent(String.self, forKey: .about)
        website = try container.decodeIfPresent(String.self, forKey: .website)
        lastfm_username = try container.decodeIfPresent(String.self, forKey: .lastfm_username)

        library = Self.decodeJSONField(container: container, key: .library)
        history = Self.decodeJSONField(container: container, key: .history)
        user_playlists = Self.decodeJSONField(container: container, key: .user_playlists)
        user_folders = Self.decodeJSONField(container: container, key: .user_folders)
        status = Self.decodeJSONField(container: container, key: .status)
        privacy = Self.decodeJSONField(container: container, key: .privacy)
        favorite_albums = Self.decodeJSONField(container: container, key: .favorite_albums)
    }

    private static func decodeJSONField(container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> String? {
        // Try as string first
        if let str = try? container.decodeIfPresent(String.self, forKey: key) {
            return str
        }
        // Try as JSON object/array and convert to string
        if let jsonObj = try? container.decodeIfPresent(JSONValue.self, forKey: key),
           let data = try? JSONSerialization.data(withJSONObject: jsonObj.value),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return nil
    }

    enum CodingKeys: String, CodingKey {
        case id, firebase_id, library, history, user_playlists, user_folders
        case username, display_name, avatar_url, banner, status, about, website
        case privacy, lastfm_username, favorite_albums
    }
}

// Helper to decode arbitrary JSON values
private struct JSONValue: Decodable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let dict = try? container.decode([String: JSONValue].self) {
            value = dict.mapValues { $0.value }
        } else if let array = try? container.decode([JSONValue].self) {
            value = array.map { $0.value }
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else {
            value = NSNull()
        }
    }
}
