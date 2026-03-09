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

    private let historyKey = "search_history"
    private let maxHistory = 20

    private var hasResults: Bool {
        !searchTracks.isEmpty || !searchArtists.isEmpty || !searchAlbums.isEmpty
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
            
            searchBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .offset(y: keyboardHeight)
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
