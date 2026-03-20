import SwiftUI

struct PlaylistDetailView: View {
    let playlist: Playlist
    @Binding var navigationPath: CompatNavigationPath
    @EnvironmentObject private var audioPlayer: AudioPlayerService
    @EnvironmentObject private var libraryManager: LibraryManager
    @EnvironmentObject private var downloadManager: DownloadManager

    @State private var tracks: [Track] = []
    @State private var loadedDetail: PlaylistDetail?
    @State private var isLoading = true

    private var playlistDownloadButton: some View {
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
                playlistHeader
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)

                if tracks.isEmpty && isLoading {
                    skeletonTrackList
                } else if tracks.isEmpty {
                    Text("No tracks available")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.mutedForeground)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
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
        .compatToolbarBackground(.hidden)
        .task { await loadPlaylist() }
    }

    // MARK: - Header

    private var playlistHeader: some View {
        VStack(spacing: 16) {
            CachedAsyncImage(url: imageURL(size: 640)) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fit)
                } else {
                    RoundedRectangle(cornerRadius: 8).fill(Theme.card)
                        .aspectRatio(1, contentMode: .fit)
                        .overlay(
                            Image(systemName: "music.note.list")
                                .font(.system(size: 48))
                                .foregroundColor(Theme.mutedForeground.opacity(0.2))
                        )
                }
            }
            .frame(width: 220, height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.4), radius: 20, y: 10)

            VStack(spacing: 6) {
                Text(loadedDetail?.title ?? playlist.title ?? "Playlist")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(Theme.foreground)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                if let desc = loadedDetail?.description, !desc.isEmpty {
                    Text(desc)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.mutedForeground)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }

                Text("\(loadedDetail?.numberOfTracks ?? playlist.numberOfTracks ?? 0) tracks")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.mutedForeground)
            }

            // Action buttons
            HStack(spacing: 16) {
                Button(action: { libraryManager.toggleFavorite(playlist: playlist) }) {
                    Image(systemName: libraryManager.isFavorite(playlistId: playlist.uuid) ? "heart.fill" : "heart")
                        .font(.system(size: 22))
                        .foregroundColor(libraryManager.isFavorite(playlistId: playlist.uuid) ? Theme.foreground : Theme.mutedForeground)
                }
                .buttonStyle(.borderless)

                playlistDownloadButton

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
                showCover: true, showIndex: nil,
                navigationPath: $navigationPath
            )
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Skeleton

    @ViewBuilder
    private var skeletonTrackList: some View {
        let count = min(playlist.numberOfTracks ?? 8, 12)
        let titleWidths: [CGFloat] = [160, 120, 180, 140, 100, 150, 130, 170, 110, 145, 155, 125]
        let subtitleWidths: [CGFloat] = [90, 110, 70, 100, 80, 95, 85, 105, 75, 115, 88, 98]
        ForEach(0..<count, id: \.self) { index in
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.secondary)
                    .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 6) {
                    SkeletonPill(width: titleWidths[index % 12], height: 14)
                    SkeletonPill(width: subtitleWidths[index % 12], height: 12)
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

    // MARK: - Data

    private func loadPlaylist() async {
        let cacheKey = "playlist_\(playlist.uuid)"
        if let cached: PlaylistDetail = CacheService.shared.get(forKey: cacheKey) {
            loadedDetail = cached
            tracks = cached.tracks
            isLoading = false
        }

        if let age = CacheService.shared.age(forKey: cacheKey),
           age < CacheService.shared.maxAge,
           !tracks.isEmpty {
            return
        }

        do {
            let detail = try await MonochromeAPI().fetchPlaylist(uuid: playlist.uuid)
            loadedDetail = detail
            tracks = detail.tracks
        } catch {
            if loadedDetail == nil { print("Error loading playlist: \(error)") }
        }
        isLoading = false
    }

    // MARK: - Helpers

    private func imageURL(size: Int = 320) -> URL? {
        let img = loadedDetail?.image ?? playlist.image
        guard let img, !img.isEmpty else { return nil }
        if img.hasPrefix("http") { return URL(string: img) }
        return MonochromeAPI().getImageUrl(id: img, size: size)
    }
}
