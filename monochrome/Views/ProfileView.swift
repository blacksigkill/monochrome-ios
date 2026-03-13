import SwiftUI

struct ProfileView: View {
    @Binding var navigationPath: NavigationPath
    @Environment(AudioPlayerService.self) private var audioPlayer
    @Environment(LibraryManager.self) private var libraryManager
    @Environment(AuthService.self) private var authService
    @Environment(ProfileManager.self) private var profileManager
    @Environment(PlaylistManager.self) private var playlistManager
    @State private var showSettings = false
    @State private var showLogin = false
    @State private var showEditProfile = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // MARK: - Header
                HStack {
                    Text("Profile")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(Theme.foreground)
                    Spacer()
                    if authService.isAuthenticated {
                        Button { showEditProfile = true } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 18))
                                .foregroundColor(Theme.foreground)
                                .frame(width: 40, height: 40)
                                .background(Theme.secondary)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    Button { showSettings = true } label: {
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
                .padding(.bottom, 16)

                // MARK: - Banner
                if authService.isAuthenticated && !profileManager.profile.banner.isEmpty {
                    AsyncImage(url: URL(string: profileManager.profile.banner)) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            Rectangle().fill(Theme.secondary)
                        }
                    }
                    .frame(height: 120)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 16)
                    .padding(.bottom, -40)
                }

                // MARK: - Avatar & User Info
                VStack(spacing: 12) {
                    // Avatar
                    if authService.isAuthenticated && !profileManager.profile.avatarUrl.isEmpty {
                        AsyncImage(url: URL(string: profileManager.profile.avatarUrl)) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill()
                            } else {
                                Circle().fill(Theme.secondary)
                                    .overlay(Text(avatarInitial).font(.system(size: 36, weight: .bold)).foregroundColor(Theme.foreground))
                            }
                        }
                        .frame(width: 100, height: 100)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Theme.background, lineWidth: 4))
                    } else {
                        ZStack {
                            Circle().fill(Theme.secondary)
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
                    }

                    VStack(spacing: 4) {
                        if authService.isAuthenticated {
                            let displayName = profileManager.profile.displayName.isEmpty
                                ? (authService.currentUser?.name ?? authService.currentUser?.email ?? "")
                                : profileManager.profile.displayName
                            Text(displayName)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(Theme.foreground)

                            if !profileManager.profile.username.isEmpty {
                                Text("@\(profileManager.profile.username)")
                                    .font(.system(size: 14))
                                    .foregroundColor(Theme.mutedForeground)
                            }

                            // Status
                            if !profileManager.profile.status.isEmpty {
                                Text(profileManager.profile.status)
                                    .font(.system(size: 13))
                                    .foregroundColor(Theme.mutedForeground)
                                    .italic()
                                    .padding(.top, 2)
                            }

                            // About
                            if !profileManager.profile.about.isEmpty {
                                Text(profileManager.profile.about)
                                    .font(.system(size: 14))
                                    .foregroundColor(Theme.foreground.opacity(0.8))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 32)
                                    .padding(.top, 4)
                            }

                            // Website
                            if !profileManager.profile.website.isEmpty {
                                Link(destination: URL(string: profileManager.profile.website) ?? URL(string: "https://example.com")!) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "link")
                                            .font(.system(size: 12))
                                        Text(profileManager.profile.website.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: ""))
                                            .font(.system(size: 13))
                                    }
                                    .foregroundColor(.blue)
                                }
                                .padding(.top, 2)
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
                .padding(.top, profileManager.profile.banner.isEmpty || !authService.isAuthenticated ? 16 : 0)
                .padding(.bottom, 24)

                // MARK: - Sign In / Sign Out
                if authService.isAuthenticated {
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
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                } else {
                    SignInButton(icon: "envelope.fill", label: "Sign In / Create Account", style: .primary) {
                        showLogin = true
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
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
                        StatCard(icon: "heart.fill", value: "\(libraryManager.favoriteTracks.count)", label: "Favorites")
                        StatCard(icon: "music.note.list", value: "\(historyCount)", label: "Listened")
                        StatCard(icon: "clock.fill", value: listeningTime, label: "Minutes")
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 32)

                // MARK: - Quick Links
                VStack(spacing: 0) {
                    ProfileLink(icon: "heart.fill", title: "Favorite Tracks", subtitle: "\(libraryManager.favoriteTracks.count) tracks") {
                        // Could navigate to library favorites
                    }
                    ProfileLink(icon: "music.note.list", title: "My Playlists", subtitle: "\(playlistManager.userPlaylists.count) playlists") {
                        // Could navigate to playlists
                    }
                    ProfileLink(icon: "clock.arrow.circlepath", title: "Listening History", subtitle: "\(historyCount) tracks") {
                        // Could navigate to history
                    }
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
        .sheet(isPresented: $showEditProfile) {
            EditProfileView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Theme.background)
        }
    }

    private var historyCount: Int {
        max(audioPlayer.playHistory.count, profileManager.profile.historyCount)
    }

    private var listeningTime: String {
        let totalSeconds = audioPlayer.playHistory.reduce(0) { $0 + $1.duration }
        let minutes = totalSeconds / 60
        return "\(minutes)"
    }

    private var avatarInitial: String {
        let name = profileManager.profile.displayName.isEmpty
            ? (authService.currentUser?.name ?? authService.currentUser?.email ?? "")
            : profileManager.profile.displayName
        return String(name.prefix(1)).uppercased()
    }
}

