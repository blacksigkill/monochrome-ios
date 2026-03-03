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
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                // Greeting header
                Text(greeting)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(Theme.foreground)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                // Recently played
                if !audioPlayer.playHistory.isEmpty || audioPlayer.currentTrack != nil {
                    recentlyPlayed
                }

                // Favorites quick access
                if !libraryManager.favoriteTracks.isEmpty {
                    favoritesSection
                }

                // Empty state
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
                }

                Spacer(minLength: 100)
            }
        }
        .background(Theme.background)
    }

    // MARK: - Recently Played

    private var recentlyPlayed: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recently played")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Theme.foreground)
                .padding(.horizontal, 16)

            // Compact grid (2 columns, Spotify style)
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
        }
    }

    private var recentTracksList: [Track] {
        var tracks: [Track] = []
        // Current track first
        if let current = audioPlayer.currentTrack {
            tracks.append(current)
        }
        // Then history (most recent first), deduplicated
        for track in audioPlayer.playHistory.reversed() {
            if !tracks.contains(where: { $0.id == track.id }) {
                tracks.append(track)
            }
        }
        return tracks
    }

    // MARK: - Favorites

    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
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

            LazyVStack(spacing: 0) {
                ForEach(Array(libraryManager.favoriteTracks.prefix(5).enumerated()), id: \.element.id) { index, track in
                    let queue = Array(libraryManager.favoriteTracks.dropFirst(index + 1))
                    TrackRow(track: track, queue: queue, showCover: true, navigationPath: $navigationPath)
                }
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
                AsyncImage(url: MonochromeAPI().getImageUrl(id: track.album?.cover)) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle().fill(Theme.card)
                    }
                }
                .frame(width: 56, height: 56)
                .clipped()

                Text(track.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.foreground)
                    .lineLimit(2)
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
