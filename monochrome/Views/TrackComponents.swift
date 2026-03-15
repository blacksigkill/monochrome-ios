import SwiftUI

struct TrackRow: View {
    let track: Track
    let queue: [Track]
    var previousTracks: [Track] = []
    var showCover: Bool = true
    var showIndex: Int? = nil
    @Binding var navigationPath: NavigationPath
    @Environment(AudioPlayerService.self) private var audioPlayer
    @Environment(LibraryManager.self) private var libraryManager
    @Environment(DownloadManager.self) private var downloadManager
    @State private var showOptions = false
    @State private var confirmationMessage: String? = nil
    
    private var isCurrentTrack: Bool {
        audioPlayer.currentTrack?.id == track.id
    }

    var body: some View {
        HStack(spacing: 12) {
            // Index or cover
            if let index = showIndex {
                Text("\(index)")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(isCurrentTrack ? Theme.highlight : Theme.mutedForeground)
                    .frame(width: 28, alignment: .center)
            } else if showCover {
                CachedAsyncImage(url: MonochromeAPI().getImageUrl(id: track.album?.cover)) { phase in
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
                HStack(spacing: 5) {
                    Text(track.title)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(isCurrentTrack ? Theme.highlight : Theme.foreground)
                        .lineLimit(1)

                    QualityBadge(audioQuality: track.audioQuality, mediaTags: track.mediaMetadata?.tags)
                }

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

            // Download indicator
            if downloadManager.isDownloaded(track.id) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.highlight)
            } else if downloadManager.isDownloading(track.id) {
                ProgressView(value: downloadManager.progress(for: track.id))
                    .progressViewStyle(.circular)
                    .scaleEffect(0.8)
            }

            // Feedback or Context menu button
            if let message = confirmationMessage {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                    Text(message)
                }
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(message.contains("Queue") ? Color.green : Color.blue)
                .clipShape(Capsule())
                .transition(.scale.combined(with: .opacity))
            } else {
                Button(action: { showOptions = true }) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16))
                        .foregroundColor(Theme.mutedForeground)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.background)
        .contentShape(Rectangle())
        .onTapGesture {
            audioPlayer.play(track: track, queue: queue, previousTracks: previousTracks)
        }
        .onLongPressGesture {
            showOptions = true
        }
        .swipeActions(edge: .leading) {
            Button {
                executeAction(type: "next")
            } label: {
                Label("Play Next", systemImage: "text.insert")
            }
            .tint(.blue)
        }
        .swipeActions(edge: .trailing) {
            Button {
                executeAction(type: "queue")
            } label: {
                Label("Add to Queue", systemImage: "text.append")
            }
            .tint(.green)
        }
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

    private func executeAction(type: String) {
        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        // Perform logic
        if type == "next" {
            audioPlayer.playNext(track: track)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                confirmationMessage = "Next"
            }
        } else {
            audioPlayer.addToQueue(track: track)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                confirmationMessage = "Added"
            }
        }
        
        // Clear feedback after 1.5s
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeOut(duration: 0.2)) {
                confirmationMessage = nil
            }
        }
    }
}

struct TrackOptionsSheet: View {
    let track: Track
    let queue: [Track]
    @Binding var navigationPath: NavigationPath
    @Binding var isPresented: Bool
    @Environment(AudioPlayerService.self) private var audioPlayer
    @Environment(LibraryManager.self) private var libraryManager
    @Environment(DownloadManager.self) private var downloadManager
    @State private var showAddToPlaylist = false

