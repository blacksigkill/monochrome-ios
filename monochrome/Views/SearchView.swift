import SwiftUI

struct SearchView: View {
    @Binding var navigationPath: NavigationPath
    @Environment(AudioPlayerService.self) private var audioPlayer

    @State private var searchText = ""
    @State private var searchTracks: [Track] = []
    @State private var searchArtists: [Artist] = []
    @State private var searchAlbums: [Album] = []
    @State private var searchPlaylists: [Playlist] = []

    @State private var isSearching = false
    @State private var hasSearched = false
    @State private var mediaFilter: MediaFilter = .albums
    @FocusState private var isFocused: Bool
    @State private var keyboardHeight: CGFloat = 0
    @State private var searchHistory: [String] = []
    @State private var suggestions: [Suggestion] = []
    @State private var autocompleteTask: Task<Void, Never>?
    @State private var autocompleteCache: SearchCache?

    private struct SearchCache {
        let query: String
        let artists: [Artist]
        let albums: [Album]
        let tracks: [Track]
        let playlists: [Playlist]
    }

    private let historyKey = "search_history"
    private let maxHistory = 20

    private var hasResults: Bool {
        !searchTracks.isEmpty || !searchArtists.isEmpty || !searchAlbums.isEmpty || !searchPlaylists.isEmpty
    }

    private var showSuggestions: Bool {
        isFocused && !suggestions.isEmpty
    }

    private enum MediaFilter: String, CaseIterable {
        case albums = "Albums"
        case singles = "Singles"
        case playlists = "Playlists"
        case all = "All"
    }

    private var filteredAlbums: [Album] {
        switch mediaFilter {
        case .albums: return searchAlbums.filter { $0.type?.uppercased() != "SINGLE" }
        case .singles: return searchAlbums.filter { $0.type?.uppercased() == "SINGLE" }
        case .all: return searchAlbums
        case .playlists: return []
        }
    }

    private var filteredPlaylists: [Playlist] {
        mediaFilter == .playlists || mediaFilter == .all ? searchPlaylists : []
    }

    private var hasMediaContent: Bool {
        !searchAlbums.isEmpty || !searchPlaylists.isEmpty
    }

    private var availableFilters: [MediaFilter] {
        var filters: [MediaFilter] = []
        let hasAlbums = searchAlbums.contains { $0.type?.uppercased() != "SINGLE" }
        let hasSingles = searchAlbums.contains { $0.type?.uppercased() == "SINGLE" }
        if hasAlbums { filters.append(.albums) }
        if hasSingles { filters.append(.singles) }
        if !searchPlaylists.isEmpty { filters.append(.playlists) }
        if filters.count > 1 { filters.append(.all) }
        return filters
    }

    private enum Suggestion: Identifiable {
        case history(String)
        case artist(Artist)
        case album(Album)
        case track(Track)
        case playlist(Playlist)

        var id: String {
            switch self {
            case .history(let q): return "h_\(q)"
            case .artist(let a): return "a_\(a.id)"
            case .album(let a): return "al_\(a.id)"
            case .track(let t): return "t_\(t.id)"
            case .playlist(let p): return "p_\(p.uuid)"
            }
        }

        var primaryText: String {
            switch self {
            case .history(let q): return q
            case .artist(let a): return a.name
            case .album(let a): return a.title
            case .track(let t): return t.title
            case .playlist(let p): return p.title ?? "Playlist"
            }
        }

        var secondaryText: String? {
            switch self {
            case .history: return nil
            case .artist: return "Artist"
            case .album(let a): return a.artist?.name ?? "Album"
            case .track(let t): return t.artist?.name ?? "Track"
            case .playlist(let p): return p.user?.name ?? "Playlist"
            }
        }

        var icon: String {
            switch self {
            case .history: return "clock.arrow.circlepath"
            case .artist: return "person.fill"
            case .album: return "square.stack"
            case .track: return "music.note"
            case .playlist: return "music.note.list"
            }
        }

