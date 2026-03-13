import Foundation

struct Track: Identifiable, Codable, Hashable {
    let id: Int
    let title: String
    let duration: Int
    let artist: Artist?
    let album: Album?
    let streamStartDate: String?
    let popularity: Double?

    var releaseYear: String? {
        guard let dateStr = streamStartDate, dateStr.count >= 4 else { return nil }
        return String(dateStr.prefix(4))
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Track, rhs: Track) -> Bool { lhs.id == rhs.id }
}

struct Artist: Identifiable, Codable, Hashable {
    let id: Int
    let name: String
    let picture: String?
    let popularity: Double?

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Artist, rhs: Artist) -> Bool { lhs.id == rhs.id }
}

struct Album: Identifiable, Codable, Hashable {
    let id: Int
    let title: String
    let cover: String?
    let numberOfTracks: Int?
    let releaseDate: String?
    let artist: Artist?
    let type: String?

    var releaseYear: String? {
        guard let d = releaseDate, d.count >= 4 else { return nil }
        return String(d.prefix(4))
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Album, rhs: Album) -> Bool { lhs.id == rhs.id }
}

struct Playlist: Identifiable, Codable, Hashable {
    let uuid: String
    let title: String?
    let image: String?
    let numberOfTracks: Int?
    let user: PlaylistUser?

    var id: String { uuid }

    func hash(into hasher: inout Hasher) { hasher.combine(uuid) }
    static func == (lhs: Playlist, rhs: Playlist) -> Bool { lhs.uuid == rhs.uuid }
}

struct PlaylistUser: Codable, Hashable {
    let name: String?
}

struct Mix: Identifiable, Codable, Hashable {
    let id: String
    let title: String?
    let subTitle: String?
    let mixType: String?
    let cover: String?

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Mix, rhs: Mix) -> Bool { lhs.id == rhs.id }
}

// MARK: - User Playlists & Folders

struct UserPlaylist: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var tracks: [Track]
    var cover: String
    var description: String
    var createdAt: Double
    var updatedAt: Double
    var numberOfTracks: Int
    var images: [String]
    var isPublic: Bool

    init(id: String = UUID().uuidString, name: String, tracks: [Track] = [], cover: String = "", description: String = "", createdAt: Double = Date().timeIntervalSince1970 * 1000, updatedAt: Double = Date().timeIntervalSince1970 * 1000, numberOfTracks: Int = 0, images: [String] = [], isPublic: Bool = false) {
        self.id = id
        self.name = name
        self.tracks = tracks
        self.cover = cover
        self.description = description
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.numberOfTracks = numberOfTracks
        self.images = images
        self.isPublic = isPublic
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: UserPlaylist, rhs: UserPlaylist) -> Bool { lhs.id == rhs.id }
}

struct UserFolder: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var cover: String
    var playlists: [String] // playlist IDs
    var createdAt: Double
    var updatedAt: Double

    init(id: String = UUID().uuidString, name: String, cover: String = "", playlists: [String] = [], createdAt: Double = Date().timeIntervalSince1970 * 1000, updatedAt: Double = Date().timeIntervalSince1970 * 1000) {
        self.id = id
        self.name = name
        self.cover = cover
        self.playlists = playlists
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: UserFolder, rhs: UserFolder) -> Bool { lhs.id == rhs.id }
}

// MARK: - User Profile

struct UserProfile: Codable {
    var username: String
    var displayName: String
    var avatarUrl: String
    var banner: String
    var status: String
    var about: String
    var website: String
    var lastfmUsername: String
    var privacy: ProfilePrivacy
    var historyCount: Int

    init(username: String = "", displayName: String = "", avatarUrl: String = "", banner: String = "", status: String = "", about: String = "", website: String = "", lastfmUsername: String = "", privacy: ProfilePrivacy = ProfilePrivacy(), historyCount: Int = 0) {
        self.username = username
        self.displayName = displayName
        self.avatarUrl = avatarUrl
        self.banner = banner
        self.status = status
        self.about = about
        self.website = website
        self.lastfmUsername = lastfmUsername
        self.privacy = privacy
        self.historyCount = historyCount
    }
}

struct ProfilePrivacy: Codable {
    var playlists: String
    var lastfm: String

    init(playlists: String = "public", lastfm: String = "public") {
        self.playlists = playlists
        self.lastfm = lastfm
    }
}

// MARK: - API Responses

struct SearchResponse: Codable {
    let data: SearchData?
}

struct SearchData: Codable {
    let items: [Track]
}

struct ArtistResponse: Codable {
    let data: ArtistData?
}

struct ArtistData: Codable {
    let id: Int?
    let name: String?
    let picture: String?
    let popularity: Double?
    let topTracks: [Track]?
    let albums: [Album]?

    enum CodingKeys: String, CodingKey {
        case id, name, picture, popularity
        case topTracks = "top_tracks"
        case albums
    }
}

struct ArtistAlbumsResponse: Codable {
    let data: ArtistAlbumsData?
}

struct ArtistAlbumsData: Codable {
    let albums: [Album]?
}
