import Foundation
import Observation

@Observable
class DownloadManager {
    static let shared = DownloadManager()

    // trackId -> download state
    var activeDownloads: [Int: DownloadState] = [:]

    private let manifestKey = "monochrome_downloads_manifest"
    private var manifest: [Int: DownloadedTrack] = [:]
    private let downloadsDir: URL

    struct DownloadedTrack: Codable {
        let trackId: Int
        let title: String
        let artist: String
        let album: String
        let fileName: String
        let downloadedAt: Double
    }

    enum DownloadState {
        case downloading(progress: Double)
        case completed
        case failed
    }

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        downloadsDir = docs.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
        loadManifest()
    }

    // MARK: - Status

    func isDownloaded(_ trackId: Int) -> Bool {
        guard let entry = manifest[trackId] else { return false }
        let path = downloadsDir.appendingPathComponent(entry.fileName)
        if FileManager.default.fileExists(atPath: path.path) {
            return true
        }
        // File was removed outside app
        manifest.removeValue(forKey: trackId)
        saveManifest()
        return false
    }

    func isDownloading(_ trackId: Int) -> Bool {
        if case .downloading = activeDownloads[trackId] { return true }
        return false
    }

    func progress(for trackId: Int) -> Double {
        if case .downloading(let p) = activeDownloads[trackId] { return p }
        return 0
    }

    func localURL(for trackId: Int) -> URL? {
        guard let entry = manifest[trackId] else { return nil }
        let path = downloadsDir.appendingPathComponent(entry.fileName)
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }
        return path
    }

    // MARK: - Download

    func downloadTrack(_ track: Track) {
        let trackId = track.id
        guard !isDownloaded(trackId), !isDownloading(trackId) else { return }

        activeDownloads[trackId] = .downloading(progress: 0)

        Task {
            do {
                let downloadQuality = AudioQuality(rawValue: SettingsManager.shared.downloadQuality.rawValue) ?? .hiResLossless
                guard let streamUrlStr = await MonochromeAPI().fetchStreamUrlWithFallback(trackId: trackId, preferredQuality: downloadQuality),
                      let streamUrl = URL(string: streamUrlStr) else {
                    await MainActor.run { activeDownloads[trackId] = .failed }
                    return
                }

                let ext = streamUrl.pathExtension.isEmpty ? "flac" : streamUrl.pathExtension
                let relativePath = SettingsManager.shared.generateFilePath(for: track, extension: ext)
                let destURL = downloadsDir.appendingPathComponent(relativePath)

                // Create directory structure if needed
                let destDir = destURL.deletingLastPathComponent()
                if !FileManager.default.fileExists(atPath: destDir.path) {
                    try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
                }

                let (tempURL, response) = try await URLSession.shared.download(from: streamUrl, delegate: ProgressDelegate { progress in
                    Task { @MainActor in
                        self.activeDownloads[trackId] = .downloading(progress: progress)
                    }
                })

                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    await MainActor.run { activeDownloads[trackId] = .failed }
                    return
                }

                // Move to permanent location
                if FileManager.default.fileExists(atPath: destURL.path) {
                    try FileManager.default.removeItem(at: destURL)
                }
                try FileManager.default.moveItem(at: tempURL, to: destURL)

                // Embed metadata (title, artist, album, cover art) into the audio file
                await self.embedMetadata(track: track, fileURL: destURL)

                let entry = DownloadedTrack(
                    trackId: trackId,
                    title: track.title,
                    artist: track.artist?.name ?? "",
                    album: track.album?.title ?? "",
                    fileName: relativePath,
                    downloadedAt: Date().timeIntervalSince1970
                )

                await MainActor.run {
                    manifest[trackId] = entry
                    saveManifest()
                    activeDownloads[trackId] = .completed
                    // Clear completed state after a moment
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        if case .completed = self.activeDownloads[trackId] {
                            self.activeDownloads.removeValue(forKey: trackId)
                        }
                    }
                }

                print("[Download] Saved: \(track.title) → \(relativePath)")
            } catch {
                print("[Download] Error for \(trackId): \(error.localizedDescription)")
                await MainActor.run { activeDownloads[trackId] = .failed }
            }
        }
    }

    func downloadTracks(_ tracks: [Track]) {
        for track in tracks where !isDownloaded(track.id) && !isDownloading(track.id) {
            downloadTrack(track)
        }
    }

    func removeDownload(_ trackId: Int) {
        if let entry = manifest[trackId] {
            let path = downloadsDir.appendingPathComponent(entry.fileName)
            try? FileManager.default.removeItem(at: path)
        }
        manifest.removeValue(forKey: trackId)
        activeDownloads.removeValue(forKey: trackId)
        saveManifest()
    }

    func removeAllDownloads() {
        // Delete the entire Downloads folder
        try? FileManager.default.removeItem(at: downloadsDir)
        try? FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
        manifest.removeAll()
        activeDownloads.removeAll()
        saveManifest()
    }

    var downloadedCount: Int {
        manifest.values.filter { entry in
            FileManager.default.fileExists(atPath: downloadsDir.appendingPathComponent(entry.fileName).path)
        }.count
    }

    // MARK: - Metadata Embedding

    private func embedMetadata(track: Track, fileURL: URL) async {
        var coverData: Data?
        if let coverUrl = MonochromeAPI().getImageUrl(id: track.album?.cover, size: 640) {
            if let (data, response) = try? await URLSession.shared.data(from: coverUrl),
               (response as? HTTPURLResponse)?.statusCode == 200, data.count > 1000 {
                coverData = data
            }
        }

        let metadata = AudioMetadataEmbedder.Metadata(
            title: track.title,
            artist: track.artist?.name ?? "",
            album: track.album?.title ?? "",
            trackNumber: track.trackNumber,
            totalTracks: track.album?.numberOfTracks,
            year: track.album?.releaseDate.flatMap { String($0.prefix(4)) } ?? track.releaseYear,
            coverData: coverData
        )

        AudioMetadataEmbedder.shared.embed(at: fileURL, metadata: metadata)
    }

    // MARK: - Persistence

    private func loadManifest() {
        guard let data = UserDefaults.standard.data(forKey: manifestKey),
              let saved = try? JSONDecoder().decode([Int: DownloadedTrack].self, from: data) else { return }
        manifest = saved
    }

    private func saveManifest() {
        if let data = try? JSONEncoder().encode(manifest) {
            UserDefaults.standard.set(data, forKey: manifestKey)
        }
    }
}

// MARK: - Download Progress Delegate

private final class ProgressDelegate: NSObject, URLSessionTaskDelegate {
    let onProgress: (Double) -> Void

    init(onProgress: @escaping (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        // observe progress via KVO
        task.addObserver(self, forKeyPath: "countOfBytesReceived", options: .new, context: nil)
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        if let task = object as? URLSessionTask, task.countOfBytesExpectedToReceive > 0 {
            let progress = Double(task.countOfBytesReceived) / Double(task.countOfBytesExpectedToReceive)
            onProgress(min(1, progress))
        }
    }
}
