import Foundation
import AVFoundation
import MediaPlayer
import Observation
import UIKit
import SwiftUI

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
    private let restartThreshold: TimeInterval = 3

    var hasPreviousTrack: Bool { !previousInSession.isEmpty || currentTime >= restartThreshold }
    var hasNextTrack: Bool { !queuedTracks.isEmpty }

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
        saveState()
    }

    func removeFromQueue(at index: Int) {
        guard queuedTracks.indices.contains(index) else { return }
        let removed = queuedTracks.remove(at: index)
        if isShuffled {
            originalQueue.removeAll { $0.id == removed.id }
        }
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
        saveState()
    }

    func addToQueue(track: Track) {
        queuedTracks.append(track)
        if isShuffled {
            originalQueue.append(track)
        }
        saveState()
    }

    func play(track: Track, queue: [Track] = [], previousTracks: [Track] = []) {
        // Clean up previous observer if any
        removeTimeObserver()

        // Push current track to history before switching
        if let current = currentTrack {
            playHistory.append(current)
        }

        // Mark where the current session starts in playHistory
        queueSessionHistoryStart = playHistory.count

        // Add previous tracks from the queue context to history
        playHistory.append(contentsOf: previousTracks)

        self.queuedTracks = queue
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
            if let streamUrlStr = try? await MonochromeAPI().fetchStreamUrl(trackId: track.id),
               let url = URL(string: streamUrlStr) {

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
            guard let streamUrlStr = try? await MonochromeAPI().fetchStreamUrl(trackId: track.id),
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

    func nextTrack() {
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
            if let streamUrlStr = try? await MonochromeAPI().fetchStreamUrl(trackId: previous.id),
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

        let historyToSave = Array(playHistory.suffix(20)) // Keep last 20
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
    }

    deinit {
        removeTimeObserver()
    }
}
