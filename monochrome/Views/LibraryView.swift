import SwiftUI

struct LibraryView: View {
    @Binding var navigationPath: NavigationPath
    @Environment(LibraryManager.self) private var libraryManager
    @Environment(AudioPlayerService.self) private var audioPlayer
    @State private var sortNewest = true

    private var sortedTracks: [Track] {
        if sortNewest {
            return libraryManager.favoriteTracks
        }
        return libraryManager.favoriteTracks.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with sort
            HStack {
                Text("Favorites")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(Theme.foreground)

                Spacer()

                if !libraryManager.favoriteTracks.isEmpty {
                    Button(action: { sortNewest.toggle() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.system(size: 12))
                            Text(sortNewest ? "Recent" : "A-Z")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(Theme.mutedForeground)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            if libraryManager.favoriteTracks.isEmpty {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "heart")
                        .font(.system(size: 52, weight: .light))
                        .foregroundColor(Theme.mutedForeground.opacity(0.4))
                    Text("Your favorite tracks will appear here")
                        .font(.system(size: 16))
                        .foregroundColor(Theme.mutedForeground)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                // Track count
                Text("\(libraryManager.favoriteTracks.count) track\(libraryManager.favoriteTracks.count > 1 ? "s" : "")")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.mutedForeground)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(sortedTracks.enumerated()), id: \.element.id) { index, track in
                            let queue = Array(sortedTracks.dropFirst(index + 1))
                            TrackRow(track: track, queue: queue, showCover: true, navigationPath: $navigationPath)
                        }
                    }
                    .padding(.bottom, 120)
                }
            }
        }
        .background(Theme.background)
    }
}

#Preview {
    LibraryView(navigationPath: .constant(NavigationPath()))
        .environment(LibraryManager.shared)
        .environment(AudioPlayerService())
}