    @ViewBuilder
    private var downloadOptionRow: some View {
        let isDownloaded = downloadManager.isDownloaded(track.id)
        let isDownloading = downloadManager.isDownloading(track.id)

        if isDownloading {
            let progress = downloadManager.progress(for: track.id)
            OptionRow(
                icon: "arrow.down.circle",
                label: "Downloading \(Int(progress * 100))%",
                iconColor: Theme.mutedForeground
            ) {}
        } else if isDownloaded {
            OptionRow(
                icon: "checkmark.circle.fill",
                label: "Downloaded",
                iconColor: Theme.highlight
            ) {
                downloadManager.removeDownload(track.id)
                isPresented = false
            }
        } else {
            OptionRow(icon: "arrow.down.circle", label: "Download") {
                downloadManager.downloadTrack(track)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Track header
            HStack(spacing: 14) {
                CachedAsyncImage(url: MonochromeAPI().getImageUrl(id: track.album?.cover)) { phase in
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

                    // Add to playlist
                    OptionRow(icon: "text.badge.plus", label: "Add to playlist") {
                        showAddToPlaylist = true
                    }

                    // Play next
                    OptionRow(icon: "text.line.first.and.arrowtriangle.forward", label: "Play next") {
                        audioPlayer.playNext(track: track)
                        isPresented = false
                    }

                    // Add to queue
                    OptionRow(icon: "text.line.last.and.arrowtriangle.forward", label: "Add to queue") {
                        audioPlayer.addToQueue(track: track)
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

                    // Go to album
                    if let album = track.album {
                        OptionRow(icon: "square.stack", label: "Go to album") {
                            isPresented = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                navigationPath.append(album)
                            }
                        }
                    }

                    // Download
                    downloadOptionRow

                    // Share
                    OptionRow(icon: "square.and.arrow.up", label: "Share") {
                        isPresented = false
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .sheet(isPresented: $showAddToPlaylist) {
            AddToPlaylistSheet(track: track, isPresented: $showAddToPlaylist)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(Theme.card)
        }
    }
}

struct AddToPlaylistSheet: View {
    let track: Track
    @Binding var isPresented: Bool
    @Environment(PlaylistManager.self) private var playlistManager
    @State private var showCreateNew = false
    @State private var newName = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add to Playlist")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Theme.foreground)
                Spacer()
                Button {
                    newName = ""
                    showCreateNew = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(Theme.foreground)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider().overlay(Theme.border)

            if playlistManager.userPlaylists.isEmpty {
                VStack(spacing: 12) {
                    Text("No playlists yet")
                        .font(.system(size: 15))
                        .foregroundColor(Theme.mutedForeground)
                    Button("Create Playlist") {
                        newName = ""
                        showCreateNew = true
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.foreground)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(playlistManager.userPlaylists) { playlist in
                            let alreadyAdded = playlist.tracks.contains { $0.id == track.id }
                            Button {
                                if !alreadyAdded {
                                    playlistManager.addTrack(track, to: playlist.id)
                                }
                                isPresented = false
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "music.note.list")
                                        .font(.system(size: 16))
                                        .foregroundColor(Theme.mutedForeground)
                                        .frame(width: 36, height: 36)
                                        .background(Theme.secondary)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(playlist.name)
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundColor(Theme.foreground)
                                            .lineLimit(1)
                                        Text("\(playlist.numberOfTracks) tracks")
                                            .font(.system(size: 12))
                                            .foregroundColor(Theme.mutedForeground)
                                    }

                                    Spacer()

                                    if alreadyAdded {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(Theme.mutedForeground)
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(alreadyAdded)
                        }
                    }
                }
            }
        }
        .alert("New Playlist", isPresented: $showCreateNew) {
            TextField("Playlist name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                let p = playlistManager.createPlaylist(name: name)
                playlistManager.addTrack(track, to: p.id)
                isPresented = false
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

// MARK: - Quality Badge

struct QualityBadge: View {
    let audioQuality: String?
    var mediaTags: [String]? = nil

    private static let qualityLevel: [String: Int] = [
        "LOW": 0, "MEDIUM": 1, "HIGH": 2, "LOSSLESS": 3,
        "HI_RES_LOSSLESS": 4, "HI_RES": 4, "HIRES_LOSSLESS": 4, "HIRES": 4
    ]

    private static let labels = ["128k", "256k", "320k", "Lossless", "Hi-Res"]

    private static let hiResTags: Set<String> = [
        "HIRES_LOSSLESS", "HI_RES_LOSSLESS", "HIRES", "HI_RES"
    ]

    private var effectiveLabel: String? {
        guard SettingsManager.shared.showTrackQuality,
              let trackQ = audioQuality,
              let trackLevel = Self.qualityLevel[trackQ] else { return nil }

        let normalizedTags = Set((mediaTags ?? []).map { $0.uppercased() })

        // Dolby Atmos reports audioQuality "LOW" but is actually high quality spatial audio
        if normalizedTags.contains("DOLBY_ATMOS") {
            return "Atmos"
        }

        let streamLevel = Self.qualityLevel[SettingsManager.shared.streamQuality.rawValue] ?? 2
        let isHiResTagged = !normalizedTags.isEmpty && !Self.hiResTags.isDisjoint(with: normalizedTags)
        let hiResLevel = Self.qualityLevel["HI_RES_LOSSLESS"] ?? trackLevel
        let effectiveTrackLevel = isHiResTagged ? max(trackLevel, hiResLevel) : trackLevel
        return Self.labels[min(effectiveTrackLevel, streamLevel)]
    }

    var body: some View {
        if let label = effectiveLabel {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(Theme.background)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Theme.mutedForeground.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
    }
}
