import SwiftUI

struct MiniPlayerView: View {
    @Binding var expansion: CGFloat
    @Environment(AudioPlayerService.self) private var audioPlayer
    @Environment(LibraryManager.self) private var libraryManager

    @State private var swipeOffset: CGFloat = 0
    @State private var dragAxis: DragAxis = .undecided
    @State private var isDragging = false

    private enum DragAxis { case undecided, horizontal, vertical }

    var body: some View {
        VStack(spacing: 0) {
            // Track content with carousel swipe
            GeometryReader { geo in
                let w = geo.size.width
                ZStack {
                    // Previous track (slides in from left)
                    if let prev = audioPlayer.previousInSession.last {
                        miniTrackRow(title: prev.title, artist: prev.artist?.name ?? "Unknown Artist",
                                     coverUrl: MonochromeAPI().getImageUrl(id: prev.album?.cover))
                            .frame(width: w)
                            .offset(x: -w + max(0, swipeOffset))
                    }

                    // Current track (follows finger)
                    currentTrackRow
                        .frame(width: w)
                        .offset(x: swipeOffset)

                    // Next track (slides in from right)
                    if let next = audioPlayer.queuedTracks.first {
                        miniTrackRow(title: next.title, artist: next.artist?.name ?? "Unknown Artist",
                                     coverUrl: MonochromeAPI().getImageUrl(id: next.album?.cover))
                            .frame(width: w)
                            .offset(x: w + min(0, swipeOffset))
                    }
                }
                .clipped()
            }
            .frame(height: 56)

            // Progress bar
            GeometryReader { geo in
                let progress = audioPlayer.duration > 0 ? (audioPlayer.currentTime / audioPlayer.duration) : 0
                ZStack(alignment: .leading) {
                    Rectangle().fill(Theme.border.opacity(0.3))
                    Rectangle().fill(Theme.foreground)
                        .frame(width: max(0, geo.size.width * progress))
                }
            }
            .frame(height: 2)
        }
        .background(Theme.secondary.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .gesture(
            DragGesture(minimumDistance: 5)
                .onChanged { value in
                    isDragging = true
                    let dx = abs(value.translation.width)
                    let dy = abs(value.translation.height)

                    // Lock direction early
                    if dragAxis == .undecided && (dx > 5 || dy > 5) {
                        dragAxis = dx > dy ? .horizontal : .vertical
                    }

                    switch dragAxis {
                    case .horizontal:
                        let raw = value.translation.width
                        // Block swipe if no track in that direction
                        if raw > 0 && !audioPlayer.hasPreviousTrack {
                            swipeOffset = 0
                        } else if raw < 0 && !audioPlayer.hasNextTrack {
                            swipeOffset = 0
                        } else {
                            swipeOffset = raw
                        }
                    case .vertical:
                        break // Handled by global swipe gesture
                    case .undecided:
                        break
                    }
                }
                .onEnded { value in
                    let lockedAxis = dragAxis
                    dragAxis = .undecided

                    // Delay resetting isDragging so tap doesn't fire
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isDragging = false
                    }

                    if lockedAxis == .horizontal {
                        let dx = value.translation.width
                        let screenW = UIScreen.main.bounds.width
                        let hasPrev = audioPlayer.hasPreviousTrack
                        let hasNext = audioPlayer.hasNextTrack

                        // Confirm if dragged past 40%
                        let goNext = dx < 0 && hasNext && abs(dx) > screenW * 0.4
                        let goPrev = dx > 0 && hasPrev && abs(dx) > screenW * 0.4

                        if goNext || goPrev {
                            let target: CGFloat = goNext ? -screenW : screenW

                            withAnimation(.easeOut(duration: 0.18)) {
                                swipeOffset = target
                            }

                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                                // Disable animation so offset reset + track change happen in one frame
                                var transaction = Transaction()
                                transaction.disablesAnimations = true
                                withTransaction(transaction) {
                                    if goNext { audioPlayer.nextTrack() }
                                    else { audioPlayer.previousTrack() }
                                    swipeOffset = 0
                                }
                            }
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                swipeOffset = 0
                            }
                        }
                    } else if lockedAxis == .vertical {
                        // Handled by global swipe gesture
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            swipeOffset = 0
                        }
                    }
                }
        )
    }

    // MARK: - Current track row (with buttons)

    private var currentTrackRow: some View {
        HStack(spacing: 10) {
            CachedAsyncImage(url: audioPlayer.currentCoverUrl) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    RoundedRectangle(cornerRadius: 4).fill(Theme.card)
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 1) {
                Text(audioPlayer.currentTrackTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.foreground)
                    .lineLimit(1)
                Text(audioPlayer.currentArtistName)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.mutedForeground)
                    .lineLimit(1)
            }

            Spacer()

            if let track = audioPlayer.currentTrack {
                Button(action: { libraryManager.toggleFavorite(track: track) }) {
                    Image(systemName: libraryManager.isFavorite(trackId: track.id) ? "heart.fill" : "heart")
                        .font(.system(size: 18))
                        .foregroundColor(libraryManager.isFavorite(trackId: track.id) ? Theme.foreground : Theme.mutedForeground)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
            }

            Button(action: { audioPlayer.togglePlayPause() }) {
                Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20))
                    .foregroundColor(Theme.foreground)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isDragging else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                expansion = 1
            }
        }
    }

    // MARK: - Preview row for next/previous track

    private func miniTrackRow(title: String, artist: String, coverUrl: URL?) -> some View {
        HStack(spacing: 10) {
            CachedAsyncImage(url: coverUrl) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    RoundedRectangle(cornerRadius: 4).fill(Theme.card)
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.foreground)
                    .lineLimit(1)
                Text(artist)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.mutedForeground)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
