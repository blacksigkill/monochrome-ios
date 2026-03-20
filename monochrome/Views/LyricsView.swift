import SwiftUI

struct LyricLine: Identifiable {
    let id: Int
    let time: TimeInterval
    let text: String
}

struct LyricsView: View {
    @EnvironmentObject private var audioPlayer: AudioPlayerService

    @State private var syncedLines: [LyricLine] = []
    @State private var plainLyrics: String?
    @State private var isLoading = false
    @State private var fetchedTrackId: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            Text("Lyrics")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)

            // Content
            if isLoading {
                lyricsPlaceholder
            } else if !syncedLines.isEmpty {
                syncedLyricsContent
            } else if let plain = plainLyrics {
                plainLyricsContent(plain)
            } else if fetchedTrackId != nil {
                Text("No lyrics available for this track.")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.3))
                    .padding(.vertical, 20)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: audioPlayer.currentTrack?.id) {
            await fetchLyrics()
        }
    }

    // MARK: - Synced Lyrics

    private var currentLineIndex: Int {
        guard !syncedLines.isEmpty else { return -1 }
        let time = audioPlayer.currentTime
        var idx = -1
        for (i, line) in syncedLines.enumerated() {
            if time >= line.time - 0.1 {
                idx = i
            } else {
                break
            }
        }
        return idx
    }

    private var syncedLyricsContent: some View {
        let current = currentLineIndex
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(syncedLines) { line in
                let isCurrent = line.id == current
                let isPast = line.id < current
                Text(line.text)
                    .font(.system(size: isCurrent ? 24 : 22, weight: isCurrent ? .bold : .medium))
                    .foregroundColor(
                        isCurrent ? .white :
                        isPast ? .white.opacity(0.3) :
                        .white.opacity(0.2)
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        audioPlayer.seek(to: line.time)
                    }
                    .animation(.easeOut(duration: 0.3), value: current)
            }
        }
    }

    // MARK: - Plain Lyrics

    private func plainLyricsContent(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 20, weight: .medium))
            .foregroundColor(.white.opacity(0.5))
            .lineSpacing(6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Placeholder

    private var lyricsPlaceholder: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(0..<6, id: \.self) { i in
                let widths: [CGFloat] = [240, 200, 260, 180, 220, 160]
                SkeletonPill(width: widths[i], height: 20)
            }
        }
        .shimmer()
        .padding(.vertical, 8)
    }

    // MARK: - Fetch

    private func fetchLyrics() async {
        guard let track = audioPlayer.currentTrack else {
            syncedLines = []
            plainLyrics = nil
            fetchedTrackId = nil
            return
        }

        // Skip if already fetched for this track
        if fetchedTrackId == track.id { return }

        syncedLines = []
        plainLyrics = nil
        isLoading = true

        // Check cache
        let cacheKey = "lyrics_\(track.id)"
        if let cached: LRCLibResponse = CacheService.shared.get(forKey: cacheKey) {
            applyResponse(cached)
            isLoading = false
            fetchedTrackId = track.id
            return
        }

        // Fetch from LRCLIB
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        var items = [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: track.artist?.name ?? ""),
        ]
        if let album = track.album?.title {
            items.append(URLQueryItem(name: "album_name", value: album))
        }
        if track.duration > 0 {
            items.append(URLQueryItem(name: "duration", value: String(track.duration)))
        }
        components.queryItems = items

        guard let url = components.url else {
            isLoading = false
            fetchedTrackId = track.id
            return
        }

        do {
            var request = URLRequest(url: url)
            request.setValue("Monochrome-iOS/1.0", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                isLoading = false
                fetchedTrackId = track.id
                return
            }

            let decoded = try JSONDecoder().decode(LRCLibResponse.self, from: data)
            CacheService.shared.set(forKey: cacheKey, value: decoded)
            applyResponse(decoded)
        } catch {
            print("[Lyrics] fetch error: \(error)")
        }

        isLoading = false
        fetchedTrackId = track.id
    }

    private func applyResponse(_ response: LRCLibResponse) {
        if let synced = response.syncedLyrics, !synced.isEmpty {
            syncedLines = parseLRC(synced)
        }
        if syncedLines.isEmpty, let plain = response.plainLyrics, !plain.isEmpty {
            plainLyrics = plain
        }
    }

    // MARK: - LRC Parser

    private func parseLRC(_ lrc: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        var index = 0

        for rawLine in lrc.components(separatedBy: "\n") {
            // Match [MM:SS.CC] or [MM:SS.CCC]
            guard let bracket = rawLine.firstIndex(of: "]"),
                  rawLine.first == "[" else { continue }

            let timeStr = rawLine[rawLine.index(after: rawLine.startIndex)..<bracket]
            let parts = timeStr.split(separator: ":")
            guard parts.count == 2,
                  let minutes = Double(parts[0]) else { continue }

            let secParts = parts[1].split(separator: ".")
            guard let seconds = Double(secParts[0]) else { continue }

            var centis = 0.0
            if secParts.count > 1 {
                let cStr = secParts[1]
                if let c = Double(cStr) {
                    centis = c / (cStr.count == 3 ? 1000.0 : 100.0)
                }
            }

            let time = minutes * 60 + seconds + centis
            let text = String(rawLine[rawLine.index(after: bracket)...]).trimmingCharacters(in: .whitespaces)

            if !text.isEmpty {
                lines.append(LyricLine(id: index, time: time, text: text))
                index += 1
            }
        }

        return lines
    }
}

// MARK: - LRCLIB Response

struct LRCLibResponse: Codable {
    let syncedLyrics: String?
    let plainLyrics: String?
}
