import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0
    @State private var homePath = NavigationPath()
    @State private var searchPath = NavigationPath()
    @State private var libraryPath = NavigationPath()
    @State private var profilePath = NavigationPath()
    @State private var playerExpansion: CGFloat = 0
    @State private var dragOffset: CGFloat = 0
    @Environment(AudioPlayerService.self) private var audioPlayer

    private let fullScreenH = UIScreen.main.bounds.height

    private var activeNavigationPath: Binding<NavigationPath> {
        switch selectedTab {
        case 0: return $homePath
        case 1: return $searchPath
        case 2: return $libraryPath
        case 3: return $profilePath
        default: return $homePath
        }
    }

    var body: some View {
        ZStack {
            if #available(iOS 26.0, *) {
                nativeTabView
            } else {
                legacyTabView
            }

            // Full-screen player overlay (always in hierarchy for smooth animation)
            if audioPlayer.currentTrack != nil {
                let effectiveExp = max(0, min(1,
                    playerExpansion - (dragOffset / fullScreenH)
                ))
                let yOffset = (1 - effectiveExp) * fullScreenH

                NowPlayingView(expansion: $playerExpansion, navigationPath: activeNavigationPath)
                    .offset(y: yOffset)
                    .allowsHitTesting(effectiveExp > 0.3)
                    .gesture(closeDragGesture)
                    .transition(.identity)
                    .ignoresSafeArea()
            }
            
        }
        .preferredColorScheme(.dark)
        .background {
            if audioPlayer.currentTrack != nil {
                GlobalSwipeUpHandler(expansion: $playerExpansion)
            }
        }
    }

    // MARK: - iOS 26+ Native Liquid Glass TabView

    @available(iOS 26.0, *)
    private var nativeTabView: some View {
        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "house.fill", value: 0) {
                NavigationStack(path: $homePath) {
                    HomeView(navigationPath: $homePath)
                        .navigationBarHidden(true)
                        .navigationDestination(for: Artist.self) { artist in
                            ArtistDetailView(artist: artist, navigationPath: $homePath)
                        }
                        .navigationDestination(for: Album.self) { album in
                            AlbumDetailView(album: album, navigationPath: $homePath)
                        }
                }
            }

            Tab("Search", systemImage: "magnifyingglass", value: 1) {
                NavigationStack(path: $searchPath) {
                    SearchView(navigationPath: $searchPath)
                        .navigationBarHidden(true)
                        .navigationDestination(for: Artist.self) { artist in
                            ArtistDetailView(artist: artist, navigationPath: $searchPath)
                        }
                        .navigationDestination(for: Album.self) { album in
                            AlbumDetailView(album: album, navigationPath: $searchPath)
                        }
                }
                .ignoresSafeArea(.keyboard)
            }

            Tab("Library", systemImage: "books.vertical.fill", value: 2) {
                NavigationStack(path: $libraryPath) {
                    LibraryView(navigationPath: $libraryPath)
                        .navigationBarHidden(true)
                        .navigationDestination(for: Artist.self) { artist in
                            ArtistDetailView(artist: artist, navigationPath: $libraryPath)
                        }
                        .navigationDestination(for: Album.self) { album in
                            AlbumDetailView(album: album, navigationPath: $libraryPath)
                        }
                }
            }

            Tab("Profile", systemImage: "person.fill", value: 3) {
                NavigationStack(path: $profilePath) {
                    ProfileView(navigationPath: $profilePath)
                        .navigationBarHidden(true)
                        .navigationDestination(for: Artist.self) { artist in
                            ArtistDetailView(artist: artist, navigationPath: $profilePath)
                        }
                        .navigationDestination(for: Album.self) { album in
                            AlbumDetailView(album: album, navigationPath: $profilePath)
                        }
                }
            }
        }
        .tabViewBottomAccessory {
            if audioPlayer.currentTrack != nil {
                MiniPlayerView(expansion: $playerExpansion)
                    .opacity(playerExpansion > 0 ? 0 : 1)
                    .allowsHitTesting(playerExpansion == 0)
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    // MARK: - Legacy Tab View (iOS < 26)

    private var legacyTabView: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                legacyNavStack(path: $homePath) { HomeView(navigationPath: $homePath) }
                    .opacity(selectedTab == 0 ? 1 : 0)
                    .allowsHitTesting(selectedTab == 0)

                legacyNavStack(path: $searchPath) { SearchView(navigationPath: $searchPath) }
                    .opacity(selectedTab == 1 ? 1 : 0)
                    .allowsHitTesting(selectedTab == 1)

                legacyNavStack(path: $libraryPath) { LibraryView(navigationPath: $libraryPath) }
                    .opacity(selectedTab == 2 ? 1 : 0)
                    .allowsHitTesting(selectedTab == 2)

                legacyNavStack(path: $profilePath) { ProfileView(navigationPath: $profilePath) }
                    .opacity(selectedTab == 3 ? 1 : 0)
                    .allowsHitTesting(selectedTab == 3)
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)

            VStack(spacing: 6) {
                if audioPlayer.currentTrack != nil {
                    MiniPlayerView(expansion: $playerExpansion)
                        .opacity(playerExpansion > 0 ? 0 : 1)
                        .allowsHitTesting(playerExpansion == 0)
                }

                HStack(spacing: 0) {
                    TabBarButton(icon: "house.fill", label: "Home", isSelected: selectedTab == 0) { selectedTab = 0 }
                    TabBarButton(icon: "magnifyingglass", label: "Search", isSelected: selectedTab == 1) { selectedTab = 1 }
                    TabBarButton(icon: "books.vertical.fill", label: "Library", isSelected: selectedTab == 2) { selectedTab = 2 }
                    TabBarButton(icon: "person.fill", label: "Profile", isSelected: selectedTab == 3) { selectedTab = 3 }
                }
                .padding(.top, 10)
                .padding(.bottom, 8)
                .padding(.horizontal, 8)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 5)
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .ignoresSafeArea()
    }

    private func legacyNavStack<Content: View>(path: Binding<NavigationPath>, @ViewBuilder content: () -> Content) -> some View {
        NavigationStack(path: path) {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.background)
                .navigationBarHidden(true)
                .navigationDestination(for: Artist.self) { artist in
                    ArtistDetailView(artist: artist, navigationPath: path)
                }
                .navigationDestination(for: Album.self) { album in
                    AlbumDetailView(album: album, navigationPath: path)
                }
        }
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

