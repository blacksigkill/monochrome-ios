import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0
    @State private var navigationPath = NavigationPath()
    @Environment(AudioPlayerService.self) private var audioPlayer

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack(alignment: .bottom) {
                // Content area
                VStack(spacing: 0) {
                    // Page content
                    Group {
                        switch selectedTab {
                        case 0: HomeView(navigationPath: $navigationPath)
                        case 1: SearchView(navigationPath: $navigationPath)
                        case 2: LibraryView(navigationPath: $navigationPath)
                        default: HomeView(navigationPath: $navigationPath)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Mini player + Tab bar spacer
                    VStack(spacing: 0) {
                        if audioPlayer.currentTrack != nil {
                            MiniPlayerView()
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }

                        // Custom tab bar
                        HStack {
                            TabBarButton(icon: "house.fill", label: "Home", isSelected: selectedTab == 0) { selectedTab = 0 }
                            TabBarButton(icon: "magnifyingglass", label: "Search", isSelected: selectedTab == 1) { selectedTab = 1 }
                            TabBarButton(icon: "books.vertical.fill", label: "Library", isSelected: selectedTab == 2) { selectedTab = 2 }
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                        .background(
                            LinearGradient(
                                colors: [Theme.background, Theme.background.opacity(0.98)],
                                startPoint: .bottom, endPoint: .top
                            )
                        )
                    }
                }
            }
            .background(Theme.background)
            .navigationBarHidden(true)
            .navigationDestination(for: Artist.self) { artist in
                ArtistDetailView(artist: artist, navigationPath: $navigationPath)
            }
        }
        .preferredColorScheme(.dark)
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
