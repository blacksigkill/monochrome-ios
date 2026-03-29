import SwiftUI

@main
struct MonochromeIOSApp: App {
    @StateObject private var audioPlayerService = AudioPlayerService()
    @StateObject private var libraryManager = LibraryManager.shared
    @StateObject private var authService = AuthService.shared
    @StateObject private var playlistManager = PlaylistManager.shared
    @StateObject private var profileManager = ProfileManager.shared
    @StateObject private var downloadManager = DownloadManager.shared
    @StateObject private var tabRouter = TabRouter()
    @State private var syncTimer: Timer?

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(audioPlayerService)
                .environmentObject(audioPlayerService.playbackProgress)
                .environmentObject(libraryManager)
                .environmentObject(authService)
                .environmentObject(playlistManager)
                .environmentObject(profileManager)
                .environmentObject(downloadManager)
                .environmentObject(tabRouter)
                .onAppear {
                    triggerSyncIfNeeded()
                    startPeriodicSync()
                }
                .onChange(of: authService.isAuthenticated) { isAuthenticated in
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
            await audioPlayerService.syncHistoryFromCloud(uid: uid)
        }
    }

    private func startPeriodicSync() {
        syncTimer?.invalidate()
        syncTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            triggerSyncIfNeeded()
        }
    }

}
