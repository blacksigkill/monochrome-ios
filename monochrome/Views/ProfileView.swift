import SwiftUI

struct ProfileView: View {
    @Binding var navigationPath: NavigationPath
    @Environment(AudioPlayerService.self) private var audioPlayer
    @Environment(LibraryManager.self) private var libraryManager
    @Environment(AuthService.self) private var authService
    @State private var showSettings = false
    @State private var showLogin = false
    @State private var isSyncing = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // MARK: - Header
                HStack {
                    Text("Profile")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(Theme.foreground)
                    Spacer()
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 20))
                            .foregroundColor(Theme.foreground)
                            .frame(width: 40, height: 40)
                            .background(Theme.secondary)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)

                // MARK: - Avatar & User Info
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(Theme.secondary)
                            .frame(width: 100, height: 100)
                        if authService.isAuthenticated {
                            Text(avatarInitial)
                                .font(.system(size: 36, weight: .bold))
                                .foregroundColor(Theme.foreground)
                        } else {
                            Image(systemName: "person.fill")
                                .font(.system(size: 40))
                                .foregroundColor(Theme.mutedForeground)
                        }
                    }

                    VStack(spacing: 4) {
                        if let user = authService.currentUser {
                            Text(user.name ?? user.email)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(Theme.foreground)
                            if user.name != nil {
                                Text(user.email)
                                    .font(.system(size: 14))
                                    .foregroundColor(Theme.mutedForeground)
                            }
                        } else {
                            Text("Guest")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(Theme.foreground)
                            Text("Sign in to sync your library")
                                .font(.system(size: 14))
                                .foregroundColor(Theme.mutedForeground)
                        }
                    }
                }
                .padding(.bottom, 32)

                // MARK: - Sign In / Sign Out Buttons
                if authService.isAuthenticated {
                    VStack(spacing: 12) {
                        // Sync button
                        Button {
                            Task { await syncLibrary() }
                        } label: {
                            HStack(spacing: 12) {
                                if isSyncing {
                                    ProgressView()
                                        .tint(Theme.foreground)
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .font(.system(size: 18))
                                }
                                Text(isSyncing ? "Syncing..." : "Sync Library")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .foregroundColor(Theme.foreground)
                            .background(Theme.secondary)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLg))
                        }
                        .buttonStyle(.plain)
                        .disabled(isSyncing)

                        // Sign out button
                        Button {
                            Task { await authService.signOut() }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                    .font(.system(size: 18))
                                Text("Sign Out")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .foregroundColor(.red)
                            .background(Theme.secondary)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLg))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                } else {
                    VStack(spacing: 12) {
                        SignInButton(
                            icon: "envelope.fill",
                            label: "Sign In / Create Account",
                            style: .primary
                        ) {
                            showLogin = true
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                }

                // MARK: - Stats
                VStack(spacing: 0) {
                    HStack {
                        Text("Your Activity")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(Theme.foreground)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)

                    HStack(spacing: 12) {
                        StatCard(
                            icon: "heart.fill",
                            value: "\(libraryManager.favoriteTracks.count)",
                            label: "Favorites"
                        )
                        StatCard(
                            icon: "music.note.list",
                            value: "\(audioPlayer.playHistory.count)",
                            label: "Listened"
                        )
                        StatCard(
                            icon: "clock.fill",
                            value: listeningTime,
                            label: "Minutes"
                        )
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 40)

                // MARK: - Quick Links
                VStack(spacing: 0) {
                    ProfileLink(icon: "heart.fill", title: "Favorite Tracks", subtitle: "\(libraryManager.favoriteTracks.count) tracks")
                    ProfileLink(icon: "clock.arrow.circlepath", title: "Listening History", subtitle: "\(audioPlayer.playHistory.count) tracks")
                    ProfileLink(icon: "square.and.arrow.up", title: "Share Profile", subtitle: "Coming soon", disabled: true)
                }
                .padding(.horizontal, 16)

                Spacer(minLength: 120)
            }
        }
        .background(Theme.background)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Theme.background)
        }
        .sheet(isPresented: $showLogin) {
            LoginView()
                .environment(authService)
                .presentationDragIndicator(.visible)
                .presentationBackground(Theme.background)
        }
    }

    private var listeningTime: String {
        let totalSeconds = audioPlayer.playHistory.reduce(0) { $0 + $1.duration }
        let minutes = totalSeconds / 60
        return "\(minutes)"
    }

    private var avatarInitial: String {
        let name = authService.currentUser?.name ?? authService.currentUser?.email ?? ""
        return String(name.prefix(1)).uppercased()
    }

    private func syncLibrary() async {
        guard let uid = authService.currentUser?.uid else { return }
        isSyncing = true
        defer { isSyncing = false }

        do {
            // Upload local favorites to cloud
            try await PocketBaseService.shared.syncLibrary(
                uid: uid,
                tracks: libraryManager.favoriteTracks,
                albums: libraryManager.favoriteAlbums
            )

            // Download cloud data and merge
            let cloud = try await PocketBaseService.shared.fetchLibrary(uid: uid)
            let cloudTracks = cloud.decodeTracks()
            let cloudAlbums = cloud.decodeAlbums()

            // Merge cloud tracks into local
            for track in cloudTracks {
                if !libraryManager.isFavorite(trackId: track.id) {
                    libraryManager.favoriteTracks.append(track)
                }
            }
            libraryManager.saveTracks()

            // Merge cloud albums into local
            for album in cloudAlbums {
                if !libraryManager.isFavorite(albumId: album.id) {
                    libraryManager.favoriteAlbums.append(album)
                }
            }
            libraryManager.saveAlbums()
        } catch {
            print("[Sync] Error: \(error.localizedDescription)")
        }
    }
}

// MARK: - Sign In Button

private enum SignInButtonStyle {
    case primary, secondary
}

private struct SignInButton: View {
    let icon: String
    let label: String
    let style: SignInButtonStyle
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                Text(label)
                    .font(.system(size: 16, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .foregroundColor(style == .primary ? Theme.primaryForeground : Theme.foreground)
            .background(style == .primary ? Theme.primary : Theme.secondary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLg))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Stat Card

private struct StatCard: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(Theme.mutedForeground)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundColor(Theme.foreground)
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(Theme.mutedForeground)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Theme.secondary.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLg))
    }
}

// MARK: - Profile Link Row

private struct ProfileLink: View {
    let icon: String
    let title: String
    let subtitle: String
    var disabled: Bool = false

    var body: some View {
        Button {
            // Not implemented yet
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(disabled ? Theme.mutedForeground.opacity(0.4) : Theme.foreground)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(disabled ? Theme.mutedForeground.opacity(0.4) : Theme.foreground)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.mutedForeground.opacity(disabled ? 0.3 : 1))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.mutedForeground.opacity(disabled ? 0.3 : 0.6))
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(Theme.secondary.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLg))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .padding(.bottom, 8)
    }
}

#Preview {
    ProfileView(navigationPath: .constant(NavigationPath()))
        .environment(AudioPlayerService())
        .environment(LibraryManager.shared)
        .environment(AuthService.shared)
}
