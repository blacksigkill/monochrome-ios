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
