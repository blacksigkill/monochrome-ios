import Foundation

class PocketBaseService {
    static let shared = PocketBaseService()

    private let baseURL = "https://data.samidy.xyz"
    private let collection = "DB_users"
    private var cachedRecordId: String?
    private let urlSession = URLSession.shared

    // MARK: - Get or Create User Record

    func getUserRecord(uid: String) async throws -> PBUserRecord {
        let filterQuery = "firebase_id=\"\(uid)\""
        guard let encoded = filterQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(baseURL)/api/collections/\(collection)/records?filter=\(encoded)&f_id=\(uid)&sort=-username") else {
            throw PBError.badURL
        }

        let (data, response) = try await urlSession.data(for: request(for: url))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw PBError.serverError }

        let listResponse = try JSONDecoder().decode(PBListResponse.self, from: data)

        if let existing = listResponse.items.first {
            cachedRecordId = existing.id
            return existing
        }

        return try await createUserRecord(uid: uid)
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
        cachedRecordId = record.id
        return record
    }

    // MARK: - Sync Library

    func fetchLibrary(uid: String) async throws -> CloudLibrary {
        let record = try await getUserRecord(uid: uid)

        let tracks = parseLibraryItems(record.library, type: "tracks")
        let albums = parseLibraryItems(record.library, type: "albums")

        return CloudLibrary(tracks: tracks, albums: albums)
    }

    func syncLibrary(uid: String, tracks: [Track], albums: [Album]) async throws {
        let record = try await getUserRecord(uid: uid)

        var library: [String: Any] = parseJSON(record.library) ?? [:]

        var tracksDict: [String: Any] = [:]
        for track in tracks {
            tracksDict[String(track.id)] = minifyTrack(track)
        }
        library["tracks"] = tracksDict

        var albumsDict: [String: Any] = [:]
        for album in albums {
            albumsDict[String(album.id)] = minifyAlbum(album)
        }
        library["albums"] = albumsDict

        try await updateField(recordId: record.id, uid: uid, field: "library", value: library)
    }

    // MARK: - Private Helpers

    private func request(for url: URL) -> URLRequest {
        var req = URLRequest(url: url)
        req.setValue("Monochrome-iOS/1.0", forHTTPHeaderField: "User-Agent")
        return req
    }

    private func updateField(recordId: String, uid: String, field: String, value: Any) async throws {
        guard let url = URL(string: "\(baseURL)/api/collections/\(collection)/records/\(recordId)?f_id=\(uid)") else {
            throw PBError.badURL
        }

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
        let body = [field: stringValue]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await urlSession.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw PBError.serverError }
    }

    private func parseJSON(_ value: String?) -> [String: Any]? {
        guard let str = value, let data = str.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func parseLibraryItems(_ libraryJSON: String?, type: String) -> [[String: Any]] {
        guard let library = parseJSON(libraryJSON),
              let items = library[type] as? [String: Any] else { return [] }
        return Array(items.values.compactMap { $0 as? [String: Any] })
    }

    private func minifyTrack(_ track: Track) -> [String: Any] {
        var data: [String: Any] = [
            "id": track.id,
            "title": track.title,
            "duration": track.duration,
            "addedAt": Int(Date().timeIntervalSince1970 * 1000)
        ]
        if let artist = track.artist {
            data["artist"] = ["id": artist.id, "name": artist.name]
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
}

// MARK: - Models

struct CloudLibrary {
    let tracks: [[String: Any]]
    let albums: [[String: Any]]

    func decodeTracks() -> [Track] {
        tracks.compactMap { dict in
            guard let data = try? JSONSerialization.data(withJSONObject: dict),
                  let track = try? JSONDecoder().decode(Track.self, from: data) else { return nil }
            return track
        }
    }

    func decodeAlbums() -> [Album] {
        albums.compactMap { dict in
            guard let data = try? JSONSerialization.data(withJSONObject: dict),
                  let album = try? JSONDecoder().decode(Album.self, from: data) else { return nil }
            return album
        }
    }
}

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
}
