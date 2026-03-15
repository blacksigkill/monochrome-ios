import Foundation
import AVFoundation
import MediaPlayer
import Observation
import UIKit
import SwiftUI

enum RepeatMode: Int, Codable {
    case off = 0
    case all = 1
    case one = 2
}

@Observable
class AudioPlayerService {
    var player: AVQueuePlayer?
    var isPlaying: Bool = false
    var currentTrackTitle: String = "No Track"
    var currentArtistName: String = "Unknown Artist"
    var currentAlbumTitle: String = ""
    var currentCoverUrl: URL? = nil
    var currentTrack: Track? = nil

    // Playback state
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    private var timeObserverToken: Any?
    private var nowPlayingArtwork: MPMediaItemArtwork?

    // Queue support
    var queuedTracks: [Track] = []
    var playHistory: [Track] = []
    var isShuffled: Bool = false
    private var originalQueue: [Track] = []
    var queueSessionHistoryStart: Int = 0
    var repeatMode: RepeatMode = .off

    @ObservationIgnored
    private var isRefreshingRecentQualities = false
    @ObservationIgnored
    private var qualityFetchAttempts: Set<Int> = []

    private var savedQueueForRepeatOne: [Track] = []
    private let restartThreshold: TimeInterval = 3
    private let historyMaxCount = 100

    var hasPreviousTrack: Bool { !previousInSession.isEmpty || currentTime >= restartThreshold }
    var hasNextTrack: Bool { !queuedTracks.isEmpty || repeatMode != .off }

    var previousInSession: [Track] {
        guard playHistory.count > queueSessionHistoryStart else { return [] }
        return Array(playHistory[queueSessionHistoryStart...])
    }

    // Persistence keys
    private let currentTrackKey = "monochrome_current_track"
    private let playHistoryKey = "monochrome_play_history"
    private let savedTimestampKey = "monochrome_saved_timestamp"
    private let savedDurationKey = "monochrome_saved_duration"
    private let queueKey = "monochrome_queued_tracks"
    private let shuffleKey = "monochrome_is_shuffled"
    private let originalQueueKey = "monochrome_original_queue"
    private let queueSessionHistoryStartKey = "monochrome_queue_session_history_start"
    private let repeatModeKey = "monochrome_repeat_mode"
    private let savedQueueRepeatOneKey = "monochrome_saved_queue_repeat_one"
    private var restoredTimestamp: TimeInterval = 0