        var fillText: String { primaryText }
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Main content (Scrolled underneath the floating bar)
            List {
                if isSearching {
                    ProgressView().tint(Theme.mutedForeground)
                        .padding(.top, 100)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                } else if hasResults {
                    
                    // ARTISTS SECTION
                    if !searchArtists.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Artistes")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(Theme.foreground)
                                .padding(.horizontal, 16)
                                .padding(.top, 20)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 16) {
                                    ForEach(searchArtists) { artist in
                                        NavigationLink(value: artist) {
                                            ArtistSearchResultRow(artist: artist)
                                        }
                                        .simultaneousGesture(TapGesture().onEnded { isFocused = false })
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                            .frame(height: 140)
                        }
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                    
                    // ALBUMS / SINGLES / PLAYLISTS SECTION
                    if hasMediaContent {
                        VStack(alignment: .leading, spacing: 12) {
                            // Filter tabs
                            if availableFilters.count > 1 {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(availableFilters, id: \.self) { filter in
                                            Button {
                                                withAnimation(.easeInOut(duration: 0.2)) {
                                                    mediaFilter = filter
                                                }
                                            } label: {
                                                Text(filter.rawValue)
                                                    .font(.system(size: 13, weight: .semibold))
                                                    .foregroundColor(mediaFilter == filter ? Theme.background : Theme.foreground)
                                                    .padding(.horizontal, 14)
                                                    .padding(.vertical, 6)
                                                    .background(mediaFilter == filter ? Theme.foreground : Theme.secondary)
                                                    .clipShape(Capsule())
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                }
                                .padding(.top, 10)
                            } else {
                                Text(availableFilters.first?.rawValue ?? "Albums")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(Theme.foreground)
                                    .padding(.horizontal, 16)
                                    .padding(.top, 10)
                            }

                            if mediaFilter == .all {
                                // Combined scroll
                                ScrollView(.horizontal, showsIndicators: false) {
                                    LazyHStack(spacing: 16) {
                                        ForEach(searchAlbums) { album in
                                            NavigationLink(value: album) {
                                                AlbumSearchResultRow(album: album)
                                            }
                                            .simultaneousGesture(TapGesture().onEnded { isFocused = false })
                                        }
                                        ForEach(searchPlaylists) { playlist in
                                            NavigationLink(value: playlist) {
                                                PlaylistSearchResultRow(playlist: playlist)
                                            }
                                            .simultaneousGesture(TapGesture().onEnded { isFocused = false })
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                }
                                .frame(height: 180)
                            } else {
                                // Albums or Singles
                                if !filteredAlbums.isEmpty {
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        LazyHStack(spacing: 16) {
                                            ForEach(filteredAlbums) { album in
                                                NavigationLink(value: album) {
                                                    AlbumSearchResultRow(album: album)
                                                }
                                                .simultaneousGesture(TapGesture().onEnded { isFocused = false })
                                            }
                                        }
                                        .padding(.horizontal, 16)
                                    }
                                    .frame(height: 180)
                                }

                                // Playlists only
                                if !filteredPlaylists.isEmpty {
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        LazyHStack(spacing: 16) {
                                            ForEach(filteredPlaylists) { playlist in
                                                NavigationLink(value: playlist) {
                                                    PlaylistSearchResultRow(playlist: playlist)
                                                }
                                                .simultaneousGesture(TapGesture().onEnded { isFocused = false })
                                            }
                                        }
                                        .padding(.horizontal, 16)
                                    }
                                    .frame(height: 180)
                                }
                            }
                        }
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }

                    // TRACKS SECTION
                    if !searchTracks.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Titres")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(Theme.foreground)
                                .padding(.horizontal, 16)
                                .padding(.top, 10)
                        }
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        
                        ForEach(Array(searchTracks.enumerated()), id: \.element.id) { index, track in
                            let queue = Array(searchTracks.dropFirst(index + 1))
                            let previous = Array(searchTracks.prefix(index))
                            TrackRow(track: track, queue: queue, previousTracks: previous, showCover: true, navigationPath: $navigationPath)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                        }
                    }
                    
                    // Spacer to ensure last items can be scrolled past the miniplayer and tab bar
                    Color.clear.frame(height: 140)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                } else if hasSearched {
                    VStack(spacing: 10) {
                        Text("No results for")
                            .font(.system(size: 16))
                            .foregroundColor(Theme.mutedForeground)
                        Text("\"\(searchText)\"")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Theme.foreground)
                    }
                    .padding(.top, 100)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                } else if !searchHistory.isEmpty {
                    // Search history
                    HStack {
                        Text("Recent")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(Theme.foreground)
                        Spacer()
                        Button("Clear") {
                            withAnimation { searchHistory = [] }
                            UserDefaults.standard.removeObject(forKey: historyKey)
                        }
                        .font(.system(size: 14))
                        .foregroundColor(Theme.mutedForeground)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)

                    ForEach(searchHistory, id: \.self) { query in
                        Button {
                            searchText = query
                            performSearch()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 15))
                                    .foregroundColor(Theme.mutedForeground)
                                    .frame(width: 24)

                                Text(query)
                                    .font(.system(size: 15))
                                    .foregroundColor(Theme.foreground)
                                    .lineLimit(1)

                                Spacer()

                                Button {
                                    withAnimation {
                                        searchHistory.removeAll { $0 == query }
                                    }
                                    UserDefaults.standard.set(searchHistory, forKey: historyKey)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(Theme.mutedForeground.opacity(0.5))
                                        .frame(width: 28, height: 28)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }

                    Color.clear.frame(height: 140)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                } else {
                    VStack(spacing: 10) {
                        Text("Search for tracks, artists...")
                            .font(.system(size: 16))
                            .foregroundColor(Theme.mutedForeground)
                    }
                    .padding(.top, 100)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 0)
            .safeAreaPadding(.top, 70) 
            
