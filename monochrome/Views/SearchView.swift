import SwiftUI

struct SearchView: View {
    @Binding var navigationPath: NavigationPath
    @Environment(AudioPlayerService.self) private var audioPlayer

    @State private var searchText = ""
    @State private var searchTracks: [Track] = []
    @State private var searchArtists: [Artist] = []
    @State private var searchAlbums: [Album] = []

    @State private var isSearching = false
    @State private var hasSearched = false
    @FocusState private var isFocused: Bool
    @State private var keyboardHeight: CGFloat = 0
    @State private var searchHistory: [String] = []
    @State private var suggestions: [Suggestion] = []
    @State private var autocompleteTask: Task<Void, Never>?

    private let historyKey = "search_history"
    private let maxHistory = 20

    private var hasResults: Bool {
        !searchTracks.isEmpty || !searchArtists.isEmpty || !searchAlbums.isEmpty
    }

    private var showSuggestions: Bool {
        isFocused && !suggestions.isEmpty
    }

    private enum Suggestion: Identifiable {
        case history(String)
        case artist(Artist)
        case album(Album)
        case track(Track)

        var id: String {
            switch self {
            case .history(let q): return "h_\(q)"
            case .artist(let a): return "a_\(a.id)"
            case .album(let a): return "al_\(a.id)"
            case .track(let t): return "t_\(t.id)"
            }
        }

        var primaryText: String {
            switch self {
            case .history(let q): return q
            case .artist(let a): return a.name
            case .album(let a): return a.title
            case .track(let t): return t.title
            }
        }

        var secondaryText: String? {
            switch self {
            case .history: return nil
            case .artist: return "Artist"
            case .album(let a): return a.artist?.name ?? "Album"
            case .track(let t): return t.artist?.name ?? "Track"
            }
        }

        var icon: String {
            switch self {
            case .history: return "clock.arrow.circlepath"
            case .artist: return "person.fill"
            case .album: return "square.stack"
            case .track: return "music.note"
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
                    
                    // ALBUMS SECTION
                    if !searchAlbums.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Albums")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(Theme.foreground)
                                .padding(.horizontal, 16)
                                .padding(.top, 10)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 16) {
                                    ForEach(searchAlbums) { album in
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
        autocompleteTask?.cancel()
        suggestions = []
        addToHistory(query)

        Task {
            do {
                let r = try await MonochromeAPI().searchAll(query: query)
                searchArtists = r.artists
                searchAlbums = r.albums
                searchTracks = r.tracks
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
        Button {
            handleSuggestionTap(suggestion)
        } label: {
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
                        .frame(width: 32, height: 32)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func suggestionIcon(_ suggestion: Suggestion) -> some View {
        switch suggestion {
        case .artist(let artist):
            AsyncImage(url: MonochromeAPI().getImageUrl(id: artist.picture, size: 160)) { phase in
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
            AsyncImage(url: MonochromeAPI().getImageUrl(id: album.cover, size: 160)) { phase in
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
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }

            do {
                let r = try await MonochromeAPI().searchAll(query: trimmed)
                guard !Task.isCancelled else { return }

                var results: [Suggestion] = Array(historyMatches)
                results += r.artists.prefix(3).map { .artist($0) }
                results += r.albums.prefix(2).map { .album($0) }
                results += r.tracks.prefix(3).map { .track($0) }

                await MainActor.run {
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
            AsyncImage(url: MonochromeAPI().getImageUrl(id: artist.picture)) { phase in
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
            AsyncImage(url: MonochromeAPI().getImageUrl(id: album.cover)) { phase in
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

#Preview {
    SearchView(navigationPath: .constant(NavigationPath()))
        .environment(AudioPlayerService())
        .environment(LibraryManager.shared)
}
