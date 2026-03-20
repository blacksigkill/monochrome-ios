import SwiftUI

struct ArtistDetailView: View {
    let artist: Artist
    @Binding var navigationPath: CompatNavigationPath
    @EnvironmentObject private var audioPlayer: AudioPlayerService
    @EnvironmentObject private var libraryManager: LibraryManager
    @EnvironmentObject private var downloadManager: DownloadManager

    @State private var artistDetail: ArtistDetail?
    @State private var bio: String?
    @State private var similarArtists: [Artist] = []
    @State private var showAllTracks = false
    @State private var showFullBio = false
    @State private var discoFilter: DiscoFilter = .all
    @State private var isRefreshing = false

    enum DiscoFilter: String, CaseIterable {
        case all = "All"
        case albums = "Albums"
        case singles = "Singles"
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            List {
                heroHeader
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                contentSection
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 0)
            .ignoresSafeArea(edges: .top)
        }
        .navigationBarTitleDisplayMode(.inline)
        .compatToolbarBackground(.hidden)
        .task { await loadAllData() }
    }

    // MARK: - Hero Header (Spotify style)

    private var heroHeader: some View {
        GeometryReader { geo in
            let minY = geo.frame(in: .global).minY
            let height: CGFloat = 380

            ZStack(alignment: .bottomLeading) {
                // Artist image with parallax
                CachedAsyncImage(url: MonochromeAPI().getImageUrl(id: artistDetail?.picture ?? artist.picture, size: 750)) { phase in
                    if let image = phase.image {
                        image.resizable()
                             .aspectRatio(contentMode: .fill)
                             .frame(width: geo.size.width, height: minY > 0 ? height + minY : height)
                             .clipped()
                             .offset(y: minY > 0 ? -minY : 0)
                    } else {
                        Rectangle().fill(Theme.secondary)
                            .frame(height: height)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(.system(size: 64))
                                    .foregroundColor(Theme.mutedForeground.opacity(0.2))
                            )
                    }
                }

                // Gradient overlay
                LinearGradient(
                    colors: [.clear, .clear, Theme.background.opacity(0.7), Theme.background],
                    startPoint: .top, endPoint: .bottom
                )

                // Name + info
                VStack(alignment: .leading, spacing: 6) {
                    Text(artistDetail?.name ?? artist.name)
                        .font(.system(size: 44, weight: .black))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.7), radius: 10, y: 2)
                        .minimumScaleFactor(0.6)
                        .lineLimit(2)

                    if let pop = artistDetail?.popularity, pop > 0 {
                        Text("\(formatNumber(Int(pop * 10000))) monthly listeners")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .frame(height: height)
        }
        .frame(height: 380)
    }

    // MARK: - Content

    @ViewBuilder
    private var contentSection: some View {
        // Action buttons row
        actionButtons
            .padding(.top, 12)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

        // Popular tracks
        if let detail = artistDetail, !detail.topTracks.isEmpty {
            popularTracks(detail.topTracks)
        } else if isRefreshing {
            skeletonTracks
        }

        // Discography
        if let detail = artistDetail, (!detail.albums.isEmpty || !detail.eps.isEmpty) {
            discography(albums: detail.albums, eps: detail.eps)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .padding(.top, 24)
        } else if isRefreshing {
            skeletonDiscography
                .padding(.top, 24)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
        }

        // About / Bio
        if let bioText = bio, !bioText.isEmpty {
            aboutSection(bioText)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .padding(.top, 24)
        }

        // Similar artists
        if !similarArtists.isEmpty {
            similarArtistsSection
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .padding(.top, 24)
        } else if isRefreshing {
            skeletonSimilarArtists
                .padding(.top, 24)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
        }

        Spacer(minLength: 120)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    // MARK: - Action Buttons (Spotify: shuffle + play)

    private var currentArtist: Artist {
        Artist(
            id: artistDetail?.id ?? artist.id,
            name: artistDetail?.name ?? artist.name,
            picture: artistDetail?.picture ?? artist.picture,
            popularity: artistDetail?.popularity ?? artist.popularity
        )
    }

    private var actionButtons: some View {
        HStack(spacing: 16) {
            // Favorite
            Button(action: { libraryManager.toggleFavorite(artist: currentArtist) }) {
                Image(systemName: libraryManager.isFavorite(artistId: artist.id) ? "heart.fill" : "heart")
                    .font(.system(size: 22))
                    .foregroundColor(libraryManager.isFavorite(artistId: artist.id) ? Theme.foreground : Theme.mutedForeground)
            }
            .buttonStyle(.borderless)

            // Shuffle
            Button(action: {
                guard let tracks = artistDetail?.topTracks, !tracks.isEmpty else { return }
                let shuffled = tracks.shuffled()
                audioPlayer.play(track: shuffled[0], queue: Array(shuffled.dropFirst()))
            }) {
                Image(systemName: "shuffle")
                    .font(.system(size: 22))
                    .foregroundColor(Theme.mutedForeground)
            }
            .buttonStyle(.borderless)

            // Download top tracks
            if let tracks = artistDetail?.topTracks, !tracks.isEmpty {
                artistDownloadButton(tracks)
            }

            Spacer()

            // Play button
            Button(action: {
                guard let tracks = artistDetail?.topTracks, let first = tracks.first else { return }
                audioPlayer.play(track: first, queue: Array(tracks.dropFirst()))
            }) {
                ZStack {
                    Circle().fill(Theme.foreground)
                        .frame(width: 48, height: 48)
                    Image(systemName: "play.fill")
                        .font(.system(size: 20))
                        .foregroundColor(Theme.primaryForeground)
                        .offset(x: 2)
                }
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
    }

    private func artistDownloadButton(_ tracks: [Track]) -> some View {
        let allDownloaded = tracks.allSatisfy { downloadManager.isDownloaded($0.id) }
        let someDownloading = tracks.contains { downloadManager.isDownloading($0.id) }

        return Button(action: {
            if !allDownloaded {
                downloadManager.downloadTracks(tracks)
            }
        }) {
            if allDownloaded {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(Theme.highlight)
            } else if someDownloading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.8)
            } else {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 22))
                    .foregroundColor(Theme.mutedForeground)
            }
        }
        .buttonStyle(.borderless)
    }

    // MARK: - Popular Tracks

    @ViewBuilder
    private func popularTracks(_ tracks: [Track]) -> some View {
        Text("Popular")
            .font(.system(size: 18, weight: .bold))
            .foregroundColor(Theme.foreground)
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
            .padding(.top, 24)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

        let displayed = showAllTracks ? tracks : Array(tracks.prefix(5))

        ForEach(Array(displayed.enumerated()), id: \.element.id) { index, track in
            let queue = Array(tracks.dropFirst(index + 1))
            let previous = Array(tracks.prefix(index))
            TrackRow(
                track: track, queue: queue, previousTracks: previous,
                showCover: true, showIndex: nil,
                navigationPath: $navigationPath
            )
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }

        if tracks.count > 5 {
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showAllTracks.toggle() } }) {
                Text(showAllTracks ? "Show less" : "See more")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Theme.mutedForeground)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Discography

    @ViewBuilder
    private func discography(albums: [Album], eps: [Album]) -> some View {
        let allReleases = albums + eps

        VStack(alignment: .leading, spacing: 12) {
            Text("Discography")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Theme.foreground)
                .padding(.horizontal, 16)

            // Filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(DiscoFilter.allCases, id: \.self) { filter in
                        Button(action: { discoFilter = filter }) {
                            Text(filter.rawValue)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(discoFilter == filter ? Theme.primaryForeground : Theme.foreground)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(discoFilter == filter ? Theme.foreground : Theme.secondary)
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(.horizontal, 16)
            }

            // Albums grid
            let filtered = filterReleases(allReleases)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(filtered) { album in
                        Button(action: { navigationPath.append(album) }) {
                            AlbumCard(album: album)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func filterReleases(_ releases: [Album]) -> [Album] {
        switch discoFilter {
        case .all: return releases
        case .albums: return releases.filter { ($0.type?.uppercased() ?? "") != "EP" && ($0.type?.uppercased() ?? "") != "SINGLE" }
        case .singles: return releases.filter { ($0.type?.uppercased() ?? "") == "EP" || ($0.type?.uppercased() ?? "") == "SINGLE" }
        }
    }

    // MARK: - About / Bio

    @ViewBuilder
    private func aboutSection(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("About")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Theme.foreground)
                .padding(.horizontal, 16)

            // Bio card with artist image
            Button(action: { showFullBio = true }) {
                VStack(alignment: .leading, spacing: 12) {
                    CachedAsyncImage(url: MonochromeAPI().getImageUrl(id: artistDetail?.picture ?? artist.picture, size: 480)) { phase in
                        if let image = phase.image {
                            image.resizable()
                                 .aspectRatio(contentMode: .fill)
                                 .frame(height: 180)
                                 .clipped()
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    if let pop = artistDetail?.popularity, pop > 0 {
                        HStack(spacing: 4) {
                            Text("\(formatNumber(Int(pop * 10000)))")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(Theme.foreground)
                            Text("monthly listeners")
                                .font(.system(size: 13))
                                .foregroundColor(Theme.mutedForeground)
                        }
                    }

                    Text(stripBioTags(text))
                        .font(.system(size: 14))
                        .foregroundColor(Theme.mutedForeground)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                .padding(16)
                .background(Theme.secondary.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
        }
        .sheet(isPresented: $showFullBio) {
            bioSheet(text)
        }
    }

    @ViewBuilder
    private func bioSheet(_ text: String) -> some View {
        CompatNavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    CachedAsyncImage(url: MonochromeAPI().getImageUrl(id: artistDetail?.picture ?? artist.picture, size: 750)) { phase in
                        if let image = phase.image {
                            image.resizable()
                                 .aspectRatio(contentMode: .fill)
                                 .frame(height: 280)
                                 .clipped()
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 16)

                    if let pop = artistDetail?.popularity, pop > 0 {
                        HStack(spacing: 4) {
                            Text("\(formatNumber(Int(pop * 10000)))")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(Theme.foreground)
                            Text("monthly listeners")
                                .font(.system(size: 14))
                                .foregroundColor(Theme.mutedForeground)
                        }
                        .padding(.horizontal, 16)
                    }

                    BioTextView(text: text) { type, id in
                        showFullBio = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            if type == "artist", let intId = Int(id) {
                                navigationPath.append(Artist(id: intId, name: "", picture: nil, popularity: nil))
                            } else if type == "album", let intId = Int(id) {
                                navigationPath.append(Album(id: intId, title: "", cover: nil, numberOfTracks: nil, releaseDate: nil, artist: nil, type: nil))
                            } else if type == "track", let intId = Int(id) {
                                Task {
                                    if let t = try? await MonochromeAPI().fetchTrack(id: intId) {
                                        DispatchQueue.main.async { audioPlayer.play(track: t, queue: []) }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)

                    Spacer(minLength: 40)
                }
                .padding(.top, 8)
            }
            .background(Theme.background)
            .navigationTitle(artistDetail?.name ?? artist.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { showFullBio = false }
                        .foregroundColor(Theme.foreground)
                }
            }
        }
        .compatPresentationDragIndicator()
        .compatPresentationBackground(Theme.background)
    }

    // MARK: - Similar Artists

    private var similarArtistsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fans also like")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Theme.foreground)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(similarArtists) { similarArtist in
                        Button(action: { navigationPath.append(similarArtist) }) {
                            VStack(spacing: 8) {
                                CachedAsyncImage(url: MonochromeAPI().getImageUrl(id: similarArtist.picture, size: 320)) { phase in
                                    if let image = phase.image {
                                        image.resizable().scaledToFill()
                                    } else {
                                        Circle().fill(Theme.secondary)
                                            .overlay(
                                                Image(systemName: "person.fill")
                                                    .foregroundColor(Theme.mutedForeground.opacity(0.3))
                                            )
                                    }
                                }
                                .frame(width: 120, height: 120)
                                .clipShape(Circle())

                                Text(similarArtist.name)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(Theme.mutedForeground)
                                    .lineLimit(1)
                            }
                            .frame(width: 120)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Skeleton Placeholders

    @ViewBuilder
    private var skeletonTracks: some View {
        Text("Popular")
            .font(.system(size: 18, weight: .bold))
            .foregroundColor(Theme.foreground)
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
            .padding(.top, 24)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

        ForEach(0..<5, id: \.self) { i in
            let titleWidths: [CGFloat] = [160, 120, 180, 140, 100]
            let subtitleWidths: [CGFloat] = [90, 110, 70, 100, 80]
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.secondary)
                    .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 6) {
                    SkeletonPill(width: titleWidths[i], height: 14)
                    SkeletonPill(width: subtitleWidths[i], height: 12)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .shimmer()
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }

    private var skeletonDiscography: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Discography")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Theme.foreground)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(0..<4, id: \.self) { i in
                        let nameWidths: [CGFloat] = [110, 90, 130, 100]
                        VStack(alignment: .leading, spacing: 6) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Theme.secondary)
                                .frame(width: 150, height: 150)

                            SkeletonPill(width: nameWidths[i], height: 13)
                            SkeletonPill(width: 60, height: 11)
                        }
                        .frame(width: 150)
                        .shimmer()
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private var skeletonSimilarArtists: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fans also like")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Theme.foreground)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(0..<5, id: \.self) { i in
                        let nameWidths: [CGFloat] = [70, 90, 55, 80, 65]
                        VStack(spacing: 8) {
                            Circle()
                                .fill(Theme.secondary)
                                .frame(width: 120, height: 120)

                            SkeletonPill(width: nameWidths[i])
                        }
                        .frame(width: 120)
                        .shimmer()
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Data Loading (cache-then-network)

    private func loadAllData() async {
        let cache = CacheService.shared
        loadFromCache()

        // Skip network if cache is valid (within user-configured maxAge) and complete
        if let age = cache.age(forKey: "artist_\(artist.id)"),
           age < cache.maxAge,
           let detail = artistDetail,
           !detail.topTracks.isEmpty {
            return
        }

        // Cache miss or stale — refresh from network
        isRefreshing = true
        async let artistTask: () = refreshArtistDetail()
        async let bioTask: () = refreshBio()
        async let similarTask: () = refreshSimilar()
        _ = await (artistTask, bioTask, similarTask)
        await MainActor.run { isRefreshing = false }
    }

    private func loadFromCache() {
        let cache = CacheService.shared
        if let cached: ArtistDetail = cache.get(forKey: "artist_\(artist.id)") {
            artistDetail = cached
        }
        if let cached: String = cache.get(forKey: "bio_\(artist.id)") {
            bio = cached
        }
        if let cached: [Artist] = cache.get(forKey: "similar_\(artist.id)") {
            similarArtists = cached
        }
    }

    private func refreshArtistDetail() async {
        do {
            let detail = try await MonochromeAPI().fetchArtist(id: artist.id)
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.3)) { artistDetail = detail }
            }
        } catch {
            if artistDetail == nil { print("Error loading artist: \(error)") }
        }
    }

    private func refreshBio() async {
        let result = await MonochromeAPI().fetchArtistBio(id: artist.id)
        await MainActor.run {
            if let result {
                withAnimation(.easeOut(duration: 0.3)) { bio = result }
            }
        }
    }

    private func refreshSimilar() async {
        let result = await MonochromeAPI().fetchSimilarArtists(id: artist.id)
        await MainActor.run {
            guard !result.isEmpty else { return }
            // Only replace if the list actually changed — avoids resetting AsyncImage states
            let cachedIds = similarArtists.map(\.id)
            let freshIds = result.map(\.id)
            if cachedIds != freshIds {
                if similarArtists.isEmpty {
                    withAnimation(.easeOut(duration: 0.3)) { similarArtists = result }
                } else {
                    similarArtists = result
                }
            }
        }
    }

    // MARK: - Helpers

    private func formatNumber(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.0fK", Double(n) / 1_000) }
        return "\(n)"
    }

    /// Strip all bracket tags, keeping just the display text
    private func stripBioTags(_ text: String) -> String {
        var clean = text
        // [wimpLink artistId="xxx"]Name[/wimpLink]
        clean = clean.replacingOccurrences(
            of: #"\[wimpLink \w+Id="[^"]*"\](.*?)\[/wimpLink\]"#,
            with: "$1", options: .regularExpression)
        // [artist:xxx]Name[/artist]
        clean = clean.replacingOccurrences(
            of: #"\[(\w+):[^\]]*\](.*?)\[/\1\]"#,
            with: "$2", options: .regularExpression)
        // [[Name|ID]]
        clean = clean.replacingOccurrences(
            of: #"\[\[([^|]*)\|[^\]]*\]\]"#,
            with: "$1", options: .regularExpression)
        // Strip HTML tags
        clean = clean.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        // HTML entities
        clean = clean.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
        return clean.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Bio Text View (parses bracket tags into tappable links)

private enum BioSegment: Identifiable {
    case text(String)
    case link(type: String, id: String, name: String)

    var id: String {
        switch self {
        case .text(let s): return "t_\(s.hashValue)"
        case .link(_, let id, let name): return "l_\(id)_\(name)"
        }
    }
}

private struct BioTextView: View {
    let text: String
    let onLinkTap: (String, String) -> Void

    var body: some View {
        let segments = parseBio(text)
        let attributed = buildAttributedString(segments)
        
        Text(attributed)
            .font(.system(size: 15))
            .lineSpacing(4)
            .tint(Theme.foreground) // Link color
            .environment(\.openURL, OpenURLAction { url in
                if url.scheme == "monochrome" {
                    let parts = url.pathComponents.filter { $0 != "/" }
                    if parts.count >= 2 {
                        onLinkTap(parts[0], parts[1])
                    }
                    return .handled
                }
                return .systemAction
            })
    }

    private func buildAttributedString(_ segments: [BioSegment]) -> AttributedString {
        var result = AttributedString()
        for segment in segments {
            switch segment {
            case .text(let str):
                var attr = AttributedString(str)
                attr.foregroundColor = Theme.foreground.opacity(0.9)
                result += attr
            case .link(let type, let id, let name):
                var attr = AttributedString(name)
                // Use a custom scheme to trap the tap
                attr.link = URL(string: "monochrome:///\(type)/\(id)")
                attr.underlineStyle = .single
                // We use .font to make it bold, color is handled by .tint on Text
                var container = AttributeContainer()
                container.font = .system(size: 15, weight: .semibold)
                attr.mergeAttributes(container)
                result += attr
            }
        }
        return result
    }

    private func parseBio(_ raw: String) -> [BioSegment] {
        // Clean HTML first
        let text = raw
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")

        var segments: [BioSegment] = []
        let patterns: [(NSRegularExpression, (NSTextCheckingResult, String) -> (type: String, id: String, name: String)?)] = {
            var p: [(NSRegularExpression, (NSTextCheckingResult, String) -> (type: String, id: String, name: String)?)] = []
            // [wimpLink artistId="xxx"]Name[/wimpLink]
            if let r = try? NSRegularExpression(pattern: #"\[wimpLink (\w+)Id="([^"]*)"\](.*?)\[/wimpLink\]"#) {
                p.append((r, { match, str in
                    guard match.numberOfRanges >= 4 else { return nil }
                    let type = String(str[Range(match.range(at: 1), in: str)!])
                    let id = String(str[Range(match.range(at: 2), in: str)!])
                    let name = String(str[Range(match.range(at: 3), in: str)!])
                    return (type, id, name)
                }))
            }
            // [artist:xxx]Name[/artist]
            if let r = try? NSRegularExpression(pattern: #"\[(\w+):([^\]]*)\](.*?)\[/\1\]"#) {
                p.append((r, { match, str in
                    guard match.numberOfRanges >= 4 else { return nil }
                    let type = String(str[Range(match.range(at: 1), in: str)!])
                    let id = String(str[Range(match.range(at: 2), in: str)!])
                    let name = String(str[Range(match.range(at: 3), in: str)!])
                    return (type, id, name)
                }))
            }
            // [[Name|ID]]
            if let r = try? NSRegularExpression(pattern: #"\[\[([^|]*)\|([^\]]*)\]\]"#) {
                p.append((r, { match, str in
                    guard match.numberOfRanges >= 3 else { return nil }
                    let name = String(str[Range(match.range(at: 1), in: str)!])
                    let id = String(str[Range(match.range(at: 2), in: str)!])
                    return ("artist", id, name)
                }))
            }
            return p
        }()

        // Find all matches across all patterns
        struct MatchInfo {
            let range: Range<String.Index>
            let type: String
            let id: String
            let name: String
        }

        var allMatches: [MatchInfo] = []
        let nsRange = NSRange(text.startIndex..., in: text)

        for (regex, extractor) in patterns {
            let matches = regex.matches(in: text, range: nsRange)
            for match in matches {
                guard let range = Range(match.range, in: text),
                      let info = extractor(match, text) else { continue }
                allMatches.append(MatchInfo(range: range, type: info.type, id: info.id, name: info.name))
            }
        }

        // Sort by position
        allMatches.sort { $0.range.lowerBound < $1.range.lowerBound }

        // Build segments
        var currentIndex = text.startIndex
        for match in allMatches {
            if currentIndex < match.range.lowerBound {
                segments.append(.text(String(text[currentIndex..<match.range.lowerBound])))
            }
            segments.append(.link(type: match.type, id: match.id, name: match.name))
            currentIndex = match.range.upperBound
        }
        if currentIndex < text.endIndex {
            segments.append(.text(String(text[currentIndex...])))
        }

        return segments.isEmpty ? [.text(text)] : segments
    }
}

// MARK: - Album Card

struct AlbumCard: View {
    let album: Album

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CachedAsyncImage(url: MonochromeAPI().getImageUrl(id: album.cover)) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    RoundedRectangle(cornerRadius: 4).fill(Theme.card)
                }
            }
            .frame(width: 150, height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            Text(album.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.foreground)
                .lineLimit(1)

            HStack(spacing: 4) {
                if let year = album.releaseYear {
                    Text(year)
                }
                if let count = album.numberOfTracks {
                    Text("·")
                    Text("\(count) tracks")
                }
            }
            .font(.system(size: 11))
            .foregroundColor(Theme.mutedForeground)
        }
        .frame(width: 150)
    }
}