            VStack(spacing: 0) {
                searchBar

                if showSuggestions {
                    suggestionsDropdown
                        .transition(.opacity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .offset(y: keyboardHeight)
        .onChange(of: searchText) { _, newValue in
            updateSuggestions(query: newValue)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            if let keyboardFrame: NSValue = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue {
                withAnimation(.easeOut(duration: 0.25)) {
                    self.keyboardHeight = keyboardFrame.cgRectValue.height * 0.38
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.25)) { self.keyboardHeight = 0 }
        }
        .ignoresSafeArea(.all, edges: .bottom)
        .ignoresSafeArea(.keyboard)
        .onAppear { loadHistory() }
        .onTapGesture { isFocused = false }
        .onChange(of: navigationPath) { isFocused = false }
    }

    private var searchBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16))
                    .foregroundColor(Theme.mutedForeground)

                TextField("What do you want to listen to?", text: $searchText)
                    .focused($isFocused)
                    .font(.system(size: 16))
                    .foregroundColor(Theme.foreground)
                    .autocorrectionDisabled()
                    .onSubmit { performSearch() }

                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                        searchTracks = []
                        searchArtists = []
                        searchAlbums = []
                        searchPlaylists = []
                        hasSearched = false
                        autocompleteTask?.cancel()
                        suggestions = []
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(Theme.mutedForeground)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 12)
        }
    }

    private func performSearch() {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        searchText = query
        isSearching = true
        hasSearched = true
        isFocused = false
        mediaFilter = .albums
        autocompleteTask?.cancel()
        suggestions = []
        addToHistory(query)

        if let cache = autocompleteCache, cache.query.lowercased() == query.lowercased() {
            searchArtists = cache.artists
            searchAlbums = cache.albums
            searchTracks = cache.tracks
            searchPlaylists = cache.playlists
            isSearching = false
            return
        }

        Task {
            do {
                let r = try await MonochromeAPI().searchAll(query: query)
                searchArtists = r.artists
                searchAlbums = r.albums
                searchTracks = r.tracks
                searchPlaylists = r.playlists
            } catch { print("Search error: \(error)") }
            isSearching = false
        }
    }

    private func addToHistory(_ query: String) {
        searchHistory.removeAll { $0.lowercased() == query.lowercased() }
        searchHistory.insert(query, at: 0)
        if searchHistory.count > maxHistory {
            searchHistory = Array(searchHistory.prefix(maxHistory))
        }
        UserDefaults.standard.set(searchHistory, forKey: historyKey)
    }

    private func loadHistory() {
        searchHistory = UserDefaults.standard.stringArray(forKey: historyKey) ?? []
    }

    // MARK: - Autocomplete

    private var suggestionsDropdown: some View {
        VStack(spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                if index > 0 {
                    Divider().opacity(0.15)
                        .padding(.horizontal, 16)
                }
                suggestionRow(suggestion)
            }
        }
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
        .padding(.horizontal, 16)
        .padding(.top, 2)
    }

    private func suggestionRow(_ suggestion: Suggestion) -> some View {
        HStack(spacing: 12) {
            suggestionIcon(suggestion)

            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.primaryText)
                    .font(.system(size: 15))
                    .foregroundColor(Theme.foreground)
                    .lineLimit(1)
                if let secondary = suggestion.secondaryText {
                    Text(secondary)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.mutedForeground)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button {
                searchText = suggestion.fillText
            } label: {
                Image(systemName: "arrow.up.left")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.mutedForeground)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            handleSuggestionTap(suggestion)
        }
    }

    @ViewBuilder
    private func suggestionIcon(_ suggestion: Suggestion) -> some View {
        switch suggestion {
        case .artist(let artist):
            CachedAsyncImage(url: MonochromeAPI().getImageUrl(id: artist.picture, size: 160)) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.mutedForeground)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.secondary)
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())
        case .album(let album):
            CachedAsyncImage(url: MonochromeAPI().getImageUrl(id: album.cover, size: 160)) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Image(systemName: "square.stack")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.mutedForeground)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.secondary)
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        case .playlist(let playlist):
            CachedAsyncImage(url: MonochromeAPI().getImageUrl(id: playlist.image, size: 160)) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.mutedForeground)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.secondary)
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        default:
            Image(systemName: suggestion.icon)
                .font(.system(size: 15))
                .foregroundColor(Theme.mutedForeground)
                .frame(width: 36, height: 36)
                .background(Theme.secondary)
                .clipShape(Circle())
        }
    }

    private func handleSuggestionTap(_ suggestion: Suggestion) {
        autocompleteTask?.cancel()
        suggestions = []

        switch suggestion {
        case .history(let query):
            searchText = query
            performSearch()
        case .artist(let artist):
            isFocused = false
            navigationPath.append(artist)
        case .album(let album):
            isFocused = false
            navigationPath.append(album)
        case .track(let track):
            isFocused = false
            audioPlayer.play(track: track, queue: [])
        case .playlist(let playlist):
            isFocused = false
            navigationPath.append(playlist)
        }
    }

    private func updateSuggestions(query: String) {
        autocompleteTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)

        if trimmed.isEmpty {
            suggestions = []
            return
        }

        // Instant: history matches
        let historyMatches = searchHistory
            .filter { $0.localizedCaseInsensitiveContains(trimmed) }
            .prefix(3)
            .map { Suggestion.history($0) }
        suggestions = Array(historyMatches)

        guard trimmed.count >= 2 else { return }

        autocompleteTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }

            do {
                let r = try await MonochromeAPI().searchAll(query: trimmed)
                guard !Task.isCancelled else { return }

                var results: [Suggestion] = Array(historyMatches)
                results += r.artists.prefix(3).map { .artist($0) }
                results += r.albums.prefix(2).map { .album($0) }
                results += r.tracks.prefix(3).map { .track($0) }
                results += r.playlists.prefix(2).map { .playlist($0) }

                await MainActor.run {
                    autocompleteCache = SearchCache(
                        query: trimmed, artists: r.artists, albums: r.albums,
                        tracks: r.tracks, playlists: r.playlists
                    )
                    withAnimation(.easeOut(duration: 0.15)) {
                        suggestions = results
                    }
                }
            } catch {}
        }
    }
}

