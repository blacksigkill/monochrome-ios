import Foundation
import Observation

@Observable
class MonochromeAPI {
    var baseURL = "https://api.monochrome.tf"
    private var urlSession = URLSession.shared

    private func request(for url: URL) -> URLRequest {
        var req = URLRequest(url: url)
        req.setValue("Monochrome-iOS/1.0", forHTTPHeaderField: "User-Agent")
        return req
    }

    // MARK: - Search

    func searchTracks(query: String) async throws -> [Track] {
        guard let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(baseURL)/search/?s=\(q)") else { throw URLError(.badURL) }

        let (data, response) = try await urlSession.data(for: request(for: url))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(SearchResponse.self, from: data).data?.items ?? []
    }

    func searchAll(query: String) async throws -> (artists: [Artist], albums: [Album], tracks: [Track]) {
        guard let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let tracksUrl = URL(string: "\(baseURL)/search/?s=\(q)"),
              let artistsUrl = URL(string: "\(baseURL)/search/?a=\(q)"),
              let albumsUrl = URL(string: "\(baseURL)/search/?al=\(q)") else { throw URLError(.badURL) }

        async let tracksTask = urlSession.data(for: request(for: tracksUrl))
        async let artistsTask = urlSession.data(for: request(for: artistsUrl))
        async let albumsTask = urlSession.data(for: request(for: albumsUrl))

        let (tData, tResp) = try await tracksTask
        var tracks: [Track] = []
        if (tResp as? HTTPURLResponse)?.statusCode == 200 {
            tracks = (try? JSONDecoder().decode(SearchResponse.self, from: tData).data?.items) ?? []
        }

        let (aData, aResp) = try await artistsTask
        var artists: [Artist] = []
        if (aResp as? HTTPURLResponse)?.statusCode == 200,
           let json = try? JSONSerialization.jsonObject(with: aData) as? [String: Any],
           let data = json["data"] as? [String: Any],
           let artistsDict = data["artists"] as? [String: Any],
           let items = artistsDict["items"] as? [[String: Any]],
           let arrData = try? JSONSerialization.data(withJSONObject: items),
           let decoded = try? JSONDecoder().decode([Artist].self, from: arrData) {
            // Filter out entries with no picture, then deduplicate by name (keep highest popularity)
            let filtered = decoded.filter { $0.picture != nil }
            var bestByName: [String: Artist] = [:]
            for a in filtered {
                let key = a.name.lowercased()
                if let existing = bestByName[key] {
                    if (a.popularity ?? 0) > (existing.popularity ?? 0) { bestByName[key] = a }
                } else {
                    bestByName[key] = a
                }
            }
            artists = filtered.filter { bestByName[$0.name.lowercased()]?.id == $0.id }
        }

        let (alData, alResp) = try await albumsTask
        var albums: [Album] = []
        if (alResp as? HTTPURLResponse)?.statusCode == 200,
           let json = try? JSONSerialization.jsonObject(with: alData) as? [String: Any],
           let data = json["data"] as? [String: Any],
           let albumsDict = data["albums"] as? [String: Any],
           let items = albumsDict["items"] as? [[String: Any]],
           let arrData = try? JSONSerialization.data(withJSONObject: items),
           let decoded = try? JSONDecoder().decode([Album].self, from: arrData) {
            // Filter out albums with no cover art
            albums = decoded.filter { $0.cover != nil }
        }

        return (artists, albums, tracks)
    }

    // MARK: - Artist (two parallel calls, same as web app)
    // Call 1: /artist/?id={id}  -> { artist: { id, name, picture, popularity, ... }, cover: {...} }
    // Call 2: /artist/?f={id}   -> { albums: { items: [...] }, tracks: [...] }