// MARK: - Edit Profile View

struct EditProfileView: View {
    @Environment(ProfileManager.self) private var profileManager
    @Environment(AuthService.self) private var authService
    @Environment(\.dismiss) private var dismiss

    @State private var username = ""
    @State private var displayName = ""
    @State private var avatarUrl = ""
    @State private var banner = ""
    @State private var status = ""
    @State private var about = ""
    @State private var website = ""
    @State private var lastfmUsername = ""
    @State private var playlistsPublic = true
    @State private var lastfmPublic = true
    @State private var isSaving = false

    var body: some View {
        NavigationView {
            List {
                Section("Display") {
                    ProfileTextField(label: "Username", text: $username, icon: "at")
                    ProfileTextField(label: "Display Name", text: $displayName, icon: "person")
                    ProfileTextField(label: "Avatar URL", text: $avatarUrl, icon: "photo")
                    ProfileTextField(label: "Banner URL", text: $banner, icon: "photo.on.rectangle")
                }

                Section("About") {
                    ProfileTextField(label: "Status", text: $status, icon: "text.bubble")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Bio")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.mutedForeground)
                        TextEditor(text: $about)
                            .font(.system(size: 15))
                            .foregroundColor(Theme.foreground)
                            .frame(minHeight: 80)
                            .scrollContentBackground(.hidden)
                    }
                    ProfileTextField(label: "Website", text: $website, icon: "link")
                }

                Section("Integrations") {
                    ProfileTextField(label: "Last.fm Username", text: $lastfmUsername, icon: "music.note")
                }

                Section("Privacy") {
                    Toggle("Public Playlists", isOn: $playlistsPublic)
                        .tint(Theme.primary)
                    Toggle("Public Last.fm", isOn: $lastfmPublic)
                        .tint(Theme.primary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        if isSaving {
                            ProgressView().tint(Theme.foreground)
                        } else {
                            Text("Save").fontWeight(.semibold)
                        }
                    }
                    .disabled(isSaving)
                }
            }
            .onAppear {
                let p = profileManager.profile
                username = p.username
                displayName = p.displayName
                avatarUrl = p.avatarUrl
                banner = p.banner
                status = p.status
                about = p.about
                website = p.website
                lastfmUsername = p.lastfmUsername
                playlistsPublic = p.privacy.playlists == "public"
                lastfmPublic = p.privacy.lastfm == "public"
            }
        }
    }

    private func save() {
        isSaving = true
        profileManager.profile.username = username.trimmingCharacters(in: .whitespaces)
        profileManager.profile.displayName = displayName.trimmingCharacters(in: .whitespaces)
        profileManager.profile.avatarUrl = avatarUrl.trimmingCharacters(in: .whitespaces)
        profileManager.profile.banner = banner.trimmingCharacters(in: .whitespaces)
        profileManager.profile.status = status.trimmingCharacters(in: .whitespaces)
        profileManager.profile.about = about.trimmingCharacters(in: .whitespaces)
        profileManager.profile.website = website.trimmingCharacters(in: .whitespaces)
        profileManager.profile.lastfmUsername = lastfmUsername.trimmingCharacters(in: .whitespaces)
        profileManager.profile.privacy.playlists = playlistsPublic ? "public" : "private"
        profileManager.profile.privacy.lastfm = lastfmPublic ? "public" : "private"

        guard let uid = authService.currentUser?.uid else {
            isSaving = false
            dismiss()
            return
        }

        Task {
            await profileManager.saveToCloud(uid: uid)
            await MainActor.run {
                isSaving = false
                dismiss()
            }
        }
    }
}

private struct ProfileTextField: View {
    let label: String
    @Binding var text: String
    var icon: String = ""

    var body: some View {
        HStack(spacing: 10) {
            if !icon.isEmpty {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(Theme.mutedForeground)
                    .frame(width: 20)
            }
            TextField(label, text: $text)
                .font(.system(size: 15))
                .foregroundColor(Theme.foreground)
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
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
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
        .environment(ProfileManager.shared)
        .environment(PlaylistManager.shared)
}
