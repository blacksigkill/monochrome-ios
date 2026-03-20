import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ProfileView: View {
    @Binding var navigationPath: CompatNavigationPath
    @EnvironmentObject private var audioPlayer: AudioPlayerService
    @EnvironmentObject private var libraryManager: LibraryManager
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var profileManager: ProfileManager
    @EnvironmentObject private var playlistManager: PlaylistManager
    @EnvironmentObject private var tabRouter: TabRouter
    @State private var activeSheet: ProfileSheet?

    private enum ProfileSheet: Identifiable, Hashable {
        case settings
        case login
        case editProfile
        case listeningHistory
        
        var id: String {
            switch self {
            case .settings: return "settings"
            case .login: return "login"
            case .editProfile: return "editProfile"
            case .listeningHistory: return "listeningHistory"
            }
        }
        
        static func == (lhs: ProfileSheet, rhs: ProfileSheet) -> Bool {
            lhs.id == rhs.id
        }
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }

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
                        Button { activeSheet = .editProfile } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 18))
                                .foregroundColor(Theme.foreground)
                                .frame(width: 40, height: 40)
                                .background(Theme.secondary)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    Button { activeSheet = .settings } label: {
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
                .zIndex(1)

                // MARK: - Banner
                if authService.isAuthenticated && !profileManager.profile.banner.isEmpty {
                    CachedAsyncImage(url: URL(string: profileManager.profile.banner)) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            Rectangle().fill(Theme.secondary)
                        }
                    }
                    .frame(height: 120)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .allowsHitTesting(false)
                    .padding(.horizontal, 16)
                    .padding(.bottom, -40)
                }

                // MARK: - Avatar & User Info
                VStack(spacing: 12) {
                    // Avatar
                    if authService.isAuthenticated && !profileManager.profile.avatarUrl.isEmpty {
                        CachedAsyncImage(url: URL(string: profileManager.profile.avatarUrl)) { phase in
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
                                statusView(profileManager.profile.status)
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

                // MARK: - Favorite Albums
                if authService.isAuthenticated && !profileManager.profile.favoriteAlbums.isEmpty {
                    VStack(spacing: 0) {
                        HStack {
                            Text("Favorite Albums")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(Theme.foreground)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(profileManager.profile.favoriteAlbums) { album in
                                    VStack(spacing: 6) {
                                        if !album.cover.isEmpty, let url = URL(string: album.cover) {
                                            CachedAsyncImage(url: url) { phase in
                                                if let image = phase.image {
                                                    image.resizable().scaledToFill()
                                                } else {
                                                    RoundedRectangle(cornerRadius: 6).fill(Theme.secondary)
                                                }
                                            }
                                            .frame(width: 100, height: 100)
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                        }
                                        Text(album.title)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(Theme.foreground)
                                            .lineLimit(1)
                                            .frame(width: 100)
                                        Text(album.artist)
                                            .font(.system(size: 11))
                                            .foregroundColor(Theme.mutedForeground)
                                            .lineLimit(1)
                                            .frame(width: 100)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    .padding(.bottom, 24)
                }

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
                        activeSheet = .login
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
                        tabRouter.pendingLibraryFilter = .tracks
                        tabRouter.selectedTab = 2
                    }
                    ProfileLink(icon: "music.note.list", title: "My Playlists", subtitle: "\(playlistManager.userPlaylists.count) playlists") {
                        tabRouter.pendingLibraryFilter = .myPlaylists
                        tabRouter.selectedTab = 2
                    }
                    ProfileLink(icon: "clock.arrow.circlepath", title: "Listening History", subtitle: "\(historyCount) tracks") {
                        activeSheet = .listeningHistory
                    }
                }
                .padding(.horizontal, 16)

                Spacer(minLength: 120)
            }
        }
        .background(Theme.background)
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .settings:
                SettingsView()
                    .compatPresentationDetents(medium: true, large: true)
                    .compatPresentationDragIndicator()
                    .compatPresentationBackground(Theme.background)
            case .login:
                LoginView()
                    .environmentObject(authService)
                    .compatPresentationDragIndicator()
                    .compatPresentationBackground(Theme.background)
            case .editProfile:
                EditProfileView()
                    .compatPresentationDetents(large: true)
                    .compatPresentationDragIndicator()
                    .compatPresentationBackground(Theme.background)
            case .listeningHistory:
                ListeningHistoryView()
                    .environmentObject(audioPlayer)
                    .compatPresentationDetents(medium: true, large: true)
                    .compatPresentationDragIndicator()
                    .compatPresentationBackground(Theme.background)
            }
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

    @ViewBuilder
    private func statusView(_ status: String) -> some View {
        if let data = status.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let title = json["title"] as? String {
            let subtitle = json["subtitle"] as? String ?? ""
            let imageUrl = json["image"] as? String ?? ""

            HStack(spacing: 8) {
                if !imageUrl.isEmpty, let url = URL(string: imageUrl) {
                    CachedAsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            RoundedRectangle(cornerRadius: 3).fill(Theme.secondary)
                        }
                    }
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("Listening to")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.mutedForeground)
                    Text("\(title)\(subtitle.isEmpty ? "" : " · \(subtitle)")")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Theme.foreground.opacity(0.85))
                        .lineLimit(1)
                }
            }
        } else {
            Text(status)
                .font(.system(size: 13))
                .foregroundColor(Theme.mutedForeground)
                .italic()
        }
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
    @EnvironmentObject private var profileManager: ProfileManager
    @EnvironmentObject private var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var username = ""
    @State private var displayName = ""
    @State private var avatarUrl = ""
    @State private var banner = ""
    @State private var statusSearch = ""
    @State private var statusJson = ""
    @State private var about = ""
    @State private var website = ""
    @State private var lastfmUsername = ""
    @State private var playlistsPublic = true
    @State private var lastfmPublic = true
    @State private var isSaving = false

    // Image picker
    @State private var isUploadingAvatar = false
    @State private var isUploadingBanner = false
    @State private var uploadError = ""

    // Favorite albums
    @State private var favoriteAlbums: [FavoriteAlbum] = []
    @State private var favAlbumSearch = ""
    @State private var favAlbumResults: [Album] = []
    @State private var favSearchTask: Task<Void, Never>?
    @State private var editingFavDescription: String? = nil
    @State private var favDescriptionText = ""

    // Status autocomplete
    @State private var statusSuggestions: [StatusSuggestion] = []
    @State private var statusTask: Task<Void, Never>?
    @State private var showStatusSuggestions = false
    @State private var suppressStatusUpdate = false
    @FocusState private var statusFocused: Bool

    var body: some View {
        CompatNavigationView {
            List {
                Section("Display") {
                    ProfileTextField(label: "Username", text: $username, icon: "at")
                    ProfileTextField(label: "Display Name", text: $displayName, icon: "person")

                    // Avatar
                    ImageUploadRow(
                        label: "Avatar",
                        currentUrl: avatarUrl,
                        isUploading: isUploadingAvatar,
                        urlBinding: $avatarUrl,
                        onImagePicked: { image in
                            uploadImage(image, for: .avatar)
                        }
                    )

                    // Banner
                    ImageUploadRow(
                        label: "Banner",
                        currentUrl: banner,
                        isUploading: isUploadingBanner,
                        urlBinding: $banner,
                        onImagePicked: { image in
                            uploadImage(image, for: .banner)
                        }
                    )

                    if !uploadError.isEmpty {
                        Text(uploadError)
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                    }
                }

                Section("About") {
                    // Status with autocomplete
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 10) {
                            Image(systemName: "text.bubble")
                                .font(.system(size: 14))
                                .foregroundColor(Theme.mutedForeground)
                                .frame(width: 20)
                            TextField("Status (listening to...)", text: $statusSearch)
                                .font(.system(size: 15))
                                .foregroundColor(Theme.foreground)
                                .focused($statusFocused)
                                .onChange(of: statusSearch) { newValue in
                                    if suppressStatusUpdate {
                                        suppressStatusUpdate = false
                                        return
                                    }
                                    updateStatusSuggestions(query: newValue)
                                }

                            if !statusJson.isEmpty {
                                Button {
                                    statusJson = ""
                                    statusSearch = ""
                                    statusSuggestions = []
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(Theme.mutedForeground)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if showStatusSuggestions && !statusSuggestions.isEmpty {
                            VStack(spacing: 0) {
                                ForEach(statusSuggestions) { suggestion in
                                    Button {
                                        selectStatus(suggestion)
                                    } label: {
                                        HStack(spacing: 10) {
                                            CachedAsyncImage(url: MonochromeAPI().getImageUrl(id: suggestion.image, size: 80)) { phase in
                                                if let image = phase.image {
                                                    image.resizable().scaledToFill()
                                                } else {
                                                    RoundedRectangle(cornerRadius: 3).fill(Theme.secondary)
                                                }
                                            }
                                            .frame(width: 36, height: 36)
                                            .clipShape(RoundedRectangle(cornerRadius: 3))

                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(suggestion.title)
                                                    .font(.system(size: 13, weight: .medium))
                                                    .foregroundColor(Theme.foreground)
                                                    .lineLimit(1)
                                                Text("\(suggestion.subtitle) · \(suggestion.type == "track" ? "Track" : "Album")")
                                                    .font(.system(size: 11))
                                                    .foregroundColor(Theme.mutedForeground)
                                                    .lineLimit(1)
                                            }
                                            Spacer()
                                        }
                                        .padding(.vertical, 6)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Bio")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.mutedForeground)
                        TextEditor(text: $about)
                            .font(.system(size: 15))
                            .foregroundColor(Theme.foreground)
                            .frame(minHeight: 80)
                            .compatScrollContentBackground(false)
                    }
                    ProfileTextField(label: "Website", text: $website, icon: "link")
                }

                Section("Favorite Albums (max 5)") {
                    ForEach(Array(favoriteAlbums.enumerated()), id: \.element.id) { index, album in
                        HStack(spacing: 10) {
                            if !album.cover.isEmpty {
                                CachedAsyncImage(url: URL(string: album.cover)) { phase in
                                    if let image = phase.image {
                                        image.resizable().scaledToFill()
                                    } else {
                                        RoundedRectangle(cornerRadius: 4).fill(Theme.secondary)
                                    }
                                }
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(album.title)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(Theme.foreground)
                                    .lineLimit(1)
                                Text(album.artist)
                                    .font(.system(size: 12))
                                    .foregroundColor(Theme.mutedForeground)
                                    .lineLimit(1)
                                if !album.description.isEmpty {
                                    Text(album.description)
                                        .font(.system(size: 11))
                                        .foregroundColor(Theme.mutedForeground.opacity(0.7))
                                        .lineLimit(1)
                                        .compatItalic()
                                }
                            }

                            Spacer()

                            Button {
                                editingFavDescription = album.id
                                favDescriptionText = album.description
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.system(size: 13))
                                    .foregroundColor(Theme.mutedForeground)
                            }
                            .buttonStyle(.borderless)

                            Button {
                                withAnimation { favoriteAlbums.removeAll { $0.id == album.id } }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.red.opacity(0.6))
                            }
                            .buttonStyle(.borderless)
                        }
                    }

                    if favoriteAlbums.count < 5 {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 10) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 14))
                                    .foregroundColor(Theme.mutedForeground)
                                    .frame(width: 20)
                                TextField("Search album to add...", text: $favAlbumSearch)
                                    .font(.system(size: 15))
                                    .foregroundColor(Theme.foreground)
                                    .onChange(of: favAlbumSearch) { newValue in
                                        searchFavAlbums(query: newValue)
                                    }
                            }

                            if !favAlbumResults.isEmpty {
                                ForEach(favAlbumResults.prefix(5)) { album in
                                    Button {
                                        addFavoriteAlbum(album)
                                    } label: {
                                        HStack(spacing: 10) {
                                            CachedAsyncImage(url: MonochromeAPI().getImageUrl(id: album.cover ?? "", size: 80)) { phase in
                                                if let image = phase.image {
                                                    image.resizable().scaledToFill()
                                                } else {
                                                    RoundedRectangle(cornerRadius: 3).fill(Theme.secondary)
                                                }
                                            }
                                            .frame(width: 36, height: 36)
                                            .clipShape(RoundedRectangle(cornerRadius: 3))

                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(album.title)
                                                    .font(.system(size: 13, weight: .medium))
                                                    .foregroundColor(Theme.foreground)
                                                    .lineLimit(1)
                                                Text(album.artist?.name ?? "")
                                                    .font(.system(size: 11))
                                                    .foregroundColor(Theme.mutedForeground)
                                                    .lineLimit(1)
                                            }
                                            Spacer()
                                            Image(systemName: "plus.circle")
                                                .font(.system(size: 16))
                                                .foregroundColor(Theme.foreground)
                                        }
                                        .padding(.vertical, 4)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
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
            .compatScrollContentBackground(false)
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
                about = p.about
                website = p.website
                lastfmUsername = p.lastfmUsername
                playlistsPublic = p.privacy.playlists == "public"
                lastfmPublic = p.privacy.lastfm == "public"
                favoriteAlbums = p.favoriteAlbums
                // Parse existing status
                if let data = p.status.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let text = json["text"] as? String {
                    statusSearch = text
                    statusJson = p.status
                } else {
                    statusSearch = p.status
                    statusJson = ""
                }
            }
            .alert("Album Description", isPresented: Binding(
                get: { editingFavDescription != nil },
                set: { if !$0 { editingFavDescription = nil } }
            )) {
                TextField("Why do you love this album?", text: $favDescriptionText)
                Button("Cancel", role: .cancel) { editingFavDescription = nil }
                Button("Save") {
                    if let id = editingFavDescription,
                       let idx = favoriteAlbums.firstIndex(where: { $0.id == id }) {
                        favoriteAlbums[idx].description = favDescriptionText
                    }
                    editingFavDescription = nil
                }
            }
        }
    }

    // MARK: - Status Autocomplete

    private func updateStatusSuggestions(query: String) {
        statusTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)

        if trimmed.count < 2 {
            statusSuggestions = []
            showStatusSuggestions = false
            statusJson = ""
            return
        }

        showStatusSuggestions = true

        statusTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }

            do {
                let r = try await MonochromeAPI().searchAll(query: trimmed)
                guard !Task.isCancelled else { return }

                var results: [StatusSuggestion] = []
                results += r.tracks.prefix(3).map {
                    StatusSuggestion(type: "track", id: String($0.id), title: $0.title, subtitle: $0.artist?.name ?? "", image: $0.album?.cover ?? "")
                }
                results += r.albums.prefix(3).map {
                    StatusSuggestion(type: "album", id: String($0.id), title: $0.title, subtitle: $0.artist?.name ?? "", image: $0.cover ?? "")
                }

                await MainActor.run {
                    statusSuggestions = results
                }
            } catch {}
        }
    }

    private func selectStatus(_ suggestion: StatusSuggestion) {
        suppressStatusUpdate = true
        statusSearch = "\(suggestion.title) - \(suggestion.subtitle)"
        showStatusSuggestions = false
        statusSuggestions = []
        statusFocused = false

        let imageUrl: String
        if let url = MonochromeAPI().getImageUrl(id: suggestion.image, size: 160) {
            imageUrl = url.absoluteString
        } else {
            imageUrl = ""
        }

        let statusObj: [String: Any] = [
            "type": suggestion.type,
            "id": suggestion.id,
            "text": "\(suggestion.title) - \(suggestion.subtitle)",
            "title": suggestion.title,
            "subtitle": suggestion.subtitle,
            "image": imageUrl,
            "link": "/\(suggestion.type)/\(suggestion.id)"
        ]

        if let data = try? JSONSerialization.data(withJSONObject: statusObj),
           let jsonStr = String(data: data, encoding: .utf8) {
            statusJson = jsonStr
        }
    }

    // MARK: - Image Upload

    private enum ImageTarget { case avatar, banner }

    private func uploadImage(_ image: UIImage, for target: ImageTarget) {
        switch target {
        case .avatar: isUploadingAvatar = true
        case .banner: isUploadingBanner = true
        }

        Task {
            guard let data = ImageUploadService.shared.compressImage(image) else {
                await MainActor.run {
                    switch target {
                    case .avatar: isUploadingAvatar = false
                    case .banner: isUploadingBanner = false
                    }
                }
                return
            }

            do {
                let url = try await ImageUploadService.shared.upload(imageData: data)
                await MainActor.run {
                    uploadError = ""
                    switch target {
                    case .avatar:
                        avatarUrl = url
                        isUploadingAvatar = false
                    case .banner:
                        banner = url
                        isUploadingBanner = false
                    }
                }
            } catch {
                print("[Upload] Error: \(error.localizedDescription)")
                await MainActor.run {
                    uploadError = error.localizedDescription
                    switch target {
                    case .avatar: isUploadingAvatar = false
                    case .banner: isUploadingBanner = false
                    }
                }
            }
        }
    }

    // MARK: - Favorite Albums Search

    private func searchFavAlbums(query: String) {
        favSearchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.count < 2 {
            favAlbumResults = []
            return
        }
        favSearchTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            do {
                let albums = try await MonochromeAPI().searchAlbums(query: trimmed)
                guard !Task.isCancelled else { return }
                await MainActor.run { favAlbumResults = albums }
            } catch {}
        }
    }

    private func addFavoriteAlbum(_ album: Album) {
        guard favoriteAlbums.count < 5 else { return }
        guard !favoriteAlbums.contains(where: { $0.id == String(album.id) }) else { return }

        let imageUrl: String
        if let url = MonochromeAPI().getImageUrl(id: album.cover ?? "", size: 320) {
            imageUrl = url.absoluteString
        } else {
            imageUrl = ""
        }

        let fav = FavoriteAlbum(
            id: String(album.id),
            title: album.title,
            artist: album.artist?.name ?? "",
            cover: imageUrl,
            description: ""
        )
        withAnimation { favoriteAlbums.append(fav) }
        favAlbumSearch = ""
        favAlbumResults = []
    }

    // MARK: - Save

    private func save() {
        isSaving = true
        profileManager.profile.username = username.trimmingCharacters(in: .whitespaces)
        profileManager.profile.displayName = displayName.trimmingCharacters(in: .whitespaces)
        profileManager.profile.avatarUrl = avatarUrl.trimmingCharacters(in: .whitespaces)
        profileManager.profile.banner = banner.trimmingCharacters(in: .whitespaces)
        profileManager.profile.status = statusJson.isEmpty ? statusSearch.trimmingCharacters(in: .whitespaces) : statusJson
        profileManager.profile.about = about.trimmingCharacters(in: .whitespaces)
        profileManager.profile.website = website.trimmingCharacters(in: .whitespaces)
        profileManager.profile.lastfmUsername = lastfmUsername.trimmingCharacters(in: .whitespaces)
        profileManager.profile.privacy.playlists = playlistsPublic ? "public" : "private"
        profileManager.profile.privacy.lastfm = lastfmPublic ? "public" : "private"
        profileManager.profile.favoriteAlbums = favoriteAlbums

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

// MARK: - Status Suggestion

private struct StatusSuggestion: Identifiable {
    let type: String
    let id: String
    let title: String
    let subtitle: String
    let image: String
}

// MARK: - Image Upload Row

private struct ImageUploadRow: View {
    let label: String
    let currentUrl: String
    let isUploading: Bool
    @Binding var urlBinding: String
    let onImagePicked: (UIImage) -> Void

    @State private var showUrlInput = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "photo")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.mutedForeground)
                    .frame(width: 20)

                Text(label)
                    .font(.system(size: 15))
                    .foregroundColor(Theme.foreground)

                Spacer()

                if isUploading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if !currentUrl.isEmpty {
                    CachedAsyncImage(url: URL(string: currentUrl)) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            RoundedRectangle(cornerRadius: 4).fill(Theme.secondary)
                        }
                    }
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }

            HStack(spacing: 8) {
                CompatPhotoPicker {
                    Label("Upload", systemImage: "arrow.up.circle")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Theme.foreground)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.secondary)
                        .clipShape(Capsule())
                } onImagePicked: { image in
                    onImagePicked(image)
                }
                .buttonStyle(.plain)

                Button {
                    showUrlInput.toggle()
                } label: {
                    Label("URL", systemImage: "link")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Theme.foreground)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.secondary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                if !currentUrl.isEmpty {
                    Button {
                        urlBinding = ""
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13))
                            .foregroundColor(.red.opacity(0.7))
                            .padding(6)
                    }
                    .buttonStyle(.plain)
                }
            }

            if showUrlInput {
                TextField("Paste image URL", text: $urlBinding)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.foreground)
                    .textFieldStyle(.roundedBorder)
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(Theme.secondary.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLg))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .padding(.bottom, 8)
    }
}

