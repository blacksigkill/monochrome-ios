import SwiftUI

struct SearchView: View {
    @Binding var navigationPath: NavigationPath
    @Environment(AudioPlayerService.self) private var audioPlayer
    @State private var searchText = ""
    @State private var searchResults: [Track] = []
    @State private var isSearching = false
    @State private var hasSearched = false

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16))
                    .foregroundColor(Theme.mutedForeground)

                TextField("What do you want to listen to?", text: $searchText)
                    .font(.system(size: 16))
                    .foregroundColor(Theme.foreground)
                    .autocorrectionDisabled()
                    .onSubmit { performSearch() }

                if !searchText.isEmpty {
                    Button(action: { searchText = ""; searchResults = []; hasSearched = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(Theme.mutedForeground)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            if isSearching {
                Spacer()
                ProgressView().tint(Theme.mutedForeground)
                Spacer()
            } else if !searchResults.isEmpty {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(searchResults.enumerated()), id: \.element.id) { index, track in
                            let queue = Array(searchResults.dropFirst(index + 1))
                            TrackRow(track: track, queue: queue, showCover: true, navigationPath: $navigationPath)
                        }
                    }
                    .padding(.bottom, 120)
                }
            } else if hasSearched {
                Spacer()
                VStack(spacing: 10) {
                    Text("No results for")
                        .font(.system(size: 16))
                        .foregroundColor(Theme.mutedForeground)
                    Text("\"\(searchText)\"")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Theme.foreground)
                }
                Spacer()
            } else {
                Spacer()
                VStack(spacing: 10) {
                    Text("Search for tracks")
                        .font(.system(size: 16))
                        .foregroundColor(Theme.mutedForeground)
                }
                Spacer()
            }
        }
        .background(Theme.background)
    }

    private func performSearch() {
        guard !searchText.isEmpty else { return }
        isSearching = true
        hasSearched = true

        Task {
            do { searchResults = try await MonochromeAPI().searchTracks(query: searchText) }
            catch { print("Search error: \(error)") }
            isSearching = false
        }
    }
}

// MARK: - Track Row (Spotify style)

struct TrackRow: View {
    let track: Track
    let queue: [Track]
    var showCover: Bool = true
    var showIndex: Int? = nil
    @Binding var navigationPath: NavigationPath
    @Environment(AudioPlayerService.self) private var audioPlayer
    @Environment(LibraryManager.self) private var libraryManager
    @State private var showOptions = false

    private var isCurrentTrack: Bool {
        audioPlayer.currentTrack?.id == track.id
    }

    var body: some View {
        Button(action: { audioPlayer.play(track: track, queue: queue) }) {
            HStack(spacing: 12) {
                // Index or cover
                if let index = showIndex {
                    Text("\(index)")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(isCurrentTrack ? Theme.highlight : Theme.mutedForeground)
                        .frame(width: 28, alignment: .center)
                } else if showCover {
                    AsyncImage(url: MonochromeAPI().getImageUrl(id: track.album?.cover)) { phase in
                        if let image = phase.image {
                            image.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            RoundedRectangle(cornerRadius: 4).fill(Theme.card)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                // Track info
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(isCurrentTrack ? Theme.highlight : Theme.foreground)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        if isCurrentTrack && audioPlayer.isPlaying {
                            Image(systemName: "waveform")
                                .font(.system(size: 10))
                                .foregroundColor(Theme.highlight)
                                .symbolEffect(.variableColor.iterative, isActive: true)
                        }
                        Text(track.artist?.name ?? "Unknown")
                    }
                    .font(.system(size: 13))
                    .foregroundColor(Theme.mutedForeground)
                    .lineLimit(1)
                }

                Spacer()

                // Context menu button
                Button(action: { showOptions = true }) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16))
                        .foregroundColor(Theme.mutedForeground)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showOptions) {
            TrackOptionsSheet(
                track: track,
                queue: queue,
                navigationPath: $navigationPath,
                isPresented: $showOptions
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .presentationBackground(Theme.card)
        }
    }
}

// MARK: - Track Options Bottom Sheet (Spotify style)

struct TrackOptionsSheet: View {
    let track: Track
    let queue: [Track]
    @Binding var navigationPath: NavigationPath
    @Binding var isPresented: Bool
    @Environment(AudioPlayerService.self) private var audioPlayer
    @Environment(LibraryManager.self) private var libraryManager

    var body: some View {
        VStack(spacing: 0) {
            // Track header
            HStack(spacing: 14) {
                AsyncImage(url: MonochromeAPI().getImageUrl(id: track.album?.cover)) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        RoundedRectangle(cornerRadius: 6).fill(Theme.secondary)
                    }
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Theme.foreground)
                        .lineLimit(1)
                    Text(track.artist?.name ?? "Unknown")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.mutedForeground)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider().overlay(Theme.border)

            // Options
            ScrollView {
                VStack(spacing: 0) {
                    // Like
                    OptionRow(
                        icon: libraryManager.isFavorite(trackId: track.id) ? "heart.fill" : "heart",
                        label: libraryManager.isFavorite(trackId: track.id) ? "Remove from favorites" : "Add to favorites",
                        iconColor: libraryManager.isFavorite(trackId: track.id) ? Theme.foreground : Theme.mutedForeground
                    ) {
                        libraryManager.toggleFavorite(track: track)
                    }

                    // Add to queue
                    OptionRow(icon: "text.line.last.and.arrowtriangle.forward", label: "Add to queue") {
                        audioPlayer.queuedTracks.append(track)
                        isPresented = false
                    }

                    // Go to artist
                    if let artist = track.artist {
                        OptionRow(icon: "person.fill", label: "Go to artist") {
                            isPresented = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                navigationPath.append(artist)
                            }
                        }
                    }

                    // Share
                    OptionRow(icon: "square.and.arrow.up", label: "Share") {
                        isPresented = false
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }
}

struct OptionRow: View {
    let icon: String
    let label: String
    var iconColor: Color = Theme.foreground
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(iconColor)
                    .frame(width: 28)

                Text(label)
                    .font(.system(size: 16))
                    .foregroundColor(Theme.foreground)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SearchView(navigationPath: .constant(NavigationPath()))
        .environment(AudioPlayerService())
        .environment(LibraryManager.shared)
}
