import SwiftUI

struct QueueSheetView: View {
    @Environment(AudioPlayerService.self) private var audioPlayer
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 1 // 0 = Previous, 1 = Queue
    @State private var editMode: EditMode = .inactive

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab bar
                HStack(spacing: 0) {
                    tabButton("Previous", tab: 0)
                    tabButton("Queue", tab: 1)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

                // Swipeable pages
                TabView(selection: $selectedTab) {
                    previousPage.tag(0)
                    queuePage.tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .background(Theme.background)
            .navigationTitle("Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.background)
        .onChange(of: selectedTab) {
            if selectedTab != 1 && editMode == .active {
                withAnimation { editMode = .inactive }
            }
        }
    }

    private func tabButton(_ title: String, tab: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) { selectedTab = tab }
        } label: {
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(selectedTab == tab ? .white : .white.opacity(0.35))
                Rectangle()
                    .fill(selectedTab == tab ? .white : .clear)
                    .frame(height: 2)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Previous Page

    private var previousPage: some View {
        Group {
            if audioPlayer.previousInSession.isEmpty {
                VStack {
                    Spacer()
                    Text("No previous tracks")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.3))
                    Spacer()
                }
            } else {
                List {
                    ForEach(audioPlayer.previousInSession.reversed()) { track in
                        trackRow(
                            title: track.title,
                            artist: track.artist?.name ?? "Unknown Artist",
                            coverUrl: MonochromeAPI().getImageUrl(id: track.album?.cover, size: 80),
                            duration: track.duration,
                            isPlaying: false,
                            audioQuality: track.audioQuality,
                            mediaTags: track.mediaMetadata?.tags
                        )
                        .listRowBackground(Theme.background)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    // MARK: - Queue Page

    private var queuePage: some View {
        List {
            // Now Playing
            if let current = audioPlayer.currentTrack {
                Section {
                    trackRow(
                        title: current.title,
                        artist: current.artist?.name ?? "Unknown Artist",
                        coverUrl: MonochromeAPI().getImageUrl(id: current.album?.cover, size: 80),
                        duration: current.duration,
                        isPlaying: true,
                        audioQuality: current.audioQuality,
                        mediaTags: current.mediaMetadata?.tags
                    )
                    .listRowBackground(Color.white.opacity(0.05))
                } header: {
                    Text("Now Playing")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                        .textCase(nil)
                }
            }

            // Next Up
            if !audioPlayer.queuedTracks.isEmpty {
                Section {
                    ForEach(Array(audioPlayer.queuedTracks.enumerated()), id: \.element.id) { index, track in
                        trackRow(
                            title: track.title,
                            artist: track.artist?.name ?? "Unknown Artist",
                            coverUrl: MonochromeAPI().getImageUrl(id: track.album?.cover, size: 80),
                            duration: track.duration,
                            isPlaying: false,
                            audioQuality: track.audioQuality,
                            mediaTags: track.mediaMetadata?.tags
                        )
                        .listRowBackground(Theme.background)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                audioPlayer.removeFromQueue(at: index)
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets.sorted().reversed() {
                            audioPlayer.removeFromQueue(at: index)
                        }
                    }
                    .onMove { source, destination in
                        audioPlayer.moveInQueue(from: source, to: destination)
                    }
                } header: {
                    HStack {
                        Text("Next Up")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.6))
                            .textCase(nil)
                        Spacer()
                        Text("\(audioPlayer.queuedTracks.count) track\(audioPlayer.queuedTracks.count > 1 ? "s" : "")")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.3))
                        Button {
                            withAnimation { editMode = editMode == .active ? .inactive : .active }
                        } label: {
                            Image(systemName: editMode == .active ? "checkmark" : "pencil")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, $editMode)
    }

    // MARK: - Row

    private func trackRow(title: String, artist: String, coverUrl: URL?, duration: Int, isPlaying: Bool, audioQuality: String? = nil, mediaTags: [String]? = nil) -> some View {
        HStack(spacing: 12) {
            CachedAsyncImage(url: coverUrl) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.card)
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(title)
                        .font(.system(size: 15, weight: isPlaying ? .semibold : .regular))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    QualityBadge(audioQuality: audioQuality, mediaTags: mediaTags)
                }
                Text(artist)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
            }

            Spacer()

            Text(formatDuration(duration))
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.white.opacity(0.3))
        }
        .padding(.vertical, 4)
    }

    private func formatDuration(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