    func fetchArtist(id: Int) async throws -> ArtistDetail {
        guard let metaUrl = URL(string: "\(baseURL)/artist/?id=\(id)"),
              let contentUrl = URL(string: "\(baseURL)/artist/?f=\(id)") else {
            throw URLError(.badURL)
        }

        async let metaTask = urlSession.data(for: request(for: metaUrl))
        async let contentTask = urlSession.data(for: request(for: contentUrl))

        // Parse artist metadata
        let (metaData, metaResp) = try await metaTask
        guard (metaResp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }

        let metaJson = try JSONSerialization.jsonObject(with: metaData) as? [String: Any]
        let artistObj = metaJson?["artist"] as? [String: Any] ?? [:]

        let name = artistObj["name"] as? String ?? "Unknown"
        let picture = artistObj["picture"] as? String
        let popularity = (artistObj["popularity"] as? NSNumber)?.doubleValue

        // Parse content (tracks + albums)
        var topTracks: [Track] = []
        var albums: [Album] = []
        var eps: [Album] = []

        if let (contentData, contentResp) = try? await contentTask,
           (contentResp as? HTTPURLResponse)?.statusCode == 200 {

            let contentJson = try? JSONSerialization.jsonObject(with: contentData) as? [String: Any]

            // Tracks: top-level "tracks" array
            if let tracksArray = contentJson?["tracks"] as? [[String: Any]] {
                // Inject/fix artist info into each track
                var artistDict: [String: Any] = ["id": id, "name": name]
                if let pic = picture { artistDict["picture"] = pic }
                let enriched = tracksArray.map { track -> [String: Any] in
                    var t = track
                    // Always ensure a proper "artist" dict is set with correct picture
                    if (t["artist"] as? [String: Any]) == nil {
                        t["artist"] = artistDict
                    }
                    return t
                }
                do {
                    let tracksData = try JSONSerialization.data(withJSONObject: enriched)
                    let decoded = try JSONDecoder().decode([Track].self, from: tracksData)
                    topTracks = decoded
                        .sorted { ($0.popularity ?? 0) > ($1.popularity ?? 0) }
                        .prefix(15)
                        .map { $0 }
                } catch {
                    print("Error decoding topTracks: \(error)")
                }
            }

            // Albums: "albums" -> "items"
            if let albumsObj = contentJson?["albums"] as? [String: Any],
               let albumItems = albumsObj["items"] as? [[String: Any]] {
                do {
                    let albumsData = try JSONSerialization.data(withJSONObject: albumItems)
                    let decoded = try JSONDecoder().decode([Album].self, from: albumsData)
                    let sorted = decoded.sorted { ($0.releaseDate ?? "") > ($1.releaseDate ?? "") }
                    for a in sorted {
                        let t = a.type?.uppercased() ?? ""
                        if t == "EP" || t == "SINGLE" {
                            eps.append(a)
                        } else {
                            albums.append(a)
                        }
                    }
                } catch {
                    print("Error decoding albums: \(error)")
                }
            }
        }

        if topTracks.isEmpty && albums.isEmpty && eps.isEmpty {
            let token = "txNoH4kkV41MfH25"
            
            // Fallback: Top Tracks
            if let tUrl = URL(string: "https://api.tidal.com/v1/artists/\(id)/toptracks?countryCode=FR") {
                var req = URLRequest(url: tUrl)
                req.setValue(token, forHTTPHeaderField: "X-Tidal-Token")
                
                if let (data, resp) = try? await urlSession.data(for: req),
                   (resp as? HTTPURLResponse)?.statusCode == 200,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let items = json["items"] as? [[String: Any]] {
                    
                    var artistDict: [String: Any] = ["id": id, "name": name]
                    if let pic = picture { artistDict["picture"] = pic }
                    
                    let enriched = items.map { track -> [String: Any] in
                        var t = track
                        if (t["artist"] as? [String: Any]) == nil { t["artist"] = artistDict }
                        return t
                    }
                    if let tracksData = try? JSONSerialization.data(withJSONObject: enriched),
                       let decoded = try? JSONDecoder().decode([Track].self, from: tracksData) {
                        topTracks = decoded.sorted { ($0.popularity ?? 0) > ($1.popularity ?? 0) }.prefix(15).map { $0 }
                    }
                }
            }
            
            // Fallback: Albums
            if let aUrl = URL(string: "https://api.tidal.com/v1/artists/\(id)/albums?countryCode=FR") {
                var req = URLRequest(url: aUrl)
                req.setValue(token, forHTTPHeaderField: "X-Tidal-Token")
                
                if let (data, resp) = try? await urlSession.data(for: req),
                   (resp as? HTTPURLResponse)?.statusCode == 200,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let items = json["items"] as? [[String: Any]] {
                    
                    if let albumsData = try? JSONSerialization.data(withJSONObject: items),
                       let decoded = try? JSONDecoder().decode([Album].self, from: albumsData) {
                        let sorted = decoded.sorted { ($0.releaseDate ?? "") > ($1.releaseDate ?? "") }
                        for a in sorted {
                            let t = a.type?.uppercased() ?? ""
                            if t == "EP" || t == "SINGLE" { eps.append(a) }
                            else { albums.append(a) }
                        }
                    }
                }
            }
        }

        return ArtistDetail(
            id: id, name: name, picture: picture, popularity: popularity,
            topTracks: topTracks, albums: albums, eps: eps
        )
    }

    // MARK: - Artist Biography (Tidal API with X-Tidal-Token)

