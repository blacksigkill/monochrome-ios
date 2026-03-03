import SwiftUI

struct NowPlayingView: View {
    @Binding var expansion: CGFloat

    @Environment(AudioPlayerService.self) private var audioPlayer
    @Environment(LibraryManager.self) private var libraryManager

    // Real screen dimensions — always correct regardless of view hierarchy
    private let screenW = UIScreen.main.bounds.width
    private let screenH = UIScreen.main.bounds.height
    private var safeT: CGFloat {
        (UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .compactMap { $0.keyWindow }
            .first?.safeAreaInsets.top) ?? 59
    }
    private var safeB: CGFloat {
        (UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .compactMap { $0.keyWindow }
            .first?.safeAreaInsets.bottom) ?? 34
    }

    var body: some View {
        let usable = screenH - safeT - safeB
        let padX: CGFloat = 24
        // Art: 42% of usable height, capped at content width
        let artSize = min(screenW - padX * 2, usable * 0.42)

        // Layout budget (% of usable height):
        //   handle  3%  +  topBar  6%  +  gap  2%
        //   art    42%  (or less if width-capped)
        //   gap     3%  +  info   7%  +  gap  1.5%
        //   prog    7%  +  gap    2%  +  ctrl 11%
        //   gap     1%  +  queue  3.5%
        //   TOTAL: 89% → 11% breathing room

        ZStack {
            backgroundLayer

            VStack(spacing: 0) {
                // -- Handle: 3% --
                Capsule()
                    .fill(.white.opacity(0.4))
                    .frame(width: 36, height: 5)
                    .frame(height: usable * 0.03)

                // -- Top bar: 6% --
                topBar
                    .frame(height: usable * 0.06)

                // -- Gap: 2% --
                Color.clear
                    .frame(height: usable * 0.02)

                // -- Album art: 42% (capped at width) --
                albumArt
                    .frame(width: artSize, height: artSize)

                // -- Gap: 3% --
                Color.clear
                    .frame(height: usable * 0.03)

                // -- Track info: 7% --
                trackInfo
                    .frame(height: usable * 0.07)

                // -- Gap: 1.5% --
                Color.clear
                    .frame(height: usable * 0.015)

                // -- Progress: 7% --
                progressBar
                    .frame(height: usable * 0.07)

                // -- Gap: 2% --
                Color.clear
                    .frame(height: usable * 0.02)

                // -- Controls: 11% --
                controls
                    .frame(height: usable * 0.11)

                // -- Gap: 1% --
                Color.clear
                    .frame(height: usable * 0.01)

                // -- Queue: 3.5% --
                queueInfo
                    .frame(height: usable * 0.035)
            }
            .padding(.horizontal, padX)
            .padding(.top, safeT)
            .padding(.bottom, safeB)
        }
        .frame(width: screenW, height: screenH)
        .clipped()
    }

    // MARK: - Background

    private var backgroundLayer: some View {
        ZStack {
            Theme.background
            if let coverUrl = audioPlayer.currentCoverUrl {
                AsyncImage(url: coverUrl) { phase in
                    if let image = phase.image {
                        image.resizable()
                            .aspectRatio(contentMode: .fill)
                            .blur(radius: 80)
                            .brightness(-0.4)
                            .scaleEffect(1.5)
                    }
                }
            }
            Color.black.opacity(0.25)
        }
        .frame(width: screenW, height: screenH)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button(action: {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    expansion = 0
                }
            }) {
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

            Color.clear.frame(width: 44, height: 44)
        }
    }

    // MARK: - Album Art

    private var albumArt: some View {
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
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.5), radius: 30, y: 15)
    }

    // MARK: - Track Info

    private var trackInfo: some View {
        HStack(alignment: .center, spacing: 8) {
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