    init() {
        setupRemoteCommandCenter()
        setupAudioSession()
        restoreState()
    }

    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to set audio session category: \(error)")
        }
    }

    func toggleShuffle() {
        if isShuffled {
            queuedTracks = originalQueue
            originalQueue = []
            isShuffled = false
        } else {
            originalQueue = queuedTracks
            queuedTracks.shuffle()
            isShuffled = true
        }
        updateRemoteCommandState()
        saveState()
    }

    func cycleRepeatMode() {
        let oldMode = repeatMode
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }

        switch (oldMode, repeatMode) {
        case (.off, .all):
            // Build circular queue: append session history + current track
            var seenIds = Set(queuedTracks.map { $0.id })
            var toAppend: [Track] = []
            for track in previousInSession {
                if seenIds.insert(track.id).inserted {
                    toAppend.append(track)
                }
            }
            if let current = currentTrack, seenIds.insert(current.id).inserted {
                toAppend.append(current)
            }
            queuedTracks.append(contentsOf: toAppend)

        case (.all, .one):
            // Strip loop duplicates (session history + current) to recover original queue
            var loopIds = Set(previousInSession.map { $0.id })
            if let current = currentTrack { loopIds.insert(current.id) }
            savedQueueForRepeatOne = queuedTracks.filter { !loopIds.contains($0.id) }
            queuedTracks = []

        case (.one, .off):
            // Restore the queue saved before repeat one
            queuedTracks = savedQueueForRepeatOne
            savedQueueForRepeatOne = []

        default:
            break
        }

        updateRemoteCommandState()
        saveState()
    }

    func removeFromQueue(at index: Int) {
        guard queuedTracks.indices.contains(index) else { return }
        let removed = queuedTracks.remove(at: index)
        if isShuffled {
            originalQueue.removeAll { $0.id == removed.id }
        }
        updateRemoteCommandState()
        saveState()
    }

    func moveInQueue(from source: IndexSet, to destination: Int) {
        queuedTracks.move(fromOffsets: source, toOffset: destination)
        if isShuffled {
            originalQueue = queuedTracks
        }
        saveState()
    }

    func playNext(track: Track) {
        queuedTracks.insert(track, at: 0)
        if isShuffled {
            originalQueue.insert(track, at: 0)
        }
        updateRemoteCommandState()
        saveState()
    }

    func addToQueue(track: Track) {
        queuedTracks.append(track)
        if isShuffled {
            originalQueue.append(track)
        }
        updateRemoteCommandState()
        saveState()
    }

    // MARK: - Quality Backfill (recent history)

    func refreshRecentQualitiesIfNeeded(tracks: [Track]) {
        guard SettingsManager.shared.showTrackQuality else { return }
        guard !isRefreshingRecentQualities else { return }

        let uniqueById = Dictionary(tracks.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        let candidates = uniqueById.values.filter {
            ($0.audioQuality == nil || $0.mediaMetadata?.tags == nil) &&
            !qualityFetchAttempts.contains($0.id) &&
            !QualityCache.isCached($0.id)
        }
        guard !candidates.isEmpty else { return }

        let limited = Array(candidates.prefix(6))
        qualityFetchAttempts.formUnion(limited.map { $0.id })
        isRefreshingRecentQualities = true

        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let api = MonochromeAPI()
            var updates: [Int: Track] = [:]
            var failedIds: [Int] = []

            await withTaskGroup(of: (Int, Track?).self) { group in
                var pending = 0
                for track in limited {
                    if pending >= 3, let (id, result) = await group.next() {
                        if let result { updates[id] = result } else { failedIds.append(id) }
                        pending -= 1
                    }
                    group.addTask {
                        // Use the proxy to check actual available quality (Tidal v1 metadata is unreliable)
                        if let quality = await api.fetchBestAvailableQuality(trackId: track.id) {
                            let updated = track.withQuality(quality)
                            return (track.id, updated)
                        }
                        return (track.id, nil)
                    }
                    pending += 1
                }
                for await (id, result) in group {
                    if let result { updates[id] = result } else { failedIds.append(id) }
                }
            }

            var cacheEntries: [(id: Int, audioQuality: String?, mediaTags: [String]?)] = []
            for (id, track) in updates {
                cacheEntries.append((id, track.audioQuality, track.mediaMetadata?.tags))
            }
            for id in failedIds {
                cacheEntries.append((id, nil, nil))
            }
            QualityCache.store(cacheEntries)

            await MainActor.run {
                defer { self.isRefreshingRecentQualities = false }
                guard !updates.isEmpty else { return }

                self.playHistory = self.playHistory.map { track in
                    guard let update = updates[track.id] else { return track }
                    return track.withUpdatedQuality(from: update)
                }
                if let current = self.currentTrack, let update = updates[current.id] {
                    self.currentTrack = current.withUpdatedQuality(from: update)
                }
                self.saveState()
            }
        }
    }

    func play(track: Track, queue: [Track] = [], previousTracks: [Track] = []) {
        // Clean up previous observer if any
        removeTimeObserver()

        // Push current track to history before switching
        if let current = currentTrack {
            playHistory.append(current)
            syncHistoryInBackground(track: current)
        }

        // Mark where the current session starts in playHistory
        queueSessionHistoryStart = playHistory.count

        // Add previous tracks from the queue context to history
        playHistory.append(contentsOf: previousTracks)

        self.queuedTracks = queue
        // Repeat all: build circular queue by appending previous tracks + current track
        if repeatMode == .all {
            var seenIds = Set(queue.map { $0.id })
            var toAppend: [Track] = []
            for t in previousTracks {
                if seenIds.insert(t.id).inserted && t.id != track.id {
                    toAppend.append(t)
                }
            }
            if seenIds.insert(track.id).inserted {
                toAppend.append(track)
            }
            self.queuedTracks.append(contentsOf: toAppend)
        }
        self.isShuffled = false
        self.originalQueue = []
        self.currentTrack = track
        self.currentTrackTitle = track.title
        self.currentArtistName = track.artist?.name ?? "Unknown Artist"
        self.currentAlbumTitle = track.album?.title ?? ""
        self.currentCoverUrl = MonochromeAPI().getImageUrl(id: track.album?.cover)
        self.currentTime = 0
        self.duration = 0

        Task {
            // Prefer local download, fall back to streaming
            var resolvedUrl: URL? = DownloadManager.shared.localURL(for: track.id)
            if resolvedUrl == nil {
                let preferredQuality = SettingsManager.shared.streamQuality
                if let streamUrlStr = await MonochromeAPI().fetchStreamUrlWithFallback(trackId: track.id, preferredQuality: preferredQuality) {
                    resolvedUrl = URL(string: streamUrlStr)
                    print("[Audio] Streaming URL: \(streamUrlStr)")
                } else {
                    print("[Audio] No stream available for track \(track.id)")
                }
            }

            if let url = resolvedUrl {
                let asset = AVURLAsset(url: url)
                let playerItem = AVPlayerItem(asset: asset)

                NotificationCenter.default.addObserver(self,
                                                       selector: #selector(playerItemDidReachEnd),
                                                       name: .AVPlayerItemDidPlayToEndTime,
                                                       object: playerItem)

                await MainActor.run {
                    if self.player == nil {
                        self.player = AVQueuePlayer(playerItem: playerItem)
                    } else {
                        self.player?.removeAllItems()
                        if self.player?.canInsert(playerItem, after: nil) == true {
                            self.player?.insert(playerItem, after: nil)
                        }
                    }

                    self.player?.play()
                    self.isPlaying = true
                    self.addTimeObserver()
                    self.updateNowPlayingInfo()
                    self.saveState()
                }

                // Load duration asynchronously
                if let durationSeconds = try? await asset.load(.duration).seconds, !durationSeconds.isNaN {
                    await MainActor.run {
                        self.duration = durationSeconds
                        self.updateNowPlayingInfo()
                        self.saveState()
                    }
                }

                // Load artwork asynchronously
                if let coverUrl = MonochromeAPI().getImageUrl(id: track.album?.cover) {
                    if let (data, _) = try? await URLSession.shared.data(from: coverUrl), let image = UIImage(data: data) {
                        await MainActor.run {
                            self.nowPlayingArtwork = MPMediaItemArtwork(boundsSize: image.size) { _ in return image }
                            self.updateNowPlayingInfo()
                        }
                    }
                } else {
                    await MainActor.run {
                        self.nowPlayingArtwork = nil
                        self.updateNowPlayingInfo()
                    }
                }
            }
        }
    }

    @objc private func playerItemDidReachEnd(notification: Notification) {
        nextTrack()
    }

    func togglePlayPause() {
        // After a restore, player is nil — need to load the stream first
        if player == nil, let track = currentTrack {
            resumeRestoredTrack(track)
            return
        }

        if isPlaying {
            player?.pause()
        } else {
            player?.play()
        }
        isPlaying.toggle()
        updateNowPlayingInfo()
    }

    /// Loads the stream for a restored track and seeks to the saved timestamp
    private func resumeRestoredTrack(_ track: Track) {
        let seekTo = restoredTimestamp
        restoredTimestamp = 0

        Task {
            let quality = SettingsManager.shared.streamQuality
            guard let streamUrlStr = await MonochromeAPI().fetchStreamUrlWithFallback(trackId: track.id, preferredQuality: quality),
                  let url = URL(string: streamUrlStr) else { return }

            let asset = AVURLAsset(url: url)
            let playerItem = AVPlayerItem(asset: asset)

            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(playerItemDidReachEnd),
                                                   name: .AVPlayerItemDidPlayToEndTime,
                                                   object: playerItem)

            await MainActor.run {
                self.player = AVQueuePlayer(playerItem: playerItem)
                self.player?.play()
                self.isPlaying = true
                self.addTimeObserver()
                self.updateNowPlayingInfo()
            }

            // Seek to saved position
            if seekTo > 0 {
                let targetTime = CMTime(seconds: seekTo, preferredTimescale: 1000)
                await self.player?.seek(to: targetTime)
            }

            // Load duration
            if let durationSeconds = try? await asset.load(.duration).seconds, !durationSeconds.isNaN {
                await MainActor.run {
                    self.duration = durationSeconds
                    self.updateNowPlayingInfo()
                    self.saveState()
                }
            }

            // Load artwork
            if let coverUrl = MonochromeAPI().getImageUrl(id: track.album?.cover),
               let (data, _) = try? await URLSession.shared.data(from: coverUrl),
               let image = UIImage(data: data) {
                await MainActor.run {
                    self.nowPlayingArtwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                    self.updateNowPlayingInfo()
                }
            }
        }
    }

    func seek(to time: TimeInterval) {
        guard let customPlayer = player else { return }

        let targetTime = CMTime(seconds: time, preferredTimescale: 1000)
        customPlayer.seek(to: targetTime) { [weak self] _ in
            self?.currentTime = time
            self?.updateNowPlayingInfo()
        }
    }

    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            if !self.isPlaying {
                self.togglePlayPause()
            }
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            if self.isPlaying {
                self.togglePlayPause()
            }
            return .success
        }

        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.nextTrack()
            return .success
        }

        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.previousTrack()
            return .success
        }

        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self = self,
                  let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self.seek(to: positionEvent.positionTime)
            return .success
        }

    }

    private func updateRemoteCommandState() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.nextTrackCommand.isEnabled = hasNextTrack || repeatMode != .off
        commandCenter.previousTrackCommand.isEnabled = hasPreviousTrack
    }

    func nextTrack() {
        // Repeat one: replay the current track from the beginning
        if repeatMode == .one, let current = currentTrack {
            // Re-stream the track (AVPlayerItem is consumed at end)
            let savedSessionStart = queueSessionHistoryStart
            let savedHistory = playHistory
            play(track: current, queue: [])
            // Restore history/session so previousTrack still works
            playHistory = savedHistory
            queueSessionHistoryStart = savedSessionStart
            return
        }

        // Repeat all: if queue is empty, rebuild it from session history
        if repeatMode == .all && queuedTracks.isEmpty {
            var allTracks: [Track] = []
            var seenIds = Set<Int>()
            for track in previousInSession {
                if seenIds.insert(track.id).inserted {
                    allTracks.append(track)
                }
            }
            if let current = currentTrack, seenIds.insert(current.id).inserted {
                allTracks.append(current)
            }
            guard !allTracks.isEmpty else {
                player?.pause()
                isPlaying = false
                updateNowPlayingInfo()
                saveState()
                return
            }
            let first = allTracks.removeFirst()
            queuedTracks = allTracks
            if isShuffled {
                queuedTracks.shuffle()
                originalQueue = queuedTracks
            }

            let wasShuffled = isShuffled
            let savedOriginal = originalQueue
            play(track: first, queue: queuedTracks)
            isShuffled = wasShuffled
            originalQueue = savedOriginal
            return
        }

        guard !queuedTracks.isEmpty else {
            player?.pause()
            isPlaying = false
            updateNowPlayingInfo()
            saveState()
            return
        }

        let next = queuedTracks.removeFirst()
        if isShuffled {
            originalQueue.removeAll { $0.id == next.id }
        }

        let wasShuffled = isShuffled
        let savedOriginal = originalQueue
        let savedSessionStart = queueSessionHistoryStart
        play(track: next, queue: queuedTracks)
        isShuffled = wasShuffled
        originalQueue = savedOriginal
        queueSessionHistoryStart = savedSessionStart
    }

    func previousTrack() {
        // If more than 3 seconds in, restart current track
        if currentTime >= restartThreshold {
            seek(to: 0)
            return
        }

        guard playHistory.count > queueSessionHistoryStart else {
            seek(to: 0)
            return
        }

        // Put current track back at front of queue
        if let current = currentTrack {
            queuedTracks.insert(current, at: 0)
            // In repeat all, remove the loop duplicate of current from the end
            if repeatMode == .all, queuedTracks.count > 1,
               let lastIdx = queuedTracks.lastIndex(where: { $0.id == current.id }), lastIdx > 0 {
                queuedTracks.remove(at: lastIdx)
            }
        }

        let previous = playHistory.removeLast()
        // Use internal play without pushing to history again
        removeTimeObserver()
        self.currentTrack = previous
        self.currentTrackTitle = previous.title
        self.currentArtistName = previous.artist?.name ?? "Unknown Artist"
        self.currentAlbumTitle = previous.album?.title ?? ""
        self.currentCoverUrl = MonochromeAPI().getImageUrl(id: previous.album?.cover)
        self.currentTime = 0
        self.duration = 0

        Task {
            let quality = SettingsManager.shared.streamQuality
            if let streamUrlStr = await MonochromeAPI().fetchStreamUrlWithFallback(trackId: previous.id, preferredQuality: quality),
               let url = URL(string: streamUrlStr) {

                let asset = AVURLAsset(url: url)
                let playerItem = AVPlayerItem(asset: asset)

                NotificationCenter.default.addObserver(self,
                                                       selector: #selector(playerItemDidReachEnd),
                                                       name: .AVPlayerItemDidPlayToEndTime,
                                                       object: playerItem)

                await MainActor.run {
                    self.player?.removeAllItems()
                    if self.player?.canInsert(playerItem, after: nil) == true {
                        self.player?.insert(playerItem, after: nil)
                    }

                    self.player?.play()
                    self.isPlaying = true
                    self.addTimeObserver()
                    self.updateNowPlayingInfo()
                    self.saveState()
                }

                if let durationSeconds = try? await asset.load(.duration).seconds, !durationSeconds.isNaN {
                    await MainActor.run {
                        self.duration = durationSeconds
                        self.updateNowPlayingInfo()
                        self.saveState()
                    }
                }

                if let coverUrl = MonochromeAPI().getImageUrl(id: previous.album?.cover) {
                    if let (data, _) = try? await URLSession.shared.data(from: coverUrl), let image = UIImage(data: data) {
                        await MainActor.run {
                            self.nowPlayingArtwork = MPMediaItemArtwork(boundsSize: image.size) { _ in return image }
                            self.updateNowPlayingInfo()
                        }
                    }
                }
            }
        }
    }

    private var lastSaveTime: TimeInterval = 0

    private func addTimeObserver() {
        guard let customPlayer = player else { return }

        let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = customPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            self.currentTime = time.seconds
            // Save state every 5 seconds
            if abs(self.currentTime - self.lastSaveTime) >= 5 {
                self.lastSaveTime = self.currentTime
                self.saveState()
            }
        }
    }

    private func removeTimeObserver() {
        if let token = timeObserverToken, let customPlayer = player {
            customPlayer.removeTimeObserver(token)
            timeObserverToken = nil
        }
    }

    private func updateNowPlayingInfo() {
        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = currentTrackTitle
        nowPlayingInfo[MPMediaItemPropertyArtist] = currentArtistName
        nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = currentAlbumTitle

        if let artwork = nowPlayingArtwork {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
        }

        if duration > 0 {
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
            nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
            nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        updateRemoteCommandState()
    }

    // MARK: - Persistence

    private func saveState() {
        if let track = currentTrack, let data = try? JSONEncoder().encode(track) {
            UserDefaults.standard.set(data, forKey: currentTrackKey)
        } else {
            UserDefaults.standard.removeObject(forKey: currentTrackKey)
        }

        // Save current playback position and duration
        UserDefaults.standard.set(currentTime, forKey: savedTimestampKey)
        UserDefaults.standard.set(duration, forKey: savedDurationKey)

        let historyToSave = Array(playHistory.suffix(historyMaxCount))
        let historyDropCount = playHistory.count - historyToSave.count
        if let data = try? JSONEncoder().encode(historyToSave) {
            UserDefaults.standard.set(data, forKey: playHistoryKey)
        }
        UserDefaults.standard.set(max(0, queueSessionHistoryStart - historyDropCount), forKey: queueSessionHistoryStartKey)

        // Save queue and shuffle state
        if let data = try? JSONEncoder().encode(queuedTracks) {
            UserDefaults.standard.set(data, forKey: queueKey)
        }
        UserDefaults.standard.set(isShuffled, forKey: shuffleKey)
        if isShuffled, let data = try? JSONEncoder().encode(originalQueue) {
            UserDefaults.standard.set(data, forKey: originalQueueKey)
        } else {
            UserDefaults.standard.removeObject(forKey: originalQueueKey)
        }
        UserDefaults.standard.set(repeatMode.rawValue, forKey: repeatModeKey)
        if !savedQueueForRepeatOne.isEmpty, let data = try? JSONEncoder().encode(savedQueueForRepeatOne) {
            UserDefaults.standard.set(data, forKey: savedQueueRepeatOneKey)
        } else {
            UserDefaults.standard.removeObject(forKey: savedQueueRepeatOneKey)
        }
    }

    private func restoreState() {
        // Restore play history
        if let data = UserDefaults.standard.data(forKey: playHistoryKey),
           let tracks = try? JSONDecoder().decode([Track].self, from: data) {
            self.playHistory = tracks
        }
        self.queueSessionHistoryStart = min(
            UserDefaults.standard.integer(forKey: queueSessionHistoryStartKey),
            self.playHistory.count
        )

        // Restore queue and shuffle state
        if let data = UserDefaults.standard.data(forKey: queueKey),
           let tracks = try? JSONDecoder().decode([Track].self, from: data) {
            self.queuedTracks = tracks
        }
        self.isShuffled = UserDefaults.standard.bool(forKey: shuffleKey)
        if isShuffled,
           let data = UserDefaults.standard.data(forKey: originalQueueKey),
           let tracks = try? JSONDecoder().decode([Track].self, from: data) {
            self.originalQueue = tracks
        }
        self.repeatMode = RepeatMode(rawValue: UserDefaults.standard.integer(forKey: repeatModeKey)) ?? .off
        if let data = UserDefaults.standard.data(forKey: savedQueueRepeatOneKey),
           let tracks = try? JSONDecoder().decode([Track].self, from: data) {
            self.savedQueueForRepeatOne = tracks
        }

        // Restore current track (paused state, not auto-playing)
        if let data = UserDefaults.standard.data(forKey: currentTrackKey),
           let track = try? JSONDecoder().decode(Track.self, from: data) {
            self.currentTrack = track
            self.currentTrackTitle = track.title
            self.currentArtistName = track.artist?.name ?? "Unknown Artist"
            self.currentAlbumTitle = track.album?.title ?? ""
            self.currentCoverUrl = MonochromeAPI().getImageUrl(id: track.album?.cover)
            self.isPlaying = false

            // Restore saved timestamp and duration for resume
            let savedTime = UserDefaults.standard.double(forKey: savedTimestampKey)
            if savedTime > 0 {
                self.restoredTimestamp = savedTime
                self.currentTime = savedTime
            }
            let savedDuration = UserDefaults.standard.double(forKey: savedDurationKey)
            if savedDuration > 0 {
                self.duration = savedDuration
            }
        }
        updateRemoteCommandState()
    }

    // MARK: - Cloud History Sync

    func syncHistoryFromCloud(uid: String) async {
        do {
            let historyTracks = try await PocketBaseService.shared.fetchHistory(uid: uid)
            guard !historyTracks.isEmpty else { return }
            await MainActor.run {
                let orderedHistory = Array(historyTracks.reversed())
                self.playHistory = orderedHistory
                self.queueSessionHistoryStart = orderedHistory.count
                self.saveState()
            }
        } catch {
            print("[Sync] History fetch error: \(error.localizedDescription)")
        }
    }

    private func syncHistoryInBackground(track: Track) {
        guard let uid = AuthService.shared.currentUser?.uid else { return }
        Task.detached(priority: .utility) {
            do {
                try await PocketBaseService.shared.syncHistoryItem(uid: uid, track: track)
            } catch {
                print("[Sync] History sync error: \(error.localizedDescription)")
            }
        }
    }

    deinit {
        removeTimeObserver()
    }
}
