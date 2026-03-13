import SwiftUI

struct AlbumDetailView: View {
    let album: Album
    @Binding var navigationPath: NavigationPath
    @Environment(AudioPlayerService.self) private var audioPlayer
    @Environment(LibraryManager.self) private var libraryManager
    @Environment(DownloadManager.self) private var downloadManager

    @State private var loadedAlbum: Album?
    @State private var tracks: [Track] = []
    @State private var isLoading = true

    private var displayAlbum: Album { loadedAlbum ?? album }

    private var albumDownloadButton: some View {
        let allDownloaded = !tracks.isEmpty && tracks.allSatisfy { downloadManager.isDownloaded($0.id) }
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

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            List {
                albumHeader
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)

                if tracks.isEmpty && isLoading {
                    skeletonTrackList
                } else {
                    trackList
                }

                Spacer(minLength: 120)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 0)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await loadAlbum() }
    }

    // MARK: - Header

    private var albumHeader: some View {
        VStack(spacing: 16) {
            AsyncImage(url: MonochromeAPI().getImageUrl(id: displayAlbum.cover, size: 640)) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fit)
                } else {
                    RoundedRectangle(cornerRadius: 8).fill(Theme.card)
                        .aspectRatio(1, contentMode: .fit)
                }
            }
            .frame(width: 220, height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.4), radius: 20, y: 10)

            VStack(spacing: 6) {
                Text(displayAlbum.title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(Theme.foreground)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                if let artist = displayAlbum.artist {
                    Button(action: { navigationPath.append(artist) }) {
                        Text(artist.name)
                            .font(.system(size: 15))
                            .foregroundColor(Theme.mutedForeground)
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 6) {
                    if let year = displayAlbum.releaseYear {
                        Text(year)
                    }
                    if let type = displayAlbum.type, type.uppercased() != "ALBUM" {
                        Text("·")
                        Text(type)
                    }
                    if let count = displayAlbum.numberOfTracks {
                        Text("·")
                        Text("\(count) tracks")
                    }
                }
                .font(.system(size: 13))
                .foregroundColor(Theme.mutedForeground)
            }

            // Play / Shuffle / Favorite buttons
            HStack(spacing: 16) {
                Button(action: { libraryManager.toggleFavorite(album: displayAlbum) }) {
                    Image(systemName: libraryManager.isFavorite(albumId: displayAlbum.id) ? "heart.fill" : "heart")
                        .font(.system(size: 22))
                        .foregroundColor(libraryManager.isFavorite(albumId: displayAlbum.id) ? Theme.foreground : Theme.mutedForeground)
                }
                .buttonStyle(.borderless)

                albumDownloadButton

                Button(action: {
                    guard !tracks.isEmpty else { return }
                    let shuffled = tracks.shuffled()
                    audioPlayer.play(track: shuffled[0], queue: Array(shuffled.dropFirst()))
                }) {
                    Image(systemName: "shuffle")
                        .font(.system(size: 22))
                        .foregroundColor(Theme.mutedForeground)
                }
                .buttonStyle(.borderless)

                Spacer()

                Button(action: {
                    guard let first = tracks.first else { return }
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
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Track List

    @ViewBuilder
    private var trackList: some View {
        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
            let queue = Array(tracks.dropFirst(index + 1))
            let previous = Array(tracks.prefix(index))
            TrackRow(
                track: track, queue: queue, previousTracks: previous,
                showCover: false, showIndex: index + 1,
                navigationPath: $navigationPath
            )
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Skeleton Track List

    @ViewBuilder
    private var skeletonTrackList: some View {
        let count = displayAlbum.numberOfTracks ?? 8
        let titleWidths: [CGFloat] = [160, 120, 180, 140, 100, 150, 130, 170, 110, 145, 155, 125]
        let subtitleWidths: [CGFloat] = [90, 110, 70, 100, 80, 95, 85, 105, 75, 115, 88, 98]
        ForEach(0..<min(count, 12), id: \.self) { index in
            HStack(spacing: 12) {
                Text("\(index + 1)")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Theme.secondary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 6) {
                    SkeletonPill(width: titleWidths[index], height: 14)
                    SkeletonPill(width: subtitleWidths[index], height: 12)
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

    // MARK: - Data (cache-then-network)

    private func loadAlbum() async {
        // Phase 1: instant from cache
        let cacheKey = "album_\(album.id)"
        if let cached: AlbumDetail = CacheService.shared.get(forKey: cacheKey) {
            loadedAlbum = cached.album
            tracks = cached.tracks
            isLoading = false
        }

        // Phase 2: skip network if cache is valid (within user-configured maxAge) and complete
        if let age = CacheService.shared.age(forKey: cacheKey),
           age < CacheService.shared.maxAge,
           !tracks.isEmpty {
            return
        }

        // Phase 3: refresh from network
        do {
            let detail = try await MonochromeAPI().fetchAlbum(id: album.id)
            loadedAlbum = detail.album
            tracks = detail.tracks
        } catch {
            if loadedAlbum == nil { print("Error loading album: \(error)") }
        }
        isLoading = false
    }
}