// MARK: - Listening History View

struct ListeningHistoryView: View {
    @EnvironmentObject private var audioPlayer: AudioPlayerService
    @Environment(\.dismiss) private var dismiss
    
    private var reversedHistory: [Track] {
        audioPlayer.playHistory.reversed()
    }
    
    var body: some View {
        CompatNavigationView {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(reversedHistory.enumerated()), id: \.offset) { index, track in
                        ProfileTrackRow(track: track, index: index + 1) {
                            audioPlayer.play(track: track, queue: Array(reversedHistory.dropFirst(index + 1)))
                        }
                    }
                }
            }
            .background(Theme.background)
            .navigationTitle("Listening History")
            .navigationBarTitleDisplayMode(.inline)
            .compatToolbarColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Profile Track Row (Simple)

private struct ProfileTrackRow: View {
    let track: Track
    let index: Int
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text("\(index)")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Theme.mutedForeground)
                    .frame(width: 28, alignment: .center)
                
                if let coverUrl = MonochromeAPI().getImageUrl(id: track.album?.cover) {
                    CachedAsyncImage(url: coverUrl) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            Rectangle().fill(Theme.secondary)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.system(size: 15))
                        .foregroundColor(Theme.foreground)
                        .lineLimit(1)
                    Text(track.artist?.name ?? "Unknown Artist")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.mutedForeground)
                        .lineLimit(1)
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ProfileView(navigationPath: .constant(CompatNavigationPath()))
        .environmentObject(AudioPlayerService())
        .environmentObject(LibraryManager.shared)
        .environmentObject(AuthService.shared)
        .environmentObject(ProfileManager.shared)
        .environmentObject(PlaylistManager.shared)
        .environmentObject(DownloadManager.shared)
        .environmentObject(TabRouter())
}
