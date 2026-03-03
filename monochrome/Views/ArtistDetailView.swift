import SwiftUI

struct ArtistDetailView: View {
    let artist: Artist
    @Binding var navigationPath: NavigationPath
    @Environment(AudioPlayerService.self) private var audioPlayer
    @Environment(LibraryManager.self) private var libraryManager

    @State private var artistDetail: ArtistDetail?
    @State private var bio: String?
    @State private var similarArtists: [Artist] = []
    @State private var isLoading = true
    @State private var showAllTracks = false
    @State private var showFullBio = false
    @State private var discoFilter: DiscoFilter = .all

    enum DiscoFilter: String, CaseIterable {
        case all = "All"
        case albums = "Albums"
        case singles = "Singles"
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            if isLoading {
                ProgressView().tint(Theme.mutedForeground)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        heroHeader
                        contentSection
                    }
                }
                .ignoresSafeArea(edges: .top)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await loadAllData() }
    }

    // MARK: - Hero Header (Spotify style)

    private var heroHeader: some View {
        GeometryReader { geo in
            let minY = geo.frame(in: .global).minY
            let height: CGFloat = 380

            ZStack(alignment: .bottomLeading) {
                // Artist image with parallax
                AsyncImage(url: MonochromeAPI().getImageUrl(id: artist.picture, size: 750)) { phase in
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
                    Text(artist.name)
                        .font(.system(size: 44, weight: .black))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.7), radius: 10, y: 2)
                        .minimumScaleFactor(0.6)
                        .lineLimit(2)

                    if let pop = artistDetail?.popularity, pop > 0 {
                        Text("\(formatNumber(pop * 10000)) monthly listeners")
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

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Action buttons row
            actionButtons

            // Popular tracks
            if let detail = artistDetail, !detail.topTracks.isEmpty {
                popularTracks(detail.topTracks)
            }

            // Discography
            if let detail = artistDetail, !detail.albums.isEmpty {
                discography(detail.albums)
            }

            // About / Bio
            if let bioText = bio, !bioText.isEmpty {
                aboutSection(bioText)
            }

            // Similar artists
            if !similarArtists.isEmpty {
                similarArtistsSection
            }

            Spacer(minLength: 120)
        }
        .padding(.top, 12)
    }

    // MARK: - Action Buttons (Spotify: shuffle + play)

    private var actionButtons: some View {
        HStack(spacing: 16) {
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

            Spacer()

            // Play button (Spotify green circle -> white circle in monochrome)
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
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Popular Tracks

    @ViewBuilder
    private func popularTracks(_ tracks: [Track]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Popular")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Theme.foreground)
                .padding(.horizontal, 16)
                .padding(.bottom, 4)

            let displayed = showAllTracks ? tracks : Array(tracks.prefix(5))

            ForEach(Array(displayed.enumerated()), id: \.element.id) { index, track in
                let queue = Array(tracks.dropFirst(index + 1))
                TrackRow(
                    track: track, queue: queue,
                    showCover: true, showIndex: index + 1,
                    navigationPath: $navigationPath
                )
            }

            if tracks.count > 5 {
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showAllTracks.toggle() } }) {
                    Text(showAllTracks ? "Show less" : "See more")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Theme.mutedForeground)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
        }
    }

    // MARK: - Discography

    @ViewBuilder
    private func discography(_ albums: [Album]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Discography")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Theme.foreground)

                Spacer()
            }
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
            let filtered = filterAlbums(albums)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(filtered) { album in
                        AlbumCard(album: album)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func filterAlbums(_ albums: [Album]) -> [Album] {
        switch discoFilter {
        case .all: return albums
        case .albums: return albums.filter { ($0.numberOfTracks ?? 0) > 3 }
        case .singles: return albums.filter { ($0.numberOfTracks ?? 0) <= 3 }
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
                    // Artist image in card
                    AsyncImage(url: MonochromeAPI().getImageUrl(id: artist.picture, size: 480)) { phase in
                        if let image = phase.image {
                            image.resizable()
                                 .aspectRatio(contentMode: .fill)
                                 .frame(height: 180)
                                 .clipped()
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    // Popularity
                    if let pop = artistDetail?.popularity, pop > 0 {
                        HStack(spacing: 4) {
                            Text("\(formatNumber(pop * 10000))")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(Theme.foreground)
                            Text("monthly listeners")
                                .font(.system(size: 13))
                                .foregroundColor(Theme.mutedForeground)
                        }
                    }

                    // Bio preview
                    Text(cleanHtml(text))
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
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Artist image
                    AsyncImage(url: MonochromeAPI().getImageUrl(id: artist.picture, size: 750)) { phase in
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
                            Text("\(formatNumber(pop * 10000))")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(Theme.foreground)
                            Text("monthly listeners")
                                .font(.system(size: 14))
                                .foregroundColor(Theme.mutedForeground)
                        }
                        .padding(.horizontal, 16)
                    }

                    Text(cleanHtml(text))
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(Theme.foreground.opacity(0.9))
                        .lineSpacing(4)
                        .padding(.horizontal, 16)

                    Spacer(minLength: 40)
                }
                .padding(.top, 8)
            }
            .background(Theme.background)
            .navigationTitle(artist.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { showFullBio = false }
                        .foregroundColor(Theme.foreground)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.background)
    }

    // MARK: - Similar Artists

    private var similarArtistsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fans also like")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Theme.foreground)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(similarArtists) { similarArtist in
                        Button(action: { navigationPath.append(similarArtist) }) {
                            VStack(spacing: 8) {
                                AsyncImage(url: MonochromeAPI().getImageUrl(id: similarArtist.picture, size: 320)) { phase in
                                    if let image = phase.image {
                                        image.resizable().aspectRatio(contentMode: .fill)
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
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Data Loading

    private func loadAllData() async {
        async let artistTask = MonochromeAPI().fetchArtist(id: artist.id)
        async let bioTask = MonochromeAPI().fetchArtistBio(id: artist.id)
        async let similarTask = MonochromeAPI().fetchSimilarArtists(id: artist.id)

        do { artistDetail = try await artistTask } catch { print("Error loading artist: \(error)") }
        bio = await bioTask
        similarArtists = await similarTask
        isLoading = false
    }

    // MARK: - Helpers

    private func formatNumber(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.0fK", Double(n) / 1_000) }
        return "\(n)"
    }

    private func cleanHtml(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Album Card

struct AlbumCard: View {
    let album: Album

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: MonochromeAPI().getImageUrl(id: album.cover)) { phase in
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
