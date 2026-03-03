import SwiftUI

struct NowPlayingView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(AudioPlayerService.self) private var audioPlayer
    @Environment(LibraryManager.self) private var libraryManager

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background layers - ignore safe area
                backgroundLayer
                Color.black.opacity(0.25).ignoresSafeArea()

                // Content - respects safe area
                let artSize = min(geo.size.width - 56, geo.size.height * 0.38)

                VStack(spacing: 0) {
                    // Top bar
                    topBar
                        .padding(.top, 8)

                    Spacer(minLength: 12)

                    // Album art - constrained size
                    albumArt(size: artSize)

                    Spacer(minLength: 20).frame(maxHeight: 32)

                    // Track info + progress + controls
                    VStack(spacing: 20) {
                        trackInfo
                        progressBar
                        controls
                    }

                    Spacer(minLength: 8)

                    // Queue info
                    queueInfo
                        .padding(.bottom, 8)
                }
                .padding(.horizontal, 28)
            }
        }
        .preferredColorScheme(.dark)
        .gesture(
            DragGesture()
                .onEnded { value in
                    if value.translation.height > 120 { dismiss() }
                }
        )
    }

    // MARK: - Background

    private var backgroundLayer: some View {
        Group {
            if let coverUrl = audioPlayer.currentCoverUrl {
                AsyncImage(url: coverUrl) { phase in
                    if let image = phase.image {
                        image.resizable()
                             .aspectRatio(contentMode: .fill)
                             .blur(radius: 80)
                             .brightness(-0.4)
                             .scaleEffect(1.5)
                    } else {
                        Theme.background
                    }
                }
            } else {
                Theme.background
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 44, height: 44)
            }

            Spacer()

            VStack(spacing: 2) {
                Text("NOW PLAYING")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                    .tracking(1)
                if let album = audioPlayer.currentTrack?.album?.title {
                    Text(album)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(1)
                }
            }

            Spacer()

            Button(action: {}) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 44, height: 44)
            }
        }
    }

    // MARK: - Album Art

    private func albumArt(size: CGFloat) -> some View {
        AsyncImage(url: audioPlayer.currentCoverUrl) { phase in
            if let image = phase.image {
                image.resizable()
                     .aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.card)
                    .aspectRatio(1, contentMode: .fit)
            }
        }
        .frame(maxWidth: size, maxHeight: size)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.5), radius: 30, y: 15)
    }

    // MARK: - Track Info

    private var trackInfo: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(audioPlayer.currentTrackTitle)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(audioPlayer.currentArtistName)
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let track = audioPlayer.currentTrack {
                Button(action: { libraryManager.toggleFavorite(track: track) }) {
                    Image(systemName: libraryManager.isFavorite(trackId: track.id) ? "heart.fill" : "heart")
                        .font(.system(size: 22))
                        .foregroundColor(libraryManager.isFavorite(trackId: track.id) ? .white : .white.opacity(0.5))
                }
                .frame(width: 44, height: 44)
            }
        }
    }

    // MARK: - Progress

    private var progressBar: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(
                    get: { audioPlayer.currentTime },
                    set: { audioPlayer.seek(to: $0) }
                ),
                in: 0...(audioPlayer.duration > 0 ? audioPlayer.duration : 1)
            )
            .tint(.white)

            HStack {
                Text(formatTime(audioPlayer.currentTime))
                Spacer()
                Text("-" + formatTime(max(0, audioPlayer.duration - audioPlayer.currentTime)))
            }
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundColor(.white.opacity(0.5))
        }
    }

    // MARK: - Controls

    private var controls: some View {
        HStack {
            Spacer()

            Button(action: { audioPlayer.previousTrack() }) {
                Image(systemName: "backward.fill")
                    .font(.system(size: 28))
                    .foregroundColor(audioPlayer.hasPreviousTrack ? .white : .white.opacity(0.3))
            }

            Spacer()

            Button(action: { audioPlayer.togglePlayPause() }) {
                ZStack {
                    Circle().fill(.white).frame(width: 64, height: 64)
                    Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 26))
                        .foregroundColor(.black)
                        .offset(x: audioPlayer.isPlaying ? 0 : 2)
                }
            }

            Spacer()

            Button(action: { audioPlayer.nextTrack() }) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 28))
                    .foregroundColor(audioPlayer.hasNextTrack ? .white : .white.opacity(0.3))
            }

            Spacer()
        }
    }

    // MARK: - Queue Info

    private var queueInfo: some View {
        Group {
            if !audioPlayer.queuedTracks.isEmpty {
                Text("\(audioPlayer.queuedTracks.count) track\(audioPlayer.queuedTracks.count > 1 ? "s" : "") in queue")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        guard time > 0 && !time.isNaN else { return "0:00" }
        let m = Int(time) / 60
        let s = Int(time) % 60
        return String(format: "%d:%02d", m, s)
    }
}