    func fetchArtistBio(id: Int) async -> String? {
        guard let url = URL(string: "https://api.tidal.com/v1/artists/\(id)/bio?locale=en_US&countryCode=GB") else { return nil }

        var req = URLRequest(url: url)
        req.setValue("Monochrome-iOS/1.0", forHTTPHeaderField: "User-Agent")
        req.setValue("txNoH4kkV41MfH25", forHTTPHeaderField: "X-Tidal-Token")

        guard let (data, response) = try? await urlSession.data(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }

        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return json?["text"] as? String
    }

    // MARK: - Similar Artists (response: { artists: [...] })

    func fetchSimilarArtists(id: Int) async -> [Artist] {
        guard let url = URL(string: "\(baseURL)/artist/similar/?id=\(id)") else { return [] }

        guard let (data, response) = try? await urlSession.data(for: request(for: url)),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }

        let artistsRaw = json["artists"] as? [[String: Any]]
            ?? json["items"] as? [[String: Any]]
            ?? []

        guard !artistsRaw.isEmpty,
              let arrData = try? JSONSerialization.data(withJSONObject: artistsRaw),
              let decoded = try? JSONDecoder().decode([Artist].self, from: arrData) else { return [] }

        return decoded
    }

    // MARK: - Album Detail

    func fetchAlbum(id: Int) async throws -> AlbumDetail {
        guard let url = URL(string: "\(baseURL)/album/?id=\(id)") else { throw URLError(.badURL) }

        let (data, response) = try await urlSession.data(for: request(for: url))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let root = json?["data"] as? [String: Any] ?? json ?? [:]

        // Parse album metadata
        var album: Album?
        if root["numberOfTracks"] != nil || root["title"] != nil,
           let albumData = try? JSONSerialization.data(withJSONObject: root),
           let decoded = try? JSONDecoder().decode(Album.self, from: albumData) {
            album = decoded
        }

        // Parse tracks from "items"
        var tracks: [Track] = []
        if let items = root["items"] as? [[String: Any]] {
            for item in items {
                let trackObj = item["item"] as? [String: Any] ?? item
                if let trackData = try? JSONSerialization.data(withJSONObject: trackObj),
                   let track = try? JSONDecoder().decode(Track.self, from: trackData) {
                    tracks.append(track)
                }
            }

            // If no album metadata, extract from first track
            if album == nil, let firstTrack = tracks.first?.album {
                album = firstTrack
            }
        }

        guard let finalAlbum = album else { throw URLError(.cannotParseResponse) }
        return AlbumDetail(album: finalAlbum, tracks: tracks)
    }

    // MARK: - Stream URL

    struct TrackResponse: Codable {
        let version: String?
        let data: TrackData?
    }

    struct TrackData: Codable {
        let trackId: Int
        let manifest: String?
    }

    struct ManifestData: Codable {
        let urls: [String]
    }

    func fetchTrack(id: Int) async throws -> Track {
        guard let url = URL(string: "https://api.tidal.com/v1/tracks/\(id)?countryCode=GB") else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.setValue("Monochrome-iOS/1.0", forHTTPHeaderField: "User-Agent")
        req.setValue("txNoH4kkV41MfH25", forHTTPHeaderField: "X-Tidal-Token")

        let (data, response) = try await urlSession.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }

        return try JSONDecoder().decode(Track.self, from: data)
    }

    func fetchStreamUrl(trackId: Int) async throws -> String? {
        guard let url = URL(string: "\(baseURL)/track/?id=\(trackId)&quality=HIGH") else { throw URLError(.badURL) }

        let (data, response) = try await urlSession.data(for: request(for: url))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }

        let apiResponse = try JSONDecoder().decode(TrackResponse.self, from: data)
        guard let manifestBase64 = apiResponse.data?.manifest,
              let manifestData = Data(base64Encoded: manifestBase64),
              let manifest = try? JSONDecoder().decode(ManifestData.self, from: manifestData) else {
            return nil
        }
        return manifest.urls.first
    }

    // MARK: - Images

    func getImageUrl(id: String?, size: Int = 320) -> URL? {
        guard let id = id, !id.isEmpty else { return nil }
        if id.hasPrefix("http") { return URL(string: id) }
        let formattedId = id.replacingOccurrences(of: "-", with: "/")
        return URL(string: "https://resources.tidal.com/images/\(formattedId)/\(size)x\(size).jpg")
    }
}

// MARK: - Artist Detail Model

struct AlbumDetail {
    let album: Album
    let tracks: [Track]
}

struct ArtistDetail {
    let id: Int
    let name: String
    let picture: String?
    let popularity: Double?
    let topTracks: [Track]
    let albums: [Album]
    let eps: [Album]
}
