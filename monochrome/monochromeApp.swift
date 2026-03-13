import SwiftUI
import AVFoundation

@main
struct MonochromeIOSApp: App {
    @State private var audioPlayerService = AudioPlayerService()
    @State private var libraryManager = LibraryManager.shared
    @State private var authService = AuthService.shared
    @State private var playlistManager = PlaylistManager.shared
    @State private var profileManager = ProfileManager.shared
    @State private var downloadManager = DownloadManager.shared
    @State private var syncTimer: Timer?

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(audioPlayerService)
                .environment(libraryManager)
                .environment(authService)
                .environment(playlistManager)
                .environment(profileManager)
                .environment(downloadManager)
                .onAppear {
                    setupAudioSession()
                    triggerSyncIfNeeded()
                    startPeriodicSync()
                }
                .onChange(of: authService.isAuthenticated) { _, isAuthenticated in
                    if isAuthenticated {
                        triggerSyncIfNeeded()
                    } else {
                        PocketBaseService.shared.clearCache()
                        profileManager.clear()
                    }
                }
        }
    }

    private func triggerSyncIfNeeded() {
        guard let uid = authService.currentUser?.uid else { return }
        Task {
            await libraryManager.syncFromCloud(uid: uid)
            await playlistManager.syncFromCloud(uid: uid)
            await profileManager.syncFromCloud(uid: uid)
        }
    }

    private func startPeriodicSync() {
        syncTimer?.invalidate()
        syncTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            triggerSyncIfNeeded()
        }
    }

    private func setupAudioSession() {
#if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
            print("AVAudioSession configured for playback.")
        } catch {
            print("Failed to set up AVAudioSession: \(error.localizedDescription)")
        }
#endif
    }
}
