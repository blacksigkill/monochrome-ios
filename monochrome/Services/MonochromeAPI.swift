import Foundation

class MonochromeAPI {
    private var urlSession = URLSession.shared

    private func request(for url: URL) -> URLRequest {
        var req = URLRequest(url: url)
        req.setValue("Monochrome-iOS/1.0", forHTTPHeaderField: "User-Agent")
        return req
    }

    /// Fetch data from the best available API instance, rotating on failure.
    private func fetchData(path: String) async throws -> Data {
        let instances = InstanceManager.shared.getInstances(type: "api")
        guard !instances.isEmpty else {
            guard let url = URL(string: "https://api.monochrome.tf\(path)") else { throw URLError(.badURL) }
            let (data, resp) = try await urlSession.data(for: request(for: url))
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            return data
        }

        var lastError: Error = URLError(.badServerResponse)
        let start = Int.random(in: 0..<instances.count)

        for i in 0..<instances.count {
            let base = instances[(start + i) % instances.count].url
            guard let url = URL(string: "\(base)\(path)") else { continue }
            do {
                let (data, resp) = try await urlSession.data(for: request(for: url))
                if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                    return data
                }
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    // MARK: - Search

    func searchTracks(query: String) async throws -> [Track] {
        guard let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { throw URLError(.badURL) }
        let data = try await fetchData(path: "/search/?s=\(q)")
        return try JSONDecoder().decode(SearchResponse.self, from: data).data?.items ?? []
    }

    func searchAll(query: String) async throws -> (artists: [Artist], albums: [Album], tracks: [Track], playlists: [Playlist]) {
        guard let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { throw URLError(.badURL) }

        async let tracksTask = fetchData(path: "/search/?s=\(q)")
        async let artistsTask = fetchData(path: "/search/?a=\(q)")
        async let albumsTask = fetchData(path: "/search/?al=\(q)")
        async let playlistsTask = fetchData(path: "/search/?p=\(q)")

        var tracks: [Track] = []
        if let tData = try? await tracksTask {
            tracks = (try? JSONDecoder().decode(SearchResponse.self, from: tData).data?.items) ?? []
        }

        var artists: [Artist] = []
        if let aData = try? await artistsTask,
           let json = try? JSONSerialization.jsonObject(with: aData) as? [String: Any],
           let data = json["data"] as? [String: Any],
           let artistsDict = data["artists"] as? [String: Any],
           let items = artistsDict["items"] as? [[String: Any]],
           let arrData = try? JSONSerialization.data(withJSONObject: items),
           let decoded = try? JSONDecoder().decode([Artist].self, from: arrData) {
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

        var albums: [Album] = []
        if let alData = try? await albumsTask,
           let json = try? JSONSerialization.jsonObject(with: alData) as? [String: Any],
           let data = json["data"] as? [String: Any],
           let albumsDict = data["albums"] as? [String: Any],
           let items = albumsDict["items"] as? [[String: Any]],
           let arrData = try? JSONSerialization.data(withJSONObject: items),
           let decoded = try? JSONDecoder().decode([Album].self, from: arrData) {
            albums = decoded.filter { $0.cover != nil }
        }

        var playlists: [Playlist] = []
        if let pData = try? await playlistsTask {
            playlists = Self.parsePlaylistSearchResults(data: pData)
        }

        return (artists, albums, tracks, playlists)
    }

    func searchAlbums(query: String) async throws -> [Album] {
        guard let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { throw URLError(.badURL) }
        let data = try await fetchData(path: "/search/?al=\(q)")

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = json["data"] as? [String: Any],
              let albumsDict = dataObj["albums"] as? [String: Any],
              let items = albumsDict["items"] as? [[String: Any]],
              let arrData = try? JSONSerialization.data(withJSONObject: items),
              let decoded = try? JSONDecoder().decode([Album].self, from: arrData) else { return [] }
        return decoded.filter { $0.cover != nil }
    }

    private static func parsePlaylistSearchResults(data: Data) -> [Playlist] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }

        let items: [[String: Any]]
        if let directItems = json["items"] as? [[String: Any]] {
            items = directItems
        } else if let dataDict = json["data"] as? [String: Any],
                  let playlistsDict = dataDict["playlists"] as? [String: Any],
                  let playlistItems = playlistsDict["items"] as? [[String: Any]] {
            items = playlistItems
        } else {
            return []
        }

        return items.compactMap { item -> Playlist? in
            guard let uuid = item["uuid"] as? String else { return nil }
            let title = item["title"] as? String
            let image = item["squareImage"] as? String ?? item["image"] as? String
            let numberOfTracks = item["numberOfTracks"] as? Int
            let userName = (item["creator"] as? [String: Any])?["name"] as? String
            return Playlist(
                uuid: uuid,
                title: title,
                image: image,
                numberOfTracks: numberOfTracks,
                user: userName != nil ? PlaylistUser(name: userName) : nil
            )
        }
    }

    private static func findItems(in dict: [String: Any]) -> [[String: Any]]? {
        if let items = dict["items"] as? [[String: Any]] { return items }
        for value in dict.values {
            if let nested = value as? [String: Any],
               let items = findItems(in: nested) {
                return items
            }
        }
        return nil
    }

    // MARK: - Artist (two parallel calls, same as web app)

    func fetchArtist(id: Int) async throws -> ArtistDetail {
        let cacheKey = "artist_\(id)"

        async let metaTask = fetchData(path: "/artist/?id=\(id)")
        async let contentTask: Data? = try? fetchData(path: "/artist/?f=\(id)")

        // Parse artist metadata
        let metaData = try await metaTask
        let metaJson = try JSONSerialization.jsonObject(with: metaData) as? [String: Any]
        let artistObj = metaJson?["artist"] as? [String: Any] ?? [:]

        let name = artistObj["name"] as? String ?? "Unknown"
        let picture = artistObj["picture"] as? String
        let popularity = (artistObj["popularity"] as? NSNumber)?.doubleValue

        // Parse content (tracks + albums)
        var topTracks: [Track] = []
        var albums: [Album] = []
        var eps: [Album] = []

        if let contentData = await contentTask {
            let contentJson = try? JSONSerialization.jsonObject(with: contentData) as? [String: Any]

            if let tracksArray = contentJson?["tracks"] as? [[String: Any]] {
                var artistDict: [String: Any] = ["id": id, "name": name]
                if let pic = picture { artistDict["picture"] = pic }
                let enriched = tracksArray.map { track -> [String: Any] in
                    var t = track
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

            // Fallback 1: Top Tracks (Direct Tidal)
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

            // Fallback 2: Albums (Direct Tidal)
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

            // Fallback 3: Search (Monochrome search if still empty)
            if topTracks.isEmpty && albums.isEmpty && eps.isEmpty {
                let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                if let searchData = try? await fetchData(path: "/search/?s=\(encodedName)"),
                   let json = try? JSONSerialization.jsonObject(with: searchData) as? [String: Any],
                   let items = (json["data"] as? [String: Any])?["items"] as? [[String: Any]] {

                    let filtered = items.filter { item in
                        guard let tracksArtist = (item["artist"] as? [String: Any])?["name"] as? String else { return false }
                        return tracksArtist.localizedCaseInsensitiveContains(name)
                    }

                    if let tracksData = try? JSONSerialization.data(withJSONObject: filtered),
                       let decoded = try? JSONDecoder().decode([Track].self, from: tracksData) {
                        topTracks = Array(decoded.prefix(15))
                    }
                }
            }
        }

        let result = ArtistDetail(
            id: id, name: name, picture: picture, popularity: popularity,
            topTracks: topTracks, albums: albums, eps: eps
        )
        CacheService.shared.set(forKey: cacheKey, value: result)
        return result
    }

    // MARK: - Artist Biography (Tidal API with X-Tidal-Token)

    func fetchArtistBio(id: Int) async -> String? {
        let cacheKey = "bio_\(id)"

        guard let url = URL(string: "https://api.tidal.com/v1/artists/\(id)/bio?locale=en_US&countryCode=GB") else { return nil }

        var req = URLRequest(url: url)
        req.setValue("Monochrome-iOS/1.0", forHTTPHeaderField: "User-Agent")
        req.setValue("txNoH4kkV41MfH25", forHTTPHeaderField: "X-Tidal-Token")

        guard let (data, response) = try? await urlSession.data(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }

        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let bio = json?["text"] as? String
        if let bio { CacheService.shared.set(forKey: cacheKey, value: bio) }
        return bio
    }

    // MARK: - Similar Artists

    func fetchSimilarArtists(id: Int) async -> [Artist] {
        let cacheKey = "similar_\(id)"

        guard let data = try? await fetchData(path: "/artist/similar/?id=\(id)") else { return [] }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }

        let artistsRaw = json["artists"] as? [[String: Any]]
            ?? json["items"] as? [[String: Any]]
            ?? []

        guard !artistsRaw.isEmpty,
              let arrData = try? JSONSerialization.data(withJSONObject: artistsRaw),
              let decoded = try? JSONDecoder().decode([Artist].self, from: arrData) else { return [] }

        CacheService.shared.set(forKey: cacheKey, value: decoded)
        return decoded
    }

    // MARK: - Album Detail

    func fetchAlbum(id: Int) async throws -> AlbumDetail {
        let cacheKey = "album_\(id)"

        let data = try await fetchData(path: "/album/?id=\(id)")
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let root = json?["data"] as? [String: Any] ?? json ?? [:]

        var album: Album?
        if root["numberOfTracks"] != nil || root["title"] != nil,
           let albumData = try? JSONSerialization.data(withJSONObject: root),
           let decoded = try? JSONDecoder().decode(Album.self, from: albumData) {
            album = decoded
        }

        var tracks: [Track] = []
        if let items = root["items"] as? [[String: Any]] {
            for item in items {
                let trackObj = item["item"] as? [String: Any] ?? item
                if let trackData = try? JSONSerialization.data(withJSONObject: trackObj),
                   let track = try? JSONDecoder().decode(Track.self, from: trackData) {
                    tracks.append(track)
                }
            }

            if album == nil, let firstTrack = tracks.first?.album {
                album = firstTrack
            }
        }

        // Paginate if the album has more tracks than returned
        let totalTracks = (root["numberOfTracks"] as? Int) ?? tracks.count
        if tracks.count < totalTracks {
            var offset = tracks.count
            while offset < totalTracks {
                guard let pageData = try? await fetchData(path: "/album/?id=\(id)&offset=\(offset)") else { break }
                guard let pageJson = try? JSONSerialization.jsonObject(with: pageData) as? [String: Any],
                      let pageRoot = pageJson["data"] as? [String: Any],
                      let pageItems = pageRoot["items"] as? [[String: Any]], !pageItems.isEmpty else { break }

                for item in pageItems {
                    let trackObj = item["item"] as? [String: Any] ?? item
                    if let trackData = try? JSONSerialization.data(withJSONObject: trackObj),
                       let track = try? JSONDecoder().decode(Track.self, from: trackData) {
                        tracks.append(track)
                    }
                }
                offset = tracks.count
            }
        }

        guard let finalAlbum = album else { throw URLError(.cannotParseResponse) }
        let result = AlbumDetail(album: finalAlbum, tracks: tracks)
        CacheService.shared.set(forKey: cacheKey, value: result)
        return result
    }

    // MARK: - Playlist

    func fetchPlaylist(uuid: String) async throws -> PlaylistDetail {
        let cacheKey = "playlist_\(uuid)"

        let data = try await fetchData(path: "/playlist/?id=\(uuid)")
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let root = json?["data"] as? [String: Any] ?? json ?? [:]

        let title = root["title"] as? String ?? "Playlist"
        let image = root["squareImage"] as? String ?? root["image"] as? String
        let description = root["description"] as? String
        let numberOfTracks = root["numberOfTracks"] as? Int

        var tracks: [Track] = []
        if let items = root["items"] as? [[String: Any]] {
            for item in items {
                let trackObj = item["item"] as? [String: Any] ?? item
                if let trackData = try? JSONSerialization.data(withJSONObject: trackObj),
                   let track = try? JSONDecoder().decode(Track.self, from: trackData) {
                    tracks.append(track)
                }
            }
        }

        let result = PlaylistDetail(
            uuid: uuid, title: title, image: image, description: description,
            numberOfTracks: numberOfTracks ?? tracks.count, tracks: tracks
        )
        CacheService.shared.set(forKey: cacheKey, value: result)
        return result
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
        let cacheKey = "track_\(id)"
        if let cached: Track = CacheService.shared.get(forKey: cacheKey) {
            return cached
        }

        guard let url = URL(string: "https://api.tidal.com/v1/tracks/\(id)?countryCode=GB") else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.setValue("Monochrome-iOS/1.0", forHTTPHeaderField: "User-Agent")
        req.setValue("txNoH4kkV41MfH25", forHTTPHeaderField: "X-Tidal-Token")

        let (data, response) = try await urlSession.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }

        let track = try JSONDecoder().decode(Track.self, from: data)
        CacheService.shared.set(forKey: cacheKey, value: track)
        return track
    }

    func fetchStreamUrl(trackId: Int, quality: AudioQuality = .high) async throws -> String? {
        let data = try await fetchData(path: "/track/?id=\(trackId)&quality=\(quality.rawValue)")

        let apiResponse = try JSONDecoder().decode(TrackResponse.self, from: data)
        guard let manifestBase64 = apiResponse.data?.manifest,
              let manifestData = Data(base64Encoded: manifestBase64),
              let manifest = try? JSONDecoder().decode(ManifestData.self, from: manifestData) else {
            return nil
        }
        return manifest.urls.first
    }

    func fetchStreamUrlWithFallback(trackId: Int, preferredQuality: AudioQuality) async -> String? {
        let allDescending: [AudioQuality] = [.hiResLossless, .lossless, .high, .medium, .low]
        let preferredIndex = allDescending.firstIndex(of: preferredQuality) ?? 0
        let lowerQualities = allDescending.dropFirst(preferredIndex + 1)
        let fallbackOrder = [preferredQuality] + lowerQualities

        var triedQualities: [String] = []

        for quality in fallbackOrder {
            do {
                if let urlString = try await fetchStreamUrl(trackId: trackId, quality: quality) {
                    if preferredQuality != quality {
                        print("[Audio] Quality \(preferredQuality.rawValue) not available, fell back to \(quality.rawValue)")
                    }
                    return urlString
                }
            } catch {
                triedQualities.append(quality.rawValue)
                print("[Audio] Quality \(quality.rawValue) failed: \(error.localizedDescription)")
            }
        }

        print("[Audio] All qualities failed: \(triedQualities)")
        return nil
    }

    // MARK: - Images

    func getImageUrl(id: String?, size: Int = 320) -> URL? {
        guard let id = id, !id.isEmpty else { return nil }
        if id.hasPrefix("http") { return URL(string: id) }
        let formattedId = id.replacingOccurrences(of: "-", with: "/")
        return URL(string: "https://resources.tidal.com/images/\(formattedId)/\(size)x\(size).jpg")
    }
}

// MARK: - Detail Models

struct AlbumDetail: Codable {
    let album: Album
    let tracks: [Track]
}

struct ArtistDetail: Codable {
    let id: Int
    let name: String
    let picture: String?
    let popularity: Double?
    let topTracks: [Track]
    let albums: [Album]
    let eps: [Album]
}

struct PlaylistDetail: Codable {
    let uuid: String
    let title: String
    let image: String?
    let description: String?
    let numberOfTracks: Int
    let tracks: [Track]
}