// MARK: - Global Swipe-Up Gesture (UIKit window-level, bypasses all SwiftUI gesture blocking)

private struct GlobalSwipeUpHandler: UIViewRepresentable {
    @Binding var expansion: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(expansion: $expansion)
    }

    func makeUIView(context: Context) -> GestureInstallerView {
        let view = GestureInstallerView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: GestureInstallerView, context: Context) {
        context.coordinator.expansionBinding = $expansion
    }

    static func dismantleUIView(_ uiView: GestureInstallerView, coordinator: Coordinator) {
        coordinator.removeGesture()
    }

    class GestureInstallerView: UIView {
        weak var coordinator: Coordinator?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let window = window {
                coordinator?.installGesture(in: window)
            } else {
                coordinator?.removeGesture()
            }
        }
    }

    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var expansionBinding: Binding<CGFloat>
        private var panGesture: UIPanGestureRecognizer?

        init(expansion: Binding<CGFloat>) {
            self.expansionBinding = expansion
        }

        func installGesture(in window: UIWindow) {
            guard panGesture == nil else { return }
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.delegate = self
            window.addGestureRecognizer(pan)
            panGesture = pan
        }

        func removeGesture() {
            if let pan = panGesture {
                pan.view?.removeGestureRecognizer(pan)
                panGesture = nil
            }
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let window = gesture.view else { return }
            let translation = gesture.translation(in: window)
            let velocity = gesture.velocity(in: window)
            let screenH = UIScreen.main.bounds.height

            switch gesture.state {
            case .changed:
                let progress = -translation.y / screenH
                expansionBinding.wrappedValue = max(0, min(1, progress))
            case .ended, .cancelled:
                let progress = -translation.y / screenH
                let upVelocity = -velocity.y

                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                    if progress > 0.15 || upVelocity > 500 {
                        expansionBinding.wrappedValue = 1
                    } else {
                        expansionBinding.wrappedValue = 0
                    }
                }
            default:
                break
            }
        }

        // MARK: UIGestureRecognizerDelegate

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            guard expansionBinding.wrappedValue == 0 else { return false }

            let velocity = pan.velocity(in: pan.view)
            let location = pan.location(in: pan.view)
            let screenH = UIScreen.main.bounds.height

            let isVertical = abs(velocity.y) > abs(velocity.x)
            let isUpward = velocity.y < 0
            // Only activate in mini player + tab bar area (~120pt from bottom)
            let isInBottomArea = location.y > screenH - 120

            return isVertical && isUpward && isInBottomArea
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            return true
        }
    }
}

#Preview {
    MainTabView()
        .environment(AudioPlayerService())
        .environment(LibraryManager.shared)
}
