import Foundation
import AVFoundation
import MediaPlayer
import Observation

@Observable
class AudioPlayerService {
    var player: AVPlayer?
    var isPlaying: Bool = false
    var currentTrackTitle: String = "No Track"
    var currentArtistName: String = "Unknown Artist"
    
    init() {
        setupRemoteCommandCenter()
    }
    
    func play(url: URL, title: String, artist: String) {
        let playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)
        player?.play()
        
        isPlaying = true
        currentTrackTitle = title
        currentArtistName = artist
        
        updateNowPlayingInfo()
    }
    
    func togglePlayPause() {
        if isPlaying {
            player?.pause()
        } else {
            player?.play()
        }
        isPlaying.toggle()
        updateNowPlayingInfo()
    }
    
    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        commandCenter.playCommand.addTarget { [weak self] event in
            self?.togglePlayPause()
            return .success
        }
        
        commandCenter.pauseCommand.addTarget { [weak self] event in
            self?.togglePlayPause()
            return .success
        }
    }
    
    private func updateNowPlayingInfo() {
        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = currentTrackTitle
        nowPlayingInfo[MPMediaItemPropertyArtist] = currentArtistName
        
        // Add duration and current playback time later when syncing with AVPlayer observer
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
}
