import SwiftUI

struct HomeView: View {
    @Binding var navigationPath: NavigationPath
    @Environment(AudioPlayerService.self) private var audioPlayer
    @Environment(LibraryManager.self) private var libraryManager

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Good morning" }
        if hour < 18 { return "Good afternoon" }
        return "Good evening"
    }

    var body: some View {
        List {
            homeContent
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .environment(\.defaultMinListRowHeight, 0)
    }

    // MARK: - Home Content

    private var homeContent: some View {
        Group {
            Text(greeting)
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(Theme.foreground)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 0, trailing: 0))
                .listRowBackground(Color.clear)

            if !audioPlayer.playHistory.isEmpty || audioPlayer.currentTrack != nil {
                recentlyPlayed
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 24, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
            }

            if !libraryManager.favoriteTracks.isEmpty {
                favoritesSection
            }

            if audioPlayer.playHistory.isEmpty && audioPlayer.currentTrack == nil && libraryManager.favoriteTracks.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "music.note")
                        .font(.system(size: 52, weight: .light))
                        .foregroundColor(Theme.mutedForeground.opacity(0.3))
                    Text("Search for a track to get started")
                        .font(.system(size: 16))
                        .foregroundColor(Theme.mutedForeground)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            Color.clear.frame(height: 100)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
    }

    // MARK: - Recently Played

    private var recentlyPlayed: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recently played")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Theme.foreground)
                .padding(.horizontal, 16)

            let recentTracks = recentTracksList
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ], spacing: 8) {
                ForEach(recentTracks.prefix(6)) { track in
                    RecentTrackCard(track: track) {
                        audioPlayer.play(track: track)
                    }
                }
            }
            .padding(.horizontal, 16)
            .task(id: recentTracks.map { $0.id }) {
                audioPlayer.refreshRecentQualitiesIfNeeded(tracks: recentTracks)
            }
        }
    }

    private var recentTracksList: [Track] {
        var tracks: [Track] = []
        if let current = audioPlayer.currentTrack {
            tracks.append(current)
        }
        for track in audioPlayer.playHistory.reversed() {
            if !tracks.contains(where: { $0.id == track.id }) {
                tracks.append(track)
            }
        }
        return tracks
    }

    // MARK: - Favorites

    private var favoritesSection: some View {
        Group {
            Section {
                ForEach(Array(libraryManager.favoriteTracks.prefix(5).enumerated()), id: \.element.id) { index, track in
                    let queue = Array(libraryManager.favoriteTracks.dropFirst(index + 1))
                    let previous = Array(libraryManager.favoriteTracks.prefix(index))
                    TrackRow(track: track, queue: queue, previousTracks: previous, showCover: true, navigationPath: $navigationPath)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            } header: {
                HStack {
                    Text("Your favorites")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Theme.foreground)

                    Spacer()

                    Text("\(libraryManager.favoriteTracks.count) track\(libraryManager.favoriteTracks.count > 1 ? "s" : "")")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.mutedForeground)
                }
                .padding(.horizontal, 16)
                .padding(.top, 24)
                .padding(.bottom, 12)
                .background(Theme.background)
            }
        }
    }
}

// MARK: - Recent Track Card (compact, 2-col grid)

struct RecentTrackCard: View {
    let track: Track
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                CachedAsyncImage(url: MonochromeAPI().getImageUrl(id: track.album?.cover)) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle().fill(Theme.card)
                    }
                }
                .frame(width: 56, height: 56)
                .clipped()

                HStack(spacing: 4) {
                    Text(track.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.foreground)
                        .lineLimit(2)

                    QualityBadge(audioQuality: track.audioQuality, mediaTags: track.mediaMetadata?.tags)
                }
                .padding(.horizontal, 10)

                Spacer()
            }
            .frame(height: 56)
            .background(Theme.secondary.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        HomeView(navigationPath: .constant(NavigationPath()))
    }
    .environment(AudioPlayerService())
    .environment(LibraryManager.shared)
}
