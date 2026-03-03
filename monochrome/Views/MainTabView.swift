import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0
    @State private var navigationPath = NavigationPath()
    @State private var playerExpansion: CGFloat = 0
    @State private var dragOffset: CGFloat = 0
    @Environment(AudioPlayerService.self) private var audioPlayer

    private let fullScreenH = UIScreen.main.bounds.height

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack(alignment: .bottom) {
                // Tab content — fills entire screen, scrolls behind bar
                Group {
                    switch selectedTab {
                    case 0: HomeView(navigationPath: $navigationPath)
                    case 1: LibraryView(navigationPath: $navigationPath)
                    default: HomeView(navigationPath: $navigationPath)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Glassmorphic bottom bar (mini player + tabs)
                VStack(spacing: 0) {
                    if audioPlayer.currentTrack != nil {
                        MiniPlayerView(expansion: $playerExpansion)
                            .opacity(playerExpansion > 0 ? 0 : 1)
                            .allowsHitTesting(playerExpansion == 0)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    HStack {
                        TabBarButton(icon: "house.fill", label: "Home", isSelected: selectedTab == 0) { selectedTab = 0 }
                        TabBarButton(icon: "books.vertical.fill", label: "Library", isSelected: selectedTab == 1) { selectedTab = 1 }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, -15)
                }
                .padding(.bottom, -15)
                .background(.ultraThinMaterial)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 0.5)
                }

                // Full-screen player overlay
                if audioPlayer.currentTrack != nil && playerExpansion > 0 {
                    let effectiveExp = max(0, min(1,
                        playerExpansion - (dragOffset / fullScreenH)
                    ))
                    let yOffset = (1 - effectiveExp) * fullScreenH

                    NowPlayingView(expansion: $playerExpansion)
                        .offset(y: yOffset)
                        .allowsHitTesting(effectiveExp > 0.3)
                        .gesture(closeDragGesture)
                        .transition(.identity)
                        .ignoresSafeArea()
                }
            }
            .background(Theme.background)
            .navigationBarHidden(true)
            .navigationDestination(for: Artist.self) { artist in
                ArtistDetailView(artist: artist, navigationPath: $navigationPath)
            }
        }
        .preferredColorScheme(.dark)
        .ignoresSafeArea()
    }

    // MARK: - Close drag (drag down from full player)

    private var closeDragGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                dragOffset = max(0, value.translation.height)
            }
            .onEnded { value in
                let velocity = value.predictedEndTranslation.height - value.translation.height
                let dragDown = value.translation.height / fullScreenH

                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                    if dragDown > 0.2 || velocity > 400 {
                        playerExpansion = 0
                    } else {
                        playerExpansion = 1
                    }
                    dragOffset = 0
                }
            }
    }
}

// MARK: - Tab Bar Button

struct TabBarButton: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(isSelected ? Theme.foreground : Theme.mutedForeground)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    MainTabView()
        .environment(AudioPlayerService())
        .environment(LibraryManager.shared)
}