// MARK: - Search Result Rows

struct ArtistSearchResultRow: View {
    let artist: Artist

    var body: some View {
        VStack(spacing: 8) {
            CachedAsyncImage(url: MonochromeAPI().getImageUrl(id: artist.picture)) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .foregroundColor(Theme.secondary)
                }
            }
            .frame(width: 90, height: 90)
            .clipShape(Circle())
            
            Text(artist.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.foreground)
                .lineLimit(1)
                .frame(maxWidth: 90)
        }
    }
}

struct AlbumSearchResultRow: View {
    let album: Album

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CachedAsyncImage(url: MonochromeAPI().getImageUrl(id: album.cover)) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(Theme.secondary)
                }
            }
            .frame(width: 120, height: 120)
            .cornerRadius(6)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(album.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.foreground)
                    .lineLimit(1)
                    .frame(maxWidth: 120, alignment: .leading)
                
                Text(album.artist?.name ?? "")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.mutedForeground)
                    .lineLimit(1)
                    .frame(maxWidth: 120, alignment: .leading)
            }
        }
    }
}

struct PlaylistSearchResultRow: View {
    let playlist: Playlist

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CachedAsyncImage(url: MonochromeAPI().getImageUrl(id: playlist.image)) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(Theme.secondary)
                        .overlay(
                            Image(systemName: "music.note.list")
                                .foregroundColor(Theme.mutedForeground)
                        )
                }
            }
            .frame(width: 120, height: 120)
            .cornerRadius(6)

            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.title ?? "Playlist")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.foreground)
                    .lineLimit(1)
                    .frame(maxWidth: 120, alignment: .leading)

                Text(playlist.user?.name ?? "")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.mutedForeground)
                    .lineLimit(1)
                    .frame(maxWidth: 120, alignment: .leading)
            }
        }
    }
}

#Preview {
    SearchView(navigationPath: .constant(NavigationPath()))
        .environment(AudioPlayerService())
        .environment(LibraryManager.shared)
}
